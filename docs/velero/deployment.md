# Velero — Backup & DR Guide

## Overview

Velero provides cluster resource backup, restore, and disaster recovery (DR). Deployed on both management and application clusters.

> **Air-gap note:** All Velero and image/volume snapshotter (restic/kopia) plugins must be loaded into Harbor.

---

## Velero Deployment via Helm on Both Clusters

### Add Helm Repo (Nexus — Air-gapped)

```bash
helm repo add vmware-tanzu https://nexus.internal.example.com/repository/helm-remote/
helm repo update
```

### Values File

```yaml
# velero-values.yaml
image:
  repository: harbor.internal.example.com/platform/velero
  tag: v1.11.0

# Restic plugin for filesystem backup
restic:
  install: true
  image: harbor.internal.example.com/platform/velero-restic-restore-helper:v1.11.0

# Backup locations (S3)
backupStorageLocation:
- name: default
  provider: generic (s3)
  default: true
  config:
    region: default
    s3_url: s3.internal.example.com
    s3_force_path_style: true
  objectStorage:
    bucket: velero-backup
    prefix: mgmt-cluster/velero

# Volume snapshot locations
volumeSnapshotLocation:
- name: default
- config:
    provider: generic
    region: default

# Container Storage Interface plugin (optional)
plugins:
- name: ingress-restore
  from: harbor.internal.example.com/platform/velero-plugin:v1.2.0
- name: csi
  from: harbor.internal.example.com/platform/velero-plugin-for-csi:v0.6.0
- name: restic
  from: harbor.internal.example.com/platform/velero-plugin-for-aws:v1.8.0

# Resources
resources:
  requests: { cpu: 500m, memory: 512Mi }
  limits:   { cpu: "2", memory: 2Gi }

# Schedule cron jobs for backup (default)
schedules:
  daily-cluster-backup:
    schedule: "0 2 * * *"
    template:
      ttl: 720h    # 30 days
      storageLocation: default
      includedNamespaces:
      - kube-system
      - cert-manager
      - gatekeeper-system
      - cattle-system
      - argocd
      - monitoring
      - logging
      - ingress-nginx
      labelSelector:
        matchExpressions:
        - key: velero.io/exclude-from-backup
          operator: DoesNotExist

  daily-namespace-backup:
    schedule: "0 3 * * *"
    template:
      ttl: 168h    # 7 days
      storageLocation: default
      defaultVolumesToFsBackup: true
      labelSelector:
        matchLabels:
          backup: daily
      includedResources:
      - deployments
      - services
      - configmaps
      - secrets
      - persistentvolumeclaims
      - ingresses
      - clusterroles
      - clusterrolebindings
      - serviceaccounts

# RBAC
rbac:
  create: true

# ServiceMonitor for Prometheus
serviceMonitor:
  enabled: true
  labels: { release: kube-prometheus-stack }
```

### Deploy

```bash
# Management cluster
kubectl config use-context mgmt-cluster
helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero --create-namespace \
  -f velero-values.yaml

# Application cluster
kubectl config use-context app-cluster
helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero --create-namespace \
  -f velero-values.yaml
```

---

## S3 Backend: Ceph RGW or MinIO

Velero requires an S3-compatible object store. In air-gap, this is Ceph RGW or MinIO.

### RGW bucket setup

```bash
# Create bucket for Velero backups
radosgw-admin bucket create velero-backup --tenant=default

# Create user with S3 access
radosgw-admin user create --uid=velero --display-name="Velero Backup"

# Get credentials
radosgw-admin key create --uid=velero --key-type=s3 --gen-access-key
```

### MinIO Setup (Alternative)

```bash
mc alias set minio https://minio.internal.example.com "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}"
mc mb minio/velero-backup --with-lock
```

---

## Restic/Velero FS Backup for Volumes

Restic performs file-level volume backups by running a sidecar inside pods.

### Annotate Pods for Filesystem Backup

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-db
spec:
  template:
    metadata:
      annotations:
        # Restic annotations
        backup.velero.io/container: db
        backup.velero.io/backup-volumes: data,config
    spec:
      containers:
      - name: db
        image: harbor.internal.example.com/db/postgres:15
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        - name: config
          mountPath: /etc/postgresql
      volumes:
      - name: data
        persistentVolumeClaim: { claimName: db-data }
      - name: config
        persistentVolumeClaim: { claimName: db-config }
```

### Use Kopia Instead of Restic (Recommended)

```yaml
# velero-values.yaml
deployAgentRestoredPods: false
restic:
  install: false

plugins:
- name: kopia
  from: harbor.internal.example.com/platform/velero-plugin-for-csi+kopia
```

---

## Backup Schedules

### Predefined Schedules

| Schedule | Frequency | TTL | Scope |
|----------|-----------|-----|-------|
| Platform resources | Daily 02:00 | 30d | System namespaces |
| Application namespaces | Daily 03:00 | 7d | Labeled namespaces |
| Full cluster | Weekly Sun 01:00 | 90d | Everything |

### Custom Schedule

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: hourly-critical-backup
  namespace: velero
spec:
  schedule: "0 * * * *"    # Every hour
  template:
    ttl: 24h
    includedNamespaces:
    - production
    - critical-apps
    defaultVolumesToFsBackup: true
    storageLocation: default
    labelSelector:
      matchLabels:
        backup: hourly
```

### Manual Backup

```bash
# Create one-off backup
velero backup create manual-backup \
  --include-namespaces my-app \
  --include-resources deployments,services,secrets,configmaps \
  --default-volumes-to-fs-backup \
  --storage-location default \
  --wait

# Verify backup
velero backup describe manual-backup --details
velero backup logs manual-backup
```

