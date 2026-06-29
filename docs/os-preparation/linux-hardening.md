# Linux Hardening Guide - Ubuntu 22.04 LTS for Kubernetes

## Overview

This guide covers the preparation of Ubuntu 22.04 LTS servers for an enterprise
cloud-native deployment in an air-gapped environment. It follows CIS Ubuntu 22.04
Benchmark Level 1 guidelines with additional Kubernetes-specific hardening.

---

## 1. OS Installation

### 1.1 Installation Method

Use the Ubuntu 22.04 LTS Server ISO (minimal server profile). In an air-gapped
environment, the ISO should be staged locally and booted via PXE or USB.

### 1.2 Disk Layout (LVM)

All partitions use LVM for flexibility. The etcd LV **must** reside on a
separate physical disk on master nodes for I/O isolation.

| Mount Point | Size | Filesystem | LVM Volume | Notes |
|---|---|---|---|---|
| `/` | 50 GB | ext4 | `rootlv` | OS and system binaries |
| `/var` | 100 GB | ext4 | `varlv` | Container images, logs |
| `/var/lib/etcd` | 10 GB | ext4 | `etcdlv` | Dedicated disk on masters |
| `/tmp` | 4 GB | ext4 | `tmplv` | Temporary files |
| swap | **NONE** | — | — | Disabled per K8s requirement |

### 1.3 Partitioning Scheme (Example)

```bash
# Master with two disks: sda (OS) + sdb (etcd)
# sda:
Partition 1: 1 GB  - /boot (primary, ext4)
Partition 2: 50 GB - /     (LVM: rootlv)
Partition 3: 100 GB- /var  (LVM: varlv)
Partition 4: 4 GB  - /tmp  (LVM: tmplv)

# sdb (separate physical disk for etcd):
Partition 1: 10 GB - /var/lib/etcd (LVM: etcdlv)
```

> **IMPORTANT**: Dedicated etcd disk is critical for master nodes. etcd is
> I/O sensitive and sharing I/O with other workloads causes cluster instability.

---

## 2. Kernel Parameters

### 2.1 Sysctl Settings for Kubernetes

Create `/etc/sysctl.d/99-kubernetes.conf`:

```ini
# Network forwarding (required for pod networking)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Bridge filtering (required for Calico/Flannel)
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-arptables = 1

# Connection tracking
net.netfilter.nf_conntrack_max = 131072

# Network performance
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 1000
net.ipv4.tcp_max_syn_backlog = 8096

# ARP
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# IPv6 (disable if not used)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# Memory
vm.overcommit_memory = 1
vm.panic_on_oom = 0
kernel.panic = 10
kernel.panic_on_oops = 1

# File handles
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
```

Apply:
```bash
sudo sysctl --system
```

### 2.2 Kernel Modules

Required modules (load at boot):

```ini
# /etc/modules-load.d/kubernetes.conf
br_netfilter
overlay
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
```

Load immediately:
```bash
sudo modprobe br_netfilter
sudo modprobe overlay
sudo modprobe ip_vs
sudo modprobe ip_vs_rr
sudo modprobe ip_vs_wrr
sudo modprobe ip_vs_sh
sudo modprobe nf_conntrack
```

---

## 3. Swap and Firewall

### 3.1 Disable Swap

Kubernetes requires swap to be disabled to guarantee memory accounting.

```bash
# Disable immediately
sudo swapoff -a

# Remove swap entries from /etc/fstab (persistent)
sudo sed -i '/\s*swap\s*/d' /etc/fstab

# Verify
free -h   # Should show 0 under 'Swap'
```

### 3.2 Disable UFW

Calico manages its own iptables rules. UFW conflicts with Calico's networking.

```bash
sudo systemctl stop ufw
sudo systemctl disable ufw
```

---

## 4. Unused Services

Disable services not required for a Kubernetes node:

```bash
# Snap and desktop services (not present on minimal server but be safe)
sudo systemctl stop snapd 2>/dev/null || true
sudo systemctl disable snapd 2>/dev/null || true

# Accounts-daemon (not needed on headless server)
sudo systemctl stop accounts-daemon 2>/dev/null || true
sudo systemctl disable accounts-daemon 2>/dev/null || true
```

