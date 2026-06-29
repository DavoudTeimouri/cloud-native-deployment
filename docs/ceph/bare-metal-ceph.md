# Bare-Metal Ceph Deployment Guide (cephadm)

## Overview

This guide covers the deployment of a production-grade Ceph cluster on bare-metal Ubuntu 22.04 nodes using **cephadm**. The cluster follows a 5 monitor (MON) + 5 OSD architecture with network separation between public and cluster traffic.

**Ceph Version:** `$CEPH_VERSION` (Reef)  
**Operating System:** Ubuntu 22.04 LTS  
**Environment:** Air-gapped (all packages from internal Nexus, no internet access)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Management Network                          │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ │
│  │  MON 1  │ │  MON 2  │ │  MON 3  │ │  MON 4  │ │  MON 5  │ │
│  │  MGR 1★ │ │  MGR 2  │ │         │ │         │ │         │ │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘ │
│                                                                 │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ │
│  │  OSD 1  │ │  OSD 2  │ │  OSD 3  │ │  OSD 4  │ │  OSD 5  │ │
│  │ WAL/DB  │ │ WAL/DB  │ │ WAL/DB  │ │ WAL/DB  │ │ WAL/DB  │ │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘ │
│                     Cluster Network                             │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

| Decision | Value | Rationale |
|----------|-------|-----------|
| MONs | 5 | Tolerate 2 failures (quorum = 3) |
| OSDs | 5 | Balanced PG distribution |
| Replication | size=3, min_size=2 | N+2 durability |
| PG Target | 100-150 per OSD | Recommended range for Reef |
| CephFS | 2 pools (metadata+data) | Separate performance tiers |
| OSD backend | BlueStore | Default and recommended |
| Network | Dual NIC separation | Security + performance |

---

## Prerequisites

### 1. Air-Gap Repository Setup

All Ceph packages must be sourced from the internal Nexus repository.

```bash
# Configure Nexus apt repository
cat <<EOF | sudo tee /etc/apt/sources.list.d/ceph.list
deb [arch=amd64] https://nexus.internal/repository/ceph-reef/ jammy main
EOF

# Add Nexus GPG key
curl -fsSL https://nexus.internal/repository/keys/ceph.gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/ceph.gpg

# Skip cephadm download from internet - use local package
sudo apt update
sudo apt install -y ceph-common cephadm ceph-mds ceph-mgr ceph-mon ceph-osd radosgw
```

> **Air-Gap Note:** Ensure Nexus hosts the complete Ceph Reef repository including:
> - ceph, ceph-common, cephadm
> - ceph-mds, ceph-mgr, ceph-mon, ceph-osd
> - radosgw (Ceph RGW)
> - ceph-volume, python3-ceph-argparse

### 2. System Requirements (per node)

| Resource | MON Node | OSD Node |
|----------|----------|----------|
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| OS Disk | 100 GB SSD | 100 GB SSD |
| OSD Data | N/A | 2-4 × HDD (per OSD disk) |
| WAL/DB | N/A | 1 × NVMe/SSD (shared) |
| Network | 2× 10GbE | 2× 10/25GbE |

### 3. NTP Configuration

```bash
# Install and configure chrony
sudo apt install -y chrony

cat <<EOF | sudo tee /etc/chrony/chrony.conf
server ntp1.internal iburst
server ntp2.internal iburst
allow 10.0.0.0/8
EOF

sudo systemctl restart chrony
sudo systemctl enable chrony

# Verify
chronyc tracking
timedatectl status
```

> **Warning:** NTP drift causes MON clock skew warnings and can destabilize the cluster. Verify all nodes are synchronized before deployment.

### 4. DNS Resolution

All nodes must resolve each other by hostname in **both forward and reverse** zones.

```bash
# Example /etc/hosts entry (or use internal DNS)
cat <<EOF | sudo tee -a /etc/hosts
10.1.1.11  mon01.mon.cluster.local  mon01
10.1.1.12  mon02.mon.cluster.local  mon02
10.1.1.13  mon03.mon.cluster.local  mon03
10.1.1.14  mon04.mon.cluster.local  mon04
10.1.1.15  mon05.mon.cluster.local  mon05
10.1.2.21  osd01.osd.cluster.local   osd01
10.1.2.22  osd02.osd.cluster.local   osd02
10.1.2.23  osd03.osd.cluster.local   osd03
10.1.2.24  osd04.osd.cluster.local   osd04
10.1.2.25  osd05.osd.cluster.local   osd05
EOF

# Verify from any node
for host in mon01 mon02 mon03 mon04 mon05 osd01 osd02 osd03 osd04 osd05; do
    ping -c 1 $host && echo "$host OK" || echo "$host FAIL"
done
```

