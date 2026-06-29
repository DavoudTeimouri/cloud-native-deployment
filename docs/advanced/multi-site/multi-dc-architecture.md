# Multi-Datacenter Architecture & Replication Guide

> **Advanced Guide** — This is a supplementary guide for multi-site deployments.  
> The standard single-site deployment guide is in the main documentation.

## Overview

This guide covers deploying and operating cloud-native infrastructure across **two or more datacenters** (sites), with independent Kubernetes clusters per site and cross-site replication at the storage, application, and platform layers.

### Why Multi-Cluster Per Site (Not Stretched Cluster)

| Factor | Stretched Cluster (Single K8s across sites) | Multi-Cluster (Recommended) |
|--------|---------------------------------------------|-----------------------------|
| **etcd latency** | Requires <10ms RTT; cross-DC typically 20-100ms+ | Local etcd, no cross-DC latency |
| **Split-brain** | Network partition = lost quorum = total failure | Partition isolates one site; others remain up |
| **Blast radius** | One bad deploy/upgrade affects ALL sites | Isolated per cluster |
| **Storage** | Ceph cross-DC replication is latency-sensitive | Local Ceph, async replication between |
| **Compliance** | Hard to enforce data locality | Easy — data stays in its DC |
| **Upgrade** | Entire cluster upgrades together | Roll upgrades site by site |
| **Recovery** | Full cluster recovery is complex | Per-cluster recovery is straightforward |
| **Complexity** | Stretched L2 network, complex etcd quorum | Standard K8s tooling, well-understood |

**Verdict**: Multi-cluster per site is the recommended architecture. A stretched cluster is only acceptable for campus-style DCs with <2ms RTT.

---

## Architecture

### Logical Topology

```
┌──────────────────────────────────────────────────────────────────────┐
│                         PRIMARY SITE (DC-1)                         │
│                                                                      │
│  ┌──────────────────────────┐   ┌──────────────────────────────┐    │
│  │  Mgmt Cluster (DC-1)     │   │  App Cluster (DC-1)          │    │
│  │  ├─ Rancher (Primary)    │   │  ├─ MetalLB                  │    │
│  │  ├─ ArgoCD (Primary)     │   │  ├─ Workloads (Active)       │    │
│  │  ├─ Central Monitoring   │   │  ├─ Ceph (Primary)            │    │
│  │  ├─ Gatekeeper           │   │  │  ├─ RBD-mirror source     │    │
│  │  ├─ cert-manager         │   │  │  ├─ RGW zone (primary)    │    │
│  │  ├─ Rook-Ceph/Backup     │   │  │  └─ CephFS snapshots      │    │
│  │  └─ Velero               │   │  ├─ Velero (backup local)    │    │
│  └──────────────────────────┘   └──────────────────────────────┘    │
│                                                                      │
│  LB-1: HAProxy + keepalived (API VIP + Ingress VIP)                 │
│  LB-2: HAProxy + keepalived (Monitoring VIP)                        │
│  Ops: Linux (deploy) + Windows (management)                         │
└──────────────────────────────┬───────────────────────────────────────┘
                               │
                    Inter-DC Link (WAN/Metro)
                    Bandwidth: ≥1 Gbps recommended
                    Latency: <50ms RTT recommended
                    Redundant links (2+ paths)
                               │
┌──────────────────────────────┴───────────────────────────────────────┐
│                       SECONDARY SITE (DC-2)                         │
│                                                                      │
│  ┌──────────────────────────┐   ┌──────────────────────────────┐    │
│  │  Mgmt Cluster (DC-2)     │   │  App Cluster (DC-2)          │    │
│  │  ├─ Rancher (Standby)    │   │  ├─ MetalLB                  │    │
│  │  ├─ ArgoCD (Secondary)   │   │  ├─ Workloads (Warm Standby) │    │
│  │  ├─ Monitoring (local)   │   │  ├─ Ceph (Replica)           │    │
│  │  ├─ Gatekeeper           │   │  │  ├─ RBD-mirror target     │    │
│  │  ├─ cert-manager         │   │  │  ├─ RGW zone (secondary)  │    │
│  │  ├─ Rook-Ceph/Backup     │   │  │  └─ CephFS replicated     │    │
│  │  └─ Velero               │   │  ├─ Velero (restore capable) │    │
│  └──────────────────────────┘   └──────────────────────────────┘    │
│                                                                      │
│  LB-1: HAProxy + keepalived                                         │
│  LB-2: HAProxy + keepalived                                         │
│  Ops: Linux (deploy) + Windows (management)                         │
└──────────────────────────────────────────────────────────────────────┘
```

