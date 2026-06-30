# Monitoring Metrics Implementation

> Simple and advanced monitoring for your cloud-native deployment

---

## 1. Simple Monitoring (Getting Started)

Simple monitoring gives you visibility into the health of your cluster with
minimal setup. Install these components and you're up and running.

### 1.1 Install metrics-server

`metrics-server` is the foundation. It collects CPU and memory usage from
all nodes and pods. Required for `kubectl top` and HPA.

```bash
# Install
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# For self-signed certificates on bare-metal clusters
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metrics-server
  namespace: kube-system
spec:
  template:
    spec:
      containers:
        - name: metrics-server
          args:
            - --kubelet-preferred-address-types=InternalIP
            - --kubelet-insecure-tls
EOF

# Verify
kubectl top nodes
kubectl top pods --all-namespaces
```

### 1.2 Basic Resource Monitoring

```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -n production --sort-by=memory

# Check specific pod containers
kubectl top pod <pod-name> -n production --containers

# Describe node for capacity info
kubectl describe node <node-name> | grep -A 10 "Allocated resources"
```

### 1.3 Simple Alerts (kubectl-based)

```bash
# Check for crashed pods
kubectl get pods --all-namespaces --field-selector status.phase=Failed

# Check for pending pods
kubectl get pods --all-namespaces --field-selector status.phase=Pending

# Check node conditions
kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status,REASON:.status.conditions[?(@.type=="Ready")].reason

# Check disk pressure
kubectl get nodes -o custom-columns=NAME:.metadata.name,DISK:.status.conditions[?(@.type=="DiskPressure")].status

# Watch events in real-time
kubectl get events --all-namespaces --watch --field-selector type=Warning
```

### 1.4 Simple Health Check Script

```bash
#!/bin/bash
# simple-health-check.sh — Quick cluster health overview

echo "=== Cluster Health Check ==="
echo "Date: $(date)"
echo ""

echo "--- Nodes ---"
kubectl get nodes -o wide
echo ""

echo "--- Node Resources ---"
kubectl top nodes 2>/dev/null || echo "metrics-server not installed"
echo ""

echo "--- Pods Not Running ---"
kubectl get pods --all-namespaces --field-selector status.phase!=Running,status.phase!=Succeeded 2>/dev/null | head -20
echo ""

echo "--- PVC Not Bound ---"
kubectl get pvc --all-namespaces --field-selector status.phase!=Bound 2>/dev/null
echo ""

echo "--- Recent Warning Events ---"
kubectl get events --all-namespaces --field-selector type=Warning --sort-by='.lastTimestamp' | tail -10
echo ""

echo "--- Certificate Expiry ---"
kubeadm certs check-expiration 2>/dev/null || echo "kubeadm not available"
echo ""

echo "=== Health Check Complete ==="
```

---

## 2. Advanced Monitoring (Full Stack)

Advanced monitoring adds Prometheus, Grafana, Loki, custom dashboards,
alerting, and long-term metric storage.

### 2.1 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Monitoring Stack                                                 │
│                                                                   │
│ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │
│ │ Prometheus   │  │ Grafana      │  │ Loki         │            │
│ │              │  │              │  │              │            │
│ │ Scrapes      │  │ Visualizes   │  │ Log          │            │
│ │ metrics      │  │ metrics      │  │ aggregation  │            │
│ │ from all     │  │ + logs       │  │              │            │
│ │ targets      │  │              │  │              │            │
│ └──────┬───────┘  └──────┬───────┘  └──────┬───────┘            │
│        │                 │                 │                     │
│ ┌──────┴─────────────────┴─────────────────┴───────┐            │
│ │              ServiceMonitors / PodMonitors         │            │
│ └───────────────────────────────────────────────────┘            │
│                                                                   │
│ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │
│ │ Alertmanager │  │ Node Exporter│  │ kube-state   │            │
│ │              │  │              │  │ -metrics     │            │
│ │ Sends alerts │  │ Hardware     │  │ K8s object   │            │
│ │ to email/    │  │ metrics      │  │ metrics      │            │
│ │ Slack/Pager  │  │              │  │              │            │
│ └──────────────┘  └──────────────┘  └──────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Install Prometheus + Grafana + Loki

