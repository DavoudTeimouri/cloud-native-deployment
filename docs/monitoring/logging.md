# Loki & Promtail — Logging Guide

## Overview

Loki is a log aggregation system inspired by Prometheus. Promtail ships logs from Kubernetes nodes to Loki. Deployed on both management and application clusters.

> **Air-gap note:** All Loki/Promtail images mirrored to Harbor. Charts from Nexus.

---

## Loki Deployment via Helm

### Add Helm Repo (Nexus — Air-gapped)

```bash
helm repo add grafana https://nexus.internal.example.com/repository/helm-remote/
helm repo update
```

### Simple Scalable Mode (Recommended for Production)

```yaml
# loki-values.yaml
loki:
  image:
    repository: harbor.internal.example.com/platform/loki
    tag: 3.0.0

  # Simple scalable mode (2 read + 2 write paths)
  deploymentMode: SimpleScalable

  simpleScalable:
    replicas: 3

  auth_enabled: false

  # Storage configuration (CephFS via PVC)
  storage:
    type: filesystem
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
      index_directory: /loki/index

  persistence:
    enabled: true
    size: 50Gi
    storageClassName: cephfs
    accessModes: ["ReadWriteOnce"]

  # Retention
  limits_config:
    retention_period: 744h    # 31 days
    max_query_length: 721h
    max_query_parallelism: 32
    reject_old_samples: true
    reject_old_samples_max_age: 168h
    ingestion_rate_mb: 20
    ingestion_burst_rate_mb: 30

  compactor:
    enabled: true
    working_directory: /loki/compactor
    compaction_interval: 10m
    retention_enabled: true
    delete_request_store: filesystem
    retention_delete_delay: 2h
    retention_delete_worker_count: 150

  # Ingester configuration
  ingester:
    chunk_idle_period: 5m
    chunk_retain_period: 30s
    max_transfer_retries: 0
    wal:
      enabled: true
      dir: /loki/wal

  # Ruler (log-based alerts)
  ruler:
    enabled: true
    storage:
      type: local
      local:
        directory: /loki/rules
    alertmanager_url: http://alertmanager.monitoring.svc.cluster.local:9093
    rule_path: /loki/rules-temp

  # Table manager retention
  table_manager:
    retention_deletes_enabled: true
    retention_period: 744h

  resources:
    requests: { cpu: 500m, memory: 1Gi }
    limits:   { cpu: "2", memory: 4Gi }

# ServiceMonitor for Prometheus
monitoring:
  serviceMonitor:
    enabled: true
    labels: { release: kube-prometheus-stack }
  selfMonitoring:
    enabled: true
    lokiCanary:
      enabled: true
      image:
        repository: harbor.internal.example.com/platform/loki-canary
        tag: 3.0.0
```

### Single Binary Mode (Development/Small)

```yaml
loki:
  deploymentMode: SingleBinary
  singleBinary:
    replicas: 1
  persistence:
    enabled: true
    size: 10Gi
    storageClassName: cephfs
```

### Deploy

```bash
helm upgrade --install loki grafana/loki \
  --namespace monitoring --create-namespace \
  -f loki-values.yaml
```

---

## Promtail as DaemonSet

```yaml
# promtail-values.yaml
config:
  clients:
  - url: http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push
    external_labels:
      cluster: mgmt-cluster

  snippets:
    pipelineStages:
    - cri: {}
    - match:
        selector: '{app=~"my-app"}'
        stages:
        - json:
            expressions:
              level: level
              msg: msg
        - labels:
            level:

daemonset:
  image:
    repository: harbor.internal.example.com/platform/promtail
    tag: 3.0.0

  resources:
    requests: { cpu: 100m, memory: 128Mi }
    limits:   { cpu: 500m, memory: 256Mi }

  # Collect journal logs (systemd)
  extraVolumes:
  - name: journal
    hostPath: { path: /var/log/journal }
  extraVolumeMounts:
  - name: journal
    mountPath: /var/log/journal
    readOnly: true

serviceMonitor:
  enabled: true
  labels: { release: kube-prometheus-stack }
```

```bash
helm upgrade --install promtail grafana/promtail \
  --namespace monitoring --create-namespace \
  -f promtail-values.yaml
```

---

## CephFS PVC for Loki Storage

Ensure CephFS storage class exists:

```bash
kubectl get storageclass cephfs
# NAME     PROVISIONER        RECLAIMPOLICY
# cephfs   ceph.com/cephfs   Delete
```

For large-scale deployments, consider object storage (Ceph RGW / MinIO):

```yaml
loki:
  storage:
    type: s3
    s3:
      endpoint: s3.internal.example.com
      bucketnames: loki-chunks
      region: default
      access_key_id: ${S3_ACCESS_KEY}
      secret_access_key: ${S3_SECRET_KEY}
      s3forcepathstyle: true
      insecure: false
```

---

## Log Retention Configuration

| Period | Setting | Default |
|--------|---------|---------|
| Retention period | `limits_config.retention_period` | 744h (31d) |
| Compaction interval | `compactor.compaction_interval` | 10m |
| Delete delay | `compactor.retention_delete_delay` | 2h |
| Reject old samples | `limits_config.reject_old_samples` | true |
| Max sample age | `limits_config.reject_old_samples_max_age` | 168h |

### Per-tenant Retention

```yaml
overrides:
  tenants:
    default:
      retention_period: 744h
    team-alpha:
      retention_period: 2160h  # 90 days
```