### Inter-DC Network Requirements

| Requirement | Minimum | Recommended | Notes |
|-------------|---------|-------------|-------|
| **Bandwidth** | 500 Mbps | 1 Gbps+ | Depends on replication volume |
| **Latency (RTT)** | <100ms | <50ms | Lower is better for Ceph replication |
| **Links** | 1 | 2+ (redundant) | Diverse paths preferred |
| **Jitter** | <5ms | <2ms | Critical for Ceph RBD-mirror |
| **Packet loss** | <0.1% | <0.01% | Impacts replication consistency |

---

## Replication Technologies by Layer

### Complete Replication Matrix

| Layer | Technology | Mode | RPO | RTO | Complexity |
|-------|-----------|------|-----|-----|------------|
| **Ceph RBD** | rbd-mirror | Async (journal-based) | Seconds-minutes | Minutes | Medium |
| **CephFS** | Snapshot + rbd export-diff | Async | Minutes-hours | Minutes | Medium |
| **CephFS** | CephFS Mirror (Squid+) | Async | Seconds-minutes | Minutes | Medium |
| **Ceph RGW** | Multi-site zone sync | Async (near-sync) | Seconds | Minutes | Medium |
| **MinIO** | Site replication | Async | Seconds-minutes | Minutes | Low |
| **K8s Resources** | ArgoCD ApplicationSets | Sync (Git-driven) | Near-zero | Minutes | Low |
| **K8s Resources** | Velero backup/restore | Scheduled | Minutes | 10-30 min | Low |
| **K8s Resources** | Rancher Fleet | Sync (Git-driven) | Near-zero | Minutes | Low |
| **etcd** | etcdctl snapshot | Scheduled | Minutes | 5-15 min | Low |
| **Secrets/Certs** | cert-manager + shared CA | Sync | N/A | N/A | Low |
| **Config/Policy** | Gatekeeper (GitOps) | Sync | Near-zero | Minutes | Low |
| **DNS** | External DNS + GSLB | Sync | Near-zero | Minutes | Medium |

---

## Storage Replication

### 1. Ceph RBD Mirror (Block Storage)

RBD-mirror provides asynchronous, journal-based replication of Ceph block images between two Ceph clusters.

#### Architecture

```
DC-1 (Primary)                          DC-2 (Secondary)
┌─────────────────┐                     ┌─────────────────┐
│ Ceph Cluster A  │  rbd-mirror daemon  │ Ceph Cluster B  │
│ ┌─────────────┐ │ ──────────────────► │ ┌─────────────┐ │
│ │ Pool: rbd   │ │  Journal-based     │ │ Pool: rbd   │ │
│ │ Image: pv-1 │ │  async replication │ │ Image: pv-1 │ │
│ │ Journal     │ │                     │ │ (read-only  │ │
│ │ enabled     │ │                     │ │  until fail)│ │
│ └─────────────┘ │                     │ └─────────────┘ │
└─────────────────┘                     └─────────────────┘
```

#### Setup on DC-1 (Primary)

```bash
# Enable journaling on RBD pool images
rbd pool init rbd
rbd config pool set rbd journal_splay_width 4
rbd config pool set rbd journal_object_size 16MB

# Enable journaling per image (or set pool default)
rbd feature enable rbd/pv-image1 journaling

# Create replication user on primary
ceph auth get-or-create client.rbd-mirror-peer \
  mon 'allow r' \
  osd 'allow *' \
  -o /etc/ceph/rbd-mirror-peer.keyring
```

#### Setup on DC-2 (Secondary)

```bash
# Install rbd-mirror daemon
apt install rbd-mirror

# Configure peer connection to DC-1
rbd mirror pool peer add rbd client.rbd-mirror-peer@dc1 \
  --remote-cluster-spec dc1-ceph-mon1:6789,dc1-ceph-mon2:6789,dc1-ceph-mon3:6789

# Enable pool mirroring
rbd mirror pool enable rbd pool  # pool-level
# OR per-image:
rbd mirror image enable rbd/pv-image1

# Start rbd-mirror daemon
systemctl enable --now ceph-rbd-mirror@rbd-mirror
```

