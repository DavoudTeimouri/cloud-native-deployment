# Hardware Requirements

## Table of Contents

- [Hardware Checklist](#hardware-checklist)
- [Minimum vs Recommended vs Production Specs](#minimum-vs-recommended-vs-production-specs)
- [Rack and Cabling Considerations](#rack-and-cabling-considerations)
- [Network Switch Requirements](#network-switch-requirements)
- [Cable and Interconnect Diagram](#cable-and-interconnect-diagram)
- [Firmware and BMC Requirements](#firmware-and-bmc-requirements)

---

## Hardware Checklist

### Complete Node Inventory

| Item | Quantity | Purpose | Reference |
|------|----------|---------|-----------|
| Master Nodes | 5 | Management Cluster control plane | [Server Specs - Master](server-specs.md#master-node) |
| Worker Nodes | 5 | Management Cluster workloads | [Server Specs - Worker](server-specs.md#worker-node) |
| Master Nodes | 5 | Application Cluster control plane | [Server Specs - Master](server-specs.md#master-node) |
| Worker Nodes | 5 | Application Cluster workloads | [Server Specs - Worker](server-specs.md#worker-node) |
| External LB Nodes | 4 | HAProxy + keepalived (2 per cluster) | [Server Specs - External LB](server-specs.md#external-load-balancer) |
| Operations Server (Linux) | 1 | Ansible/KubeSpray control node | [Server Specs - Ops Linux](server-specs.md#operations-server-linux) |
| Operations Server (Windows) | 1 | AD/DNS management | [Server Specs - Ops Windows](server-specs.md#operations-server-windows) |
| Nexus Server | 1 | Artifact repository | [Server Specs - Ops Linux](server-specs.md#operations-server-linux) |
| Harbor Server | 1 | Container registry | [Server Specs - Ops Linux](server-specs.md#operations-server-linux) |
| **Total Compute** | **25** | | |

### Network Equipment

| Item | Quantity | Purpose | Reference |
|------|----------|---------|-----------|
| 10GbE Switch (24-port) | 2 | Access layer (servers) | [Network Switch Requirements](#network-switch-requirements) |
| 25GbE Switch (24-port) | 2 | Ceph storage network | [Network Switch Requirements](#network-switch-requirements) |
| 100GbE Switch (32-port) | 1 | Spine/core layer | [Network Switch Requirements](#network-switch-requirements) |
| Management Switch (1GbE) | 1 | IPMI/iDRAC/iLO | [Network Switch Requirements](#network-switch-requirements) |
| Patch Panels | 4 | Cable management | [Cable and Interconnect Diagram](#cable-and-interconnect-diagram) |
| DAC Cables (10GbE) | 40 | Server to access switch | [Cable and Interconnect Diagram](#cable-and-interconnect-diagram) |
| DAC Cables (25GbE) | 20 | Ceph network | [Cable and Interconnect Diagram](#cable-and-interconnect-diagram) |
| Fiber Optic Cables (100GbE) | 8 | Spine uplinks | [Cable and Interconnect Diagram](#cable-and-interconnect-diagram) |
| Console Cable (USB-RJ45) | 25 | Out-of-band management | [Cable and Interconnect Diagram](#cable-and-interconnect-diagram) |

### Storage Per Node

| Node Type | OS Disk | Data Disk | Total Disk |
|-----------|---------|-----------|------------|
| Master | 256 GB SSD | 200 GB NVMe (etcd) | 456 GB |
| Worker | 512 GB SSD | 2x 2TB SSD (OSD) | 4.5 TB |
| External LB | 256 GB SSD | — | 256 GB |
| Operations (Linux) | 1 TB SSD | — | 1 TB |
| Operations (Windows) | 512 GB SSD | — | 512 GB |
| Nexus | 512 GB SSD | 4x 2TB SSD (RAID 10) | 8.5 TB |
| Harbor | 512 GB SSD | 4x 4TB SSD (RAID 10) | 16.5 TB |

### Total Storage Summary

| Category | Raw Capacity | Usable (RAID/Replication) |
|----------|-------------|--------------------------|
| etcd (5 masters) | 1 TB NVMe | 1 TB (no RAID) |
| Ceph OSD (Mgmt) | 10 TB SSD | ~6.6 TB (size=3) |
| Ceph OSD (App) | 10 TB SSD | ~6.6 TB (size=3) |
| Nexus | 8 TB SSD | 4 TB (RAID 10) |
| Harbor | 16 TB SSD | 8 TB (RAID 10) |
| **Total** | **45 TB** | **~26.2 TB** |

---

## Minimum vs Recommended vs Production Specs

### Master Nodes

| Component | Minimum | Recommended | Production |
|-----------|---------|-------------|------------|
| CPU | 8 cores (Intel Xeon E-2300) | 16 cores (Intel Xeon Silver 4300) | 16+ cores (Intel Xeon Gold 6300) |
| RAM | 16 GB DDR4 ECC | 32 GB DDR4 ECC | 64 GB DDR4 ECC |
| OS Disk | 100 GB SATA SSD | 256 GB NVMe SSD | 512 GB NVMe SSD (RAID 1) |
| etcd Disk | 50 GB SATA SSD | 100 GB NVMe SSD | 200 GB NVMe SSD |
| Network | 1x 10GbE | 2x 10GbE (LACP) | 2x 25GbE (LACP) |
| BMC | IPMI 2.0 | iDRAC 9 / iLO 5 | iDRAC 9 / iLO 5 with dedicated NIC |
| PSU | 1x 500W | 2x 800W (redundant) | 2x 1200W (redundant) |

### Worker Nodes

| Component | Minimum | Recommended | Production |
|-----------|---------|-------------|------------|
| CPU | 16 cores (Intel Xeon Silver) | 32 cores (Intel Xeon Gold) | 64 cores (Intel Xeon Platinum) |
| RAM | 32 GB DDR4 ECC | 64 GB DDR4 ECC | 256 GB DDR4 ECC |
| OS Disk | 256 GB SATA SSD | 512 GB NVMe SSD | 1 TB NVMe SSD (RAID 1) |
| OSD Disk | 1x 1TB HDD | 2x 2TB SSD | 4x 4TB NVMe SSD |
| Network | 1x 10GbE | 2x 25GbE (LACP) | 2x 100GbE (LACP) |
| Ceph Network | 1x 10GbE | 1x 25GbE | 2x 100GbE |
| BMC | IPMI 2.0 | iDRAC 9 / iLO 5 | iDRAC 9 / iLO 5 with dedicated NIC |
| PSU | 1x 800W | 2x 1200W (redundant) | 2x 1600W (redundant) |
| HBA | — | LSI 9300-8i (IT mode) | LSI 9400-16i (IT mode) |

### External Load Balancer Nodes

| Component | Minimum | Recommended | Production |
|-----------|---------|-------------|------------|
| CPU | 4 cores | 8 cores | 8 cores |
| RAM | 8 GB | 16 GB | 32 GB |
| Disk | 100 GB SATA SSD | 256 GB NVMe SSD | 512 GB NVMe SSD (RAID 1) |
| Network | 2x 10GbE | 2x 25GbE (LACP) | 2x 25GbE (LACP) |
| BMC | IPMI 2.0 | iDRAC 9 / iLO 5 | iDRAC 9 / iLO 5 |
| PSU | 1x 500W | 2x 800W (redundant) | 2x 800W (redundant) |

---

## Rack and Cabling Considerations

### Rack Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│ 42U Rack — Management Cluster                                       │
├─────────────────────────────────────────────────────────────────────┤
│ U42-U41  │ Patch Panel (10GbE)                                      │
│ U40-U39  │ Patch Panel (25GbE - Ceph)                               │
│ U38-U37  │ 10GbE Access Switch                                      │
│ U36-U35  │ 25GbE Switch (Ceph)                                      │
│ U34-U33  │ LB-MGMT-01, LB-MGMT-02                                   │
│ U32-U31  │ MGMT-M1, MGMT-M2                                        │
│ U30-U29  │ MGMT-M3, MGMT-M4                                        │
│ U28      │ MGMT-M5                                                  │
│ U27-U26  │ MGMT-W1, MGMT-W2                                        │
│ U25-U24  │ MGMT-W3, MGMT-W4                                        │
│ U23      │ MGMT-W5                                                  │
│ U22-U1   │ (Reserved for expansion)                                 │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ 42U Rack — Application Cluster                                      │
├─────────────────────────────────────────────────────────────────────┤
│ U42-U41  │ Patch Panel (10GbE)                                      │
│ U40-U39  │ Patch Panel (25GbE - Ceph)                               │
│ U38-U37  │ 10GbE Access Switch                                      │
│ U36-U35  │ 25GbE Switch (Ceph)                                      │
│ U34-U33  │ LB-APP-01, LB-APP-02                                     │
│ U32-U31  │ APP-M1, APP-M2                                          │
│ U30-U29  │ APP-M3, APP-M4                                          │
│ U28      │ APP-M5                                                    │
│ U27-U26  │ APP-W1, APP-W2                                          │
│ U25-U24  │ APP-W3, APP-W4                                          │
│ U23      │ APP-W5                                                    │
│ U22-U1   │ (Reserved for expansion)                                 │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ 42U Rack — Infrastructure & Operations                              │
├─────────────────────────────────────────────────────────────────────┤
│ U42-U41  │ Patch Panel (10GbE)                                      │
│ U40-U39  │ Patch Panel (1GbE - Management)                          │
│ U38-U37  │ 10GbE Access Switch                                      │
│ U36-U35  │ 1GbE Management Switch (IPMI)                            │
│ U34-U33  │ OPS-LINUX, OPS-WINDOWS                                   │
│ U32-U31  │ NEXUS, HARBOR                                            │
│ U30-U29  │ DNS-01, DNS-02                                           │
│ U28-U2   │ (Reserved for expansion)                                 │
│ U1       │ KVM / Console                                            │
└─────────────────────────────────────────────────────────────────────┘
```

### Cabling Standards

| Cable Type | Standard | Color Code | Use |
|------------|----------|------------|-----|
| 10GbE DAC | SFP+ | Yellow | Server to access switch |
| 25GbE DAC | SFP28 | Orange | Ceph network |
| 100GbE Fiber | QSFP28 | Blue | Spine/core uplinks |
| 1GbE Copper | RJ-45 | Gray | IPMI/management |
| Console | USB-RJ45 | Black | Out-of-band access |
| Power | C13/C14 | Black | PDU to server |

### Cable Management

- **Horizontal cable managers**: Between every 2U of equipment.
- **Vertical cable managers**: On both sides of the rack.
- **Labeling**: Both ends labeled with source/destination (e.g., `MGMT-W1:eno1 → SW-ACC-01:eth0/1`).
- **Bend radius**: Maintain minimum bend radius for fiber cables.
- **Cable length**: Measure precisely; use custom-length DACs where possible.

---

## Network Switch Requirements

### Access Switch (10GbE)

| Requirement | Specification |
|-------------|---------------|
| Ports | 24x 10GbE SFP+ + 4x 25GbE SFP28 (uplink) |
| Switching Capacity | ≥ 480 Gbps |
| Throughput | ≥ 357 Mpps |
| VLAN Support | 802.1Q, up to 4094 VLANs |
| LACP | 802.3ad, up to 48 groups |
| Spanning Tree | 802.1w (RSTP), 802.1s (MSTP) |
| Jumbo Frames | MTU ≥ 9216 |
| Management | SNMP v3, SSH, REST API |
| Redundancy | Dual PSU, dual fans |

### Ceph Switch (25GbE)

| Requirement | Specification |
|-------------|---------------|
| Ports | 24x 25GbE SFP28 + 4x 100GbE QSFP28 (uplink) |
| Switching Capacity | ≥ 1.2 Tbps |
| Throughput | ≥ 890 Mpps |
| VLAN Support | 802.1Q, up to 4094 VLANs |
| Flow Control | 802.1Qbb (PFC), 802.1Qaz (ETS) |
| Jumbo Frames | MTU ≥ 9216 |
| RoCE | RDMA over Converged Ethernet (optional) |
| Management | SNMP v3, SSH, REST API |
| Redundancy | Dual PSU, dual fans |

### Spine Switch (100GbE)

| Requirement | Specification |
|-------------|---------------|
| Ports | 32x 100GbE QSFP28 |
| Switching Capacity | ≥ 6.4 Tbps |
| Throughput | ≥ 4.7 Bpps |
| BGP | eBGP, iBGP, EVPN |
| VXLAN | VXLAN routing |
| ECMP | Equal-Cost Multi-Path |
| Management | SNMP v3, SSH, gNMI, REST API |
| Redundancy | Dual PSU, dual fans, dual route processors |

### Management Switch (1GbE)

| Requirement | Specification |
|-------------|---------------|
| Ports | 24x 1GbE RJ45 + 4x 10GbE SFP+ (uplink) |
| Switching Capacity | ≥ 128 Gbps |
| VLAN Support | 802.1Q |
| Management | SNMP v3, SSH, web GUI |
| Purpose | IPMI/iDRAC/iLO, KVM, console |

### Switch Configuration Example

```bash
# Access Switch VLAN Configuration (Cisco-style)
vlan 100
 name MANAGEMENT
vlan 101
 name INFRASTRUCTURE
vlan 102
 name MASTERS_MGMT
vlan 103
 name WORKERS_MGMT
vlan 104
 name MASTERS_APP
vlan 105
 name WORKERS_APP
vlan 110
 name CEPH_PUBLIC
vlan 111
 name CEPH_CLUSTER

# Trunk port to server
interface GigabitEthernet0/1
 switchport mode trunk
 switchport trunk allowed vlan 100,102,110,111
 switchport trunk native vlan 100
 mtu 9216

# Uplink to spine
interface TwentyFiveGigE0/25
 switchport mode trunk
 switchport trunk allowed vlan 100:111
 mtu 9216
```

---

## Cable and Interconnect Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              CABLE INTERCONNECT DIAGRAM                              │
│                                                                                     │
│  ┌──────────────────────┐         ┌──────────────────────┐                          │
│  │   MGMT-W1            │         │   10GbE SWITCH       │                          │
│  │                      │         │   (Access)           │                          │
│  │  eno1 ───────────────┼──DAC────┼── eth0/1             │                          │
│  │  eno2 ───────────────┼──DAC────┼── eth0/2  (LACP)     │                          │
│  │  enp3 ───────────────┼──DAC────┼── eth0/3  (Ceph Pub)  │                          │
│  │  enp4 ───────────────┼──DAC────┼── eth0/4  (Ceph Clus) │                          │
│  │  iDRAC ──────────────┼──Copper─┼── eth0/24 (Mgmt)     │                          │
│  └──────────────────────┘         └──────────┬───────────┘                          │
│                                              │                                      │
│                                              │ 100GbE Uplink                         │
│                                              │                                      │
│                                   ┌──────────┴───────────┐                          │
│                                   │   100GbE SPINE       │                          │
│                                   │   (Core)             │                          │
│                                   │                      │                          │
│                                   │  uplink to:           │                          │
│                                   │  - 10GbE Access x2   │                          │
│                                   │  - 25GbE Ceph x2     │                          │
│                                   │  - 1GbE Mgmt x1      │                          │
│                                   └──────────┬───────────┘                          │
│                                              │                                      │
│                              ┌───────────────┼───────────────┐                      │
│                              │               │               │                      │
│                   ┌──────────┴──────┐ ┌──────┴──────┐ ┌──────┴──────┐               │
│                   │  25GbE SWITCH   │ │  25GbE SWITCH│ │  1GbE SWITCH│               │
│                   │  (Ceph Public)  │ │  (Ceph Clus) │ │  (Mgmt)     │               │
│                   │                 │ │              │ │             │               │
│                   │  Ceph Public    │ │  Ceph Cluster│ │  IPMI/iDRAC │               │
│                   │  Network        │ │  Network     │ │  Network    │               │
│                   └─────────────────┘ └──────────────┘ └─────────────┘               │
│                                                                                     │
│  Cable Legend:                                                                      │
│  ───────  DAC (10GbE)                                                              │
│  ═══════  DAC (25GbE)                                                              │
│  ▬▬▬▬▬▬▬  Fiber (100GbE)                                                            │
│  ─ ─ ─ ─  Copper (1GbE)                                                            │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Firmware and BMC Requirements

### Firmware Requirements

| Component | Requirement | Verification |
|-----------|-------------|--------------|
| BIOS/UEFI | Latest stable release | `dmidecode -s bios-version` |
| BMC Firmware | Latest stable release | Vendor-specific tool |
| NIC Firmware | Latest stable release | `ethtool -i <interface>` |
| SSD Firmware | Latest stable release | `smartctl -a /dev/sda` |
| RAID Controller | Latest firmware (if used) | Vendor tool |
| TPM | 2.0 (for secure boot) | `/dev/tpm0` |

### BMC Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| BMC NIC | Dedicated (not shared) | Out-of-band management |
| BMC IP | Static, from management subnet | Reliable access |
| BMC VLAN | Dedicated management VLAN | Security isolation |
| BMC User | Individual service accounts | Audit trail |
| BMC Auth | LDAP/AD integration | Centralized auth |
| Serial Console | Enabled over SOL | Headless recovery |
| Virtual Media | Enabled | Remote OS installation |

### Pre-Deployment Firmware Checklist

```bash
#!/bin/bash
# Pre-deployment firmware verification script

echo "=== Firmware Verification ==="

# BIOS
echo "BIOS Version:"
dmidecode -s bios-version

# BMC
echo "BMC Version:"
ipmitool mc info | grep "Firmware Revision"

# NIC
echo "NIC Firmet:"
for iface in $(ls /sys/class/net/ | grep -v lo); do
    echo "  $iface: $(ethtool -i $iface | grep firmware)"
done

# SSD
echo "SSD Firmware:"
for disk in /dev/sd? /dev/nvme?n1; do
    echo "  $disk: $(smartctl -a $disk | grep Firmware)"
done

# Memory
echo "Memory:"
dmidecode -t memory | grep -E "Size|Speed|Locator"

# CPU
echo "CPU:"
lscpu | grep -E "Model name|CPU\(s\)|Thread"

echo "=== Verification Complete ==="
```

### Secure Boot Considerations

| Setting | Recommendation | Notes |
|---------|---------------|-------|
| Secure Boot | Enabled (if supported by KubeSpray) | May need custom keys |
| Boot Mode | UEFI (not Legacy/BIOS) | Required for GPT disks > 2TB |
| TPM | Enabled | For measured boot, encryption |
| Password | BIOS/UEFI password set | Prevent unauthorized boot |

---

## Power Requirements

| Node Type | Typical Power Draw | PSU Configuration |
|-----------|-------------------|-------------------|
| Master | 300-400W | 2x 800W (redundant) |
| Worker | 500-800W | 2x 1200W (redundant) |
| External LB | 200-300W | 2x 500W (redundant) |
| Operations | 300-400W | 2x 800W (redundant) |
| Nexus/Harbor | 400-600W | 2x 1000W (redundant) |
| Switch (10GbE) | 150-200W | 2x PSU |
| Switch (25GbE) | 200-300W | 2x PSU |
| Switch (100GbE) | 300-500W | 2x PSU |

### Total Power Budget

| Category | Count | Per Unit (W) | Total (W) |
|----------|-------|-------------|-----------|
| Masters | 5 | 400 | 2,000 |
| Workers (Mgmt) | 5 | 800 | 4,000 |
| Workers (App) | 5 | 800 | 4,000 |
| External LBs | 4 | 300 | 1,200 |
| Operations | 2 | 400 | 800 |
| Nexus/Harbor | 2 | 600 | 1,200 |
| Switches | 5 | 300 | 1,500 |
| **Total** | | | **14,700** |

> **Note**: Plan for 15-20 kW total capacity including cooling overhead. Use dual PDUs per rack for redundancy.
