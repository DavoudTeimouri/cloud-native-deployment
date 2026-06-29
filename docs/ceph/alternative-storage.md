# Alternative Storage Options Comparison

## Overview

This document provides a comprehensive comparison of software-defined storage (SDS) options for enterprise cloud-native deployments in air-gapped environments. It covers Rook-Ceph, MinIO, Longhorn, OpenEBS, and Local Path Provisioner.

---

## Summary of Solutions

### 1. Rook-Ceph

| Aspect | Details |
|--------|---------|
| **Type** | Unified storage (Block + File + Object) |
| **Architecture** | Ceph cluster managed by Kubernetes operator |
| **Production Since** | 2018 (Rook), 2006 (Ceph) |
| **License** | Apache 2.0 |
| **Primary Protocols** | RBD (block), CephFS (file), RGW (S3) |
| **Minimum Nodes** | 3 (minimum viable), 5 (recommended) |
| **Strengths** | Mature, unified storage, enterprise features |
| **Weaknesses** | Complex, resource-intensive, steep learning curve |

**When to Use:**
- Unified block, file, AND object storage needed
- Multi-tenancy with isolated storage pools
- Enterprise requiring feature-rich storage
- Team has Ceph expertise
- 100TB+ scale requirements

**Architecture Diagram:**
```
┌─────────────────────────────────────────────┐
│              Kubernetes Cluster              │
│  ┌──────────────────────────────────────┐   │
│  │         Rook Operator                 │   │
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐   │   │
│  │  │ MON │ │ MON │ │ MON │ │ MGR │   │   │
│  │  └─────┘ └─────┘ └─────┘ └─────┘   │   │
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐   │   │
│  │  │ OSD │ │ OSD │ │ OSD │ │ OSD │   │   │
│  │  │ SSD │ │ HDD │ │ HDD │ │ HDD │   │   │
│  │  └─────┘ └─────┘ └─────┘ └─────┘   │   │
│  │  ┌─────┐ ┌─────┐                    │   │
│  │  │ MDS │ │ RGW │                    │   │
│  │  └─────┘ └─────┘                    │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

---

### 2. MinIO

| Aspect | Details |
|--------|---------|
| **Type** | Object storage only |
| **Architecture** | Standalone server or K8s operator |
| **Production Since** | 2014 |
| **License** | AGPL v3 (Community) / Commercial |
| **Primary Protocols** | S3-compatible |
| **Minimum Nodes** | 1 (standalone), 4 (distributed) |
| **Strengths** | Simple, high-performance S3, air-gap friendly |
| **Weaknesses** | Object-only, no block/file support |

**When to Use:**
- S3-compatible object storage only needed
- Rapid deployment required
- Small team, limited storage expertise
- Velero backups, artifact storage, data lakes
- 1TB to 500TB scale

**Architecture Diagram:**
```
┌─────────────────────────────────────────────┐
│              Kubernetes Cluster              │
│  ┌──────────────────────────────────────┐   │
│  │         MinIO Operator                │   │
│  │  ┌─────────┐  ┌─────────┐            │   │
│  │  │ Node 1  │  │ Node 2  │            │   │
│  │  │ ┌─────┐ │  │ ┌─────┐ │            │   │
│  │  │ │Drive│ │  │ │Drive│ │            │   │
│  │  │ │ x4  │ │  │ │ x4  │ │            │   │
│  │  │ └─────┘ │  │ └─────┘ │            │   │
│  │  └─────────┘  └─────────┘            │   │
│  │  ┌─────────┐  ┌─────────┐            │   │
│  │  │ Node 3  │  │ Node 4  │            │   │
│  │  │ ┌─────┐ │  │ ┌─────┐ │            │   │
│  │  │ │Drive│ │  │ │Drive│ │            │   │
│  │  │ │ x4  │ │  │ │ x4  │ │            │   │
│  │  │ └─────┘ │  │ └─────┘ │            │   │
│  │  └─────────┘  └─────────┘            │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

---

### 3. Longhorn

| Aspect | Details |
|--------|---------|
| **Type** | Distributed block storage |
| **Architecture** | K8s-native block storage with iSCSI/NVMe-oF |
| **Production Since** | 2019 |
| **License** | Apache 2.0 |
| **Primary Protocols** | Block (iSCSI, NVMe-oF), K8s PV |
| **Minimum Nodes** | 3 |
| **Strengths** | Simple, lightweight, built-in backup/snapshot |
| **Weaknesses** | Block-only, performance overhead vs raw, small project |

**When to Use:**
- Simple block storage for Kubernetes
- Built-in backup/replication needed
- Small to medium scale (10TB-100TB)
- Team wants minimal operational overhead
- Primarily K8s workloads

