# Physical Server Customization Guide

> Vendor-specific and OS-specific configurations for bare-metal deployments

---

## 1. Dell PowerEdge

### 1.1 BIOS Settings

```
System Setup → System BIOS:
  - Processor Settings:
    - Logical Processor: Enabled (Hyper-Threading)
    - Virtualization Technology: Enabled
    - VT for Direct I/O: Enabled
  - Memory Settings:
    - Memory Operating Mode: Optimizer Mode
    - Node Interleaving: Disabled
  - SATA Settings:
    - Embedded SATA: AHCI Mode
    - Boot Mode: UEFI
  - Network Settings:
    - Enable UEFI Network Stack
    - NIC Selection: Enabled
  - System Profile Settings:
    - System Profile: Performance Optimized
    - Turbo Boost: Enabled
    - C-States: Disabled (for K8s nodes)
    - Frequency Limiting: Disabled
```

### 1.2 iDRAC Configuration

```bash
# Configure iDRAC IP
racadm set iDRAC.NIC.DHCPEnable 0
racadm set iDRAC.NIC.IPAddress 10.0.0.50
racadm set iDRAC.NIC.Netmask 255.255.255.0
racadm set iDRAC.NIC.Gateway 10.0.0.1

# Set hostname
racadm set iDRAC.NIC.DNSName node-1

# Enable IPMI
racadm set iDRAC.IPMILan.Enable Enabled

# Configure SNMP
racadm set iDRAC.SNMP.Agent Enable Enabled
racadm set iDRAC.SNMP.TrapCommunity public

# Update firmware
racadm update -f /path/to/firmware.exe
```

### 1.3 Dell Best Practices

| Setting | Recommendation | Why |
|---------|---------------|-----|
| **Boot mode** | UEFI with Secure Boot | Modern, secure |
| **Disk controller** | HBA330 (for Ceph) or PERC (for OS) | HBA for Ceph, RAID for OS |
| **Network** | 25GbE+ for storage, 10GbE for management | Performance |
| **Power** | Redundant PSU, set to max performance | Reliability |
| **Cooling** | Set to max performance in BIOS | Prevent throttling |
| **Lifecycle Controller** | Enable for remote management | iDRAC features |
| **QuickSync** | Enable for hardware monitoring | iDRAC features |

### 1.4 Dell Disk Configuration

```bash
# For Ceph OSDs (HBA mode)
racadm set BIOS.SysProfileSettings.EmbSata AhciMode

# For OS (RAID mode)
racadm set BIOS.SysProfileSettings.EmbSata RaidMode

# Create RAID 1 for OS
racadm storage.createvd:RAID.Integrated.1-1 \
  -rl r1 -wp wb -rp nra \
  -pdisk=Disk.Bay.0:Enclosure.Internal.0-1:RAID.Integrated.1-1 \
  -pdisk=Disk.Bay.1:Enclosure.Internal.0-1:RAID.Integrated.1-1

# List physical disks
racadm storage.pdisk:list
```

---

## 2. HPE ProLiant

### 2.1 BIOS Settings

```
System Configuration → BIOS/Platform Configuration (RBSU):
  - Processor Options:
    - Intel Hyper-Threading: Enabled
    - Intel Virtualization Technology: Enabled
    - Intel VT-d: Enabled
  - Virtualization Options:
    - SR-IOV: Enabled
    - ARI (Alternative Routing ID): Enabled
  - Memory Options:
    - Advanced Memory Protection: ECC Only
    - Memory Interleaving: Auto
  - Boot Options:
    - Boot Mode: UEFI Mode
    - UEFI Boot Order: Hard Drive first
  - Power and Performance:
    - Workload Profile: Custom
    - Minimum Processor Idle Power Core C-State: No C-states
    - Minimum Processor Idle Power Package C-State: No Package State
    - Intel Turbo Boost: Enabled
    - Collaborative Power Control: Disabled
```

### 2.2 iLO Configuration