---

## 5. SSH Hardening

### 5.1 Configuration

Edit `/etc/ssh/sshd_config`:

```bash
# Authentication
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey

# Protocol
Protocol 2

# Ciphers and MACs (CIS compliant)
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Connection limits
MaxAuthTries 3
MaxSessions 4
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# Logging
LogLevel VERBOSE

# Restrict to deploy user
AllowUsers deploy

# Disable forwarding features not needed
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
```

### 5.2 Restart SSH

```bash
sudo systemctl restart sshd
```

> **WARNING**: Ensure you have key-based access for the `deploy` user
> before restarting sshd. Test in a second session.

---

## 6. User Setup

### 6.1 Create Deploy User

```bash
sudo useradd -m -s /bin/bash -c "Ansible Deploy User" deploy
sudo usermod -aG sudo,adm,systemd-journal deploy

# Allow passwordless sudo for automation
echo "deploy ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/deploy
sudo chmod 440 /etc/sudoers.d/deploy
```

### 6.2 SSH Key for Deploy User

```bash
sudo mkdir -p /home/deploy/.ssh
sudo cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
sudo chown -R deploy:deploy /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
sudo chmod 600 /home/deploy/.ssh/authorized_keys
```

---

## 7. Security Limits

Edit `/etc/security/limits.d/99-kubernetes.conf`:

```ini
# Kubernetes components
*               soft    nofile          1048576
*               hard    nofile          1048576
*               soft    nproc           65535
*               hard    nproc           65535

# Root
root            soft    nofile          1048576
root            hard    nofile          1048576
root            soft    nproc           unlimited
root            hard    nproc           unlimited

# Deploy user
deploy          soft    nofile          65536
deploy          hard    nofile          65536
```

---

## 8. Time Synchronization (Chrony - Air-Gap)

In air-gapped environments, time must be synchronized from a local NTP server.

### 8.1 Install Chrony

```bash
sudo apt-get install -y chrony
```

### 8.2 Configuration

Edit `/etc/chrony/chrony.conf`:

```conf
# Air-gap configuration - no internet NTP servers
server ntp1.internal.lan iburst prefer
server ntp2.internal.lan iburst

# Record the rate at which the system clock gains/loses time
driftfile /var/lib/chrony/chrony.drift

# Allow NTP client access from internal network
allow 10.0.0.0/8

# Serve time even if not synchronized to a time source
local stratum 10

# Log files
logdir /var/log/chrony

# Kernel synchronization of the real-time clock (rtc)
rtcsync

# Step the system clock if adjustment is larger than 1 second
# but only in the first three clock updates
makestep 1.0 3
```

### 8.3 Start Chrony

```bash
sudo systemctl enable chrony
sudo systemctl restart chrony
chronyc tracking   # Verify
chronyc sources   # Check sources
```

---

## 9. DNS Configuration

Configure `/etc/resolv.conf` (or systemd-resolved):

```bash
# /etc/resolv.conf
nameserver 10.0.0.2
nameserver 10.0.0.3
search internal.lan cluster.local
options timeout:2 attempts:3
```

If using systemd-resolved, edit `/etc/systemd/resolved.conf`:

```ini
[Resolve]
DNS=10.0.0.2 10.0.0.3
FallbackDNS=
Domains=internal.lan
DNSSEC=no
DNSOverTLS=no
Cache=yes
```

---

## 10. Containerd Installation and Configuration

### 10.1 Installation

From local Nexus repository (packages pre-staged):

```bash
# Update sources to point to local Nexus
echo "deb [arch=amd64] https://nexus.internal.lan/repository/ubuntu jammy universe" | \
  sudo tee /etc/apt/sources.list.d/nexus.list

# Install containerd
sudo apt-get update
sudo apt-get install -y containerd
```

### 10.2 Configuration

Create `/etc/containerd/config.toml`:

