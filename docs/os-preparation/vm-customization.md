# VM Customization Guide

> Hypervisor-specific best practices and configurations for virtual machines

---

## 1. Proxmox VE

### 1.1 VM Template Setup

```bash
# Create a cloud-init template
qm create 9000 --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 /path/to/ubuntu-22.04-server-cloudimg-amd64.img local-lvm
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot c --scsi0
qm set 9000 --agent enabled=1
qm set 9000 --ipconfig0 ip=dhcp
qm set 9000 --ciuser deploy --cipassword ***
qm set 9000 --sshkeys ~/.ssh/id_ed25519.pub
qm template 9000

# Clone from template
qm clone 9000 101 --name master-1
qm set 101 --ipconfig0 ip=10.0.0.11/24,gw=10.0.0.1
qm set 101 --memory 8192 --cores 4
qm start 101
```

### 1.2 Proxmox Best Practices

| Setting | Recommendation | Why |
|---------|---------------|-----|
| **CPU type** | `host` or `x86-64-v3` | Best performance for K8s |
| **Machine type** | `q35` | PCIe support, better performance |
| **Disk controller** | `VirtIO SCSI` | Best disk performance |
| **Network** | `VirtIO` | Best network performance |
| **Ballooning** | Disable for K8s nodes | Prevent memory pressure |
| **QEMU Agent** | Enable | Better host-guest integration |
| **Cloud-Init** | Use for initial setup | Automated provisioning |
| **Storage** | Use SSD/NVMe pool for K8s | etcd is I/O sensitive |
| **Backup** | Schedule VM snapshots | Disaster recovery |
| **HA** | Enable HA for master VMs | Automatic failover |

### 1.3 Proxmox Network Configuration

```bash
# /etc/network/interfaces (Proxmox host)
auto eno1
iface eno1 inet manual

auto vmbr0
iface vmbr0 inet static
    address 10.0.0.2/24
    gateway 10.0.0.1
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0

# For VLANs
auto vmbr0.100
iface vmbr0.100 inet static
    address 10.0.100.2/24
```

### 1.4 Proxmox Firewall

```bash
# /etc/pve/firewall/cluster.fw
[OPTIONS]
enable: 1

[IN]
ACCEPT -p tcp -dport 22
ACCEPT -p tcp -dport 6443
ACCEPT -p tcp -dport 2379:2380
ACCEPT -p tcp -dport 10250:10259
ACCEPT -p tcp -dport 30000:32767
ACCEPT -p tcp -dport 8443
ACCEPT -p tcp -dport 9090
ACCEPT -p tcp -dport 443
ACCEPT -p tcp -dport 80
```

---

## 2. VMware vSphere

### 2.1 VM Configuration

```bash
# Using govc (CLI)
govc vm.create \
  -m 8192 \
  -c 4 \
  -disk 100G \
  -net "VM Network" \
  -g ubuntu-64 \
  -firmware efi \
  master-1

# Set cloud-init data
govc vm.change -vm master-1 \
  -e "guestinfo.metadata.encoding=base64" \
  -e "guestinfo.userdata.encoding=base64"

# Power on
govc vm.power -on master-1
```

### 2.2 VMware Best Practices

| Setting | Recommendation | Why |
|---------|---------------|-----|
| **Hardware version** | 19+ | Latest features |
| **Disk controller** | VMware Paravirtual | Best disk performance |
| **Network** | VMXNET3 | Best network performance |
| **Firmware** | EFI | Modern, secure |
| **CPU** | Hot-add enabled | Scale without downtime |
| **Memory** | Reserve all | Prevent ballooning |
| **NUMA** | Align with physical | Better performance |
| **Disks** | Thick provision eager zeroed | Best performance |
| **Snapshots** | Delete after 72h | Performance impact |
| **VMware Tools** | Install latest | Better integration |

### 2.3 VMware Storage

| Storage Type | Use Case | Performance |
|-------------|----------|-------------|
| **vSAN** | Hyper-converged | High |
| **NVMe over Fabrics** | High-performance | Highest |
| **FC/iSCSI** | Traditional SAN | High |
| **NFS** | Shared storage | Medium |

### 2.4 VMware Networking

| Network Type | Use Case |
|-------------|----------|
| **Standard vSwitch** | Simple, single host |
| **Distributed vSwitch** | Multi-host, advanced features |
| **NSX-T** | Micro-segmentation, advanced |

---

## 3. KVM/libvirt

### 3.1 VM Creation with virt-install

