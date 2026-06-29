# CephFS CSI Driver Guide

## Overview

The CephFS CSI (Container Storage Interface) driver enables Kubernetes workloads to consume CephFS volumes dynamically. This guide covers deployment for both bare-metal Ceph and Rook-Ceph clusters in an air-gapped environment.

---

## CephFS vs RBD Decision Table

| Criteria | CephFS (File) | RBD (Block) |
|----------|---------------|-------------|
| **Access Mode** | ReadWriteMany (RWX) | ReadWriteOnce (RWO) |
| **Use Case** | Shared storage, home dirs, config | Databases, single-writer apps |
| **Multi-Pod** | Yes (concurrent) | No (exclusive) |
| **Snapshot** | Yes | Yes |
| **Clone** | Yes | Yes |
| **Resize** | Yes | Yes |
| **Performance** | Lower (metadata overhead) | Higher (direct block) |
| **POSIX Semantics** | Full | N/A |
| **NFS Replacement** | Yes | No |
| **K8s Native** | Via CSI | Via CSI |
| **Best For** | Shared content, CI/CD artifacts, logs | PostgreSQL, etcd, high-IOPS workloads |

### Decision Flowchart

```
Need shared access (multiple pods)?
├── YES → CephFS
└── NO
    ├── Need block device semantics?
    │   ├── YES → RBD
    │   └── NO
    │       ├── Need POSIX file operations?
    │       │   ├── YES → CephFS
    │       │   └── NO → RBD (default for single-writer)
    └── Performance critical?
        ├── YES → RBD
        └── NO → CephFS (more flexible)
```

---

## CSI Driver Deployment

### Prerequisites

| Component | Minimum Version |
|-----------|----------------|
| Kubernetes | 1.25+ |
| containerd | 1.6+ |
| Ceph | Reef (18.x) |
| Helm | 3.12+ |

### Air-Gap Image Requirements

All images must be available in Harbor:

```bash
# Required CSI images
IMAGES=(
    "quay.io/cephcsi/cephcsi:v$CEPH_CSI_VERSION"
    "registry.k8s.io/sig-storage/csi-provisioner:v$CSI_PROVISIONER_VERSION"
    "registry.k8s.io/sig-storage/csi-attacher:v$CSI_ATTACHER_VERSION"
    "registry.k8s.io/sig-storage/csi-resizer:v$CSI_RESIZER_VERSION"
    "registry.k8s.io/sig-storage/csi-snapshotter:v$CSI_SNAPSHOTTER_VERSION"
    "registry.k8s.io/sig-storage/csi-node-driver-registrar:v$CSI_NODE_DRIVER_VERSION"
)

# Push to Harbor
REGISTRY="harbor.internal/ceph-csi"
for img in "${IMAGES[@]}"; do
    crane copy "$img" "${REGISTRY}/$(basename "$img")"
done
```

### Deploy via Helm (Bare-Metal Ceph)

```bash
# Add ceph-csi Helm repo (or use local chart)
helm repo add ceph-csi https://ceph.github.io/csi-charts
helm repo update

# Create values file
cat <<EOF > ceph-csi-values.yaml
# Image overrides for air-gap
images:
  csiProvisioner:
    repository: harbor.internal/ceph-csi/csi-provisioner
    tag: "$CSI_PROVISIONER_VERSION"
  csiAttacher:
    repository: harbor.internal/ceph-csi/csi-attacher
    tag: "$CSI_ATTACHER_VERSION"
  csiResizer:
    repository: harbor.internal/ceph-csi/csi-resizer
    tag: "$CSI_RESIZER_VERSION"
  csiSnapshotter:
    repository: harbor.internal/ceph-csi/csi-snapshotter
    tag: "$CSI_SNAPSHOTTER_VERSION"
  csiNodeDriverRegistrar:
    repository: harbor.internal/ceph-csi/csi-node-driver-registrar
    tag: "$CSI_NODE_DRIVER_VERSION"
  driver:
    repository: harbor.internal/ceph-csi/cephcsi
    tag: "$CEPH_CSI_VERSION"

# Ceph cluster configuration
csiConfig:
  - clusterID: <CEPH_FSID>
    monitors:
      - 10.1.1.11:6789
      - 10.1.1.12:6789
      - 10.1.1.13:6789
      - 10.1.1.14:6789
      - 10.1.1.15:6789

# Enable topology for topology-aware scheduling
topology:
  enabled: true

# Resource limits
provisioner:
  resources:
    limits:
      cpu: "500m"
      memory: "512Mi"
    requests:
      cpu: "100m"
      memory: "128Mi"

nodeplugin:
  resources:
    limits:
      cpu: "500m"
      memory: "512Mi"
    requests:
      cpu: "100m"
      memory: "128Mi"

# StorageClass creation
storageClass:
  create: true
  name: cephfs-sc
  clusterID: <CEPH_FSID>
  fsName: cephfs
  pool: cephfs_data
  provisioner: rook-ceph.cephfs.csi.ceph.com
  reclaimPolicy: Delete
  allowVolumeExpansion: true
  mountOptions:
    - noatime
    - nodiratime

# RBD StorageClass
rbdStorageClass:
  create: true
  name: rbd-sc
  clusterID: <CEPH_FSID>
  pool: k8s-rbd
  provisioner: rook-ceph.rbd.csi.ceph.com
  reclaimPolicy: Delete
  allowVolumeExpansion: true
  imageFormat: "2"
  imageFeatures: layering,deep-flatten,exclusive-lock,object-map,fast-diff
  fstype: ext4
  mountOptions:
    - discard
EOF

# Install
helm install ceph-csi ceph-csi/ceph-csi \
    --namespace ceph-csi \
    --create-namespace \
    --values ceph-csi-values.yaml
```