```bash
# Configure iLO IP
set /map1/en1 dhcpstatus=disabled
set /map1/en1 ipaddress=10.0.0.51
set /map1/en1 subnet=255.255.255.0
set /map1/en1 gateway=10.0.0.1

# Set hostname
set /map1/dns_name=node-1

# Configure SNMP
set /map1/snmp enable=Yes
set /map1/snmp community=public

# Update firmware
hponcfg -f /path/to/firmware.bin
```

### 2.3 HPE Best Practices

| Setting | Recommendation | Why |
|---------|---------------|-----|
| **Boot mode** | UEFI Secure Boot | Modern, secure |
| **Disk controller** | HPE Smart Array (RAID for OS) | Reliability |
| **Network** | 25GbE FlexFabric | Performance + flexibility |
| **Power** | Redundant PSU, High Performance mode | Reliability |
| **Thermal** | Set fan to optimal cooling | Prevent overheating |
| **Agentless Management** | Enable for hardware monitoring | iLO features |
| **One-button SPCR** | Enable for secure erase | Data security |

### 2.4 HPE Disk Configuration

```bash
# Create RAID 1 for OS
ssacli controller slot=0 create type=ld drives=1I:1:1,1I:1:2 raid=1

# Show disk status
ssacli controller slot=0 pd all show detail

# Show logical drives
ssacli controller slot=0 ld all show detail
```

---

## 3. Lenovo ThinkSystem

### 3.1 BIOS Settings

```
UEFI Setup → System Settings:
  - Processors:
    - Hyper-Threading: Enabled
    - Intel Virtualization Technology: Enabled
    - Intel VT-d: Enabled
  - Memory:
    - Memory Speed: Max Performance
    - Memory Interleaving: Auto
  - Devices and I/O Ports:
    - Graphics: Onboard
    - SATA Mode: AHCI (for Ceph) or RAID (for OS)
  - Boot:
    - Boot Mode: UEFI
    - Secure Boot: Enabled
  - Power:
    - Platform Controlled Type: Maximum Performance
    - Intel SpeedStep: Enabled
    - Intel Turbo Boost: Enabled
```

### 3.2 XClarity Controller (XCC)

```bash
# Configure XCC IP
ipmitool -I lanplus -H <bmc-ip> -U USERID -P PASSW0RD raw 0x30 0x30 0x01 0x01

# Set hostname
ipmitool -I lanplus -H <bmc-ip> -U USERID -P PASSW0RD raw 0x30 0x30 0x02 0x01

# Update firmware
# Use Lenovo XClarity Essentials
```

### 3.3 Lenovo Best Practices

| Setting | Recommendation | Why |
|---------|---------------|-----|
| **Boot mode** | UEFI Secure Boot | Modern, secure |
| **Disk controller** | Intel RSTe (RAID for OS) | Reliability |
| **Network** | 25GbE for storage | Performance |
| **Power** | Redundant PSU, Maximum Performance | Reliability |
| **XClarity** | Enable for remote management | BMC features |
| **RAID** | RAID 1 for OS, JBOD for Ceph | Best of both |

---

## 4. Ubuntu Server (All Vendors)

### 4.1 Installation Configuration

```bash
# Preseed file for automated install
# /var/www/html/preseed.cfg
d-i debian-installer/locale string en_US.UTF-8
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string node-1
d-i netcfg/get_domain string internal.lan
d-i mirror/http/hostname string archive.ubuntu.com
d-i mirror/http/directory string /ubuntu
d-i mirror/http/proxy string
d-i clock-setup/utc boolean true
d-i time/zone string UTC
d-i partman-auto/method string lvm
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-auto-lvm/guided_size string max
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_write_new_label boolean true
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
d-i passwd/root-login boolean false
d-i passwd/user-fullname string Deploy User
d-i passwd/username string deploy
d-i passwd/user-password-crypted string $6$rounds=4096$...
d-i apt-setup/non-free boolean true
d-i apt-setup/contrib boolean true
d-i pkgsel/include string openssh-server chrony htop vim
d-i pkgsel/update-policy select unattended-upgrades
d-i finish-install/reboot_in_progress note
```

