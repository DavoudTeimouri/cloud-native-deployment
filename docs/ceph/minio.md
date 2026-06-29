# MinIO as SDS (Software-Defined Storage) Option

## Overview

MinIO is a high-performance, S3-compatible object storage solution. It can serve as an alternative to Ceph RGW for S3 workloads in an air-gapped environment. This guide covers MinIO deployment modes, configuration, and integration with Kubernetes workloads.

---

## When to Choose MinIO over Ceph RGW

| Criteria | MinIO | Ceph RGW |
|----------|-------|----------|
| **Deployment Complexity** | Very Low | Medium-High |
| **Operational Overhead** | Minimal | Moderate |
| **S3 Compatibility** | Excellent (native) | Excellent |
| **Performance** | High (single-purpose) | Good (multi-purpose) |
| **Scalability** | Horizontal (easy) | Horizontal (complex) |
| **Resource Overhead** | Low | Higher |
| **Multi-Protocol** | Object only | Block + File + Object |
| **Erasure Coding** | Built-in | CRUSH + pools |
| **K8s-Native** | Operator available | Via Rook |
| **Air-Gap Friendliness** | Excellent (single binary) | Good |
| **Small Scale (1-10TB)** | Ideal | Overkill |
| **Large Scale (100TB+)** | Good | Better |
| **Team Expertise Required** | Low | High |
| **Best For** | S3-only workloads, rapid deployment | Multi-workload storage |

### Decision Flowchart

```
Need block or file storage?
├── YES → Use Ceph (RBD/CephFS)
└── NO (object only)
    ├── Need multi-protocol in future?
    │   ├── YES → Use Ceph RGW
    │   └── NO
    ├── Team has Ceph expertise?
    │   ├── YES → Either works
    │   └── NO → Use MinIO
    └── Deployment timeline?
        ├── Days → Use MinIO
        └── Weeks → Either works
```

---

## MinIO Deployment Modes

### Mode 1: Single-Node Single-Drive (SNSD)

```
┌─────────────────┐
│   MinIO Server  │
│   1 Node        │
│   1 Drive       │
└─────────────────┘
```

- **Use Case:** Development, testing, small datasets
- **Durability:** None (single drive)
- **Capacity:** Single drive capacity
- **Performance:** Limited by single drive

```bash
minio server /data --console-address ":9001"
```

### Mode 2: Single-Node Multi-Drive (SNMD)

```
┌─────────────────────────────┐
│       MinIO Server          │
│       1 Node                │
│  ┌──────┐ ┌──────┐ ┌──────┐│
│  │Drive1│ │Drive2│ │Drive3││
│  └──────┘ └──────┘ └──────┘│
└─────────────────────────────┘
```

- **Use Case:** Small production, medium datasets
- **Durability:** Erasure coding across drives
- **Capacity:** Sum of drives (with parity)
- **Performance:** Good (single node, no network overhead)

```bash
minio server /data{1...4} --console-address ":9001"
```

### Mode 3: Multi-Node Multi-Drive (MNMD) — Recommended

```
┌─────────────────────────────────────────────────────────┐
│                  MinIO Cluster                          │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │
│  │  Node 1     │ │  Node 2     │ │  Node 3     │       │
│  │ ┌────┐┌────┐│ │ ┌────┐┌────┐│ │ ┌────┐┌────┐│       │
│  │ │D1  ││D2  ││ │ │D3  ││D4  ││ │ │D5  ││D6  ││       │
│  │ └────┘└────┘│ │ └────┘└────┘│ │ └────┘└────┘│       │
│  └─────────────┘ └─────────────┘ └─────────────┘       │
│  ┌─────────────┐ ┌─────────────┐                        │
│  │  Node 4     │ │  Node 5     │                        │
│  │ ┌────┐┌────┐│ │ ┌────┐┌────┐│                        │
│  │ │D7  ││D8  ││ │ │D9  ││D10 ││                        │
│  │ └────┘└────┘│ │ └────┘└────┘│                        │
│  └─────────────┘ └─────────────┘                        │
└─────────────────────────────────────────────────────────┘
```

- **Use Case:** Production, high availability, large scale
- **Durability:** Erasure coding across nodes AND drives
- **Capacity:** Sum of all drives (with parity)
- **Performance:** Excellent (distributed)
- **Minimum Nodes:** 4 (for erasure coding)

