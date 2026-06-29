# Ceph RGW (RADOS Gateway) Deployment Guide

## Overview

Ceph RGW (RADOS Gateway) provides S3-compatible object storage for Kubernetes workloads. This guide covers RGW deployment for Velero backups, ArgoCD artifacts, and general S3 use cases in an air-gapped environment.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    S3 Clients                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  Velero  │  │  ArgoCD  │  │   Apps   │  │  s3cmd   │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │
│       │              │              │              │         │
│       └──────────────┴──────────────┴──────────────┘         │
│                          │                                   │
│                    ┌─────┴─────┐                             │
│                    │  RGW (2x) │                             │
│                    │  Active   │                             │
│                    └─────┬─────┘                             │
│                          │                                   │
│              ┌───────────┴───────────┐                       │
│              │    Ceph Cluster       │                       │
│              │  5 MON + 5 OSD        │                       │
│              └───────────────────────┘                       │
└──────────────────────────────────────────────────────────────┘
```

---

## Zone/Zonegroup Configuration

### Concepts

| Concept | Description | Our Setup |
|---------|-------------|-----------|
| **Zone** | A group of RGW instances with its own data | `primary` |
| **Zonegroup** | A group of zones that share the same metadata | `default` |
| **Realm** | A namespace for multi-site | `default` |
| **Zone Type** | primary vs secondary | `primary` (no secondary in single cluster) |

### Configuration

```bash
# Create realm, zonegroup, and zone
sudo ceph realm create --default default
sudo ceph zonegroup create --default --master default
sudo ceph zone create --master --default primary

# Commit the changes
sudo ceph period update --commit
```

### Multi-Zone (Optional, for future expansion)

```bash
# For future multi-zone setup:
sudo ceph zonegroup add-zone default primary
sudo ceph zonegroup list default
```

---

## S3 User and Bucket Creation

### Create S3 User for Velero

```bash
# Create Velero user
sudo radosgw-admin user create \
    --uid="velero" \
    --display-name="Velero Backup User" \
    --email="velero@internal" \
    --access-key="$VELELO_ACCESS_KEY" \
    --secret-key="$VELELO_SECRET_KEY"

# Verify
sudo radosgw-admin user info --uid=velero
```

### Create S3 User for ArgoCD

```bash
sudo radosgw-admin user create \
    --uid="argocd" \
    --display-name="ArgoCD Artifact User" \
    --email="argocd@internal" \
    --access-key="$ARGOCD_ACCESS_KEY" \
    --secret-key="$ARGOCD_SECRET_KEY"
```

### Create S3 User for General Applications

```bash
sudo radosgw-admin user create \
    --uid="app-s3" \
    --display-name="Application S3 User" \
    --email="apps@internal" \
    --access-key="$APP_ACCESS_KEY" \
    --secret-key="$APP_SECRET_KEY"
```

### Create Buckets

```bash
# Velero backup bucket
sudo radosgw-admin bucket create \
    --bucket=velero-backups \
    --uid=velero \
    --zonegroup=default \
    --placement-rule=default-placement \
    --tenant=""

# ArgoCD artifacts bucket
sudo radosgw-admin bucket create \
    --bucket=argocd-artifacts \
    --uid=argocd \
    --zonegroup=default \
    --placement-rule=default-placement \
    --tenant=""

# General application bucket
sudo radosgw-admin bucket create \
    --bucket=app-data \
    --uid=app-s3 \
    --zonegroup=default \
    --placement-rule=default-placement \
    --tenant=""

# Verify
sudo radosgw-admin bucket list
sudo radosgw-admin bucket stats --bucket=velero-backups
```

### Set Bucket Quotas

```bash
# Set quota on Velero bucket (1 TB)
sudo radosgw-admin quota set \
    --quota-scope=bucket \
    --uid=velero \
    --max-objects=-1 \
    --max-size-kb=1048576000 \
    --check-on-raw=false

# Enable quota enforcement
sudo radosgw-admin quota enable \
    --quota-scope=bucket \
    --uid=velero
```

---

## Velero Integration

### Install Velero with Ceph RGW

```bash
# Download Velero CLI
# (from Nexus in air-gap)
tar -xzf velero-$VELERO_VERSION-linux-amd64.tar.gz
sudo mv velero-$VELERO_VERSION/velero /usr/local/bin/

# Create credentials file for Velero
cat <<EOF > /tmp/credentials-velero
[default]
aws_access_key_id = $VELELO_ACCESS_KEY
aws_secret_access_key = $VELELO_SECRET_KEY
EOF

# Install Velero
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:$VELERO_AWS_PLUGIN_VERSION \
    --bucket velero-backups \
    --secret-file /tmp/credentials-velero \
    --backup-location-config region=primary,s3ForcePathStyle=true,s3Url=https://s3.internal \
    --snapshot-location-config region=primary \
    --use-restic \
    --default-volumes-to-restic \
    --namespace velero \
    --wait