### 4.2 Ubuntu Post-Install

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install essential packages
sudo apt-get install -y \
  curl wget gnupg2 software-properties-common \
  apt-transport-https ca-certificates lsb-release \
  bash-completion vim htop tmux git jq tree \
  unzip zip net-tools dnsutils iputils-ping \
  tcpdump strace rsync chrony auditd apparmor \
  apparmor-utils fail2ban

# Configure NTP
sudo systemctl enable chrony
sudo systemctl start chrony

# Configure auditd
sudo systemctl enable auditd
sudo systemctl start auditd

# Configure fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Disable unnecessary services
sudo systemctl disable --now snapd
sudo systemctl disable --now ModemManager
sudo systemctl disable --now avahi-daemon
sudo systemctl disable --now cups
sudo systemctl disable --now bluetooth
```

### 4.3 Ubuntu Kernel Parameters

```bash
# /etc/sysctl.d/99-kubernetes-hardening.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-arptables = 1
net.netfilter.nf_conntrack_max = 262144
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.overcommit_memory = 1
vm.panic_on_oom = 0
kernel.panic = 10
kernel.panic_on_oops = 1
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.perf_event_paranoid = 3
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1

sudo sysctl --system
```

---

## 5. Rocky Linux / RHEL

### 5.1 Installation Configuration

```bash
# Kickstart file for automated install
# /var/www/html/ks.cfg
lang en_US.UTF-8
keyboard us
timezone UTC --utc
rootpw --iscrypted $6$rounds=4096$...
user --name=deploy --iscrypted --password=$6$rounds=4096$...
clearpart --all --initlabel
autopart --type=lvm
bootloader --location=mbr
zerombr
firewall --enabled --ssh
selinux --enforcing
firstboot --disable
poweroff

%packages
@core
chronie
vim
htop
git
curl
wget
net-tools
bind-utils
tcpdump
strace
audit
fail2ban-server
%end

%post
systemctl enable chronyd
systemctl enable auditd
systemctl enable fail2ban
systemctl disable kdump
%end
```

### 5.2 Rocky/RHEL Post-Install

```bash
# Update system
sudo dnf update -y

# Install essential packages
sudo dnf install -y \
  curl wget gnupg2 vim htop tmux git jq tree \
  net-tools bind-utils tcpdump strace \
  chronie audit fail2ban-server \
  bash-completion

# Configure NTP
sudo systemctl enable chronyd
sudo systemctl start chronyd

# Configure SELinux
sudo setenforce 1
sudo sed -i 's/SELINUX=permissive/SELINUX=enforcing/' /etc/selinux/config

# Configure firewall
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=2379-2380/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=10259/tcp
sudo firewall-cmd --permanent --add-port=30000-32767/tcp
sudo firewall-cmd --permanent --add-port=179/tcp
sudo firewall-cmd --reload

# Disable unnecessary services
sudo systemctl disable --now kdump
sudo systemctl disable --now avahi-daemon
sudo systemctl disable --now cups
```

### 5.3 Rocky/RHEL Kernel Parameters

```bash
# /etc/sysctl.d/99-kubernetes-hardening.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-arptables = 1
net.netfilter.nf_conntrack_max = 262144
net.core.somaxconn = 65535
vm.overcommit_memory = 1
kernel.panic = 10
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288

sudo sysctl --system
```

---

## 6. Oracle Linux

### 6.1 Installation Configuration

```bash
# Kickstart for Oracle Linux
# Similar to Rocky but with Oracle-specific packages
lang en_US.UTF-8
keyboard us
timezone UTC --utc
rootpw --iscrypted $6$rounds=4096$...
user --name=deploy --iscrypted --password=$6$rounds=4096$...
clearpart --all --initlabel
autopart --type=lvm
bootloader --location=mbr
firewall --enabled --ssh
selinux --enforcing

%packages
@core
chronie
vim
htop
git
curl
wget
net-tools
bind-utils
tcpdump
strace
audit
%end
```

### 6.2 Oracle Linux Post-Install

```bash
# Update
sudo dnf update -y

# Install UEK kernel (if needed)
sudo dnf install -y kernel-uek

# Configure NTP
sudo systemctl enable chronyd

# Configure SELinux
sudo setenforce 1