### 5. SSH Key-Based Authentication

```bash
# On bootstrap node (mon01), generate key
ssh-keygen -t ed25519 -f ~/.ssh/id_edph -N '' -C "cephadm@cluster"

# Distribute to all nodes
for node in mon01 mon02 mon03 mon04 mon05 osd01 osd02 osd03 osd04 osd05; do
    ssh-copy-id -i ~/.ssh/id_edph.pub $node
done

# Test passwordless SSH
for node in mon01 mon02 mon03 mon04 mon05 osd01 osd02 osd03 osd04 osd05; do
    ssh $node "hostname && echo 'SSH OK'"
done
```

### 6. Firewall Configuration

```bash
# Allow Ceph ports between all cluster nodes
sudo ufw allow from 10.1.1.0/24 to any port 6789,3300  # MON
sudo ufw allow from 10.1.2.0/24 to any port 6800:7300  # OSD/MGR
sudo ufw allow from 10.1.2.0/24 to any port 9283       # MGR Dashboard
```

---

## Network Architecture

### Dual-Network Configuration

| Network | CIDR | VLAN | Purpose |
|---------|------|------|---------|
| Public Network | `10.1.1.0/24` | VLAN 100 | Client access, MONs |
| Cluster Network | `10.1.2.0/24` | VLAN 200 | OSD replication, recovery |

```bash
# On each OSD node, configure cluster network
cat <<EOF | sudo tee /etc/netplan/02-cluster-network.yaml
network:
  version: 2
  ethernets:
    ens2:
      addresses:
        - 10.1.2.21/24  # Adjust per node
      mtu: 9000       # Jumbo frames for cluster network
EOF

sudo netplan apply
```

> **Performance Tip:** Enable jumbo frames (MTU 9000) on the cluster network for better throughput during replication and recovery.

---

## Step-by-Step Deployment

### Step 1: Bootstrap First Monitor

```bash
# On mon01 - bootstrap the cluster
sudo cephadm bootstrap \
    --mon-ip 10.1.1.11 \
    --cluster-network 10.1.2.0/24 \
    --allow-fqdn-hostname \
    --dashboard-password-noupdate \
    --output-keyring /etc/ceph/ceph.client.admin.keyring \
    --output-config /etc/ceph/ceph.conf \
    --initial-dashboard-password "$DASHBOARD_PASSWORD" \
    --ssh-private-key /root/.ssh/id_ed25519 \
    --ssh-public-key /root/.ssh/id_ed25519.pub
```

**Generated files:**
- `/etc/ceph/ceph.conf` — Cluster configuration
- `/etc/ceph/ceph.client.admin.keyring` — Admin authentication
- `/etc/ceph/ceph.pub` — Cluster public SSH key

**Verify bootstrap:**
```bash
sudo ceph -s
sudo ceph health detail
```

### Step 2: Add Remaining Monitors

```bash
# Copy SSH key to new MON nodes (cephadm handles this, but verify)
ssh-copy-id -f -i /etc/ceph/ceph.pub mon02
ssh-copy-id -f -i /etc/ceph/ceph.pub mon03
ssh-copy-id -f -i /etc/ceph/ceph.pub mon04
ssh-copy-id -f -i /etc/ceph/ceph.pub mon05

# Add MONs
sudo ceph orch apply mon --unmanaged  # If not using cephadm orchestrator
# OR for cephadm-managed:
sudo ceph orch apply mon mon02
sudo ceph orch apply mon mon03
sudo ceph orch apply mon mon04
sudo ceph orch apply mon mon05

# Set MON IPs explicitly
sudo ceph config set mon mon02 public_addr 10.1.1.12
sudo ceph config set mon mon03 public_addr 10.1.1.13
sudo ceph config set mon mon04 public_addr 10.1.1.14
sudo ceph config set mon mon05 public_addr 10.1.1.15

# Wait for quorum
sudo ceph -w
```