```bash
export MINIO_ROOT_USER=admin
export MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD

minio server \
    https://minio{1...4}/data{1...4} \
    --console-address ":9001"
```

---

## Distributed MinIO Deployment (4+ Nodes)

### Hardware Requirements (per node)

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| Data Drives | 4 × HDD | 8 × HDD |
| OS Drive | 1 × SSD | 1 × SSD |
| Network | 10 GbE | 25 GbE |

### Deployment Steps

#### Step 1: Prepare Drives

```bash
# On each node, format and mount data drives
for drive in /dev/sdb /dev/sdc /dev/sdd /dev/sde; do
    sudo mkfs.xfs -f $drive
    sudo mkdir -p /data/$(basename $drive)
    sudo mount $drive /data/$(basename $drive)
    echo "$drive /data/$(basename $drive) xfs defaults,noatime 0 0" | \
        sudo tee -a /etc/fstab
done
```

#### Step 2: Deploy MinIO

```bash
# Set environment variables
export MINIO_ROOT_USER="minioadmin"
export MINIO_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD"  # Min 8 chars
export MINIO_BROWSER=on
export MINIO_PROMETHEUS_AUTH_TYPE=public

# Start MinIO cluster
minio server \
    https://minio{1...4}/data{1...4} \
    --console-address ":9001" \
    --address ":9000"
```

#### Step 3: Verify Cluster

```bash
# Check cluster health
mc alias set local https://minio1:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
mc admin info local

# Check drive status
mc admin heal --dry-run local
```

---

## MinIO Operator for Kubernetes Deployment

### Install MinIO Operator

```bash
# Add MinIO Helm repo (or use local chart in air-gap)
helm repo add minio https://operator.min.io/
helm repo update

# Create namespace
kubectl create namespace minio-operator

# Deploy operator
helm install minio-operator minio/minio-operator \
    --namespace minio-operator \
    --set image.repository=harbor.internal/minio/operator \
    --set image.tag="$MINIO_VERSION" \
    --set console.image.repository=harbor.internal/minio/console \
    --set console.tag="$MINIO_VERSION" \
    --set securityContext.enabled=false
```

### Create Tenant (Cluster)

```yaml
apiVersion: min.io/v2
kind: Tenant
metadata:
  name: minio-tenant
  namespace: minio-operator
spec:
  image: harbor.internal/minio/minio:$MINIO_VERSION
  imagePullPolicy: IfNotPresent
  
  # Pool configuration - distributed
  pools:
    - name: pool-0
      servers: 4
      volumesPerServer: 4
      volumeClaimTemplate:
        metadata:
          name: data
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Ti
          storageClassName: local-storage
  
  # Erasure coding configuration
  erasureCodeParity: 2  # EC:4+2 (tolerates 2 node failures)
  
  # Console configuration
  console:
    image: harbor.internal/minio/console:$MINIO_VERSION
    replicas: 2
    consoleSecret:
      name: minio-console-secret
  
  # Prometheus monitoring
  prometheus:
    image: harbor.internal/prom/prometheus:latest
    sidecarImage: harbor.internal/minio/sidecar:latest
    initImage: harbor.io/busybox:latest
    diskCapacityGB: 50
  
  # S3 configuration
  s3:
    bucketDNS: false
  
  # Certificate
  certConfig:
    commonName: minio.internal
    dnsNames:
      - minio.internal
      - minio-tenant-hl.minio-operator.svc.cluster.local
    organizationName: Internal
  
  # K8s service
  serviceMetadata:
    minioServiceLabels:
      app: minio
    consoleServiceLabels:
      app: minio-console
  
  # Environment variables
  configuration:
    name: minio-configuration
  
  # Security
  security:
    tls:
      enabled: true
```

### Create Configuration Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: minio-configuration
  namespace: minio-operator
type: Opaque
stringData:
  config.env: |
    export MINIO_ROOT_USER=minioadmin
    export MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD
    export MINIO_BROWSER=on
    export MINIO_PROMETHEUS_AUTH_TYPE=public
    export MINIO_STORAGE_CLASS_STANDARD=EC:4
    export MINIO_STORAGE_CLASS_RRS=EC:2