**Architecture Diagram:**
```
┌─────────────────────────────────────────────┐
│              Kubernetes Cluster              │
│  ┌──────────────────────────────────────┐   │
│  │         Longhorn Manager              │   │
│  │  ┌─────────┐  ┌─────────┐            │   │
│  │  │ Node 1  │  │ Node 2  │            │   │
│  │  │ ┌─────┐ │  │ ┌─────┐ │            │   │
│  │  │ │Disk │ │  │ │Disk │ │            │   │
│  │  │ └─────┘ │  │ └─────┘ │            │   │
│  │  │Replica │  │Replica │            │   │
│  │  └─────────┘  └─────────┘            │   │
│  │  ┌─────────┐  ┌─────────┐            │   │
│  │  │ Node 3  │  │ Node 4  │            │   │
│  │  │ ┌─────┐ │  │ ┌─────┐ │            │   │
│  │  │ │Disk │ │  │ │Disk │ │            │   │
│  │  │ └─────┘ │  │ └─────┘ │            │   │
│  │  │Replica │  │Replica │            │   │
│  │  └─────────┘  └─────────┘            │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

**Deployment:**
```bash
# Add Longhorn repo
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Install
kubectl create namespace longhorn-system
helm install longhorn longhorn/longhorn \
    --namespace longhorn-system \
    --set defaultSettings.defaultDataPath="/mnt/storage" \
    --set persistence.defaultClassReplicaCount=3

# Air-gap: set image registry
helm install longhorn longhorn/longhorn \
    --namespace longhorn-system \
    --set defaultSettings.registrySecret=harbor-pull-secret \
    --set image.longhorn.manager.repository=harbor.internal/longhornio/longhorn-manager \
    --set image.longhorn.engine.repository=harbor.internal/longhornio/longhorn-engine \
    --set image.longhorn.instanceManager.repository=harbor.internal/longhornio/longhorn-instance-manager \
    --set image.longhorn.shareManager.repository=harbor.internal/longhornio/longhorn-share-manager \
    --set image.longhorn.backingImageManager.repository=harbor.internal/longhornio/backing-image-manager
```

---

### 4. OpenEBS

| Aspect | Details |
|--------|---------|
| **Type** | Container-attached storage (CAS) |
| **Architecture** | Multiple engines (cStor, Mayastor, LocalPV, Jiva) |
| **Production Since** | 2017 |
| **License** | Apache 2.0 |
| **Primary Protocols** | Block (iSCSI, NVMe-oF), K8s PV |
| **Minimum Nodes** | 1 (LocalPV), 3 (replicated) |
| **Strengths** | Multiple engines, flexible, CNCF project |
| **Weaknesses** | Complex engine selection, performance varies |

**When to Use:**
- Need flexible engine selection
- CAS architecture preferred
- Specific workload optimizations (cStor for replication, Mayastor for NVMe)
- Already using CNCF projects

**Engines:**
| Engine | Type | Durability | Performance |
|--------|------|------------|-------------|
| **LocalPV** | Local disk | None | Highest |
| **cStor** | Replicated block | High (3x) | Good |
| **Jiva** | Replicated block | High (3x) | Moderate |
| **Mayastor** | NVMe-native | High (replication) | Highest |

**Architecture Diagram:**
```
┌─────────────────────────────────────────────┐
│              Kubernetes Cluster              │
│  ┌──────────────────────────────────────┐   │
│  │         OpenEBS Operator              │   │
│  │  ┌─────────┐  ┌─────────┐            │   │
│  │  │ Node 1  │  │ Node 2  │            │   │
│  │  │ ┌─────┐ │  │ ┌─────┐ │            │   │
│  │  │ │Pool │ │  │ │Pool │ │            │   │
│  │  │ │ cStor│ │  │ │cStor│ │            │   │
│  │  │ └─────┘ │  │ └─────┘ │            │   │
│  │  │ SPG  │  │ SPG   │            │   │
│  │  └─────────┘  └─────────┘            │   │
│  │  ┌─────────┐  ┌─────────┐            │   │
│  │  │ Node 3  │  │ Node 4  │            │   │
│  │  │ ┌─────┐ │  │ ┌─────┐ │            │   │
│  │  │ │Pool │ │  │ │Pool │ │            │   │
│  │  │ │cStor│ │  │ │cStor│ │            │   │
│  │  │ └─────┘ │  │ └─────┘ │            │   │
│  │  └─────────┘  └─────────┘            │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

---

### 5. Local Path Provisioner

| Aspect | Details |
|--------|---------|
| **Type** | Local persistent storage provisioner |
| **Architecture** | Thin wrapper around local filesystem |
| **Production Since** | 2019 (Rancher) |
| **License** | Apache 2.0 |
| **Primary Protocols** | Local block/file via K8s PV |
| **Minimum Nodes** | 1 |
| **Strengths** | Zero overhead, simplest possible K8s storage |
| **Weaknesses** | No HA, no replication, manual management |

