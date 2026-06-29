# OS Preparation Guide

> Server preparation for management server and K8s nodes — time, firewall, services, updates

---

## 1. Time Configuration (Chrony)

### 1.1 Install Chrony

```bash
sudo apt-get install -y chrony
```

### 1.2 Timezone Configuration

```bash
# List available timedatectl list-timezones | grep -i "your-region"

# Set timezone (example: America/New_York, Europe/London, Asia/Tehran)
sudo timedatectl set-timezone America/New_York

# Verify
timedatectl
date
```

### 1.3 Chrony Configuration

```bash
cat > /etc/chrony/chrony.conf <<'EOF'
# ============================================================
# Chrony Configuration — Air-Gapped / Internal NTP
# ============================================================

# === Internal NTP Servers ===
# Add your local NTP servers here
server ntp1.internal.lan iburst prefer maxpoll 6
server ntp2.internal.lan iburst maxpoll 6

# === Fallback: Local clock (if NTP servers unreachable) ===
local stratum 10

# === Drift file ===
driftfile /var/lib/chrony/chrony.drift

# === Logging ===
logdir /var/log/chrony
log statistics measurements tracking

# === Access Control ===
# Allow local network to query NTP
allow 10.0.0.0/8
allow 172.16.0.0/12
allow 192.168.0.0/16

# === Performance ===
# Step the system clock if adjustment is larger than 1 second
# but only in the first three clock updates
makestep 1.0 3

# Record the rate at which the system clock gains/loses time
rtcsync

# Kernel synchronization of the real-time clock (RTC)
# Requires CONFIG_RTC_HCTOSYS=y
lock_all

# === Tuning ===
# Minimum number of sources to select
minsources 2

# Maximum skew before we start worrying
maxupdateskew 100.0

# Listen only on localhost for security
bindaddress 0.0.0.0

# Serve time even if not synchronized
# (useful during boot before NTP sync completes)
EOF
```

### 1.4 Add NTP Servers Dynamically

```bash
# Add additional NTP servers
sudo chronyc add server ntp3.internal.lan iburst

# Add public NTP (if internet available)
sudo chronyc add server 0.pool.ntp.org iburst
sudo chronyc add server 1.pool.ntp.org iburst

# Delete a server
sudo chronyc delete ntp3.internal.lan

# Check configured sources
chronyc sources -v

# Check tracking status
chronyc tracking
```

### 1.5 Verify Time Sync

```bash
# Check chrony status
sudo systemctl status chrony
chronyc tracking
chronyc sources
chronyc sourcestats

# Force immediate sync
sudo chronyc -a makestep

# Check system clock
timedatectl show
date
hwclock --show
```

---

## 2. Firewall Configuration

### 2.1 Disable UFW (K8s Nodes)

Calico manages its own iptables rules. UFW conflicts with Calico's networking.

```bash
# Disable UFW
sudo ufw disable
sudo systemctl stop ufw
sudo systemctl disable ufw

# Verify
sudo ufw status  # Should show "inactive"
```

### 2.2 Enable and Configure UFW (Management Server)

The management server **should** have a firewall since it's the entry point.

```bash
# Enable UFW
sudo ufw enable

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH from internal network only
sudo ufw allow from 10.0.0.0/8 to any port 22 proto tcp comment "SSH internal"

# Allow Cockpit (if installed)
sudo ufw allow from 10.0.0.0/8 to any port 9090 proto tcp comment "Cockpit"

# Allow HTTP/HTTPS (for reverse proxy)
sudo ufw allow 80/tcp comment "HTTP"
sudo ufw allow 443/tcp comment "HTTPS"

# Allow Kubernetes API (if this server is also a master)
sudo ufw allow 6443/tcp comment "K8s API"

# Allow specific ports for services
sudo ufw allow 8081/tcp comment "Nexus"
sudo ufw allow 5000/tcp comment "Nexus Docker"
sudo ufw allow 5043/tcp comment "Harbor"

# Rate limit SSH
sudo ufw limit ssh

# List rules with numbers
sudo ufw status numbered

# Delete a rule by number
sudo ufw delete <number>

# Reload
sudo ufw reload

# Reset to defaults
sudo ufw reset
```