---

## Backup for K8s Resources

Velero backs up:

- Namespaced resources: Deployments, Services, ConfigMaps, Secrets, Ingresses, etc.
- Cluster-scoped resources: ClusterRoles, ClusterRoleBindings, StorageClasses, etc.
- Persistent Volume Claims (referenced; requires CSI snapshot or restic)

### Selective Backup

```bash
# Backup specific types only
velero backup create config-backup \
  --include-resources configmaps,secrets \
  --exclude-namespaces kube-system,public \
  --selector backup=strategic

# Backup using label selector
velero backup create app-team-backup \
  --selector team=alpha \
  --wait
```

---

## Backup for Persistent Volumes

### Option 1: CSI Snapshots (Preferred)

Requires Ceph CSI driver with snapshot support:

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: csi-snapshot-schedule
spec:
  schedule: "0 4 * * *"
  template:
    defaultVolumesToCSISnapshot: true
```

### Option 2: Restic/Kopia Filesystem Backup

Annotate pods with `backup.velero.io/backup-volumes` listing data volumes. Restic snapshots the volume mount directly.

---

## Velero UI (backube/velero-ui)

```yaml
# velero-ui-values.yaml
image:
  repository: harbor.internal.example.com/platform/velero-ui
  tag: 0.3.0
  pullPolicy: IfNotPresent

ui:
  title: Backup Management
  logoURL: ""
  primaryColor: "#1976d2"
  veleroServerURL: "https://velero-velero-ui.velero.svc.cluster.local:8085"
  s3Bucket: velero-backup

ingress:
  enabled: true
  hosts: { velero-ui.example.com: / }
  tls:
  - hosts: [velero-ui.example.com]

serviceMonitor:
  enabled: true
  labels: { release: kube-prometheus-stack }

```

```bash
helm upgrade --install velero-ui backube/velero-ui \
  --namespace velero --create-namespace \
  -f velero-ui-values.yaml
```

Features:
- View backup status, schedules, restores
- Trigger manual backups
- Browse backed-up resources
- Download logs from backup runs

---

## Cross-site Restore Procedures

### Prerequisites

1. Velero installed on target cluster
2. Same storage backend access (S3 bucket shared or replicated)
3. Images available in local Harbor

### Restore Steps

```bash
# 1. List available backups in the S3 bucket
velero backup-location get
velero backup get

# 2. Restore specific backup
velero restore create from-dr-backup \
  --from-backup daily-cluster-backup-20240601 \
  --wait

# 3. Restore to specific namespace
velero restore create --from-backup daily-cluster-backup \
  --namespace-mappings my-app:my-app-restored \
  --wait

# 4. Verify restored resources
kubectl get pods -n my-app-restored
kubectl get all -A
```

### Restore with Storage Class Mapping

```bash
velero restore create from-backup \
  --from-backup my-backup \
  --storage-class-mappings cephfs:rbd \
  --namespace-mappings my-app:my-app \
  --wait
```

---

## Disaster Recovery Runbook

### Scenario 1: Complete Cluster Loss

```bash
# 1. Verify Velero images are available
kubectl get pods -n velero

# 2. Create a fresh cluster (RKE2, kubeadm, etc.)

# 3. Install Velero (same chart, same S3 bucket)
helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero --create-namespace \
  -f velero-values.yaml

# 4. Confirm backup is accessible
velero backup-location get
velero backup get

# 5. Restore all namespaces
velero restore create full-restore \
  --from-backup <latest-backup> \
  --restore-volumes=true \
  --wait

# 6. Verify workloads
kubectl get pods -A
kubectl get svc -A
```

### Scenario 2: Partial Namespace Loss

```bash
# Restore single namespace from backup
velero restore create ns-restore \
  --from-backup daily-cluster-backup \
  --namespace-mappings my-app:my-app-restored \
  --selector backup=daily \
  --wait
```

### Scenario 3: Data Corruption in PV

```bash
# Restore specific PVC with its bound pod
velero restore create pv-restore \
  --from-backup <backup-name> \
  --resource-filtering=PersistentVolumeClaim,PersistentVolume,Pod \
  --namespace-mappings my-app:my-app \
  --wait
```

### Recovery Time Objectives (RTO)

| Scenario | RTO | RPO |
|----------|-----|-----|
| Single namespace | 15 min | 24h |
| Complete cluster | 1-2 hours | 24h |
| Multi-cluster DR | 4-8 hours | 24h |

---

## Air-gap: Velero Images from Harbor

### Required Images

| Component | Harbor Image |
|-----------|-------------|
| Velero | `harbor.internal.example.com/platform/velero:v1.11.0` |
| Restic plugin | `harbor.internal.example.com/platform/velero-restic-restore-helper:v1.11.0` |
| AWS plugin | `harbor.internal.example.com/platform/velero-plugin-for-aws:v1.8.0` |
| CSI plugin | `harbor.internal.example.com/platform/velero-plugin-for-csi:v0.6.0` |
| Velero UI | `harbor.internal.example.com/platform/velero-ui:0.3.0` |
| Kopia plugin | `harbor.internal.example.com/platform/velero-kopia:v0.18.0` |

### Mirror Script

```bash
#!/bin/bash
HARBOR=harbor.internal.example.com/platform
V=v1.11.0
for IMG in \
  "velero/velero:${V}" \
  "velero/restic-restore-helper:${V}" \
  "velero/velero-plugin-for-aws:v1.8.0" \
  "velero/velero-plugin-for-csi:v0.6.0"; do
  DST="${HARBOR}/$(echo $IMG | cut -d/ -f2-)"
  docker pull "$IMG" && docker tag "$IMG" "$DST" && docker push "$DST"
done
```