```bash
# Create a KVM VM
sudo virt-install \
  --name master-1 \
  --ram 8192 \
  --vcpus 4 \
  --disk path=/var/lib/libvirt/images/master-1.qcow2,size=100,format=qcow2 \
  --os-variant ubuntu22.04 \
  --network bridge=br0,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --location 'http://archive.ubuntu.com/ubuntu/dists/noble/main/installer-amd64/' \
  --extra-args 'console=ttyS0,115200n8 serial'

# Cloud-init ISO
sudo cloud-localds /var/lib/libvirt/images/master-1-seed.img cloud-init.iso
```

### 3.2 KVM Best Practices

| Setting | Recommendation | Why |
|---------|---------------|-----|
| **Disk format** | `qcow2` with `lazy_refcounts` | Snapshots, thin provisioning |
| **Cache mode** | `none` or `writethrough` | Data integrity |
| **I/O scheduler** | `none` or `mq-deadline` | Best for VMs |
| **CPU mode** | `host-passthrough` | Best performance |
| **CPU pinning** | Pin to physical cores | Predictable performance |
| **Hugepages** | Enable for K8s nodes | Better memory performance |
| **NUMA** | Match physical topology | Better performance |
| **VirtIO** | Use for all devices | Best paravirtualized performance |
| **Bridge** | Linux bridge or OVS | Flexible networking |

### 3.3 KVM Tuning

```bash
# Enable hugepages
echo 4096 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# CPU pinning (pin vCPU 0-3 to physical CPU 0-3)
virsh vcpupin master-1 0 0
virsh vcpupin master-1 1 1
virsh vcpupin master-1 2 2
virsh vcpupin master-1 3 3

# Set I/O scheduler for VM disks
virsh blkdeviotune master-1 --total-iops-sec 10000

# Memory backing
# In XML:
# <memoryBacking>
#   <hugepages/>
#   <locked/>
# </memoryBacking>
```

### 3.4 KVM Networking

```bash
# /etc/netplan/01-kvm-br0.yaml
network:
  version: 2
  ethernets:
    enp1s0: {}
  bridges:
    br0:
      addresses: [10.0.0.2/24]
      interfaces: [enp1s0]
      parameters:
        stp: false
        forward-delay: 0
```

---

## 4. Hyper-V

### 4.1 VM Creation

```powershell
# Create VM
New-VM -Name master-1 -MemoryStartupBytes 8GB -Generation 2 `
  -NewVHDPath "C:\VMs\master-1.vhdx" -NewVHDSizeBytes 100GB `
  -SwitchName "External Switch"

# Configure
Set-VMProcessor master-1 -Count 4
Set-VMMemory master-1 -DynamicMemoryEnabled $true `
  -MinimumBytes 4GB -MaximumBytes 16GB
Enable-VMIntegrationService -Name "Guest Service Interface" -VM master-1

# Start
Start-VM master-1
```

### 4.2 Hyper-V Best Practices

| Setting | Recommendation | Why |
|---------|---------------|-----|
| **Generation** | Generation 2 | UEFI, Secure Boot |
| **Disk** | VHDX, fixed size | Best performance |
| **Memory** | Dynamic with min/max | Flexibility + guarantee |
| **Network** | Synthetic adapter | Best performance |
| **Checkpoint** | Production only | Standard checkpoints impact performance |
| **Replication** | Enable for DR | Disaster recovery |
| **NUMA** | Enable NUMA spanning | Large VMs |

---

## 5. General VM Best Practices for Kubernetes

### 5.1 Resource Allocation

| Resource | Master Node | Worker Node | etcd Node |
|----------|------------|-------------|-----------|
| **CPU** | 4 cores | 8+ cores | 4 cores |
| **RAM** | 8 GB | 16+ GB | 8 GB |
| **System disk** | 100 GB SSD | 100 GB SSD | 100 GB SSD |
| **etcd disk** | — | — | 50 GB NVMe |
| **Pod disk** | — | 200+ GB | — |

### 5.2 VM Settings Checklist

- [ ] Disable memory ballooning for K8s nodes
- [ ] Reserve 100% of memory for K8s nodes
- [ ] Use paravirtualized network adapters (VirtIO/VMXNET3)
- [ ] Use paravirtualized disk controllers (VirtIO SCSI/PVSCSI)
- [ ] Disable snapshots during production
- [ ] Enable NTP sync in VM
- [ ] Disable screen saver / power management
- [ ] Set disk to "independent-persistent" if using snapshots
- [ ] Enable QEMU guest agent / VMware Tools / Hyper-V Integration Services
- [ ] Configure cloud-init for first-boot automation

### 5.3 VM Backup Strategy

| Strategy | RPO | Method |
|----------|-----|--------|
| **VM snapshots** | Hours | Hypervisor snapshot |
| **VM replication** | Minutes | Hypervisor replication |
| **File-level backup** | Hours | Agent inside VM |
| **etcd backup** | Minutes | Velero + etcdctl |
| **Storage replication** | Seconds | Ceph/Storage replication |