### 2.3 iptables Direct (Advanced)

For K8s nodes where you need fine-grained control:

```bash
# Flush existing rules
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t mangle -F

# Default policies
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# Allow loopback
sudo iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow SSH
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow K8s ports
sudo iptables -A INPUT -p tcp --dport 6443 -j ACCEPT   # API server
sudo iptables -A INPUT -p tcp --dport 10250 -j ACCEPT  # kubelet
sudo iptables -A INPUT -p tcp --dport 10259 -j ACCEPT  # kube-scheduler
sudo iptables -A INPUT -p tcp --dport 10257 -j ACCEPT  # kube-controller-manager
sudo iptables -A INPUT -p tcp --dport 2379:2380 -j ACCEPT  # etcd
sudo iptables -A INPUT -p tcp --dport 30000:32767 -j ACCEPT  # NodePort

# Allow Calico BGP
sudo iptables -A INPUT -p tcp --dport 179 -j ACCEPT

# Drop everything else
sudo iptables -A INPUT -j DROP

# Save rules
sudo netfilter-persistent save
```

---

## 3. Service Optimization

### 3.1 Disable Unnecessary Services

```bash
# List all running services
systemctl list-units --type=service --state=running

# Disable and stop unnecessary services
sudo systemctl stop --now snapd
sudo systemctl disable snapd

sudo systemctl stop --now accounts-daemon
sudo systemctl disable accounts-daemon

sudo systemctl stop --now ModemManager
sudo systemctl disable ModemManager

sudo systemctl stop --now avahi-daemon
sudo systemctl disable avahi-daemon

sudo systemctl stop --now bluetooth
sudo systemctl disable bluetooth

sudo systemctl stop --now cups
sudo systemctl disable cups

sudo systemctl stop --now wpa_supplicant
sudo systemctl disable wpa_supplicant

# Mask so they can't be started accidentally
sudo systemctl mask snapd
sudo systemctl mask ModemManager
```

### 3.2 Optimize System Services

```bash
# Reduce journald storage
sudo mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-size.conf <<EOF
[Journal]
SystemMaxUse=500M
RuntimeMaxUse=500M
MaxFileSec=7day
EOF
sudo systemctl restart systemd-journald

# Reduce log rotation frequency
cat > /etc/logrotate.d/custom <<EOF
/var/log/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root adm
}
EOF

# Optimize tmpfiles cleanup
cat > /etc/tmpfiles.d/custom.conf <<EOF
# Clean /tmp daily
d /tmp 1777 root root 10d
d /var/tmp 1777 root root 30d
EOF
sudo systemd-tmpfiles --clean

# Disable unnecessary timers
sudo systemctl disable --now apt-daily.timer
sudo systemctl disable --now apt-daily-upgrade.timer
sudo systemctl disable --now man-db.timer
sudo systemctl disable --now locate.timer
sudo systemctl disable --now fwupd-refresh.timer
```

### 3.3 Optim I/O Scheduler

```bash
# For SSD/NVMe — use none/mq-deadline
echo 'none' | sudo tee /sys/block/sda/queue/scheduler

# For HDD — use mq-deadline
echo 'mq-deadline' | sudo tee /sys/block/sda/queue/scheduler

# Make persistent
cat > /etc/udev/rules.d/60-io-scheduler.rules <<EOF
# SSD/NVMe
ACTION=="add|change", KERNEL=="sd[a-z]|nvme[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"

# HDD
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
EOF
```

### 3.4 Optimize Network Stack

```bash
# Already in sysctl section but worth repeating for performance
cat >> /etc/sysctl.d/99-performance.conf <<EOF
# Network buffer sizes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 1048576 16777216

# TCP performance
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_fastopen = 3

# Connection tracking
net.netfilter.nf_conntrack_max = 262144
net.netfilter.nf_conntrack_tcp_timeout_established = 86400

# File descriptors
fs.file-max = 2097152
fs.nr_open = 2097152
EOF

sudo sysctl --system
```

