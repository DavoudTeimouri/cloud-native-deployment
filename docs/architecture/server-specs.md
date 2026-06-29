# Server Specifications

## Table of Contents

- [Master Node](#master-node)
- [Worker Node](#worker-node)
- [External Load Balancer](#external-load-balancer)
- [Ceph Monitor Node](#ceph-monitor-node)
- [Ceph OSD Node](#ceph-osd-node)
- [Operations Server (Linux)](#operations-server-linux)
- [Operations Server (Windows)](#operations-server-windows)
- [Network Requirements](#network-requirements)
- [Scaling Guidance](#scaling-guidance)

---

## Master Node

Master nodes run the Kubernetes control plane components (kube-apiserver, kube-scheduler, kube-controller-manager, etcd).

### Specifications

| Component | Minimum | Recommended | Enterprise |
|-----------|---------|-------------|------------|
| **CPU** | 8 cores | 16 cores | 16+ cores |
| **RAM** | 16 GB | 32 GB | 64 GB |
| **OS Disk** | 100 GB SSD | 256 GB SSD | 512 GB SSD (RAID 1) |
| **etcd Disk** | 50 GB SSD | 100 GB NVMe | 200 GB NVMe (dedicated) |
| **Network** | 10 GbE | 10 GbE (bonded) | 25 GbE (bonded) |
| **NIC** | 1x 10GbE | 2x 10GbE (LACP) | 2x 25GbE (LACP) |

### Disk Layout

```bash
# Master node disk partitioning scheme
# /dev/sda - OS Disk (256 GB SSD)
/dev/sda1  - 1GB    - /boot          (EFI system partition)
/dev/sda2  - 50GB   - /              (root filesystem)
/dev/sda3  - 200GB  - /var/log       (logs, audit)

# /dev/nvme0n1 - etcd Disk (200 GB NVMe, dedicated)
/dev/nvme0n1p1 - 200GB - /var/lib/etcd   (etcd data)
```

### Configuration Notes

- **etcd**: MUST be on dedicated SSD/NVMe. High IOPS is critical for cluster performance.
- **Swap**: Disabled (`swapoff -a`, remove from `/etc/fstab`).
- **Kernel**: Linux 5.x with `overlay` and `br_netfilter` modules enabled.
- **BIOS**: Enable VT-x, VT-d. Set performance governor to `performance`.

---

## Worker Node

Worker nodes run application workloads, platform services, and Ceph OSDs.

### Specifications

| Component | Minimum | Recommended | Enterprise |
|-----------|---------|-------------|------------|
| **CPU** | 16 cores | 32 cores | 64 cores |
| **RAM** | 32 GB | 64 GB | 256 GB |
| **OS Disk** | 256 GB SSD | 512 GB SSD | 1 TB NVMe (RAID 1) |
| **OSD Disk** | 1x 1TB HDD | 2x 2TB SSD | 4x 4TB NVMe |
| **Network** | 10 GbE | 2x 10GbE (bonded) | 2x 25GbE (bonded) |
| **NIC** | 1x 10GbE | 2x 10GbE + 1x 25GbE (Ceph) | Multiple bonded |

### Disk Layout

```bash
# Worker node disk partitioning scheme
# /dev/sda - OS Disk (512 GB SSD)
/dev/sda1  - 1GB    - /boot
/dev/sda2  - 50GB   - /
/dev/sda3  - 460GB  - /var/lib/containerd  (container images)

# /dev/nvme0n1 - Ceph OSD (2TB SSD, dedicated)
/dev/nvme0n1p1 - 2TB - /var/lib/ceph/osd/0  (BlueStore OSD)

# /dev/nvme1n1 - Ceph OSD (2TB SSD, dedicated)
/dev/nvme1n1p1 - 2TB - /var/lib/ceph/osd/1  (BlueStore OSD)
```

### Configuration Notes

- **containerd**: Uses overlayfs snapshotter.
- **Ceph OSD**: One OSD per physical disk (do not share disks).
- **NUMA**: Consider NUMA affinity for Ceph OSDs on large servers.
- **HDD vs SSD**: SSDs strongly recommended for OSDs; use `bluestore` with `block.db` / `block.wal` on SSD if data is on HDD.

---

## External Load Balancer

External load balancer nodes run HAProxy + keepalived for K8s API HA and service load balancing.

### Specifications

| Component | Minimum | Recommended | Enterprise |
|-----------|---------|-------------|------------|
| **CPU** | 4 cores | 8 cores | 8 cores |
| **RAM** | 8 GB | 16 GB | 32 GB |
| **Disk** | 100 GB SSD | 256 GB SSD | 512 GB SSD (RAID 1) |
| **Network** | 2x 10 GbE | 2x 10 GbE (bonded) | 2x 25GbE (bonded) |
| **NIC** | 2x 10GbE | 2x 10GbE (LACP) | 2x 25GbE (LACP) |

### Configuration Notes

- **keepalived**: VRRP between LB pairs for VIP failover.
- **HAProxy**: Run in `mode tcp` for K8s API, `mode http` for SNI-based routing.
- **Monitoring**: HAProxy stats socket or Prometheus exporter.
- **Bonding**: Use 802.3ad (LACP) for NIC bonding.

---

## Ceph Monitor Node

Ceph Monitor nodes maintain cluster state and quorum. If co-located on master/worker nodes, use the same specs.

### Specifications

| Component | Minimum | Recommended | Enterprise |
|-----------|---------|-------------|------------|
| **CPU** | 4 cores | 8 cores | 8 cores |
| **RAM** | 8 GB | 16 GB | 32 GB |
| **Disk (OS)** | 100 GB SSD | 256 GB SSD | 512 GB SSD |
| **Disk (RocksDB/WAL)** | 50 GB SSD | 100 GB NVMe | 200 GB NVMe |
| **Network** | 10 GbE | 2x 10GbE | 2x 25GbE |

### Configuration Notes

- **RocksDB**: Ceph MON stores metadata in RocksDB. Low-latency storage is critical.
- **WAL**: RocksDB write-ahead log should be on the fastest available storage.
- **No LB**: Ceph MONs do NOT use a load balancer. Clients connect directly.
- **Minimum 3 MONs**: For quorum. 5 recommended for production environments.

---

## Ceph OSD Node

Ceph OSD nodes store data. Often co-located with worker nodes.

### Specifications

| Component | Minimum | Recommended | Enterprise |
|-----------|---------|-------------|------------|
| **CPU** | 8 cores | 16 cores | 32 cores |
| **RAM** | 16 GB | 32 GB | 128 GB |
| **Disk (OS)** | 100 GB SSD | 256 GB SSD | 512 GB SSD |
| **Disk (OSD)** | 1x 1TB | 2x 2TB SSD | 4x 4TB NVMe |
| **Disk (DB/WAL)** | SSD partition | Dedicated SSD | Dedicated NVMe |
| **Network** | 10 GbE | 2x 25GbE | 2x 100GbE |
| **Network (Cluster)** | 10 GbE | 25 GbE | 100 GbE |

### Configuration Notes

- **BlueStore**: Default Ceph OSD backend (replacing FileStore).
- **OSD Count**: One BlueStore OSD per physical disk.
- **DB/WAL**: If using HDDs for data, place DB and WAL on SSD partitions.
- **Recovery**: Limit recovery/backfill bandwidth to avoid impacting workloads.

### Ceph OSD Tuning

```ini
# /etc/ceph/ceph.conf OSD section
[osd]
osd_op_threads = 8
osd_disk_threads = 4
osd_max_object_name_len = 256
osd_max_object_namespace_len = 64

# BlueStore tuning
bluestore_cache_size_ssd = 3221225472  # 3GB for SSD
bluestore_cache_size_hdd = 1073741824  # 1GB for HDD
bluestore_cache_meta_ratio = 0.4
bluestore_cache_kv_ratio = 0.4
```

---

## Operations Server (Linux)

The Linux operations server serves as the Ansible/KubeSpray control node.

### Specifications

| Component | Minimum | Recommended | Enterprise |
|-----------|---------|-------------|------------|
| **CPU** | 8 cores | 16 cores | 32 cores |
| **RAM** | 16 GB | 32 GB | 64 GB |
| **Disk** | 500 GB SSD | 1 TB SSD | 2 TB NVMe |
| **Network** | 10 GbE | 10 GbE | 25 GbE |
| **OS** | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |

### Installed Software

| Software | Version | Purpose |
|----------|---------|---------|
| Ansible | $ANSIBLE_VERSION | Configuration management |
| KubeSpray | $KUBESPRAY_VERSION | Kubernetes deployment |
| kubectl | $K8S_VERSION | Kubernetes CLI |
| helm | $HELM_VERSION | Helm package manager |
| Ceph-common | $CEPH_VERSION | Ceph CLI tools |
| Python 3.x | 3.10+ | KubeSpray dependencies |
| Git | 2.x | Version control |
| jq | 1.6+ | JSON processing |
| rclone | 1.62+ | Artifact sync (for air-gap) |
| Docker/podman | latest | Container build (for air-gap) |

---

## Operations Server (Windows)

The Windows operations server manages Active Directory, Windows DNS, and Windows workloads.

### Specifications

| Component | Minimum | Recommended | Enterprise |
|-----------|---------|-------------|------------|
| **CPU** | 4 cores | 8 cores | 16 cores |
| **RAM** | 8 GB | 16 GB | 32 GB |
| **Disk** | 256 GB SSD | 512 GB SSD | 1 TB SSD |
| **Network** | 10 GbE | 10 GbE | 25 GbE |
| **OS** | Windows Server 2019 | Windows Server 2022 | Windows Server 2022 |

### Installed Software

| Software | Version | Purpose |
|----------|---------|---------|
| Active Directory Domain Services | 2022 | Identity management |
| DNS Server | 2022 | Internal DNS |
| RSAT Tools | 2022 | Remote admin |
| PowerShell | 7.x | Scripting |
| kubectl | $K8S_VERSION | Kubernetes CLI |
| Windows Admin Center | latest | Server management |

---

## Network Requirements

### Minimum Network Requirements

| Role | Bandwidth | NIC Configuration |
|------|-----------|-------------------|
| Master | 10 GbE | 1x 10GbE |
| Worker | 10 GbE | 1x 10GbE minimum |
| External LB | 10 GbE | 2x 10GbE (bonded) |
| Ceph MON | 10 GbE | 1x 10GbE |
| Ceph OSD | 10 GbE | 2x NICs (public + cluster) |
| Operations | 10 GbE | 1x 10GbE |

### Recommended Network Requirements

| Role | Bandwidth | NIC Configuration |
|------|-----------|-------------------|
| Master | 10 GbE | 2x 10GbE (LACP) |
| Worker | 25 GbE | 2x 25GbE (LACP) |
| External LB | 25 GbE | 2x 25GbE (LACP) |
| Ceph MON | 25 GbE | 2x 25GbE (LACP) |
| Ceph OSD | 100 GbE | 2x 100GbE (public + cluster) |
| Operations | 10 GbE | 1x 10GbE |

### NIC Bonding Configuration

```bash
# /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    eno1:
      dhcp4: false
    eno2:
      dhcp4: false
  bonds:
    bond0:
      addresses:
        - 10.0.3.11/24
      routes:
        - to: default
          via: 10.0.3.1
      interfaces:
        - eno1
        - eno2
      parameters:
        mode: 802.3ad
        transmit-hash-policy: layer3+4
        mii-monitor-interval: 100ms
      lacp-rate: fast
```

---

## Scaling Guidance

### Minimum Deployment

| Role | Count | Notes |
|------|-------|-------|
| Masters | 3 | Minimum for etcd quorum |
| Workers | 3 | Minimum for workload distribution |
| External LBs | 2 | Required for VIP HA |
| Ceph MONs | 3 | Minimum for quorum |
| Ceph OSDs | 3 | Minimum for size=3 replication |

### Recommended Deployment

| Role | Count | Notes |
|------|-------|-------|
| Masters | 5 | Enhanced HA, rolling upgrades |
| Workers | 5 | Good resource availability |
| External LBs | 2 | Required for VIP HA |
| Ceph MONs | 5 | Enhanced HA |
| Ceph OSDs | 5 | Good capacity and redundancy |

### Enterprise Deployment

| Role | Count | Notes |
|------|-------|-------|
| Masters | 5-7 | Large-scale, multi-region |
| Workers | 10-50+ | Based on workload demand |
| External LBs | 2-4 | Per-region or per-cluster |
| Ceph MONs | 5-7 | Large cluster support |
| Ceph OSDs | 10-100+ | Based on storage demand |

### Scaling Triggers

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU utilization | > 70% sustained | Add worker nodes |
| RAM utilization | > 80% sustained | Add worker nodes |
| Ceph capacity | > 80% | Add OSD nodes |
| Ceph IOPS | > disk limits | Add OSDs or upgrade disks |
| Network bandwidth | > 70% link capacity | Upgrade NICs or add bonds |
| Pod count per node | > 110 (default) | Add worker nodes or increase maxPods |

### Node Sizing Formulas

```
# Master nodes: based on number of total nodes
masters = max(3, ceil(total_nodes / 50))

# Worker nodes: based on workload demand
workers = ceil(total_cpu_needed / cpu_per_worker) + ceil(total_ram_needed / ram_per_worker)

# Ceph OSDs: based on storage capacity
osds = ceil(total_storage_tb / osd_disk_tb)

# Ceph MONs: based on cluster size
mons = 3 if osds < 50 else 5 if osds < 200 else 7
```
