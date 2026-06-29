# Velero Backup & Storage Guide

> Velero backup configuration with external storage targets

---

## 1. Architecture

```
┌─────────────────────────────────────────────────────┐
│ Kubernetes Cluster │
│ │
│ ┌──────────────┐ │
│ │ Velero │ │
│ │ Server │ │
│ │ │ │
│ │ - Backup │ │
│ │ - Schedule │ │
│ │ - Restore │ │
│ └──────┬───────┘ │
│ │ │
│ ┌──────┴───────┐ │
│ │ Restic/CSI │ │
│ │ (PV backups) │ │
│ └──────────────┘ │
└──────────┬──────────────────────────────────────────┘
│
│ Object Storage API (S3-compatible)
│
┌──────────┴──────────────────────────────────────────┐
│ Storage Target │
│ │
│ Option A: MinIO (on-prem) │
│ Option B: Ceph RGW │
│ Option C: NFS share │
│ Option D: AWS S3 (if internet) │
│ │
└─────────────────────────────────────────────────────┘
```

---

## 2. Storage Targets

### 2.1 MinIO (Recommended for Air-Gap)

```bash
# Deploy MinIO as container
docker run -d \
  --name minio \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin123 \
  -v /opt/minio/data:/data \
  minio/minio:latest \
  server /data --console-address ":9001"

# Create bucket for Velero
docker run --rm \
  -e MC_HOST_minio=http://minioadmin:minioadmin123@localhost:9000 \
  minio/mc:latest \
  mb minio/velero-backups

# Create access key
docker run --rm \
  -e MC_HOST_minio=http://minioadmin:minioadmin123@localhost:9000 \
  minio/mc:latest \
  admin user add minio velero velero_secret_key

# Set policy
docker run --rm \
  -e MC_HOST_minio=http://minioadmin:minioadmin123@localhost:9000 \
  minio/mc:latest \
  admin policy set minio readwrite user=velero
```

### 2.2 Ceph RGW (If Using Ceph)

```bash
# Create RGW user for Velero
radosgw-admin user create --uid=velero --display-name="Velero Backup"
radosgw-admin subuser create --uid=velero --subuser=velero:swift --access=full

# Get keys
radosgw-admin user info --uid=velero

# Create bucket via S3
aws s3 mb s3://velero-backups \
  --endpoint-url=http://ceph-rgw.internal:7480

# Or via radosgw-admin
radosgw-admin bucket create --bucket=velero-backups
```

### 2.3 NFS Share

```bash
# On NFS server
sudo mkdir -p /exports/velero
sudo chmod 777 /exports/velero
echo "/exports/velero 10.0.0.0/8(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
sudo exportfs -ra

# On Velero — use NFS directly via restic
# (Velero doesn't support NFS as object storage, but restic can backup to NFS)
```

### 2.4 Local MinIO for Development

```bash
# Quick MinIO for testing
docker run -d \
  --name minio-dev \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin123 \
  minio/minio:latest server /data --console-address ":9001"
```

---

## 3. Install Velero

### 3.1 Install Velero CLI

```bash
VELERO_VERSION=1.12.0
curl -sL "https://github.com/vmware-tanzu/velero/releases/download/v${VELERO_VERSION}/velero-v${VELERO_VERSION}-linux-amd64.tar.gz" | tar xz
sudo mv velero-v${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/
```

### 3.2 Install Velero with MinIO

```bash
# Create credentials file
cat > credentials-velero <<EOF
[default]
aws_access_key_id = velero
aws_secret_access_key = velero_secret_key
EOF

# Install Velero
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=minio,s3ForcePathStyle=true,s3Url=http://minio.internal:9000 \
  --use-restic \
  --wait
```

### 3.3 Install Velero with Ceph RGW

```bash
cat > credentials-velero <<EOF
[default]
aws_access_key_id = <RGW_ACCESS_KEY>
aws_secret_access_key = <RGW_SECRET_KEY>
EOF

velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=us-east-1,s3ForcePathStyle=true,s3Url=http://ceph-rgw.internal:7480 \
  --use-restic \
  --wait
```

### 3.4 Install Velero via Helm

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

cat > values-velero.yaml <<EOF
configuration:
  backupStorageLocation:
    - name: default
      provider: aws
      bucket: velero-backups
      config:
        region: minio
        s3ForcePathStyle: "true"
        s3Url: http://minio.internal:9000
  volumeSnapshotLocation:
    - name: default
      provider: aws
      config:
        region: minio
  restic:
    podVolumeBackup:
      defaultVolumesToRestic: true