**Verify MON quorum:**
```bash
sudo ceph mon stat
# Expected: e1: 5 mons at {mon01,mon02,mon03,mon04,mon05}, election epoch 12, leader 0

sudo ceph quorum_status
```

### Step 3: Deploy MGRs (Active + Standby)

```bash
# Deploy 2 MGR daemons (active + standby)
sudo ceph orch apply mgr mon01,mon02

# Verify
sudo ceph mgr stat
# Expected: active: mon01, standby: mon02

# Enable required modules
sudo ceph mgr module enable dashboard
sudo ceph mgr module enable prometheus
sudo ceph mgr module enable balancer
```

### Step 4: Deploy OSDs with BlueStore

#### 4a. Add OSD Hosts

```bash
# Copy SSH keys to OSD nodes
for node in osd01 osd02 osd03 osd04 osd05; do
    ssh-copy-id -f -i /etc/ceph/ceph.pub $node
done

# Add hosts to cephadm
sudo ceph orch host add osd01 10.1.1.21 10.1.2.21
sudo ceph orch host add osd02 10.1.1.22 10.1.2.22
sudo ceph orch host add osd03 10.1.1.23 10.1.2.23
sudo ceph orch host add osd04 10.1.1.24 10.1.2.24
sudo ceph orch host add osd05 10.1.1.25 10.1.2.25
```

#### 4b. Deploy OSDs

**Option A: Use all available devices (auto-discovery)**
```bash
# Apply OSD service spec to all OSD hosts
cat <<EOF | sudo tee /tmp/ceph-osd.yaml
service_type: osd
service_id: all-ossd
placement:
  host_pattern: 'osd*'
spec:
  data_devices:
    all: true
  db_devices:
    paths:
      - /dev/nvme0n1  # SSD/NVMe for WAL/DB
  encrypted: true
EOF

sudo ceph orch apply -i /tmp/ceph-osd.yaml
```

**Option B: Explicit device selection**
```bash
cat <<EOF | sudo tee /tmp/ceph-osd.yaml
service_type: osd
service_id: osd-spec
placement:
  host_pattern: 'osd*'
spec:
  data_devices:
    paths:
      - /dev/sdb
      - /dev/sdc
      - /dev/sdd
  db_devices:
    paths:
      - /dev/nvme0n1
  encrypted: true
EOF

sudo ceph orch apply -i /tmp/ceph-osd.yaml
```

**Option C: Per-host device specification**
```bash
# For hosts with different disk layouts
cat <<EOF | sudo tee /tmp/ceph-osd-osd01.yaml
service_type: osd
service_id: osd-osd01
placement:
  hosts:
    - osd01
spec:
  data_devices:
    paths:
      - /dev/disk/by-id/ata-WDC_WD8003FRYZ-01W901_VK0GHKRC
      - /dev/disk/by-id/ata-WDC_WD8003FRYZ-01W901_VK0GJLSD
  db_devices:
    paths:
      - /dev/nvme0n1
EOF

sudo ceph orch apply -i /tmp/ceph-osd-osd01.yaml
```

**Verify OSD deployment:**
```bash
sudo ceph osd tree
sudo ceph osd status
sudo ceph osd df
```

#### 4c. BlueStore WAL/DB Sizing Guidelines

| Device Type | WAL Size | DB Size | Notes |
|-------------|----------|---------|-------|
| NVMe (shared) | 10 GB | 60 GB | Optimal for HDD-backed OSDs |
| NVMe (dedicated) | Full partition | Full partition | Best performance |
| SATA SSD | 2 GB | 10 GB | Minimum viable |

```bash
# Check BlueStore allocation
sudo ceph osd df tree
```

### Step 5: Create CephFS

#### 5a. Deploy MDS (Active + Standby)

```bash
# Deploy MDS daemons
sudo ceph orch apply mds cephfs --placement="2 mon01 mon02"

# Wait for active
sudo ceph fs status
```

#### 5b: Create CephFS Pools

