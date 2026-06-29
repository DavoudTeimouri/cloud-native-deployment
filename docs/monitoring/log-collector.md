# Vector — Log Collector Guide

## Overview

Vector is a high-performance, lightweight (Rust-based) log collector that can replace Promtail. It supports multiple sources and sinks with powerful transformation pipelines.

> **Air-gap note:** Vector image mirrored to Harbor. No external network access required.

---

## Vector Deployment as Alternative to Promtail

### Add Helm Repo (Nexus — Air-gapped)

```bash
helm repo add vector https://nexus.internal.example.com/repository/helm-remote/
helm repo update
```

### Values File

```yaml
# vector-values.yaml
image:
  repository: harbor.internal.example.com/platform/vector
  tag: 0.35.0-debian
  pullPolicy: IfNotPresent

# Deploy as DaemonSet (log collector on each node)
role: Agent

customConfig:
  # Sources
  sources:
    kubernetes_logs:
      type: kubernetes_logs
      auth:
        token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      self_node_name: "${VECTOR_SELF_NODE_NAME}"
      pod_annotation_fields:
        container_image: "container.image"
        container_name: "container.name"
        pod_labels: "pod.labels"
        pod_name: "pod.name"
        pod_namespace: "pod.namespace"
        pod_uid: "pod.uid"

    host_metrics:
      type: host_metrics
      collectors:
        - cpu
        - disk
        - filesystem
        - load
        - memory
        - network

    internal_metrics:
      type: internal_metrics

  # Transforms
  transforms:
    # Add cluster label to all logs
    add_cluster:
      type: remap
      inputs: ["kubernetes_logs"]
      source: |
        .cluster = "mgmt-cluster"
        .environment = get_env_var!("ENVIRONMENT")

    # Parse JSON logs
    parse_json:
      type: remap
      inputs: ["add_cluster"]
      source: |
        parsed = parse_json!(.message)
        . = merge(., parsed)

    # Route by severity
    route_errors:
      type: route
      inputs: ["parse_json"]
      route:
        error: '.level == "error" || .level == "ERROR"'
        info: '.level == "info" || .level == "INFO"'

    # Remove high-cardinality fields
    reduce_cardinality:
      type: remap
      inputs: ["route_errors.info", "route_errors.error"]
      source: |
        del(.pod_uid)
        del(.stream)

  # Sinks
  sinks:
    # Primary: Loki
    loki:
      type: loki
      inputs: ["reduce_cardinality"]
      endpoint: "http://loki.monitoring.svc.cluster.local:3100"
      encoding:
        codec: json
      labels:
        app: "{{ pod_name }}"
        namespace: "{{ pod_namespace }}"
        cluster: "{{ cluster }}"
        environment: "{{ environment }}"
      remove_label_fields: true
      healthcheck:
        enabled: true

    # Secondary: File backup
    file_backup:
      type: file
      inputs: ["route_errors.error"]
      path: /var/log/vector/errors/{{ pod_namespace }}-{{ pod_name }}-%Y-%m-%d.log
      encoding:
        codec: json

    # Stdout (for debugging)
    stdout:
      type: console
      inputs: ["internal_metrics"]
      encoding:
        codec: json

    # Prometheus metrics
    prometheus:
      type: prometheus_exporter
      inputs: ["internal_metrics", "host_metrics"]
      address: "0.0.0.0:9090"

serviceMonitor:
  enabled: true
  labels: { release: kube-prometheus-stack }

resources:
  requests: { cpu: 50m, memory: 64Mi }
  limits:   { cpu: 200m, memory: 128Mi }

# Tolerations to run on all nodes
tolerations:
- operator: Exists
```

### Deploy

```bash
helm upgrade --install vector vector/vector \
  --namespace monitoring --create-namespace \
  -f vector-values.yaml
```

---

## Configuration for K8s Log Collection

### Source: Kubernetes Logs

The `kubernetes_logs` source automatically:
- Discovers pod log files from `/var/log/pods`
- Enriches logs with pod metadata (namespace, labels, annotations)
- Handles container rotation (log rotation)
- Respects Kubernetes log format (CRI-O, containerd, docker)

### Source: Journald (System Logs)

```toml
[sources.journald]
type = "journald"
include_units = ["kubelet", "containerd", "docker"]

[transforms.journald_transform]
type = "remap"
inputs = ["journald"]
source = '''
  .cluster = "mgmt-cluster"
  .hostname = get_hostname!()
'''

[sinks.journald_loki]
type = "loki"
inputs = ["journald_transform"]
endpoint = "http://loki.monitoring.svc.cluster.local:3100"
labels.source = "journald"
labels.unit = "{{ UNIT }}"
```

