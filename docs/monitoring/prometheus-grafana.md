# Prometheus & Grafana — Monitoring Guide

## Overview

The kube-prometheus-stack provides a complete monitoring stack: Prometheus, Grafana, Alertmanager, Node Exporter, and kube-state-metrics. Deployed on both management and application clusters.

> **Air-gap note:** All images mirrored to Harbor. Charts from Nexus. No external scrape targets.

---

## Deployment via Helm

### Add Helm Repo (Nexus — Air-gapped)

```bash
helm repo add prometheus-community https://nexus.internal.example.com/repository/helm-remote/
helm repo update
```

### Values File (Management Cluster — Central)

```yaml
# monitoring-values-mgmt.yaml
namespaceOverride: monitoring

prometheus:
  prometheusSpec:
    retention: 30d
    retentionSize: 90GB
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: cephfs
          accessModes: ["ReadWriteOnce"]
          resources:
            requests: { storage: 100Gi }

    # Remote write receiver (for app cluster to push metrics)
    enableRemoteWriteReceiver: true

    # Additional scrape configs
    additionalScrapeConfigs:
    - job_name: 'argocd-metrics'
      static_configs:
      - targets: ['argocd-metrics.argocd.svc.cluster.local:8082']
    - job_name: 'argocd-repo-server'
      static_configs:
      - targets: ['argocd-repo-server-metrics.argocd.svc.cluster.local:8084']

    resources:
      requests: { cpu: 500m, memory: 2Gi }
      limits:   { cpu: "2", memory: 4Gi }

    # Alerting rules
    additionalAlertRuleGroups:
    - name: node-alerts
      rules:
      - alert: NodeDiskRunningFull
        expr: |
          (node_filesystem_avail_bytes{job="node-exporter",fstype!=""} / node_filesystem_size_bytes{job="node-exporter",fstype!=""} < 0.05) and
          (predict_linear(node_filesystem_avail_bytes{job="node-exporter",fstype!=""}[6h], 3600 * 24 * 4) < 0)
        for: 30m
        labels: { severity: critical }
        annotations:
          summary: "Node {{ $labels.instance }} disk {{ $labels.mountpoint }} running full"
      - alert: NodeMemoryPressure
        expr: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.1
        for: 5m
        labels: { severity: warning }
        annotations:
          summary: "Node {{ $labels.instance }} memory pressure"

    - name: storage-alerts
      rules:
      - alert: CephClusterWarning
        expr: ceph_health_status == 1
        for: 5m
        labels: { severity: warning }
        annotations:
          summary: "Ceph cluster in WARN state"
      - alert: CephClusterCritical
        expr: ceph_health_status == 2
        for: 1m
        labels: { severity: critical }
        annotations:
          summary: "Ceph cluster in CRITICAL state"

    - name: kube-alerts
      rules:
      - alert: KubePodCrashLooping
        expr: rate(kube_pod_container_status_restarts_total[5m]) * 60 * 5 > 0
        for: 15m
        labels: { severity: warning }
        annotations:
          summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} crash looping"
      - alert: KubeDeploymentReplicasUnavailable
        expr: kube_deployment_status_replicas_unavailable > 0
        for: 10m
        labels: { severity: warning }

  ingress:
    enabled: true
    ingressClassName: nginx
    hosts: [prometheus.example.com]
    tls:
    - hosts: [prometheus.example.com]
      secretName: prometheus-tls

alertmanager:
  alertmanagerSpec:
    retention: 120h
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: cephfs
          resources:
            requests: { storage: 10Gi }
    resources:
      requests: { cpu: 100m, memory: 128Mi }
      limits:   { cpu: 500m, memory: 512Mi }

  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'namespace', 'service']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: 'default'
      routes:
      - match: { severity: critical }
        receiver: 'critical'
        repeat_interval: 5m
      - match: { severity: warning }
        receiver: 'warning'
        repeat_interval: 30m
    receivers:
    - name: 'default'
      webhook_configs:
      - url: 'https://webhook.internal.example.com/alerts'
        send_resolved: true
    - name: 'critical'
      email_configs:
      - to: 'oncall@example.com'
        from: 'alerts@example.com'
        smarthost: 'smtp.internal.example.com:25'
      webhook_configs:
      - url: 'https://webhook.internal.example.com/alerts/critical'
    - name: 'warning'
      email_configs:
      - to: 'platform@example.com'
        from: 'alerts@example.com'
        smarthost: 'smtp.internal.example.com:25'
    inhibit_rules:
    - source_match: { severity: critical }
      target_match: { severity: warning }
      equal: ['alertname', 'namespace']

  ingress:
    enabled: true
    ingressClassName: nginx
    hosts: [alertmanager.example.com]

grafana:
  adminPassword: "${GRAFANA_ADMIN_PASSWORD}"
  persistence:
    enabled: true
    storageClassName: cephfs
    size: 10Gi

  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-operated.monitoring.svc.cluster.local:9090
        isDefault: true
        access: proxy
      - name: Loki
        type: loki
        url: http://loki.monitoring.svc.cluster.local:3100
        access: proxy

  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: default
        orgId: 1
        folder: General
        type: file
        disableDeletion: false
        editable: true
        options: { path: /var/lib/grafana/dashboards/default }

  ingress:
    enabled: true
    ingressClassName: nginx
    hosts: [grafana.example.com]
    tls:
    - hosts: [grafana.example.com]
      secretName: grafana-tls

  resources:
    requests: { cpu: 100m, memory: 128Mi }
    limits:   { cpu: 500m, memory: 512Mi }

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true
```

### Values File (Application Cluster — Remote Writes to Mgmt)