```

---

## Erasure Coding Configuration

### EC Levels and Trade-offs

| EC Level | Data Shards | Parity Shards | Usable Capacity | Fault Tolerance |
|----------|-------------|---------------|-----------------|-----------------|
| EC:2 | 2 | 2 | 50% | 2 failures |
| EC:4 | 4 | 2 | 67% | 2 failures |
| EC:6 | 6 | 2 | 75% | 2 failures |
| EC:8 | 8 | 2 | 80% | 2 failures |
| EC:4+2 | 4 | 2 | 67% | 2 node failures |
| EC:8+4 | 8 | 4 | 67% | 4 node failures |

### Recommended Configurations

| Use Case | EC Level | Nodes | Drives/Node | Raw Capacity | Usable |
|----------|----------|-------|-------------|--------------|--------|
| Dev/Test | EC:2 | 4 | 4 | 16 TB | 8 TB |
| Production | EC:4 | 4 | 4 | 16 TB | 10.7 TB |
| Archive | EC:6 | 6 | 8 | 48 TB | 36 TB |
| Critical | EC:4+2 | 6 | 4 | 24 TB | 16 TB |

### StorageClass for Reduced Redundancy

```bash
# Set storage class on bucket
mc admin config set local storage_class standard=EC:4
mc admin config set local storage_class rrs=EC:2  # Reduced Redundancy
```

---

## MinIO as S3 Backend for Velero

### Create Velero Bucket and Credentials

```bash
# Create bucket
mc mb local/velero-backups

# Create service account for VelIO
mc admin user add local velero $VELELO_SECRET_KEY

# Create policy for Velero
cat <<EOF > /tmp/velero-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:ListBucket",
                "s3:ListBucketMultipartUploads"
            ],
            "Resource": ["arn:aws:s3:::velero-backups"]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:AbortMultipartUpload",
                "s3:DeleteObject",
                "s3:GetObject",
                "s3:ListMultipartUploadParts",
                "s3:PutObject"
            ],
            "Resource": ["arn:aws:s3:::velero-backups/*"]
        }
    ]
}
EOF

mc admin policy create local velero-policy /tmp/velero-policy.json
mc admin policy attach local velero-policy --user velero

# Get service account credentials
mc admin user list local | grep velero
```

### Install Velero with MinIO

```bash
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:$VELERO_AWS_PLUGIN_VERSION \
    --bucket velero-backups \
    --secret-file /tmp/credentials-velero \
    --backup-location-config region=minio,s3ForcePathStyle=true,s3Url=https://minio.internal \
    --snapshot-location-config region=minio \
    --use-restic \
    --default-volumes-to-restic \
    --namespace velero \
    --wait
```

---

## MinIO Console (GUI)

The MinIO Console provides web-based management:

```bash
# Access console
https://minio.internal:9001

# Login with MINIO_ROOT_USER and MINIO_ROOT_PASSWORD
```

### Console Features

- **Dashboard:** Cluster health, usage metrics
- **Bucket Management:** Create, configure, browse buckets
- **User Management:** Create users, assign policies
- **Service Accounts:** Manage S3 access keys
- **Audit Logs:** Track access and operations
- **Lifecycle Rules:** Set expiration and transition policies

### Expose Console via Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: minio-console
  namespace: minio-operator
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/proxy-body-size: "10g"
spec:
  tls:
    - hosts:
        - minio-console.internal
      secretName: minio-tls
  rules:
    - host: minio-console.internal
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: minio-tenant-console
                port:
                  number: 9001
```

---

## Bucket Notifications and Lifecycle

### Bucket Notifications

```bash
# Enable event notifications (e.g., to webhook or NATS)
mc event add local/velero-backups arn:aws:sqs:us-east-1:webhook \
    --event put,delete

# Supported destinations:
# - PostgreSQL
# - MySQL
# - NATS
# - Redis
# - AMQP
# - MQTT
# - Webhook
# - Kafka
# - Elasticsearch
```

### Lifecycle Policies