```toml
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "registry.internal.lan/google_containers/pause:3.9"
    
    [plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        endpoint = ["https://registry-1.docker.io"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."docker.io".tls]
          insecure_skip_verify_skip = false
      
      # Internal mirrors (Nexus/Harbor)
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."nexus.internal.lan"]
        endpoint = ["https://nexus.internal.lan:5000"]
      [plugins."io.containerd.grpc.v1.cri".registry.configs."nexus.internal.lan".tls]
        insecure_skip_verify = false
      
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.internal.lan"]
        endpoint = ["https://harbor.internal.lan"]
      [plugins."io.containerd.grpc.v1.cri".registry.configs."harbor.internal.lan".tls]
        insecure_skip_verify = false

    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true

[plugins."io.containerd.grpc.v1.cri".cni]
  bin_dir = "/opt/cni/bin"
  conf_dir = "/etc/cni/net.d"
```

### 10.3 Start Containerd

```bash
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
# Apply custom config above
sudo systemctl restart containerd
sudo systemctl enable containerd
```

---

## 11. AppArmor

AppArmor should be enabled and set to enforce mode per Kubernetes best practices.

```bash
# Verify AppArmor is loaded
sudo aa-status

# Ensure AppArmor is enabled at boot
sudo systemctl enable apparmor
sudo systemctl start apparmor

# Set to enforce mode
sudo aa-enforce /etc/apparmor.d/*
```

Kubernetes workloads benefit from AppArmor profiles for container isolation.

---

## 12. Auditd Configuration

### 12.1 Installation

```bash
sudo apt-get install -y auditd audispd-plugins
sudo systemctl enable auditd
```

### 12.2 Rules

Create `/etc/audit/rules.d/kubernetes.rules`:

```bash
# Delete all existing rules
-D

# Buffer size
-b 8192

# Failure mode
-f 1

# Monitor Kubernetes binaries
-w /usr/bin/kubepaddle -p wa -k kubernetes
-w /usr/bin/kubelet -p wa -k kubernetes
-w /usr/bin/kubectl -p wa -k kubernetes
-w /usr/bin/containerd -p wa -k containerd
-w /usr/bin/ctr -p wa -k containerd

# Monitor config files
-w /etc/kubernetes/ -p wa -k kubernetes-config
-w /etc/containerd/ -p wa -k containerd-config
-w /etc/cni/ -p wa -k cni-config

# Monitor authentication
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Monitor mount operations (CSI)
-w /bin/mount -p x -k mounts
-w /bin/umount -p x -k mounts

# Monitor privileged operations
-a always,exit -F arch=b64 -S setuid -S setgid -S setreuid -S setregid -k privilege_escalation
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k root_commands

# Make configuration immutable
-e 2
```

### 12.3 Restart

```bash
sudo systemctl restart auditd
```

---

## 13. Resource Limits for Kubernetes Workloads

### 13.1 System Reserved Resources

Ensure the kubelet has reserved resources configured (via kubeadm or kubelet config):

```yaml
# /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
systemReserved:
  cpu: "500m"
  memory: "512Mi"
kubeReserved:
  cpu: "500m"
  memory: "512Mi"
evictionHard:
  memory.available: "256Mi"
  nodefs.available: "10%"
```

### 13.2 Kernel-Level Limits

Ensure the following sysctl values are set:

```ini
# /etc/sysctl.d/99-kubernetes.conf (additional entries)
net.ipv4.neigh.default.gc_thresh1 = 128
net.ipv4.neigh.default.gc_thresh2 = 512
net.ipv4.neigh.default.gc_thresh3 = 1024
```

---

## 14. Verification Checklist

After completing all steps, verify:

- [ ] `free -h` shows 0 swap
- [ ] `sysctl net.ipv4.ip_forward` returns 1
- [ ] `sysctl net.bridge.bridge-nf-call-iptables` returns 1
- [ ] `lsmod | grep br_netfilter` shows module loaded
- [ ] `lsmod | grep overlay` shows module loaded
- [ ] `systemctl is-active chrony` shows active
- [ ] `systemctl is-active containerd` shows active
- [ ] `systemctl is-active auditd` shows active
- [ ] SSH key-only auth works for deploy user
- [ ] Root login is disabled
- [ ] AppArmor is in enforce mode
- [ ] DNS resolves internal services
- [ ] Container images can be pulled from internal registry

---

## References

- CIS Ubuntu 22.04 Benchmark v1.0.0
- Kubernetes Documentation: Production Environment
- containerd Documentation: Registry Configuration