---

## LogQL Query Examples

```logql
# All logs from a namespace
{namespace="my-app"}

# Logs from specific app with error level
{app="my-app"} |= "error" | json | level="error"

# Count of errors per minute
sum(rate({app="my-app"} |= "error" [5m]))

# Latency percentiles from structured logs
{app="my-app"} | json | line_format "{{.msg}}" | label_format latency="{{.duration_ms}}"
quantile_over_time(0.99, {app="my-app"} | json | unwrap duration_ms [5m])

# K8s events for a pod
{app="kube-events"} | json | object_involved_object_name="my-pod"

# Recent crash logs
{namespace="my-app"} |= "panic" |~ `goroutine \\d+`

# Logs between timestamps
{app="my-app"} |= "timeout" | line_format "{{.ts}} {{.msg}}"
```

---

## Grafana Loki Datasource

Configured in Grafana values or via UI:

```yaml
# grafana-values.yaml (datasource section)
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Loki
      type: loki
      url: http://loki.monitoring.svc.cluster.local:3100
      access: proxy
      isDefault: false
      jsonData:
        maxLines: 1000
        derivedFields:
        - datasourceName: Prometheus
          matcherRegex: "traceID=(\\w+)"
          name: TraceID
          url: "$${__value.raw}"
```

---

## Log-based Alerts via Loki Ruler

```yaml
# Log-based alert rule (store in /loki/rules/)
groups:
- name: app-errors
  rules:
  - alert: HighErrorRate
    expr: |
      sum(rate({app="my-app"} |= "error" [5m])) by (namespace, app)
      /
      sum(rate({app="my-app"} [5m])) by (namespace, app)
      > 0.1
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High error rate for {{ $labels.app }}"
      description: "Error rate is {{ $value | humanizePercentage }}"

  - alert: PodCrashLoop
    expr: |
      count_over_time({app="my-app"} |= "CrashLoopBackOff" [5m]) > 3
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Pod {{ $labels.app }} crash looping"
```

---

## Log Labels and Structured Logging

### Recommended Labels

| Label | Source | Description |
|-------|--------|-------------|
| `app` | Pod label | Application name |
| `namespace` | K8s metadata | Namespace |
| `cluster` | Promtail config | Cluster name |
| `environment` | Pod label | dev/staging/prod |
| `container` | K8s metadata | Container name |
| `pod` | K8s metadata | Pod name |
| `node` | K8s metadata | Node name |

### Structured Logging Best Practices

1. Output logs in JSON format for easy parsing
2. Include `level`, `msg`, `timestamp`, `trace_id` fields
3. Avoid high-cardinality labels (use filters instead)
4. Set appropriate `max_label_names_per_series` limit

---

## Centralized Logging

App cluster Promtail ships logs to mgmt cluster Loki:

```
App Cluster                    Management Cluster
┌──────────────┐              ┌──────────────────┐
│  Promtail    │──push logs──▶│  Loki            │──▶ Grafana
│  (DaemonSet) │              │  (SimpleScalable) │
│              │              │  Ruler            │──▶ Alertmanager
└──────────────┘              └──────────────────┘
```

### App Cluster Promtail Configuration

```yaml
# promtail-values-app.yaml
config:
  clients:
  - url: https://loki-mgmt.example.com/loki/api/v1/push
    external_labels:
      cluster: app-cluster
    basic_auth:
      username: loki-push
      password: ${LOKI_PUSH_PASSWORD}
    tls_config:
      ca_file: /etc/ssl/certs/internal-ca.crt
```

---

## Alternative: Vector as Log Collector

See [log-collector.md](./log-collector.md) for full Vector deployment guide.

---

## Comparison: Promtail vs Vector vs Fluent Bit

| Feature | Promtail | Vector | Fluent Bit |
|---------|----------|--------|------------|
| Language | Go | Rust | C |
| Memory usage | ~100-200Mi | ~30-50Mi | ~20-40Mi |
| CPU usage | Moderate | Low | Low |
| K8s native | Yes (Loki-first) | Yes (vendor-agnostic) | Yes |
| Loki support | Native | Native | Via plugin |
| Transformations | Pipeline stages | VRL language | Lua/modifiers |
| Structured parsing | Limited | Extensive | Moderate |
| Ecosystem | Grafana | Datadog (OSS) | CNCF |
| Air-gap maturity | High | High | High |
| Configuration | YAML | TOML/YAML/JSON | JSON |
| Best for | Simple Loki setups | High-throughput, multi-sink | Lightweight, embedded |

---

## Air-gap: Loki/Promtail Images from Harbor

### Required Images

| Component | Harbor Image |
|-----------|-------------|
| Loki | `harbor.internal.example.com/platform/loki:3.0.0` |
| Promtail | `harbor.internal.example.com/platform/promtail:3.0.0` |
| Loki Canary | `harbor.internal.example.com/platform/loki-canary:3.0.0` |
| Gateway (nginx) | `harbor.internal.example.com/platform/nginx:1.25-alpine` |

### Mirror Script

```bash
#!/bin/bash
HARBOR=harbor.internal.example.com/platform
VERSION=3.0.0
for IMG in loki promtail loki-canary; do
  SRC="grafana/${IMG}:${VERSION}"
  DST="${HARBOR}/${IMG}:${VERSION}"
  docker pull "$SRC" && docker tag "$SRC" "$DST" && docker push "$DST"
done
```
