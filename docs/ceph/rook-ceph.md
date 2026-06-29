# Rook-Ceph Deployment Guide

## Overview

Rook-Ceph provides a Kubernetes-native operator for deploying and managing Ceph clusters. This guide covers deploying Ceph via the Rook operator in an air-gapped environment using Harbor for container images.

---

## Decision Matrix: Rook-Ceph vs Bare-Metal Ceph

| Criteria | Rook-Ceph | Bare-Metal Ceph (cephadm) |
|----------|-----------|--------------------------|
| **Deployment Complexity** | Medium (K8s-native) | High (manual orchestration) |
| **Operational Overhead** | Low (operator-managed) | High (manual management) |
| **Kubernetes Integration** | Native (CRDs) | Requires external CSI |
| **Upgrade Process** | Rolling (operator-driven) | Manual (cephadm) |
| **Scaling** | Add nodes via CRD | Manual host addition |
| **Self-Healing** | Automatic pod rescheduling | Depends on cephadm |
| **Multi-Cluster** | Per-cluster operator | Independent clusters |
| **Resource Overhead** | Higher (K8s overhead) | Lower (bare-metal) |
| **Flexibility** | Limited by CRD | Full Ceph feature access |
| **Air-Gap Complexity** | Medium (images from Harbor) | Medium (packages from Nexus) |
| **Monitoring** | Built-in Prometheus rules | Manual setup |
| **Team Skill Required** | K8s + Storage | Linux + Storage + Ceph |
| **Best For** | Cloud-native workloads, K8s-first orgs | Maximum control, existing Ceph expertise |

### Recommendation

- **Management Cluster:** Choose bare-metal Ceph if team has deep Ceph expertise; choose Rook-Ceph for operational simplicity.
- **Application Cluster:** Rook-Ceph recommended for tighter K8s integration and automated lifecycle management.

---

## Prerequisites

### Kubernetes Cluster Requirements

| Requirement | Value |
|-------------|-------|
| Kubernetes Version | 1.25+ |
| Container Runtime | containerd 1.6+ |
| Helm | 3.12+ |
| Kernel | 5.4+ (for RBD CSI) |
| Nodes | Minimum 5 for dedicated storage |

### Air-Gap Image Preparation

All Rook-Ceph images must be available in Harbor:

```bash
# Required images (adjust versions as needed)
IMAGES=(
    "docker.io/rook/ceph:v$ROOK_VERSION"
    "docker.io/ceph/ceph:v$CEPH_VERSION"
    "quay.io/cephcsi/cephcsi:v$CEPH_CSI_VERSION"
    "quay.io/ceph/ceph:v$CEPH_VERSION"
    "docker.io/ceph/ceph-grafana:latest"
    "quay.io/ceph/ceph:latest"
    "registry.k8s.io/sig-storage/csi-provisioner:v$CSI_PROVISIONER_VERSION"
    "registry.k8s.io/sig-storage/csi-attacher:v$CSI_ATTACHER_VERSION"
    "registry.k8s.io/sig-storage/csi-resizer:v$CSI_RESIZER_VERSION"
    "registry.k8s.io/sig-storage/csi-snapshotter:v$CSI_SNAPSHOTTER_VERSION"
    "registry.k8s.io/sig-storage/csi-node-driver-registrar:v$CSI_NODE_DRIVER_VERSION"
)

# Push to Harbor
for img in "${IMAGES[@]}"; do
    crane copy "$img" "harbor.internal/rook-ceph/$(basename "$img")"
done
```

### Node Labeling for Storage Nodes

```bash
# Label storage nodes for Rook scheduling
kubectl label nodes osd01 osd02 osd03 osd04 osd05 \
    rook-ceph-role=storage-node

# Label specific nodes for MONs (optional)
kubectl label nodes mon01 mon02 mon03 \
    rook-ceph-mon=node

# Taint storage nodes to prevent other workloads (optional)
kubectl taint nodes osd01 osd02 osd03 osd04 osd05 \
    dedicated=rook-ceph:NoSchedule
```

---

## Rook-Ceph Operator Deployment via Helm

### Step 1: Add Rook Helm Repository

```bash
# In air-gap: use local chart or Harbor-hosted chart
helm repo add rook-release https://charts.rook.io/release
helm repo update

# Or use local chart (downloaded and pushed to Harbor)
helm pull rook-release/rook-ceph --version $ROOK_VERSION
# Push chart to Harbor chart museum if available
```

### Step 2: Create Namespace and Values