#### Verify Replication

```bash
# Check mirror status
rbd mirror pool status rbd
rbd mirror image status rbd/pv-image1

# Expected output:
# pv-image1:
#   global_id:   abc123...
#   state:       up+replaying
#   description: replaying, {"bytes_per_sec": 5242880.0, ...}
#   last_update: 2025-01-15 10:30:00
```

#### Failover Procedure (RBD)

```bash
# On DC-1: Stop all K8s workloads using the RBD images
kubectl cordon <nodes>
kubectl drain <nodes> --ignore-daemonsets --delete-emptydir-data

# On DC-2: Promote images to primary
rbd mirror image promote rbd/pv-image1
# Or force promote if DC-1 is unreachable:
rbd mirror image promote --force rbd/pv-image1

# Update CSI configuration in DC-2 K8s cluster
# Point StorageClass to DC-2 Ceph cluster
```

### 2. Ceph RGW Multi-Site (Object Storage)

RGW multi-site provides asynchronous zone-level replication for S3 objects.

#### Architecture

```
DC-1 (Zone Primary)                     DC-2 (Zone Secondary)
┌───────────────────────┐               ┌───────────────────────┐
│ RGW Zone: dc1-zone   │  Async sync   │ RGW Zone: dc2-zone   │
│ ┌─────────┐ ┌──────┐ │ ─────────────►│ ┌─────────┐ ┌──────┐ │
│ │ Bucket1 │ │Meta  │ │  Metadata +   │ │ Bucket1 │ │Meta  │ │
│ │ Objects │ │Data  │ │  data sync    │ │ Objects │ │Data  │ │
│ └─────────┘ └──────┘ │               │ └─────────┘ └──────┘ │
│                        │               │                       │
│ Period: realm1         │               │ Period: realm1        │
│ Zonegroup: multi-dc    │               │ Zonegroup: multi-dc   │
└───────────────────────┘               └───────────────────────┘
```

#### Setup Multi-Site RGW

```bash
# On DC-1: Create realm, zonegroup, and zone
radosgw-admin realm create --rgw-realm=multi-dc --default
radosgw-admin zonegroup create --rgw-zonegroup=multi-dc \
  --endpoints=http://dc1-rgw:8080 --master --default
radosgw-admin zone create --rgw-zonegroup=multi-dc --rgw-zone=dc1-zone \
  --endpoints=http://dc1-rgw:8080 --master --default

# Create system user for sync
radosgw-admin user create --uid=zone-sync-user \
  --display-name="Zone Sync User" --system

# Get access keys
radosgw-admin key create --uid=zone-sync-user --key-type=sync

# Commit period
radosgw-admin period update --commit

# On DC-2: Pull realm and create secondary zone
radosgw-admin realm pull --url=http://dc1-rgw:8080 \
  --access-key=<KEY> --secret=<SECRET>

radosgw-admin zone create --rgw-zonegroup=multi-dc --rgw-zone=dc2-zone \
  --endpoints=http://dc2-rgw:8080 \
  --access-key=<KEY> --secret=<SECRET>

radosgw-admin period update --commit
```

### 3. CephFS Replication

CephFS replication options (ordered by preference):

| Method | Version Required | RPO | Complexity | Status |
|--------|-----------------|-----|------------|--------|
| **CephFS Mirror** | Squid (v19)+ | Seconds-minutes | Low | Stable in Squid |
| **Snapshot + rbd export-diff** | Any | Minutes-hours | Medium | Scripting required |
| **Snapshot + rsync** | Any | Minutes-hours | Low | Simple but slow |

#### CephFS Mirror (Ceph Squid+)

```bash
# Enable CephFS mirroring
ceph fs snapshot mirror enable <fs_name>

# Add peer cluster
ceph fs snapshot mirror peer_add <fs_name> \
  client.rbd-mirror-peer@dc2 \
  dc2-ceph-mon1:6789,dc2-ceph-mon2:6789

# Configure directory mirroring
ceph fs snapshot mirror add <fs_name> /k8s-volumes
ceph fs snapshot mirror add <fs_name> /shared-data

# Configure snapshot schedule
ceph fs snapshot schedule add <fs_name> /k8s-volumes 1h
ceph fs snapshot schedule add <fs_name> /shared-data 15m
```