```bash
# Calculate PGs: target ~150 PGs per OSD
# Formula: (Total PGs) / (OSD count) / (replication factor) = target
# 150 = Total_PGs / 5 / 3 → Total_PGs = 2250
# Round to power of 2: 2048

# Metadata pool (SSD recommended, 3x replication)
sudo ceph osd pool create cephfs_metadata 64 64 replicated
sudo ceph osd pool set cephfs_metadata size 3
sudo ceph osd pool set cephfs_metadata min_size 2

# Data pool
sudo ceph osd pool create cephfs_data 2048 2048 replicated
sudo ceph osd pool set cephfs_data size 3
sudo ceph osd pool set cephfs_data min_size 2

# Enable application
sudo ceph osd pool application enable cephfs_metadata cephfs
sudo ceph osd pool application enable cephfs_data cephfs
```

#### 5c: Create Filesystem

```bash
# Create CephFS
sudo ceph fs new cephfs cephfs_metadata cephfs_data
sudo ceph fs status cephfs

# Verify MDS
sudo ceph mds stat
# Expected: cephfs:1 {0=mon01=active} {1=mon02=standby}
```

#### 5d: CephFS Subvolumes (for Kubernetes namespaces)

```bash
# Create subvolume groups for K8s isolation
sudo ceph fs subvolumegroup create cephfs csi

# Create subvolumes per namespace
sudo ceph fs subvolume create cephfs csi-nfs --group_name csi --size 100G
sudo ceph fs subvolume create cephfs csi-default --group_name csi --size 500G
```

### Step 6: Create RGW for S3

```bash
# Deploy RGW instances
sudo ceph orch apply rgw myrealm myzone --placement="2 mon01 mon02"

# Configure RGW
sudo ceph config set client.rgw.myrealm.myzone rgw_frontends "civetweb port=8080"
sudo ceph config set client.rgw.myrealm.myzone rgw_dns_name s3.internal

# Restart RGW
sudo ceph orch restart rgw.myrealm.myzone

# Verify
sudo ceph orch ps --daemon_type rgw
```

See [rados-gateway.md](rados-gateway.md) for detailed RGW configuration including TLS, users, and Velero integration.

### Step 7: Create RBD Pool for Kubernetes Block Storage

```bash
# Create RBD pool
sudo ceph osd pool create k8s-rbd 512 512 replicated
sudo ceph osd pool set k8s-rbd size 3
sudo ceph osd pool set k8s-rbd min_size 2
sudo ceph osd pool application enable k8s-rbd rbd

# Initialize for RBD
sudo rbd pool init k8s-rbd
```

---

## CRUSH Map Tuning

### Rack/Host Awareness

CRUSH rules ensure replicas are distributed across failure domains.

```bash
# Create CRUSH hierarchy
sudo ceph osd crush add-bucket mon01 rack rack-a
sudo ceph osd crush add-bucket mon02 rack rack-a
sudo ceph osd crush add-bucket mon03 rack rack-b
sudo ceph osd crush add-bucket mon04 rack rack-b
sudo ceph osd crush add-bucket mon05 rack rack-c

sudo ceph osd crush move mon01 rack=rack-a
sudo ceph osd crush move mon02 rack=rack-a
sudo ceph osd crush move mon03 rack=rack-b
sudo ceph osd crush move mon04 rack=rack-b
sudo ceph osd crush move mon05 rack=rack-c

# Move OSD hosts to racks
sudo ceph osd crush move osd01 rack=rack-a
sudo ceph osd crush move osd02 rack=rack-b
sudo ceph osd crush move osd03 rack=rack-c
sudo ceph osd crush move osd04 rack=rack-a
sudo ceph osd crush move osd05 rack=rack-b

# Create CRUSH rule for rack-aware replication
sudo ceph osd crush rule create-replicated rack-aware default rack

# Apply rule to pools
sudo ceph osd pool set cephfs_data crush_rule rack-aware
sudo ceph osd pool set cephfs_metadata crush_rule rack-aware
sudo ceph osd pool set k8s-rbd crush_rule rack-aware
```

**Verify CRUSH map:**
```bash
sudo ceph osd crush tree
sudo ceph osd crush rule list
```

---

## PG/PGP Calculator

### Formula

```
Total PGs = (Target PGs per OSD × Total OSDs) / Replication Factor
```

### Calculation for This Cluster