**When to Use:**
- Single-node clusters
- Development/testing
- Databases with built-in replication (e.g., PostgreSQL with Patroni)
- Stateless apps with persistent logs
- Cost-sensitive environments

**Deployment:**
```bash
# Deploy Local Path Provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# Air-gap: use local registry
# Or use Harbor-hosted image

# Configure
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-path-config
  namespace: local-path-storage
data:
  config.json: |
    {
      "nodePathMap": [
        {
          "node": "DEFAULT_NODE_PATH_FOR_NON_LISTED_NODES",
          "paths": ["/opt/local-path-provisioner"]
        }
      ]
    }
  setup: |-
    #!/bin/bash
    set -eu
    mkdir -m 0777 -p ${VOL_DIR}
  teardown: |-
    #!/bin/bash
    set -eu
    rm -rf ${VOL_DIR}
```

---

## Comprehensive Comparison Table

| Feature | Rook-Ceph | MinIO | Longhorn | OpenEBS | Local Path |
|---------|-----------|-------|----------|---------|------------|
| **Deployment Complexity** | High | Low | Medium | Medium | Very Low |
| **Air-Gap Friendliness** | Good | Excellent | Good | Good | Excellent |
| **High Availability** | Excellent | Excellent (MNMD) | Good (3x repl) | Good (engine-dependent) | None |
| **Performance** | High | Very High (S3) | Good | Varies (Mayastor high) | Highest (local) |
| **K8s-Native** | Yes (operator) | Yes (operator) | Yes (operator) | Yes (operator) | Yes (provisioner) |
| **Block Storage** | RBD | ✗ | ✓ (iSCSI) | ✓ (cStor/Mayastor) | ✓ (local) |
| **File Storage** | CephFS | ✗ | ✗ | ✗ | ✓ (local) |
| **Object Storage** | RGW | ✓ (S3) | ✗ | ✗ | ✗ |
| **Erasure Coding** | CRUSH (3x/EC pools) | Built-in (EC:N) | 3x replication | cStor (replication) | ✗ |
| **Minimum Nodes** | 3 | 4 (HA) | 3 | 1-3 | 1 |
| **Recommended Scale** | 50TB-10PB+ | 1TB-500TB | 10TB-100TB | 10TB-100TB | Single node |
| **Upgrade Process** | Rolling (complex) | Simple (replace) | Rolling | Engine-dependent | Re-deploy |
| **Backup Built-in** | RBD snapshots | Bucket replication | ✓ (to NFS/S3) | cStor (zfs) | ✗ |
| **Monitoring** | Prometheus (manual) | Prometheus (built-in) | Prometheus (built-in) | Prometheus (built-in) | ✗ |
| **Multi-Tenancy** | Strong (pools/users) | Strong (tenants/policies) | Basic | Good (CAS) | ✗ |
| **Encryption** | RBD encryption | ✓ (server-side) | ✓ (LUKS) | cStor (zfs) | ✗ |
| **Snapshot/Clone** | ✓ | ✗ (bucket versioning) | ✓ | ✓ (cStor) | ✗ |
| **Resize** | ✓ | N/A | ✓ | ✓ | ✗ (fixed) |
| **Multi-Cluster** | Federation | Federation | DR Stitching | Replicated | ✗ |
| **Resource Overhead** | High (16GB+ per OSD) | Low (4GB per node) | Medium | Medium | Negligible |
| **CNCF Status** | Ceph only | ✓ | ✓ | ✓ | ✗ |
| **Learning Curve** | Steep | Gentle | Gentle | Moderate | None |
| **Community** | Large (Ceph) | Large | Medium | Medium | Small |

---

## Decision Matrix: Which Storage for Which Use Case

### Use Case Mapping