### 4. MinIO Site Replication

For environments using MinIO instead of (or alongside) Ceph RGW:

```bash
# On DC-1 MinIO
mc alias set dc1 http://dc1-minio:9000 admin <password>

# On DC-2 MinIO
mc alias set dc2 http://dc2-minio:9000 admin <password>

# Configure site replication
mc admin replicate add dc1 dc2

# Verify
mc admin replicate info dc1
```

---

## Kubernetes Application Replication

### ArgoCD ApplicationSets for Multi-Cluster

ArgoCD ApplicationSets provide the cleanest way to deploy applications across multiple clusters from a single Git repository.

#### Cluster Generator Example

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: workload-deploy
  namespace: argocd
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          environment: production
  template:
    metadata:
      name: '{{name}}-workload'
    spec:
      project: default
      source:
        repoURL: https://gitlab.internal/devops/k8s-manifests.git
        targetRevision: main
        path: apps/workload/overlays/{{name}}
      destination:
        server: '{{server}}'
        namespace: workload
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

#### Git Directory Generator Example

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: multi-site-workloads
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://gitlab.internal/devops/k8s-manifests.git
      revision: main
      directories:
      - path: apps/*/dc1
      - path: apps/*/dc2
  template:
    metadata:
      name: '{{path.basename}}-{{path[1]}}'
    spec:
      project: default
      source:
        repoURL: https://gitlab.internal/devops/k8s-manifests.git
        targetRevision: main
        path: '{{path}}'
      destination:
        name: '{{path[1]}}'
        namespace: '{{path.basename}}'
```

### Rancher Fleet for Multi-Cluster

Alternative to ArgoCD ApplicationSets, Fleet (built into Rancher) provides GitOps-based multi-cluster deployment:

```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: multi-site-workloads
  namespace: fleet-default
spec:
  repo: https://gitlab.internal/devops/fleet-manifests.git
  branch: main
  paths:
  - apps/workload
  targets:
  - clusterSelector:
      matchLabels:
        environment: production
        site: dc1
  - clusterSelector:
      matchLabels:
        environment: production
        site: dc2
```

### Registering Clusters Between Sites

#### App Cluster (DC-2) → Mgmt Cluster (DC-1) via Rancher

```bash
# Register DC-2 app cluster with DC-1 Rancher
# Ensure inter-DC network connectivity on port 443
# In Rancher UI: Add Cluster → Existing Cluster → Import
# Or via API:

curl -k -X POST \
  -H "Authorization: Bearer $RANCHER_TOKEN" \
  -H "Content-Type: application/json" \
  https://dc1-rancher/v3/clusters \
  -d '{
    "name": "app-cluster-dc2",
    "labels": {
      "site": "dc2",
      "environment": "production"
    }
  }'
```

---

## DNS & Global Load Balancing (GSLB)

### Architecture

```
                    ┌──────────────────┐
                    │    GSLB / DNS    │
                    │  (F5 GTM, Infoblox │
                    │   or PowerDNS)   │
                    └───────┬──────────┘
                            │
            ┌───────────────┼───────────────┐
            │                               │
    ┌───────▼──────┐               ┌───────▼──────┐
    │  DC-1 DNS    │               │  DC-2 DNS    │
    │  app.prod →  │               │  app.prod →  │
    │  DC-1 VIP    │               │  DC-2 VIP    │
    └──────────────┘               └──────────────┘
```

### PowerDNS GSLB Configuration

```yaml
# PowerDNS with geo-ip backend for GSLB
# db.yml for PowerDNS geo backend
---
domains:
- name: prod.internal
  ttl: 30
  records:
    app.prod.internal:
      - soa: ns1.prod.internal admin.prod.internal 2025011501 3600 600 604800 300
      - ns: ns1.prod.internal
      - a: 10.1.0.100    # DC-1 VIP (primary)
        geo-ip:
          default: 10.1.0.100
          dc2: 10.2.0.100  # DC-2 VIP
      - txt: "datacenter=dc1"
        geo-ip:
          default: "datacenter=dc1"
          dc2: "datacenter=dc2"