```bash
# Create lifecycle policy
cat <<EOF > /tmp/lifecycle.json
{
    "Rules": [
        {
            "ID": "expire-old-backups",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "backups/"
            },
            "Expiration": {
                "Days": 30
            }
        },
        {
            "ID": "transition-to-cold",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "archive/"
            },
            "Transitions": [
                {
                    "Days": 90,
                    "StorageClass": "COLD"
                }
            ],
            "Expiration": {
                "Days": 365
            }
        }
    ]
}
EOF

mc ilm import local/velero-backups < /tmp/lifecycle.json

# List lifecycle rules
mc ilm list local/velero-backups
```

---

## IAM and Access Control

### User Management

```bash
# Create user
mc admin user add local app-user $APP_SECRET_KEY

# Create group
mc admin group add local app-team app-user

# Assign policy to group
mc admin policy attach local read-only --group app-team

# List users
mc admin user list local

# Remove user
mc admin user remove local app-user
```

### Policy Examples

#### Read-Only Access

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:ListBucket"],
            "Resource": ["arn:aws:s3:::app-data"]
        },
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject"],
            "Resource": ["arn:aws:s3:::app-data/*"]
        }
    ]
}
```

#### Read-Write Access

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": ["arn:aws:s3:::app-data"]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListMultipartUploadParts",
                "s3:AbortMultipartUpload"
            ],
            "Resource": ["arn:aws:s3:::app-data/*"]
        }
    ]
}
```

#### Bucket-Specific Access

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:*"],
            "Resource": [
                "arn:aws:s3:::app-data",
                "arn:aws:s3:::app-data/*"
            ]
        },
        {
            "Effect": "Deny",
            "Action": ["s3:DeleteBucket"],
            "Resource": ["arn:aws:s3:::app-data"]
        }
    ]
}
```

---

## TLS Configuration

### Self-Signed Certificate

```bash
# Generate certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/minio/private.key \
    -out /etc/minio/public.crt \
    -subj "/CN=minio.internal" \
    -addext "subjectAltName=DNS:minio.internal,DNS:*.minio.internal"

# Place certificates
# MinIO looks for certs in:
# ~/.minio/certs/ (user)
# /etc/minio/certs/ (system)
```

### Internal CA Certificate

```bash
# Generate CSR
openssl req -new -newkey rsa:2048 -nodes \
    -keyout /etc/minio/private.key \
    -out /etc/minio/public.csr \
    -subj "/CN=minio.internal"

# Sign with internal CA
openssl x509 -req -in /etc/minio/public.csr \
    -CA /etc/ssl/certs/internal-ca.pem \
    -CAkey /etc/ssl/private/internal-ca-key.pem \
    -CAcreateserial \
    -out /etc/minio/public.crt \
    -days 365 \
    -extfile <(printf "subjectAltName=DNS:minio.internal,DNS:*.minio.internal")

# Restart MinIO
```

### Kubernetes TLS (Operator)

```yaml
# In Tenant spec
spec:
  security:
    tls:
      enabled: true
      certSecret:
        name: minio-tls-cert
---
apiVersion: v1
kind: Secret
metadata:
  name: minio-tls-cert
  namespace: minio-operator
type: kubernetes.io/tls
data:
  tls.crt: <BASE64_CERT>
  tls.key: <BASE64_KEY>
```

---

## Monitoring with Prometheus

### Enable Prometheus Metrics

```bash
# Set environment variable
export MINIO_PROMETHEUS_AUTH_TYPE=public

# Metrics available at:
# http://minio.internal:9000/minio/v2/metrics/cluster
# http://minio.internal:9000/minio/v2/metrics/node
```

### Prometheus ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: minio-tenant
  namespace: minio-operator
spec:
  selector:
    matchLabels:
      app: minio
  namespaceSelector:
    matchNames:
      - minio-operator
  endpoints:
    - port: http-minio
      path: /minio/v2/metrics/cluster
      interval: 30s
    - port: http-minio
      path: /minio/v2/metrics/node
      interval: 30s
```