---

## 4. System Update

### 4.1 Update Package Lists

```bash
# From Nexus (air-gap)
sudo apt-get update

# Check for available updates
apt list --upgradable

# Check security updates only
sudo apt-get upgrade -s | grep -i security
```

### 4.2 Upgrade Packages

```bash
# Standard upgrade (safe — no removals)
sudo apt-get upgrade -y

# Full upgrade (may remove packages — use with caution)
sudo apt-get dist-upgrade -y

# Upgrade specific package
sudo apt-get install --only-upgrade <package-name>
```

### 4.3 Kernel Update

```bash
# Check current kernel
uname -r

# Install latest kernel
sudo apt-get install -y linux-image-generic linux-headers-generic

# Install specific kernel version
sudo apt-get install -y linux-image-6.5.0-xx-generic linux-headers-6.5.0-xx-generic

# Remove old kernels (keep current + 1 previous)
sudo apt-get autopurge -y

# Reboot to apply kernel
sudo reboot
```

### 4.4 Update Containerd

```bash
# Check current version
containerd --version

# Update from Nexus
sudo apt-get install --only-upgrade -y containerd.io

# Restart
sudo systemctl restart containerd
```

### 4.5 Update Ceph Packages

```bash
# Check current version
ceph -v

# Update from Nexus
sudo apt-get install --only-upgrade -y ceph-common ceph-osd ceph-mon

# Restart affected services
sudo systemctl restart ceph-osd.target
```

### 4.6 Post-Update Verification

```bash
# Verify OS version
lsb_release -a
cat /etc/os-release

# Verify kernel
uname -r

# Verify all services running
systemctl is-active kubelet
systemctl is-active containerd
systemctl is-active chrony

# Verify no broken packages
sudo apt-get check

# Verify no held-back packages
apt list --upgradable

# Check for reboot requirement
if [ -f /var/run/reboot-required ]; then
    echo "REBOOT REQUIRED"
    cat /var/run/reboot-required.pkgs
fi
```

---

## 5. Ansible Playbook for OS Preparation

```yaml
---
# ansible/playbooks/os-prep-time-firewall.yml
- name: OS Preparation — Time, Firewall, Services, Update
  hosts: all
  become: true
  gather_facts: true
  vars:
    timezone: "America/New_York"
    ntp_servers:
      - ntp1.internal.lan
      - ntp2.internal.lan
    enable_ufw: false  # Set true for management server
    disable_services:
      - snapd
      - accounts-daemon
      - ModemManager
      - avahi-daemon
      - bluetooth
      - cups
    update_packages: true
    upgrade_type: "dist"  # "safe" or "dist"

  tasks:
    # === Timezone ===
    - name: Set timezone
      community.general.timezone:
        name: "{{ timezone }}"

    - name: Verify timezone
      ansible.builtin.command: timedatectl
      changed_when: false

    # === Chrony ===
    - name: Install chrony
      ansible.builtin.apt:
        name: chrony
        state: present

    - name: Configure chrony
      ansible.builtin.template:
        src: templates/chrony.conf.j2
        dest: /etc/chrony/chrony.conf
        mode: '0644'
      notify: Restart chrony

    - name: Enable and start chrony
      ansible.builtin.systemd:
        name: chrony
        state: started
        enabled: true

    # === Firewall ===
    - name: Disable UFW (K8s nodes)
      community.general.ufw:
        state: disabled
      when: not enable_ufw

    - name: Configure UFW (management server)
      when: enable_ufw
      block:
        - name: Set UFW defaults
          community.general.ufw:
            direction: "{{ item.direction }}"
            policy: "{{ item.policy }}"
          loop:
            - { direction: incoming, policy: deny }
            - { direction: outgoing, policy: allow }

        - name: Allow SSH
          community.general.ufw:
            rule: allow
            port: '22'
            proto: tcp
            src: 10.0.0.0/8

        - name: Allow HTTP/HTTPS
          community.general.ufw:
            rule: allow
            port: "{{ item }}"
            proto: tcp
          loop:
            - '80'
            - '443'

        - name: Enable UFW
          community.general.ufw:
            state: enabled

    # === Disable Services ===
    - name: Disable unnecessary services
      ansible.builtin.systemd:
        name: "{{ item }}"
        state: stopped
        enabled: false
        masked: true
      loop: "{{ disable_services }}"
      failed_when: false

    # === System Update ===
    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: yes
        cache_valid_time: 3600
      when: update_packages

    - name: Upgrade packages
      ansible.builtin.apt:
        upgrade: "{{ upgrade_type }}"
        autoremove: true
        autoclean: true
      when: update_packages

    - name: Check if reboot required
      ansible.builtin.stat:
        path: /var/run/reboot-required
      register: reboot_required

    - name: Reboot if required
      ansible.builtin.reboot:
        msg: "Rebooting for kernel update"
        connect_timeout: 5
        reboot_timeout: 300
      when: reboot_required.stat.exists

  handlers:
    - name: Restart chrony
      ansible.builtin.systemd:
        name: chrony
        state: restarted
```