### Deploy via Rook-Ceph (Simplified)

When using Rook-Ceph, the CSI drivers are deployed automatically:

```bash
# CSI is enabled by default in Rook-Ceph
# Verify CSI pods
kubectl -n rook-ceph get pods -l app=csi-cephfsplugin
kubectl -n rook-ceph get pods -l app=csi-cephfsplugin-provisioner
kubectl -n rook-ceph get pods -l app=csi-rbdplugin
kubectl -n rook-ceph get pods -l app=csi-rbdplugin-provisioner

# StorageClasses are created automatically
kubectl get sc
# rook-cephfs
# rook-ceph-block
```

---

## Bare-Metal Ceph: External Cluster Configuration

### Step 1: Create CephFS CSI User

```bash
# On Ceph admin node
sudo ceph auth get-or-create client.csi-cephfs \
    mon 'allow r, allow command "osd blacklist"' \
    osd 'allow rw pool=cephfs_metadata, allow rw pool=cephfs_data' \
    mds 'allow rw, allow' \
    mgr 'allow r'

# Get the key
sudo ceph auth get-key client.csi-cephfs
# Save output as CSI_CEPHFS_KEY

# Get cluster FSID
sudo ceph fsid
# Save output as CEPH_FSID
```

### Step 2: Create RBD CSI User

```bash
sudo ceph auth get-or-create client.csi-rbd \
    mon 'allow r, allow command "osd blacklist"' \
    osd 'allow rw pool=k8s-rbd' \
    mgr 'allow r'

sudo ceph auth get-key client.csi-rbd
# Save output as CSI_RBD_KEY
```

### Step 3: Export MON Endpoints

```bash
# Get MON dump
sudo ceph mon dump -f json | jq -r '.mons[].addr' | head -5
# Output: 10.1.1.11:6789,10.1.1.12:6789,...
```

### Step 4: Create Kubernetes Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: csi-cephfs-secret
  namespace: ceph-csi
stringData:
  userID: csi-cephfs
  userKey: "<CSI_CEPHFS_KEY>"
---
apiVersion: v1
kind: Secret
metadata:
  name: csi-rbd-secret
  namespace: ceph-csi
stringData:
  userID: csi-rbd
  userKey: "<CSI_RBD_KEY>"
```

---

## StorageClass Configuration

### CephFS StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cephfs-sc
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: "<CEPH_FSID>"
  fsName: cephfs
  pool: cephfs_data
  provisioner-secret-name: csi-cephfs-secret
  provisioner-secret-namespace: ceph-csi
  controller-expand-secret-name: csi-cephfs-secret
  controller-expand-secret-namespace: ceph-csi
  node-stage-secret-name: csi-cephfs-secret
  node-stage-secret-namespace: ceph-csi
  csi.storage.k8s.io/fstype: ext4
  # Mount options
  mountOptions:
    - noatime
    - nodiratime
    - noquotareclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

### RBD StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rbd-sc
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: "<CEPH_FSID>"
  pool: k8s-rbd
  imageFormat: "2"
  imageFeatures: layering,deep-flatten,exclusive-lock,object-map,fast-diff
  csi.storage.k8s.io/provisioner-secret-name: csi-rbd-secret
  csi.storage.k8s.io/provisioner-secret-namespace: ceph-csi
  csi.storage.k8s.io/controller-expand-secret-name: csi-rbd-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: ceph-csi
  csi.storage.k8s.io/node-stage-secret-name: csi-rbd-secret
  csi.storage.k8s.io/node-stage-secret-namespace: ceph-csi
  csi.storage.k8s.io/fstype: ext4
  encrypted: "false"
  # Cluster-specific network settings
  radosNamespace: ""
  mapOptions: ""
  topologyConstrainedPools: |
    - poolName: k8s-rbd
      domainSegments:
        - "region": us-east-1
          - "zone": rack-a
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
  - discard
  - noatime
volumeBindingMode: WaitForFirstConsumer
```