```yaml
# monitoring-values-app.yaml
namespaceOverride: monitoring

prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: cephfs
          resources:
            requests: { storage: 50Gi }

    # Remote write to mgmt cluster Prometheus
    remoteWrite:
    - url: "https://prometheus-mgmt.example.com/api/v1/write"
      sendExemplars: true
      queueConfig:
        maxSamplesPerSend: 500
        capacity: 2500

    resources:
      requests: { cpu: 200m, memory: 1Gi }
      limits:   { cpu: "1", memory: 2Gi }

alertmanager:
  enabled: false  # Alerts managed centrally on mgmt cluster

grafana:
  enabled: false  # Use mgmt cluster Grafana
```

### Deploy

```bash
# Management cluster
kubectl config use-context mgmt-cluster
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f monitoring-values-mgmt.yaml

# Application cluster
kubectl config use-context app-cluster
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f monitoring-values-app.yaml
```

---

## Prometheus Configuration

### Retention

| Environment | Retention | Storage | Notes |
|-------------|-----------|---------|-------|
| Development | 7d | 20Gi | Minimal |
| Staging | 15d | 50Gi | Moderate |
| Production (App) | 15d | 50Gi | Per-cluster |
| Production (Mgmt) | 30d | 100Gi | Central |

### Recording Rules

```yaml
# Reduce cardinality, speed up dashboard queries
groups:
- name: node-recording
  interval: 30s
  rules:
  - record: node:cpu:utilization
    expr: 100 - (100 * avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])))
  - record: node:memory:utilization
    expr: 100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
  - record: node:disk:utilization
    expr: 100 * (1 - node_filesystem_avail_bytes / node_filesystem_size_bytes)
```

---

## Grafana Configuration

### Essential Dashboards

| Dashboard | UID / Source | Description |
|-----------|-------------|-------------|
| Node Exporter Full | `rYdddlPWck` | Node CPU, memory, disk, network |
| Kubernetes Cluster | `k8s.views.nodes` | Cluster-wide K8s overview |
| Kube-State-Metrics | `k8s.views.pods` | Pod/deployment status |
| Ceph Cluster | `bt6Kphg4z` | Ceph health, OSD, PG, capacity |
| Calico/Felix | `calico-felix` | Network policy, BGP status |
| NGINX Ingress | `nginx-ingress` | Request rate, latency, errors |
| ArgoCD | `argocd` | Sync status, app health |
| Velero | `velero` | Backup status, schedules |

### Import Dashboard

```bash
# Via Grafana API
curl -X POST -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"pluginId":"grafana","title":"Custom Dashboard","overwrite":true}' \
  "https://grafana.example.com/api/dashboards/import"
```

---

## Alertmanager

### Silences Management

```bash
# Create silence via amtool
amtool silence add \
  --alertmanager.url=https://alertmanager.example.com \
  --comment="Planned maintenance" \
  --expire="2024-12-01T00:00:00Z" \
  alertname=NodeDiskRunningFull instance=node1

# List silences
amtool silence query --alertmanager.url=https://alertmanager.example.com

# Expire silence
amtool silence expire <silence-id> --alertmanager.url=https://alertmanager.example.com
```

---

## Centralized Monitoring

App cluster Prometheus remote-writes to mgmt cluster:

```
App Cluster                 Management Cluster
┌──────────────┐           ┌──────────────────┐
│  Prometheus  │──remote──▶│  Prometheus      │──▶ Grafana
│  (15d ret)   │  write    │  (30d ret)       │──▶ Alertmanager
│  Node Exporter│          │  Node Exporter   │
│  KSMB        │          │  KSMB            │
└──────────────┘           └──────────────────┘
```

### Remote Write Authentication

```yaml
remoteWrite:
- url: "https://prometheus-mgmt.example.com/api/v1/write"
  basicAuth:
    username: { name: prometheus-remote-write, key: username }
    password: { name: prometheus-remote-write, key: password }
  tlsConfig:
    ca: { name: internal-ca, key: ca.crt }
    serverName: prometheus-mgmt.example.com
```

---

## Air-gap: Images from Harbor

### Required Images

| Component | Harbor Image |
|-----------|-------------|
| Prometheus | `harbor.internal.example.com/platform/prometheus:v2.52.0` |
| Alertmanager | `harbor.internal.example.com/platform/alertmanager:v0.27.0` |
| Grafana | `harbor.internal.example.com/platform/grafana:11.1.0` |
| Node Exporter | `harbor.internal.example.com/platform/node-exporter:v1.8.2` |
| KSM | `harbor.internal.example.com/platform/kube-state-metrics:v2.13.0` |
| Config Reloader | `harbor.internal.example.com/platform/configmap-reload:v0.8.0` |
| Prometheus Operator | `harbor.internal.example.com/platform/prometheus-operator:v0.72.0` |

### Mirror Script

```bash
#!/bin/bash
HARBOR=harbor.internal.example.com/platform
for IMG in \
  "prometheus/prometheus:v2.52.0" \
  "prometheus/alertmanager:v0.27.0" \
  "grafana/grafana:11.1.0" \
  "prometheus/node-exporter:v1.8.2" \
  "prometheus/kube-state-metrics:v2.13.0"; do
  DST="${HARBOR}/$(echo $IMG | cut -d/ -f2-)"
  docker pull "$IMG" && docker tag "$IMG" "$DST" && docker push "$DST"
done
```

---

## Resource Sizing

| Cluster Size | Prometheus | Grafana | Alertmanager | Node Exporter |
|--------------|-----------|---------|-------------|---------------|
| Small (<20 nodes) | 500m/2Gi | 100m/128Mi | 50m/64Mi | 50m/64Mi |
| Medium (20-100) | 1000m/4Gi | 200m/256Mi | 100m/128Mi | 100m/128Mi |
| Large (>100) | 2000m/8Gi | 500m/512Mi | 200m/256Mi | 100m/128Mi |