```bash
# Add repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin \
  --set grafana.sidecar.dashboards.enabled=true \
  --set grafana.sidecar.datasources.enabled=true

# Install Loki + Promtail
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=50Gi

# Verify
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

### 2.3 Access Dashboards

```bash
# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000 — login: admin / admin

# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090

# Alertmanager
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# Open http://localhost:9093
```

### 2.4 Custom Prometheus Rules

```yaml
# custom-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: custom-alerts
  namespace: monitoring
spec:
  groups:
    - name: node-alerts
      rules:
        - alert: NodeHighCPU
          expr: (1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100 > 80
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High CPU usage on {{ $labels.instance }}"
            description: "CPU usage is {{ $value }}%"

        - alert: NodeHighMemory
          expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High memory usage on {{ $labels.instance }}"

        - alert: NodeDiskAlmostFull
          expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Disk almost full on {{ $labels.instance }}"

        - alert: NodeDiskWillFillIn4Hours
          expr: predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 4 * 3600) < 0
          for: 1h
          labels:
            severity: critical
          annotations:
            summary: "Disk on {{ $labels.instance }} will fill in 4 hours"

    - name: pod-alerts
      rules:
        - alert: PodCrashLooping
          expr: rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash looping"

        - alert: PodNotReady
          expr: kube_pod_status_phase{phase="Pending"} == 1
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} stuck in Pending"

        - alert: DeploymentReplicasMismatch
          expr: kube_deployment_spec_replicas != kube_deployment_status_ready_replicas
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has replica mismatch"

        - alert: PVCAlmostFull
          expr: (kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes) * 100 < 10
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} almost full"

    - name: certificate-alerts
      rules:
        - alert: CertificateExpiringSoon
          expr: (certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 14
          labels:
            severity: warning
          annotations:
            summary: "Certificate {{ $labels.name }} expiring in {{ $value }} days"
```

### 2.5 LogQL Queries (Loki)

```bash
# All logs from a namespace
{app="nginx"} | json

# Error logs
{app="nginx"} |= "error"

# Logs from specific pod
{namespace="production", pod="web-xxx"} | json | line_format "{{.method}} {{.path}} {{.status}}"

# Rate of errors
rate({app="nginx"} |= "error" [5m])

# Top 10 paths by request count
topk(10, sum(count_over_time({app="nginx"}[1h])) by (path))
```

### 2.6 Advanced Grafana Dashboards

Import these dashboard IDs into Grafana:

| Dashboard | ID | Description |
|-----------|-----|-------------|
| **Node Exporter Full** | 1860 | Complete node metrics |
| **Kubernetes Cluster** | 7249 | Cluster overview |
| **Kubernetes Deployment** | 8588 | Deployment metrics |
| **Kubernetes Pod** | 6336 | Pod metrics |
| **Kubernetes Node** | 15760 | Node metrics |
| **Ceph Cluster** | 2842 | Ceph metrics |
| **Ceph OSD** | 5336 | OSD metrics |
| **Ceph Pool** | 5342 | Pool metrics |
| **NGINX Ingress** | 9614 | Ingress metrics |
| **PostgreSQL** | 9628 | Database metrics |
| **Redis** | 763 | Cache metrics |
| **Elasticsearch** | 4358 | Search metrics |
| **JVM** | 3060 | Java metrics |
| **Blackbox Exporter** | 7587 | Uptime monitoring |

### 2.7 Custom ServiceMonitor

```yaml
# Monitor your own application
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-monitor
  namespace: production
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

### 2.8 kube-state-metrics

```bash
# Install (included in kube-prometheus-stack, or standalone)
helm install kube-state-metrics prometheus-community/kube-state-metrics \
  --namespace monitoring

# Key metrics:
# - kube_deployment_status_replicas
# - kube_pod_container_status_restarts_total
# - kube_node_status_condition
# - kube_resourcequota
# - kube_persistentvolumeclaim_status_phase
```

### 2.9 Node Exporter

```bash
# Included in kube-prometheus-stack, or standalone
helm install node-exporter prometheus-community/prometheus-node-exporter \
  --namespace monitoring

# Collectors:
# - node_cpu_seconds_total
# - node_memory_MemTotal_bytes
# - node_filesystem_avail_bytes
# - node_network_receive_bytes_total
# - node_disk_io_time_seconds_total
```

### 2.10 Alertmanager Configuration

```yaml
# alertmanager-config.yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-config
  namespace: monitoring
stringData:
  alertmanager.yaml: |
    global:
      resolve_timeout: 5m
      smtp_smarthost: 'smtp.internal:25'
      smtp_from: 'alerts@internal.lan'

    route:
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'default'
      routes:
        - match:
            severity: critical
          receiver: 'critical'
          continue: true
        - match:
            severity: warning
          receiver: 'warning'

    receivers:
      - name: 'default'
        email_configs:
          - to: 'team@internal.lan'
      - name: 'critical'
        email_configs:
          - to: 'oncall@internal.lan'
        slack_configs:
          - api_url: 'https://hooks.slack.com/services/xxx'
            channel: '#alerts-critical'
        pagerduty_configs:
          - service_key: '<pagerduty-key>'
      - name: 'warning'
        slack_configs:
          - api_url: 'https://hooks.slack.com/services/xxx'
            channel: '#alerts-warning'

    inhibit_rules:
      - source_match:
          severity: 'critical'
        target_match:
          severity: 'warning'
        equal: ['alertname', 'namespace']
```

### 2.11 Long-Term Storage (Thanos / Cortex)

```bash
# Thanos for long-term metric storage
helm install thanos bitnami/thanos \
  --namespace monitoring \
  --set query.stores=prometheus-operated:9090 \
  --set storegateway.enabled=true \
  --set compactor.enabled=true

# Or use kube-prometheus-stack with Thanos sidecar
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.remoteWrite[0].url="http://thanos-receive:19291/api/v1/receive"
```

---

## 3. Monitoring Best Practices

### 3.1 Golden Signals

Monitor these four signals for every service:

| Signal | What to Measure | Prometheus Metric |
|--------|----------------|-------------------|
| **Latency** | Request duration | `http_request_duration_seconds` |
| **Traffic** | Requests per second | `rate(http_requests_total[5m])` |
| **Errors** | Error rate | `rate(http_requests_total{status=~"5.."}[5m])` |
| **Saturation** | Resource utilization | `node_cpu_seconds_total`, `node_memory_MemUsed_bytes` |

### 3.2 RED Method (Services)

| Metric | Description |
|--------|-------------|
| **Rate** | Requests per second |
| **Errors** | Failed requests per second |
| **Duration** | Time to process requests |

### 3.3 USE Method (Resources)

| Metric | Description |
|--------|-------------|
| **Utilization** | % of resource used |
| **Saturation** | Queue depth or wait time |
| **Errors** | Error count |

### 3.4 Alerting Rules

| Rule | Priority | Response |
|------|----------|----------|
| **Critical** | PagerDuty/Phone | Immediate action required |
| **Warning** | Slack/Email | Investigate within hours |
| **Info** | Dashboard only | Review during business hours |

### 3.5 Dashboard Organization

| Dashboard | Audience | Content |
|-----------|----------|---------|
| **Cluster Overview** | SRE/Admin | Node health, resource usage, alerts |
| **Namespace Dashboard** | Developers | Pod health, deployment status, logs |
| **Application Dashboard** | Developers | App-specific metrics, latency, errors |
| **Infrastructure Dashboard** | SRE | Ceph, network, storage metrics |
| **Capacity Dashboard** | Planning | Resource trends, forecasting |

---

## 4. Monitoring Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `grafana_admin_password` | `admin` | Grafana admin password |
| `prometheus_retention` | `15d` | How long to keep metrics |
| `prometheus_storage` | `100Gi` | Prometheus storage size |
| `loki_storage` | `50Gi` | Loki log storage size |
| `alert_email` | `team@internal.lan` | Alert email recipient |
| `slack_webhook_url` | — | Slack webhook for alerts |
| `pagerduty_key` | — | PagerDuty integration key |
| `thanos_enabled` | `false` | Enable long-term storage |
| `scrape_interval` | `30s` | How often to scrape metrics |