| Parameter | Value |
|-----------|-------|
| OSDs | 5 (per node) × 5 nodes = 25 |
| Target PGs/OSD | 100-150 |
| Replication | 3 |
| **Total PGs** | **(150 × 25) / 3 = 1250** |
| **Rounded (power of 2)** | **1024** |

```bash
# Set PGs for pools
sudo ceph osd pool set cephfs_data pg_num 1024
sudo ceph osd pool set cephfs_data pgp_num 1024
sudo ceph osd pool set cephfs_metadata pg_num 64
sudo ceph osd pool set cephfs_metadata pgp_num 64
sudo ceph osd pool set k8s-rbd pg_num 512
sudo ceph osd pool set k8s-rbd pgp_num 512
```

### PG Autoscaling

```bash
# Enable autoscaler globally
sudo ceph config set global osd_pg_autoscale_mode on

# Set per-pool
sudo ceph osd pool set cephfs_data pg_autoscale_mode on
sudo ceph osd pool set k8s-rbd pg_autoscale_mode on

# Set target ratio
sudo ceph config set global target_max_object_size 128M
```

---

## Replication and Durability

```bash
# Set global defaults
sudo ceph config set global osd_pool_default_size 3
sudo ceph config set global osd_pool_default_min_size 2
sudo ceph config set global osd_pool_default_pg_autoscale_warn_threshold_ratio 0.5

# Verify per-pool
for pool in cephfs_metadata cephfs_data k8s-rbd; do
    echo "=== $pool ==="
    sudo ceph osd pool get $pool size
    sudo ceph osd pool get $pool min_size
done
```

---

## Scrubbing Schedule

```bash
# Configure scrubbing (default: weekly deep scrub)
sudo ceph config set osd osd_scrub_begin_hour 22
sudo ceph config set osd osd_scrub_end_hour 6
sudo ceph config set osd osd_scrub_sleep 0.1
sudo ceph config set osd osd_scrub_chunk_min 1
sudo ceph config set osd osd_scrub_chunk_max 5

# Auto-scrub based on threshold
sudo ceph config set osd osd_scrub_auto_repair true

# Deep scrub interval (every 7 days)
sudo ceph config set osd osd_deep_scrub_interval 604800

# Manual scrub (maintenance window)
sudo ceph osd scrub cephfs_data
sudo ceph osd deep-scrub cephfs_data
```

---

## Dashboard Setup

```bash
# Enable dashboard module
sudo ceph mgr module enable dashboard

# Create self-signed certificate (or import from internal CA)
sudo ceph dashboard create-self-signed-cert

# Set dashboard port
sudo ceph config set mgr mgr/dashboard/server_port 8443

# Create admin user
sudo ceph dashboard set-login-credentials admin "$DASHBOARD_PASSWORD"

# Enable Grafana integration
sudo ceph mgr module enable prometheus
sudo ceph dashboard set-grafana-api-url https://grafana.internal

# Restart
sudo ceph mgr restart
```

See [ceph-dashboard.sh](../../scripts/ceph/ceph-dashboard.sh) for automated configuration.

---

## Performance Tuning

### OSD Performance

```bash
# BlueStore cache settings
sudo ceph config set osd bluestore_cache_size_ssd 4294967296    # 4GB for SSD
sudo ceph config set osd bluestore_cache_size_hbd 1073741824    # 1GB for HDD
sudo ceph config set osd bluestore_cache_meta_ratio 0.5
sudo ceph config set osd bluestore_cache_kv_ratio 0.3

# OSD op threads
sudo ceph config set osd osd_op_threads 8

# Recovery and rebalancing
sudo ceph config set osd osd_recovery_max_active 3
sudo ceph config set osd osd_recovery_sleep 0.5
sudo ceph config set osd osd_max_backfills 2
```

### Network Performance

```bash
# Messenger settings
sudo ceph config set global ms_type async  # Use async messenger in Reef
sudo ceph config set osd ms_max_backlog 500000
sudo ceph config set osd ms_send_prefetch_max_bytes 4194304

# Buffer sizes
sudo ceph config set osd osd_network_threads 4
```

### MDS Performance

```bash
# MDS cache
sudo ceph config set mds mds_cache_memory_limit 4294967296  # 4GB
sudo ceph config set mds mds_cache_reservation 0.05
sudo ceph config set mds mds_health_cache_threshold 1.5
```