```bash
kubectl create namespace rook-ceph
```

### Step 3: Deploy Operator

```bash
# values-operator.yaml for air-gap
cat <<EOF > rook-ceph-operator-values.yaml
image:
  repository: harbor.internal/rook-ceph/rook/ceph
  tag: "$ROOK_VERSION"

csi:
  cephFSImage: "harbor.internal/rook-ceph/cephcsi/cephcsi:v$CEPH_CSI_VERSION"
  provisionerImage: "harbor.internal/rook-ceph/csi-provisioner:v$CSI_PROVISIONER_VERSION"
  attacherImage: "harbor.internal/rook-ceph/csi-attacher:v$CSI_ATTACHER_VERSION"
  resizerImage: "harbor.internal/rook-ceph/csi-resizer:v$CSI_RESIZER_VERSION"
  snapshotterImage: "harbor.internal/rook-ceph/csi-snapshotter:v$CSI_SNAPSHOTTER_VERSION"
  nodeDriverRegistrarImage: "harbor.internal/rook-ceph/csi-node-driver-registrar:v$CSI_NODE_DRIVER_VERSION"

# Air-gap: disable internet-dependent features
enableDiscoveryDaemon: false
pspEnable: false

# Resource limits
resources:
  limits:
    cpu: "1"
    memory: "512Mi"
  requests:
    cpu: "200m"
    memory: "128Mi"
EOF

helm install rook-ceph rook-release/rook-ceph \
    --namespace rook-ceph \
    --values rook-ceph-operator-values.yaml \
    --set operatorNamespace=rook-ceph
```

### Step 4: Verify Operator

```bash
kubectl -n rook-ceph get pods -l app=rook-ceph-operator
# Expected: 1 pod Running

kubectl -n rook-ceph get pods -l app=rook-ceph-ocs
```

---

## CephCluster CRD Configuration

### Full Cluster Specification

```yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: harbor.internal/rook-ceph/ceph/ceph:v$CEPH_VERSION
    allowUnsupported: false
  
  dataDirHostPath: /var/lib/rook
  
  mon:
    count: 3
    allowMultiplePerNode: false
    volumeClaimTemplate:
      spec:
        storageClassName: local-ssd  # Use fast storage for MONs
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 20Gi
  
  mgr:
    count: 2
    allowMultiplePerNode: false
    modules:
      - name: pg_autoscaler
        enabled: true
      - name: balancer
        enabled: true
      - name: dashboard
        enabled: true
  
  storage:
    useAllDevices: false
    config:
      osdsPerDevice: "1"
      encryptedDevice: "true"
    nodes:
      - name: "osd01"
        devices:
          - name: /dev/sdb
          - name: /dev/sdc
          - name: /dev/sdd
        config:
          databaseSizeMB: "1024"    # WAL on SSD
          walSizeMB: "512"
          deviceClass: hdd
      - name: "osd02"
        devices:
          - name: /dev/sdb
          - name: /dev/sdc
          - name: /dev/sdd
        config:
          databaseSizeMB: "1024"
          walSizeMB: "512"
          deviceClass: hdd
      - name: "osd03"
        devices:
          - name: /dev/sdb
          - name: /dev/sdc
          - name: /dev/sdd
        config:
          databaseSizeMB: "1024"
          walSizeMB: "512"
          deviceClass: hdd
      - name: "osd04"
        devices:
          - name: /dev/sdb
          - name: /dev/sdc
          - name: /dev/sdd
        config:
          databaseSizeMB: "1024"
          walSizeMB: "512"
          deviceClass: hdd
      - name: "osd05"
        devices:
          - name: /dev/sdb
          - name: /dev/sdc
          - name: /dev/sdd
        config:
          databaseSizeMB: "1024"
          walSizeMB: "512"
          deviceClass: hdd
    # Shared SSD/NVMe for WAL/DB
    storageClassDeviceSets:
      - name: wal-db-storage
        count: 5
        portable: false
        tuneDeviceClass: true
        volumeClaimTemplates:
          - metadata:
              name: data
            spec:
              storageClassName: local-nvme
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 100Gi
        placement:
          nodeAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
                - matchExpressions:
                    - key: rook-ceph-role
                      operator: In
                      values:
                        - storage-node
  
  network:
    connections:
      encryption:
        enabled: false
      compression:
        enabled: false
    multiCluster:
      serviceCIDR: "10.1.1.0/24"
  
  resources:
    mgr:
      limits:
        cpu: "2"
        memory: "2Gi"
      requests:
        cpu: "500m"
        memory: "512Mi"
    mon:
      limits:
        cpu: "1"
        memory: "1Gi"
      requests:
        cpu: "250m"
        memory: "256Mi"
    osd:
      limits:
        cpu: "2"
        memory: "4Gi"
      requests:
        cpu: "500m"
        memory: "2Gi"
    mds:
      limits:
        cpu: "2"
        memory: "4Gi"
      requests:
        cpu: "500m"
        memory: "1Gi"
  
  priorityClassNames:
    mon: system-cluster-critical
    osd: system-node-critical
    mgr: system-cluster-critical
  
  healthCheck:
    daemonHealth:
      mon:
        disabled: false
        interval: 45s
      osd:
        disabled: false
        interval: 60s
      status:
        disabled: false
        interval: 60s
    livenessProbe:
      mgr:
        disabled: false
      mon:
        disabled: false
      osd:
        disabled: false
```