credentials:
  secretContents:
    cloud: |
      [default]
      aws_access_key_id = velero
      aws_secret_access_key = velero_secret_key

initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:v1.8.0
    volumeMounts:
      - name: plugins
        mountPath: /target

deployNodeAgent: true
snapshotsEnabled: true
EOF

helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --values values-velero.yaml
```

---

## 4. Backup Configuration

### 4.1 Create Backup Schedule

```bash
# Daily backup of all namespaces
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --include-namespaces='*' \
  --exclude-namespaces=velero,kube-system \
  --ttl=720h \
  --default-volumes-to-restic

# Weekly full backup
velero schedule create weekly-backup \
  --schedule="0 3 * * 0" \
  --include-namespaces='*' \
  --default-volumes-to-restic \
  --ttl=2160h

# Hourly critical namespaces only
velero schedule create hourly-critical \
  --schedule="0 * * * *" \
  --include-namespaces=production,monitoring,gitlab \
  --default-volumes-to-restic \
  --ttl=168h
```

### 4.2 Manual Backup

```bash
# Backup all namespaces
velero backup create full-backup-$(date +%Y%m%d) \
  --include-namespaces='*' \
  --default-volumes-to-restic \
  --wait

# Backup specific namespace
velero backup create production-backup \
  --include-namespaces=production \
  --default-volumes-to-restic \
  --wait

# Backup with specific labels
velero backup create app-backup \
  --selector app=my-app \
  --default-volumes-to-restic \
  --wait
```

### 4.3 Verify Backup

```bash
# List backups
velero backup get

# Check backup details
velero backup describe <backup-name> --details

# Check backup logs
velero backup logs <backup-name>

# Download backup
velero backup download <backup-name>
```

---

## 5. Restore Configuration

### 5.1 Restore from Backup

```bash
# Full restore
velero restore create --from-backup <backup-name> --wait

# Restore specific namespace
velero restore create --from-backup <backup-name> \
  --namespace-mappings old-ns:new-ns \
  --wait

# Restore specific resources
velero restore create --from-backup <backup-name> \
  --include-resources deployments,services,configmaps \
  --wait
```

### 5.2 Disaster Recovery

```bash
# Restore to new cluster
velero restore create --from-backup <backup-name> \
  --restore-volumes=true \
  --wait

# Restore with namespace mapping
velero restore create dr-restore \
  --from-backup latest \
  --namespace-mappings production:production-dr \
  --wait
```

---

## 6. Velero with NFS (Restic to NFS)

Since Velero's object storage doesn't support NFS, use Restic for PV backups to NFS:

```yaml
# restic-nfs.yaml
apiVersion: v1
kind: Pod
metadata:
  name: restic-nfs-test
  namespace: velero
spec:
  containers:
    - name: restic
      image: restic/restic:latest
      command: ["sleep", "3600"]
      volumeMounts:
        - name: nfs-backup
          mountPath: /backup
        - name: restic-cache
          mountPath: /cache
      env:
        - name: RESTIC_REPOSITORY
          value: /backup
        - name: RESTIC_PASSWORD
          valueFrom:
            secretKeyRef:
              name: restic-credentials
              key: password
  volumes:
    - name: nfs-backup
      nfs:
        server: nfs.internal
        path: /exports/velero
    - name: restic-cache
      emptyDir: {}
```

---

## 7. Service Health (Velero)

```bash
# Check Velero pod
kubectl get pods -n velero

# Check Velero logs
kubectl logs -n velero deploy/velero --tail=50

# Check restic/node-agent logs
kubectl logs -n velero -l name=node-agent --tail=50

# Check backup storage location
velero backup-location get
velero backup-location describe default

# Check snapshot location
velero snapshot-location get

# Check schedules
velero schedule get

# Check backup status
velero backup get

# Check restore status
velero restore get

# Test S3 connectivity
aws s3 ls s3://velero-backups/ \
  --endpoint-url=http://minio.internal:9000 \
  --aws-access-key=velero \
  --aws-secret-key=velero_secret_key
```

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Backup stuck in "InProgress" | S3 connectivity | Check endpoint URL, credentials |
| Restic backup fails | NFS permissions | Check NFS export, pod user |
| Restore fails | Storage not available | Check PV provisioning |
| "No backup storage location found" | BSL not configured | `velero backup-location create` |
| Snapshot fails | CSI driver missing | Install CSI driver or use restic |
| Backup timeout | Large volumes | Increase `--item-operation-timeout` |