```

### DNS-Based Failover

```bash
# Automated failover script
# Monitors DC-1 health, updates DNS on failure

#!/usr/bin/env bash
DC1_VIP="10.1.0.100"
DC2_VIP="10.2.0.100"
CHECK_URL="https://app.prod.internal/healthz"

while true; do
  if ! curl -skf --max-time 5 "$CHECK_URL" > /dev/null 2>&1; then
    echo "$(date) DC-1 unreachable, failing over DNS to DC-2"
    # Update PowerDNS API
    curl -X PATCH \
      -H "X-API-Key: $PDNS_API_KEY" \
      -H "Content-Type: application/json" \
      http://dns-api:8081/api/v1/servers/localhost/zones/prod.internal \
      -d '{"rrsets": [{"name": "app.prod.internal.", "type": "A", "ttl": 30, "records": [{"content": "'$DC2_VIP'", "disabled": false}], "changetype": "REPLACE"}]}'
  fi
  sleep 10
done
```

---

## Failover Runbooks

### Active-Passive Failover (Recommended)

In active-passive mode, DC-1 runs all production workloads; DC-2 is a warm standby with replicated data.

#### Failover Steps

| Step | Action | Estimated Time |
|------|--------|---------------|
| 1 | **Detect failure** — monitoring detects DC-1 is down | 0-2 min |
| 2 | **Confirm failure** — manual or automated confirmation | 1-5 min |
| 3 | **Promote Ceph** — promote RBD images on DC-2 | 1-3 min |
| 4 | **Update DNS** — GSLB switches traffic to DC-2 | 1-5 min |
| 5 | **Scale workloads** — scale up DC-2 deployments from standby | 2-5 min |
| 6 | **Verify services** — health checks on DC-2 | 2-5 min |
| 7 | **Notify stakeholders** | Immediate |
| **Total** | | **~7-25 min** |

#### Failback Steps (After DC-1 Recovers)

| Step | Action | Estimated Time |
|------|--------|---------------|
| 1 | Re-establish replication from DC-2 → DC-1 | Depends on data size |
| 2 | Wait for sync to complete | Variable |
| 3 | Test DC-1 services | 5-10 min |
| 4 | Switch DNS back to DC-1 | 1-5 min |
| 5 | Demote DC-2 back to standby | 1-3 min |
| 6 | Re-enable DC-1 → DC-2 replication | Immediate |

### Active-Active (Advanced)

Active-active is possible but requires:

- **Application-level**: Applications must handle concurrent writes from both sites
- **Database**: Multi-master replication or sharding by site
- **Storage**: Ceph RGW multi-site (active-active zones)
- **Session affinity**: Sticky sessions to one DC per user
- **Conflict resolution**: Application must handle write conflicts

> **Recommendation**: Start with active-passive. Move to active-active only for specific stateless workloads that can tolerate split-brain scenarios.

---

## Cross-Site Network Requirements

### Firewall Rules (Inter-DC)

| Source | Destination | Port | Protocol | Purpose |
|--------|------------|------|----------|---------|
| DC-1 Ceph MON | DC-2 Ceph MON | 6789, 3300 | TCP | Ceph monitor communication |
| DC-1 Ceph OSD | DC-2 Ceph OSD | 6800-7300 | TCP | RBD-mirror, PG peering |
| DC-1 RGW | DC-2 RGW | 8080 | TCP | RGW multi-site sync |
| DC-1 rbd-mirror | DC-2 Ceph | 6789, 6800-7300 | TCP | RBD mirroring |
| DC-1 K8s API | DC-2 K8s API | 6443 | TCP | Rancher cluster registration |
| DC-1 Rancher | DC-2 Nodes | 443, 9345, 80 | TCP | Rancher agent communication |
| DC-1 ArgoCD | DC-2 K8s API | 6443 | TCP | ArgoCD cross-cluster deploy |
| DC-1 Prometheus | DC-2 Prometheus | 9090 | TCP | Remote write |
| DC-1 GitLab | DC-2 | 22, 80, 443 | TCP | Git replication |
| DC-1 MinIO | DC-2 MinIO | 9000 | TCP | Site replication |

### Bandwidth Sizing

| Replication Type | Per-TB Data | Bandwidth Needed | Notes |
|-----------------|------------|------------------|-------|
| Ceph RBD-mirror | 1 TB RBD images | ~10-50 Mbps | Depends on change rate |
| Ceph RGW sync | 1 TB objects | ~5-30 Mbps | Depends on upload rate |
| CephFS snapshots | 1 TB filesystem | ~5-20 Mbps | Periodic, not continuous |
| MinIO replication | 1 TB objects | ~5-30 Mbps | Change-rate driven |
| Velero backups | N/A | Burst, not sustained | Scheduled |

**Total recommended inter-DC bandwidth**: 1 Gbps minimum for production workloads with 10+ TB of replicated data.

---

## Monitoring Multi-Site

### Cross-Site Monitoring Architecture

```
DC-1 (Central Observability Hub)          DC-2 (Local Monitoring)
┌──────────────────────────┐              ┌──────────────────────────┐
│ Prometheus (Central)     │◄─remote──────│ Prometheus (Local)       │
│ Grafana (Central)        │  write       │ Node Exporter            │
│ Loki (Central)           │◄─ship───────│ Promtail / Loki (Local)  │
│ Alertmanager             │              │ Alertmanager (Local)     │
│ Velero UI                │              │ Velero (backup local)    │
└──────────────────────────┘              └──────────────────────────┘
```

### Key Alerts for Multi-Site

```yaml
# Ceph replication lag alert
- alert: CephRBDMirrorLag
  expr: ceph_rbd_mirror_snapshot_sync_lag_seconds > 300
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Ceph RBD mirror lag exceeds 5 minutes"
    description: "Replication from {{ $labels.source }} to {{ $labels.target }} is lagging by {{ $value }}s"