---

## Health Monitoring Commands

```bash
# Overall status
sudo ceph -s
sudo ceph health detail

# OSD status
sudo ceph osd stat
sudo ceph osd tree
sudo ceph osd df
sudo ceph osd perf

# Pool status
sudo ceph osd pool stats
sudo ceph osd pool ls detail

# PG status
sudo ceph pg stat
sudo ceph pg dump
sudo ceph pg dump_stuck inactive
sudo ceph pg dump_stuck unclean

# MDS status
sudo ceph mds stat
sudo ceph fs status

# RGW status
sudo ceph orch ps --daemon_type rgw

# Performance
sudo ceph osd perf
sudo ceph tell osd.* perf dump
sudo ceph pg dump --format json-pretty | jq '.pg_map.pg_stats[] | select(.state | contains("degraded"))'

# Alert conditions to monitor
# - HEALTH_ERR/HEALTH_WARN
# - OSD down or out
# - PG inactive/unclean
# - MON quorum lost
# - MDS inactive
# - Disk usage > 80% (nearfull ratio)
```

---

## Create K8s CSI User

```bash
# Create CephFS CSI user
sudo ceph auth get-or-create client.csi-cephfs \
    mon 'allow r' \
    osd 'allow rw pool=cephfs_metadata, allow rw pool=cephfs_data' \
    mds 'allow rw' \
    mgr 'allow r'

# Create RBD CSI user
sudo ceph auth get-or-create client.csi-rbd \
    mon 'allow r' \
    osd 'allow rw pool=k8s-rbd' \
    mgr 'allow r'

# Export keys for Kubernetes secrets
sudo ceph auth get-key client.csi-cephfs
sudo ceph auth get-key client.csi-rbd

# Export MON endpoints for CSI
sudo ceph mon dump -f json | jq -r '.mons[].addrs' | head -1
# Output format: 10.1.1.11:6789,10.1.1.12:6789,10.1.1.13:6789,10.1.1.14:6789,10.1.1.15:6789
```

### Kubernetes Secret for CSI

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: csi-cephfs-secret
  namespace: ceph-csi
stringData:
  userID: csi-cephfs
  userKey: <PASTE_KEY_HERE>
  encryptionPassphrase: <PASSPHRASE>
---
apiVersion: v1
kind: Secret
metadata:
  name: csi-rbd-secret
  namespace: ceph-csi
stringData:
  userID: csi-rbd
  userKey: <PASTE_KEY_HERE>
```

---

## Air-Gap Considerations

| Component | Source | Notes |
|-----------|--------|-------|
| Ceph packages | Nexus apt repo | Mirror `reef` repository |
| cephadm image | Harbor | `harbor.internal/ceph/ceph:v$CEPH_VERSION` |
| Container images | Harbor | All daemon images |
| OS packages | Nexus apt repo | Ubuntu packages |

### Pre-deployment Checklist

- [ ] Nexus repository populated with Ceph Reef packages
- [ ] Harbor registry has all Ceph container images
- [ ] All nodes can reach Nexus and Harbor
- [ ] SSH keys distributed
- [ ] NTP synchronized across all nodes
- [ ] DNS forward and reverse resolution working
- [ ] Firewall rules configured
- [ ] Network MTU configured (jumbo frames on cluster network)
- [ ] Disks identified and labeled

---

## Troubleshooting

| Issue | Command | Resolution |
|-------|---------|------------|
| MON quorum lost | `sudo ceph mon stat` | Restart MONs, check NTP |
| OSD down | `sudo ceph osd tree` | Check disk, restart daemon |
| PG stuck | `sudo ceph pg dump_stuck` | Check OSD health, network |
| Slow PGs | `sudo ceph pg query` | Check network, OSD perf |
| MDS lag | `sudo ceph mds perf` | Increase cache, check metadata ops |
| Near-full OSD | `sudo ceph osd df` | Add OSDs, adjust nearfull ratio |

---

## References

- [Ceph Documentation - Reef](https://docs.ceph.com/en/reef/)
- [cephadm Guide](https://docs.ceph.com/en/reef/cephadm/)
- [Ceph Performance Tuning](https://docs.ceph.com/en/reef/architecture)