# Configure firewall
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --reload
```

---

## 7. Physical Server Best Practices

### 7.1 Hardware Checklist

| Component | Recommendation |
|-----------|---------------|
| **CPU** | Enable virtualization extensions (VT-x, VT-d) |
| **Memory** | ECC RAM, enable memory mirroring for critical nodes |
| **Disk controller** | Battery-backed cache, RAID 1 for OS |
| **Network** | Dual NIC, bonded (LACP), separate storage network |
| **Power** | Dual PSU, separate power circuits |
| **BMC** | Dedicated BMC NIC, latest firmware |
| **Boot** | UEFI Secure Boot enabled |

### 7.2 Firmware Update Procedures

```bash
# Dell
racadm update -f /path/to/firmware.exe

# HPE
hponcfg -f /path/to/firmware.bin

# Lenovo
# Use Lenovo XClarity Essentials or OneCLI

# Generic (Linux)
# Use fwupd
fwupdmgr refresh
fwupdmgr update
```

### 7.3 IPMI/BMC Security

```bash
# Change default password
ipmitool -I lanplus -H <bmc-ip> -U admin -P admin user set password 2 <new-password>

# Enable IPMI encryption
ipmitool -I lanplus -H <bmc-ip> -U admin -P <pass> raw 0x30 0x30 0x01 0x01

# Restrict IPMI to dedicated network
ipmitool -I lanplus -H <bmc-ip> -U admin -P <pass> lan set 1 ipsrc static
ipmitool -I lanplus -H <bmc-ip> -U admin -P <pass> lan set 1 ipaddr 10.0.100.50
ipmitool -I lanplus -H <bmc-ip> -U admin -P <pass> lan set 1 netmask 255.255.255.0
```

### 7.4 Disk Layout

| Partition | Size | Type | Purpose |
|-----------|------|------|---------|
| **/boot** | 1 GB | EFI | Boot loader |
| **/boot/efi** | 512 MB | FAT32 | EFI partition |
| **/ (root)** | 50 GB | ext4/xfs | OS |
| **/var** | 100 GB | ext4/xfs | Logs, containers |
| **/var/lib/etcd** | 50 GB | ext4/xfs | etcd (masters only) |
| **swap** | 0 | — | Disabled for K8s |

### 7.5 Network Bonding

```bash
# /etc/netplan/01-bond.yaml
network:
  version: 2
  ethernets:
    enp1s0: {}
    enp2s0: {}
  bonds:
    bond0:
      addresses: [10.0.0.20/24]
      routes:
        - to: default
          via: 10.0.0.1
      nameservers:
        addresses: [10.0.0.2, 10.0.0.3]
      interfaces: [enp1s0, enp2s0]
      parameters:
        mode: 802.3ad
        transmit-hash-policy: layer3+4
        mii-monitor-interval: 100ms
        lacp-rate: fast
        min-links: 1
```

### 7.6 RAID Configuration

```bash
# RAID 1 for OS (mdadm)
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sda /dev/sdb
sudo mkfs.xfs /dev/md0
sudo mount /dev/md0 /

# RAID 10 for Ceph (if not using Ceph's replication)
sudo mdadm --create /dev/md1 --level=10 --raid-devices=4 /dev/sd[cdef]
```

---

## 8. Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `server_vendor` | `dell` | dell, hpe, lenovo, generic |
| `bmc_ip` | — | BMC/IPMI/iLO/iDRAC IP |
| `bmc_user` | `admin` | BMC username |
| `bmc_pass` | — | BMC password |
| `os_boot_mode` | `uefi` | uefi or bios |
| `os_secure_boot` | `true` | Enable Secure Boot |
| `os_selinux` | `enforcing` | enforcing, permissive, disabled |
| `disk_controller_mode` | `ahci` | ahci, raid, hba |
| `network_bond_mode` | `802.3ad` | 802.3ad, active-backup, balance-rr |
| `ntp_servers` | `10.0.0.2, 10.0.0.3` | NTP server IPs |
| `dns_servers` | `10.0.0.2, 10.0.0.3` | DNS server IPs |
| `timezone` | `UTC` | Server timezone |
| `deploy_user` | `deploy` | SSH deploy user |