### Apply Cluster

```bash
kubectl apply -f cephcluster.yaml

# Watch deployment
kubectl -n rook-ceph get cephcluster -w
kubectl -n rook-ceph get pods -w
```

### Verify Cluster

```bash
kubectl -n rook-ceph get cephcluster rook-ceph -o yaml | jq '.status'

# Expected phases:
# - Progressing (deploying)
# - Ready (operational)
```

---

## CephFilesystem CRD

```yaml
apiVersion: ceph.rook.io/v1
kind: CephFilesystem
metadata:
  name: rook-ceph-filesystem
  namespace: rook-ceph
spec:
  metadataPool:
    replicated:
      size: 3
      requireSafeReplicaSize: true
    parameters:
      compression_mode: none
  dataPools:
    - name: replicated
      replicated:
        size: 3
        requireSafeReplicaSize: true
      parameters:
        compression_mode: none
  preservePoolsOnDelete: true
  metadataServer:
    activeCount: 1
    activeStandby: true
    resources:
      limits:
        cpu: "2"
        memory: "4Gi"
      requests:
        cpu: "500m"
        memory: "1Gi"
```

```bash
kubectl apply -f cephfilesystem.yaml
kubectl -n rook-ceph get cephfilesystem
```

---

## CephObjectStore CRD (S3)

```yaml
apiVersion: ceph.rook.io/v1
kind: CephObjectStore
metadata:
  name: rook-ceph-rgw
  namespace: rook-ceph
spec:
  metadataPool:
    replicated:
      size: 3
      requireSafeReplicaSize: true
    parameters:
      compression_mode: none
  dataPool:
    replicated:
      size: 3
      requireSafeReplicaSize: true
      ecConfig:
        dataChunks: 4
        codingChunks: 2
  preservePoolsOnDelete: true
  gateway:
    port: 80
    securePort: 443
    instances: 2
    allNodes: false
    resources:
      limits:
        cpu: "1"
        memory: "2Gi"
      requests:
        cpu: "250m"
        memory: "512Mi"
  healthCheck:
    bucket:
      disabled: false
      interval: 60s
```

---

## CephBlockPool CRD (RBD)

```yaml
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: rook-ceph-blockpool
  namespace: rook-ceph
spec:
  failureDomain: host
  replicated:
    size: 3
  parameters:
    compression_mode: none
  deviceClass: hdd
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: rook-ceph-blockpool
  imageFormat: "2"
  imageFeatures: layering,deep-flatten,exclusive-lock,object-map,fast-diff
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
  csi.storage.k8s.io/fstype: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
  - discard
```

---

## Monitoring Integration

Rook ships with Prometheus rules and Grafana dashboards:

```bash
# Enable Prometheus integration
kubectl apply -f https://raw.githubusercontent.com/rook/rook/release-$ROOK_VERSION/deploy/examples/monitoring/rbac.yaml

# ServiceMonitor for Ceph
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rook-ceph-mgr
  namespace: rook-ceph
spec:
  selector:
    matchLabels:
      app: rook-ceph-mgr
      rook_cluster: rook-ceph
  namespaceSelector:
    matchNames:
      - rook-ceph
  endpoints:
    - port: http-metrics
      interval: 15s
```

### Key Metrics to Monitor

| Metric | Alert Threshold |
|--------|-----------------|
| `ceph_health_status` | != 0 |
| `ceph_osd_up` | < total OSDs |
| `ceph_osd_in` | < total OSDs |
| `ceph_pool_stored` | > 80% capacity |
| `ceph_pg_inactive` | > 0 |
| `ceph_pg_unclean` | > 0 |
| `ceph_mon_quorum_status` | != 1 for leader |