---

## PVC Examples

### CephFS PVC (ReadWriteMany)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cephfs-shared-data
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: cephfs-sc
  resources:
    requests:
      storage: 100Gi
```

### RBD PVC (ReadWriteOnce)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rbd-database
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: rbd-sc
  resources:
    requests:
      storage: 50Gi
```

### Pod Using CephFS

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-cephfs
spec:
  containers:
    - name: app
      image: nginx:latest
      volumeMounts:
        - name: shared-data
          mountPath: /usr/share/nginx/html
  volumes:
    - name: shared-data
      persistentVolumeClaim:
        claimName: cephfs-shared-data
```

### StatefulSet with RBD

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15
          volumeMounts:
            - name: pg-data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata:
        name: pg-data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: rbd-sc
        resources:
          requests:
            storage: 100Gi
```

---

## Snapshot and Clone

### Enable Volume Snapshot Support

```bash
# Verify snapshotter is deployed
kubectl get pods -n ceph-csi -l app=csi-snapshotter

# Install VolumeSnapshotClass (if not auto-created)
```

### VolumeSnapshotClass

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: cephfs-snapshotclass
driver: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: "<CEPH_FSID>"
  fsName: cephfs
  pool: cephfs_data
  snapshotter-secret-name: csi-cephfs-secret
  snapshotter-secret-namespace: ceph-csi
deletionPolicy: Delete
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: rbd-snapshotclass
driver: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: "<CEPH_FSID>"
  pool: k8s-rbd
  snapshotter-secret-name: csi-rbd-secret
  snapshotter-secret-namespace: ceph-csi
deletionPolicy: Delete
```

### Create Snapshot

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: cephfs-snapshot-demo
spec:
  volumeSnapshotClassName: cephfs-snapshotclass
  source:
    persistentVolumeClaimName: cephfs-shared-data
```

### Restore from Snapshot

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cephfs-from-snapshot
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: cephfs-sc
  resources:
    requests:
      storage: 100Gi
  dataSource:
    name: cephfs-snapshot-demo
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

### Clone Volume

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cephfs-clone
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: cephfs-sc
  resources:
    requests:
      storage: 100Gi
  dataSource:
    name: cephfs-shared-data
    kind: PersistentVolumeClaim
    apiGroup: ""
```

---

## Volume Expansion

```bash
# Online expansion (while PVC is in-use)
kubectl edit pvc cephfs-shared-data
# Change resources.requests.storage to new value

# Verify
kubectl get pvc cephfs-shared-data
kubectl describe pvc cephfs-shared-data | grep -i "resize"

# Filesystem resize happens automatically on node
```

---

## Mount Options and Performance Tuning

### CephFS Mount Options

| Option | Description | Recommendation |
|--------|-------------|----------------|
| `noatime` | Disable access time updates | Always enable |
| `nodiratime` | Disable directory access time | Always enable |
| `noquota` | Disable quota checking | Enable if no quotas |
| `fsnap` | Enable snapshot mounting | For read-only snapshots |
| `name` | Username | CSI handles this |
| `secret` | Authentication | CSI handles this |

### RBD Performance Tuning

```yaml
# StorageClass with performance options
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rbd-fast
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: "<CEPH_FSID>"
  pool: k8s-rbd
  imageFormat: "2"
  imageFeatures: layering,exclusive-lock,object-map,fast-diff
  csi.storage.k8s.io/fstype: ext4
  # RBD-specific tuning
  mapOptions: ""  # e.g., "lock_onread" for read-only maps
  stripeUnit: ""
  stripeCount: ""
  objectSize: ""
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
  - discard
  - noatime
  - nobarrier
```

### Kernel Tuning for CephFS

```bash
# On all nodes using CephFS
# Increase buffer sizes
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216"
sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216"