### Key Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `minio_cluster_capacity_usable_total_bytes` | Total usable capacity | N/A |
| `minio_cluster_capacity_usable_free_bytes` | Free capacity | < 20% |
| `minio_cluster_nodes_online_total` | Online nodes | < expected |
| `minio_cluster_nodes_offline_total` | Offline nodes | > 0 |
| `minio_cluster_drives_online_total` | Online drives | < expected |
| `minio_cluster_drives_offline_total` | Offline drives | > 0 |
| `minio_cluster_drives_healing_total` | Healing drives | > 0 for > 1h |
| `minio_s3_requests_total` | Total S3 requests | N/A |
| `minio_s3_errors_total` | S3 errors | > threshold |
| `minio_s3_traffic_received_bytes` | Ingress | N/A |
| `minio_s3_traffic_sent_bytes` | Egress | N/A |

### Grafana Dashboard

```bash
# Import MinIO Grafana dashboard
# Dashboard ID: 13502 (MinIO Dashboard)
# Available at: https://grafana.com/grafana/dashboards/13502

# Or use Prometheus Mixin for MinIO
```

---

## Air-Gap Considerations

| Component | Source | Image/Path |
|-----------|--------|------------|
| MinIO Server | Harbor | `harbor.internal/minio/minio:$MINIO_VERSION` |
| MinIO Operator | Harbor | `harbor.internal/minio/operator:$MINIO_VERSION` |
| MinIO Console | Harbor | `harbor.internal/minio/console:$MINIO_VERSION` |
| MinIO Client (mc) | Nexus | Binary download |
| Prometheus sidecar | Harbor | `harbor.internal/minio/sidecar:$MINIO_VERSION` |

### Image Synchronization

```bash
#!/bin/bash
# sync-minio-images.sh

REGISTRY="harbor.internal/minio"
MINIO_VERSION="${MINIO_VERSION:-RELEASE.2024-01-01T00-00-00Z}"

IMAGES=(
    "quay.io/minio/minio:${MINIO_VERSION}"
    "quay.io/minio/operator:${MINIO_VERSION}"
    "quay.io/minio/console:${MINIO_VERSION}"
    "quay.io/minio/sidecar:${MINIO_VERSION}"
    "quay.io/minio/mc:${MINIO_VERSION}"
)

for img in "${IMAGES[@]}"; do
    echo "Copying $img"
    crane copy "$img" "${REGISTRY}/$(basename "$img")"
done
```

---

## Migration Path: MinIO ↔ Ceph RGW

### MinIO to Ceph RGW

```bash
# 1. Export all objects from MinIO
mc mirror --watch local/ https://s3.internal/source-bucket

# 2. Create bucket in Ceph RGW
sudo radosgw-admin bucket create --bucket=migrated-data

# 3. Sync data
mc mirror local/source-bucket https://s3.internal/migrated-data

# 4. Verify
mc ls local/source-bucket
aws s3 ls s3://migrated-data --endpoint-url https://s3.internal

# 5. Update application endpoints
# Change S3 endpoint from minio.internal to s3.internal
```

### Ceph RGW to MinIO

```bash
# 1. Create bucket in MinIO
mc mb local/migrated-data

# 2. Sync from Ceph RGW
aws s3 sync s3://source-bucket local/migrated-data \
    --source-endpoint-url https://s3.internal \
    --endpoint-url https://minio.internal

# 3. Verify
mc ls local/migrated-data

# 4. Update application endpoints
```

### Considerations

| Migration Direction | Complexity | Downtime | Notes |
|---------------------|------------|----------|-------|
| MinIO → Ceph RGW | Medium | Possible | Different IAM models |
| Ceph RGW → MinIO | Medium | Possible | Different bucket policies |
| Both → New S3 | Low | Avoid | Use `mc mirror` for live migration |

---

## MinIO Client Quick Reference

```bash
# Set alias
mc alias set local https://minio.internal:9000 admin password

# Bucket operations
mc mb local/new-bucket
mc rb local/old-bucket
mc ls local/

# Object operations
mc cp file.txt local/bucket/
mc cp --recursive /data local/bucket/
mc rm local/bucket/file.txt
mc mv local/bucket/old local/bucket/new

# Info
mc admin info local
mc admin heal local
mc admin bucket quota local/bucket

# User management
mc admin user add local newuser password
mc admin user list local
mc admin policy list local
```

---

## References

- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [MinIO Operator GitHub](https://github.com/minio/operator)
- [MinIO Kubernetes Guide](https://min.io/docs/minio/linux/operations/installation.html)
- [mc CLI Reference](https://min.io/docs/minio/linux/reference/minio-mc.html)