# RGW sync lag alert
- alert: CephRGWSyncLag
  expr: ceph_rgw_sync_lag > 60
  for: 5m
  labels:
    severity: warning

# Inter-DC connectivity alert
- alert: InterDCConnectivityLost
  expr: probe_success{job="blackbox-inter-dc"} == 0
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Inter-DC connectivity lost between {{ $labels.instance }} and {{ $labels.target }}"

# Site health composite alert  
- alert: SitePartialOutage
  expr: up{job=~"k8s-apiserver", site="dc1"} == 0
  for: 5m
  labels:
    severity: critical
```

---

## Operational Procedures

### Daily Checks

- [ ] Verify Ceph replication status (`rbd mirror pool status`)
- [ ] Verify RGW sync status (`radosgw-admin sync status`)
- [ ] Check inter-DC latency (ping, traceroute)
- [ ] Review Velero backup completion
- [ ] Check for any cross-site certificate expirations

### Weekly Checks

- [ ] Test failover procedure (non-production)
- [ ] Review replication lag trends
- [ ] Verify DNS failover configuration
- [ ] Review capacity at both sites
- [ ] Test backup restore on secondary site

### Monthly Checks

- [ ] Full failover drill (planned maintenance window)
- [ ] Update inter-DC firewall rules review
- [ ] Capacity planning review for both sites
- [ ] Update runbook with any changes

---

## Security Considerations

- **mTLS** between Ceph clusters for cross-DC replication
- **IPSec/WireGuard** tunnel for inter-DC K8s API communication
- **Certificate trust**: Both sites must trust the same internal CA
- **Gateway-proxy**: If strict firewall, use a reverse proxy for Ceph cross-DC traffic
- **Audit logging**: Log all cross-site administrative actions

---

## Scaling to 3+ Sites

Three or more sites provide:

- Quorum-based decisions (2 of 3 sites agree)
- Ceph RGW can support 3+ zone multi-site
- RBD-mirror supports 1-to-N replication
- ArgoCD ApplicationSets scale to any number of clusters

```
         ┌──────────────┐
         │    DC-1      │
         │  (Primary)   │
         └──────┬───────┘
                │
        ┌───────┴───────┐
        │               │
┌───────▼──────┐ ┌──────▼───────┐
│    DC-2      │ │    DC-3      │
│  (Replica)   │ │  (Replica)   │
└──────────────┘ └──────────────┘
```

With 3 sites, you can implement:
- **Rancher multi-cluster** with 3 registered clusters
- **ArgoCD** deploying to all 3 via ApplicationSets
- **Ceph RGW** 3-zone multi-site (any zone can be promoted)
- **GSLB** with health-based routing (closest healthy DC)