# Make persistent
cat <<EOF >> /etc/sysctl.d/99-cephfs.conf
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF
sysctl --system
```

---

## Multi-Cluster Storage Access

For scenarios where both management and application clusters need access to the same Ceph cluster:

### Architecture

```
┌─────────────────────┐     ┌─────────────────────┐
│ Management Cluster  │     │ Application Cluster │
│                     │     │                     │
│ ┌─────────────────┐ │     │ ┌─────────────────┐ │
│ │  Ceph CSI       │ │     │ │  Ceph CSI       │ │
│ │  (same cluster)  │─┼─────┼─│  (same cluster)  │ │
│ └─────────────────┘ │     │ └─────────────────┘ │
│                     │     │                     │
└─────────────────────┘     └─────────────────────┘
            │                           │
            └───────────┬───────────────┘
                        │
              ┌─────────┴─────────┐
              │   Ceph Cluster    │
              │  (bare-metal)     │
              │  5 MON + 5 OSD   │
              └───────────────────┘
```

### Configuration

```yaml
# Both clusters use the same Ceph cluster config
# Different user IDs for isolation
# Management cluster user
apiVersion: v1
kind: Secret
metadata:
  name: csi-cephfs-secret
  namespace: ceph-csi
stringData:
  userID: csi-cephfs-mgmt
  userKey: "<MGMT_CLUSTER_KEY>"
---
# Application cluster user
apiVersion: v1
kind: Secret
metadata:
  name: csi-cephfs-secret
  namespace: ceph-csi
stringData:
  userID: csi-cephfs-app
  userKey: "<APP_CLUSTER_KEY>"
```

### Ceph User Caps for Multi-Cluster

```bash
# Management cluster user - full access
sudo ceph auth get-or-create client.csi-cephfs-mgmt \
    mon 'allow r' \
    osd 'allow rw pool=cephfs_metadata, allow rw pool=cephfs_data' \
    mds 'allow rw' \
    mgr 'allow r'

# Application cluster user - restricted to specific pool
sudo ceph auth get-or-create client.csi-cephfs-app \
    mon 'allow r' \
    osd 'allow rw pool=app_data' \
    mds 'allow rw' \
    mgr 'allow r'
```

---

## Air-Gap Considerations

| Component | Image | Harbor Path |
|-----------|-------|-------------|
| cephcsi | cephcsi:v$CEPH_CSI_VERSION | `harbor.internal/ceph-csi/cephcsi` |
| csi-provisioner | csi-provisioner:v$CSI_PROVISIONER_VERSION | `harbor.internal/ceph-csi/csi-provisioner` |
| csi-attacher | csi-attacher:v$CSI_ATTACHER_VERSION | `harbor.internal/ceph-csi/csi-attacher` |
| csi-resizer | csi-resizer:v$CSI_RESIZER_VERSION | `harbor.internal/ceph-csi/csi-resizer` |
| csi-snapshotter | csi-snapshotter:v$CSI_SNAPSHOTTER_VERSION | `harbor.internal/ceph-csi/csi-snapshotter` |
| csi-node-driver-registrar | csi-node-driver-registrar:v$CSI_NODE_DRIVER_VERSION | `harbor.internal/ceph-csi/csi-node-driver-registrar` |

### Verification

```bash
# Verify all images are from Harbor
kubectl -n ceph-csi get pods -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u

# All should show harbor.internal/ prefix
```

---

## Troubleshooting

### PVC Stuck in Pending

```bash
kubectl describe pvc <pvc-name>
# Check Events section

# Check provisioner logs
kubectl -n ceph-csi logs -l app=csi-cephfsplugin-provisioner --tail=50

# Common causes:
# - Wrong clusterID
# - MON unreachable
# - User lacks permissions
# - Pool doesn't exist
```

### Mount Failure

```bash
kubectl describe pod <pod-name>
# Check for mount errors

# Check node plugin logs
kubectl -n ceph-csi logs -l app=csi-cephfsplugin --tail=50

# Verify Ceph cluster health
# (from Ceph admin node)
sudo ceph -s
```

### Snapshot Not Working

```bash
# Verify snapshotter is running
kubectl -n ceph-csi get pods -l app=csi-snapshotter

# Check VolumeSnapshotClass exists
kubectl get volumesnapshotclass

# Check snapshot events
kubectl describe volumesnapshot <name>
```

---

## References

- [Ceph CSI GitHub](https://github.com/ceph/ceph-csi)
- [CSI Spec](https://github.com/container-storage-interface/spec)
- [Kubernetes CSI Documentation](https://kubernetes.io/docs/concepts/storage/container-storage-interface/)