```

### Verify Velero

```bash
# Check Velero deployment
kubectl -n velero get pods

# Test backup
kubectl -n velero create backup test-backup \
    --include-namespaces=default \
    --wait

# Verify backup in S3
sudo radosgw-admin bucket stats --bucket=velero-backups
```

### Velero Backup Schedule

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  template:
    includedNamespaces:
      - default
      - production
    excludedResources:
      - events
      - pods
    labelSelector:
      matchLabels:
        backup: "true"
    defaultVolumesToRestic: true
    ttl: 720h  # 30 days
    storageLocation: default
    volumeSnapshotLocations:
      - default
```

---

## TLS Configuration

### Option 1: Self-Signed Certificate

```bash
# Generate certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ceph/rgw-key.pem \
    -out /etc/ceph/rgw-cert.pem \
    -subj "/CN=s3.internal/O=Internal/C=US"

# Configure RGW
sudo ceph config set client.rgw.myrealm.myzone \
    rgw_frontends "civetweb port=443s ssl_certificate=/etc/ceph/rgw-cert.pem"
```

### Option 2: Internal CA Certificate

```bash
# Generate CSR
openssl req -new -newkey rsa:2048 -nodes \
    -keyout /etc/ceph/rgw-key.pem \
    -out /etc/ceph/rgw-csr.pem \
    -subj "/CN=s3.internal/O=Internal/C=US"

# Sign with internal CA
openssl x509 -req -in /etc/ceph/rgw-csr.pem \
    -CA /etc/ssl/certs/internal-ca.pem \
    -CAkey /etc/ssl/private/internal-ca-key.pem \
    -CAcreateserial \
    -out /etc/ceph/rgw-cert.pem \
    -days 365

# Configure RGW with signed cert
sudo ceph config set client.rgw.myrealm.myzone \
    rgw_frontends "civetweb port=443s ssl_certificate=/etc/ceph/rgw-cert.pem"

# Restart RGW
sudo ceph orch restart rgw.myrealm.myzone
```

### Option 3: Terminate TLS at Load Balancer

```yaml
# If using an external LB (NGINX, HAProxy) for TLS termination:
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rgw-ingress
  namespace: rook-ceph
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/proxy-body-size: "10g"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
spec:
  tls:
    - hosts:
        - s3.internal
      secretName: s3-tls-secret
  rules:
    - host: s3.internal
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: rook-ceph-rgw-my-store
                port:
                  number: 80
```

---

## Monitoring and Health Checks

### Prometheus Metrics

RGW exposes metrics via the Ceph manager prometheus module:

```bash
# Enable prometheus module
sudo ceph mgr module enable prometheus

# Check RGW metrics endpoint
curl -s http://mon01:9283/api/prometheus/metrics | grep rgw
```

### Key RGW Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `ceph_rgw_req` | Total requests | N/A |
| `ceph_rgw_failed_req` | Failed requests | > 100/min |
| `ceph_rgw_get` | GET requests | N/A |
| `ceph_rgw_put` | PUT requests | N/A |
| `ceph_rgw_get_b` | Bytes received | N/A |
| `ceph_rgw_put_b` | Bytes sent | N/A |
| `ceph_rgw_metadata_bytes` | Metadata memory | > 1GB |
| `ceph_rgw_gc_entries` | GC queue depth | > 10000 |

### Health Check Script

```bash
#!/bin/bash
# rgw-health-check.sh

RGW_ENDPOINT="https://s3.internal"
ACCESS_KEY="$VELELO_ACCESS_KEY"
SECRET_KEY="$VELELO_SECRET_KEY"

# Check RGW endpoint
echo "=== RGW Endpoint Check ==="
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$RGW_ENDPOINT")
if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 403 ]; then
    echo "OK: RGW responding (HTTP $HTTP_CODE)"
else
    echo "FAIL: RGW not responding (HTTP $HTTP_CODE)"
fi

# Check bucket access
echo "=== Bucket Access Check ==="
aws s3 ls s3://velero-backups \
    --endpoint-url "$RGW_ENDPOINT" \
    --no-verify-ssl 2>/dev/null && echo "OK: Bucket accessible" || echo "FAIL: Bucket not accessible"

# Check Ceph cluster health
echo "=== Ceph Cluster Health ==="
CEPH_HEALTH=$(sudo ceph -s --format json | jq -r '.health.status')
echo "Cluster health: $CEPH_HEALTH"

# Check RGW daemons
echo "=== RGW Daemon Status ==="
sudo ceph orch ps --daemon_type rgw
```

### RGW Log Monitoring

```bash
# Check RGW logs
sudo ceph orch logs --daemon_type rgw.myrealm.myzone

# Common log locations
# /var/log/ceph/ceph-rgw-*.log
```