---

## Upgrade Procedure

### 1. Verify Current State

```bash
kubectl -n rook-ceph get cephcluster
kubectl -n rook-ceph get pods
```

### 2. Update Operator

```bash
# Update Helm chart
helm upgrade rook-ceph rook-release/rook-ceph \
    --namespace rook-ceph \
    --set image.tag="$NEW_ROOK_VERSION"
```

### 3. Update Ceph Version

```yaml
# Update CephCluster CRD
spec.cephVersion.image: harbor.internal/rook-ceph/ceph/ceph:v$NEW_CEPH_VERSION
```

```bash
kubectl apply -f cephcluster.yaml
# Rook performs rolling upgrade automatically
```

### 4. Monitor Upgrade

```bash
kubectl -n rook-ceph get cephcluster -w
kubectl -n rook-ceph get pods -w
```

> **Note:** Upgrades are rolling. Each OSD/MON/MGR is restarted sequentially. PGs will temporarily be degraded during OSD restarts.

---

## Troubleshooting Common Issues

### OSD Pod Fails to Start

```bash
# Check events
kubectl -n rook-ceph describe pod <osd-pod-name>

# Check operator logs
kubectl -n rook-ceph logs -l app=rook-ceph-operator --tail=100

# Common causes:
# - Disk not available/wiped
# - Permission issues
# - Resource limits
```

### Cluster Stuck in "Progressing"

```bash
kubectl -n rook-ceph get cephcluster -o jsonpath='{.status.ceph.status.health}'

# Check individual component status
kubectl -n rook-ceph get cephmon,cephosd,cephmgr,cephfilesystem
```

### MON Quorum Lost

```bash
# Exec into MON pod
kubectl -n rook-ceph exec -it <mon-pod> -- ceph mon stat

# Check MON logs
kubectl -n rook-ceph logs <mon-pod>
```

### OSD Not Claiming Device

```bash
# Ensure device is unmounted and wiped
sudo umount /dev/sdb
sudo wipefs -a /dev/sdb

# Check if device is recognized
kubectl -n rook-ceph logs -l app=rook-ceph-operator | grep -i "device\|disk"
```

### Performance Issues

```bash
# Check OSD resource usage
kubectl -n rook-ceph top pods

# Check network latency between nodes
# Check disk IOPS on OSD nodes
```

---

## Air-Gap Considerations

| Component | Source | Image |
|-----------|--------|-------|
| Rook Operator | Harbor | `harbor.internal/rook-ceph/rook/ceph:v$ROOK_VERSION` |
| Ceph Daemons | Harbor | `harbor.internal/rook-ceph/ceph/ceph:v$CEPH_VERSION` |
| CSI Drivers | Harbor | `harbor.internal/rook-ceph/cephcsi/cephcsi:v$CEPH_CSI_VERSION` |
| CSI Sidecars | Harbor | Various (see prerequisites) |
| Discovery Daemon | Disabled | Not needed in air-gap |

### Image Synchronization Script

```bash
#!/bin/bash
# sync-rook-images.sh - Run from internet-connected host

REGISTRY="harbor.internal/rook-ceph"
ROOK_VERSION="${ROOK_VERSION:-v1.13.0}"
CEPH_VERSION="${CEPH_VERSION:-v18.2.1}"
CSI_VERSION="${CEPH_CSI_VERSION:-v3.9.0}"

IMAGES=(
    "docker.io/rook/ceph:${ROOK_VERSION}"
    "docker.io/ceph/ceph:${CEPH_VERSION}"
    "quay.io/cephcsi/cephcsi:${CSI_VERSION}"
    "registry.k8s.io/sig-storage/csi-provisioner:v3.6.0"
    "registry.k8s.io/sig-storage/csi-attacher:v4.4.0"
    "registry.k8s.io/sig-storage/csi-resizer:v1.9.0"
    "registry.k8s.io/sig-storage/csi-snapshotter:v6.3.0"
    "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.9.0"
)

for img in "${IMAGES[@]}"; do
    echo "Copying $img"
    crane copy "$img" "${REGISTRY}/$(basename "$img")"
done

echo "All images synced to $REGISTRY"
```

---

## References

- [Rook-Ceph Documentation](https://rook.io/docs/rook/latest/)
- [Rook GitHub](https://github.com/rook/rook)
- [Ceph CSI Documentation](https://docs.ceph.com/en/latest/rbd/rbd-kubernetes/)