| Use Case | Primary Choice | Alternative | Rationale |
|----------|---------------|-------------|-----------|
| **Velero Backups** | MinIO | Ceph RGW | S3 simplicity vs unified stack |
| **Database (RWO block)** | Rook-Ceph RBD | Longhorn | Maturity vs simplicity |
| **Shared Files (RWX)** | Rook-Ceph CephFS | ✗ (only option) | Only enterprise file solution |
| **ML/Data Lake** | MinIO | Ceph RGW | Native S3, erasure coding |
| **ArgoCD Artifacts** | MinIO | Ceph RGW | S3-first, simple |
| **CI/CD Cache** | MinIO | Local Path | Fast object store vs zero replication |
| **CoreDNS etcd** | Local Path | Rook-Ceph RBD | Low latency, simple |
| **Monitoring (Prometheus)** | Rook-Ceph RBD | Longhorn | Need durability + block |
| **Log Storage (Loki)** | MinIO | RGW | S3 backend |
| **Multi-Tenant Platform** | Rook-Ceph | MinIO + Longhorn | Unified vs modular |
| **Air-Gap Mgmt Cluster** | MinIO + Longhorn | Rook-Ceph | Simpler management |
| **Air-Gap App Cluster** | Rook-Ceph | MinIO + Longhorn | Full-featured |
| **Dev/Test** | Local Path | MinIO (SNSD) | Simplicity |
| **Edge/IoT** | MinIO (SNSD) | Local Path | Minimal footprint |
| **Large Scale (100TB+)** | Rook-Ceph | MinIO | Proven at scale |

### Deployment Complexity vs Feature Richness

```
Feature Richness ▲
                   │
    Rook-Ceph  ●   │
                   │
                   │       ● OpenEBS
                   │
                   │   ● Longhorn
                   │
                   │               ● MinIO
                   │   ● Local Path
                   └──────────────────────────► 
                   Simple          Complex
                        Deployment
```

---

## Air-Gap Deployment Difficulty

| Solution | Package Complexity | Image Count | Config Complexity | Overall Difficulty |
|----------|-------------------|-------------|-------------------|-------------------|
| **Rook-Ceph** | High (many packages) | 10+ images | High | **Complex** |
| **MinIO** | Low (single binary) | 3-5 images | Low | **Simple** |
| **Longhorn** | Medium | 5 images | Low-Medium | **Moderate** |
| **OpenEBS** | Medium | 5-8 images | Medium | **Moderate** |
| **Local Path** | Very Low | 1 image | Very Low | **Trivial** |

### Air-Gap Package Checklist

#### Rook-Ceph
- [ ] Ceph Reef packages (apt repo from Nexus)
- [ ] cephadm binary
- [ ] 10+ container images in Harbor
- [ ] CSI driver images
- [ ] Rook operator image

#### MinIO
- [ ] minio binary (or container image)
- [ ] mc binary
- [ ] operator image (if K8s-native)
- [ ] console image
- [ ] Total: 3-5 images

#### Longhorn
- [ ] longhorn-manager image
- [ ] longhorn-engine image
- [ ] longhorn-instance-manager image
- [ ] longhorn-share-manager image
- [ ] backing-image-manager image
- [ ] Total: 5 images

#### OpenEBS
- [ ] maya-apiserver image
- [ ] openebs-provisioner image
- [ ] cstor-pool image
- [ ] cstor-volume-mgmt image
- [ ] mayastor images (if using Mayastor)
- [ ] Total: 5-8 images

#### Local Path Provisioner
- [ ] rancher/local-path-provisioner image
- [ ] Total: 1 image

---

## Recommended Architecture for Air-Gap Deployment

### Management Cluster

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Object Storage** | MinIO (distributed) | Simple, reliable, S3-native |
| **Block Storage** | Longhorn | Lightweight, K8s-native |
| **File Storage** | None (NFS from NAS) | Management workloads don't need CephFS |

### Application Cluster

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Unified Storage** | Rook-Ceph | Full-featured, multi-tenant |
| **Block** | RBD | Databases, high-performance |
| **File** | CephFS | Shared workloads |
| **Object** | RGW or MinIO | Based on team preference |

### Alternative: Minimal Management Cluster

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Object Storage** | MinIO (SNSD for mgmt) | Minimal footprint |
| **Block Storage** | Local Path Provisioner | Zero overhead |
| **File Storage** | CephFS (from app cluster) | Access cross-cluster |

---

## Mixed Deployment Example

```
┌─────────────────────────────────────────────────────────────────┐
│                    Management Cluster                            │
│  ┌─────────────────┐  ┌─────────────────┐                       │
│  │   MinIO (HA)    │  │   Longhorn      │                       │
│  │   4 nodes       │  │   3 nodes       │                       │
│  │   10 TB EC:4   │  │   5 TB repl:3   │                       │
│  │   Velero, Artif │  │   Databases     │                       │
│  └─────────────────┘  └─────────────────┘                       │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    Application Cluster                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Rook-Ceph                             │   │
│  │   5 MON + 5 OSD (30 TB raw, 10 TB usable EC:2)           │   │
│  │   CephFS (shared), RBD (block), RGW (S3)                │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## References

- [Rook-Ceph](https://rook.io/)
- [MinIO](https://min.io/)
- [Longhorn](https://longhorn.io/)
- [OpenEBS](https://openebs.io/)
- [Local Path Provisioner](https://github.com/rancher/local-path-provisioner)
- [Ceph](https://ceph.com/)