### Chrony Template (`templates/chrony.conf.j2`)

```jinja2
# Chrony Configuration — Generated by Ansible
# Timezone: {{ timezone }}

{% for server in ntp_servers %}
server {{ server }} iburst prefer maxpoll 6
{% endfor %}

local stratum 10
driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
log statistics measurements tracking
makestep 1.0 3
rtcsync
lock_all
minsources 2
maxupdateskew 100.0
bindaddress 0.0.0.0
```

---

## 6. Suggestions & Best Practices

### 6.1 Time
- **Always use Chrony** over systemd-timesyncd — better for air-gap, faster sync, handles intermittent connections
- **Add at least 2 NTP servers** for redundancy
- **Use `local stratum 10`** as fallback so nodes don't drift if NTP servers are unreachable
- **Monitor clock drift** with `chronyc tracking` — if "System time" keeps jumping, investigate

### 6.2 Firewall
- **K8s nodes**: Disable UFW entirely — Calico/iptables handle everything
- **Management server**: Enable UFW with explicit allow rules
- **Never expose 22 to the public** — restrict to internal subnets
- **Use `ufw limit ssh`** to prevent brute force

### 6.3 Services
- **Disable snapd** — it runs background services and auto-updates unpredictably
- **Disable ModemManager** — irrelevant on servers, causes unnecessary CPU spikes
- **Mask services** (not just disable) to prevent accidental activation
- **Reduce journald storage** — 500M is plenty for most servers

### 6.4 Updates
- **Always `apt-get update` before installing** — stale cache causes 404s in air-gap
- **Use `dist-upgrade`** for kernel updates, `safe-upgrade` for routine updates
- **Check `/var/run/reboot-required`** after kernel updates
- **Pin critical packages** if specific versions are required:
  ```bash
  echo "kubelet hold" | sudo dpkg --set-selections
  echo "kubeadm hold" | sudo dpkg --set-selections
  ```

### 6.5 Additional Suggestions

| Area | Suggestion |
|------|-----------|
| **Kernel** | Use `linux-image-generic-hwe-22.04` for latest hardware support |
| **SSH** | Use Ed25519 keys only — `ssh-keygen -t ed25519` |
| **Logging** | Forward journald to Loki via Promtail for centralized logs |
| **Monitoring** | Install node_exporter on every node for hardware metrics |
| **Audit** | Enable auditd with K8s-specific rules for compliance |
| **Kernel modules** | Blacklist unnecessary modules: `usb-storage`, `bluetooth`, `firewire-core` |
| **cgroups** | Use cgroup v2 (default in 22.04) — required for K8s 1.24+ |
| **Unattended upgrades** | Disable in air-gap — manual control only |