---

## S3 Client Configuration

### AWS CLI

```bash
# Configure AWS CLI for Ceph RGW
aws configure --profile ceph
# AWS Access Key ID: $VELELO_ACCESS_KEY
# AWS Secret Access Key: $VELELO_SECRET_KEY
# Default region name: primary
# Default output format: json

# Usage
aws s3 ls --profile ceph --endpoint-url https://s3.internal --no-verify-ssl
aws s3 cp /data s3://velero-backups/ --recursive --profile ceph --endpoint-url https://s3.internal
```

### s3cmd

```bash
# Configure s3cmd
cat <<EOF > ~/.s3cfg
[default]
access_key = $VELELO_ACCESS_KEY
secret_key = $VELELO_SECRET_KEY
host_base = s3.internal
host_bucket = s3.internal
use_https = True
check_ssl_certificate = False
EOF

# Usage
s3cmd ls s3://velero-backups
s3cmd put /data s3://velero-backups/ --recursive
```

### Python boto3

```python
import boto3

s3 = boto3.client(
    's3',
    aws_access_key_id='$VELELO_ACCESS_KEY',
    aws_secret_access_key='$VELELO_SECRET_KEY',
    endpoint_url='https://s3.internal',
    verify=False
)

# List buckets
response = s3.list_buckets()
for bucket in response['Buckets']:
    print(f"Bucket: {bucket['Name']}")

# Upload file
s3.upload_file('/local/file', 'velero-backups', 'file')

# Download file
s3.download_file('velero-backups', 'file', '/local/file')
```

---

## RGW Performance Tuning

### RGW Configuration

```bash
# Threads and workers
sudo ceph config set client.rgw.myrealm.myzone rgw_thread_pool_size 1024
sudo ceph config set client.rgw.myrealm.myzone rgw_num_rados_handles 3

# Cache settings
sudo ceph config set client.rgw.myrealm.myzone rgw_cache_enabled true
sudo ceph config set client.rgw.myrealm.myzone rgw_cache_lru_size 10000

# GC settings
sudo ceph config set client.rgw.myrealm.myzone rgw_gc_max_objs 300
sudo ceph config set client.rgw.myrealm.myzone rgw_gc_obj_min_wait 300
sudo ceph config set client.rgw.myrealm.myzone rgw_gc_processor_max_time 3600
sudo ceph config set client.rgw.myrealm.myzone rgw_gc_processor_period 600

# Throttle
sudo ceph config set client.rgw.myrealm.myzone rgw_max_put_size 5368709120  # 5GB
sudo ceph config set client.rgw.myrealm.myzone rgw_max_chunk_size 4194304    # 4MB
```

### RGW Pool Tuning

```bash
# RGW metadata pool (if separate)
sudo ceph osd pool set .rgw.root pg_num 64
sudo ceph osd pool set .rgw.root pgp_num 64

# RGW data pool
sudo ceph osd pool set default.rgw.buckets.data pg_num 1024
sudo ceph osd pool set default.rgw.buckets.data pgp_num 1024
```

---

## RGW Multisite (Optional)

For future multi-cluster setup:

```bash
# Create realm
sudo ceph realm create --default default

# Create master zonegroup
sudo ceph zonegroup create --master --default default

# Create secondary zonegroup (future)
sudo ceph zonegroup create --secondary secondary

# Pull master zone
sudo ceph zone create --master primary
sudo ceph zone create secondary --rgw-zonegroup=secondary \
    --access-key=$SECONDARY_KEY --secret=$SECONDARY_SECRET

# Commit
sudo ceph period update --commit
```

---

## Air-Gap Considerations

| Component | Source |
|-----------|--------|
| RGW packages | Nexus apt repo (radosgw) |
| RGW container image | Harbor (if using Rook) |
| Velero CLI | Nexus binary repo |
| Velero plugin images | Harbor |
| TLS certificates | Internal CA |

---

## Troubleshooting

| Issue | Command | Resolution |
|-------|---------|------------|
| RGW not responding | `sudo ceph orch ps --daemon_type rgw` | Restart RGW |
| S3 auth failure | Check user credentials | Verify access/secret key |
| Slow uploads | Check network, RGW metrics | Tune thread pool |
| Bucket not found | `sudo radosgw-admin bucket list` | Check zone/zonegroup |
| GC backlog | `sudo radosgw-admin gc list` | Increase GC workers |
| Metadata overflow | Check RGW memory | Increase cache, add MDS resources |

---

## References

- [Ceph RGW Documentation](https://docs.ceph.com/en/reef/radosgw/)
- [Velero Ceph Integration](https://velero.io/docs/v1.12/ceph/)
- [S3 API Reference](https://docs.ceph.com/en/reef/radosgw/s3/)