---

## Transformation Pipelines

### VRL (Vector Remap Language) Examples

```
# Extract trace ID from log message
trace_id = parse_regex!(.message, r'trace_id=(?P<trace_id>\w+)')?.trace_id
.trace_id = trace_id

# Redact sensitive data
.message = replace!(.message, r'password=\S+', 'password=REDACTED')

# Add timestamp from custom field
.ts = parse_timestamp!(.custom_ts, "%Y-%m-%d %H:%M:%S")

# Filter out health check logs
if contains!(.message, "health_check") {
  abort
}
```

### Multi-stage Pipeline

```yaml
transforms:
  # Stage 1: Parse
  parse:
    type: remap
    inputs: ["kubernetes_logs"]
    source: |
      . = merge!(., parse_json!(.message))

  # Stage 2: Enrich
  enrich:
    type: remap
    inputs: ["parse"]
    source: |
      .cluster = get_env_var!("CLUSTER_NAME")
      .environment = .pod_labels.environment
      .team = .pod_labels.team

  # Stage 3: Filter
  filter:
    type: filter
    inputs: ["enrich"]
    condition: |
      .level != "debug" && .level != "trace"

  # Stage 4: Deduplicate
  dedup:
    type: dedupe
    inputs: ["filter"]
    fields: ["message", "pod_name"]
    window: 60
```

---

## Multi-sink Output

```yaml
sinks:
  # Primary: Loki
  loki:
    type: loki
    inputs: ["filter"]
    endpoint: "http://loki.monitoring.svc.cluster.local:3100"

  # Backup: File
  file_backup:
    type: file
    inputs: ["filter"]
    path: /var/log/vector/backup-%Y-%m-%d.log
    encoding: { codec: json }

  # Debug: Console
  console:
    type: console
    inputs: ["route_errors.error"]
    encoding: { codec: json }

  # Alert: Webhook for error logs
  error_webhook:
    type: http
    inputs: ["route_errors.error"]
    uri: "https://webhook.internal.example.com/log-alerts"
    method: post
    encoding: { codec: json }
    batch:
      max_bytes: 1048576
      timeout_secs: 5
```

---

## Resource Usage Comparison

| Collector | CPU (per node) | Memory (per node) | Disk I/O | Binary Size |
|-----------|---------------|-------------------|----------|-------------|
| Promtail | 50-150m | 100-200Mi | Moderate | ~30MB |
| Vector | 20-80m | 30-80Mi | Low | ~50MB |
| Fluent Bit | 10-40m | 20-50Mi | Very Low | ~3MB |

Benchmark with 1000 log lines/sec:

| Metric | Promtail | Vector | Fluent Bit |
|--------|----------|--------|------------|
| P50 latency | 5ms | 2ms | 1ms |
| P99 latency | 50ms | 15ms | 10ms |
| Memory RSS | 180Mi | 55Mi | 35Mi |
| CPU % | 8% | 3% | 2% |

---

## When to Use Vector vs Promtail

### Use Vector When:
- High log throughput (>10K lines/sec per node)
- Need complex transformations (VRL)
- Multi-sink output required (Loki + S3 + file)
- Tight memory constraints
- Need protocol/encoding conversion
- Want vendor-agnostic collector

### Use Promtail When:
- Simple Loki-only deployment
- Grafana ecosystem preference
- Minimal transformation needed
- Default K8s log pipeline is sufficient
- Loki-specific features needed (tenant headers, chunk streaming)

### Migration Path

```bash
# 1. Deploy Vector alongside Promtail (dual shipping)
# 2. Verify logs arrive identically in Loki
# 3. Remove Promtail DaemonSet
# 4. Monitor Vector performance
```

---

## Air-gap: Vector Image from Harbor

| Component | Upstream Image | Harbor Image |
|-----------|---------------|--------------|
| Vector | `timberio/vector:0.35.0-debian` | `harbor.internal.example.com/platform/vector:0.35.0-debian` |

### Mirror Script

```bash
#!/bin/bash
HARBOR=harbor.internal.example.com/platform
VERSION=0.35.0-debian
SRC="timberio/vector:${VERSION}"
DST="${HARBOR}/vector:${VERSION}"
docker pull "$SRC" && docker tag "$SRC" "$DST" && docker push "$DST"
```

### Helm Chart from Nexus

```bash
helm pull vector/vector --version 0.35.0
curl -u admin:password --upload-file vector-0.35.0.tgz \
  "https://nexus.internal.example.com/repository/helm-hosted/"
```
