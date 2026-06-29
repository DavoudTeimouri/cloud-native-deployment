# Monitoring & Backup Cheat Sheet

> Quick reference for Prometheus, Grafana, Loki, Alertmanager, Velero

---

## Prometheus

### PromQL Examples

| Use Case | Query |
|----------|-------|
| CPU usage by pod | `rate(container_cpu_usage_seconds_total{container!=""}[5m])` |
| Memory usage by pod | `container_memory_working_set_bytes{container!=""}` |
| Disk usage | `node_filesystem_avail_bytes / node_filesystem_size_bytes * 100` |
| Network receive | `rate(node_network_receive_bytes_total[5m])` |
| Network transmit | `rate(node_network_transmit_bytes_total[5m])` |
| Pod restart count | `kube_pod_container_status_restarts_total` |
| Request rate | `rate(http_requests_total[5m])` |
| Error rate | `rate(http_requests_total{status=~"5.."}[5m])` |
| 95th percentile latency | `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))` |
| Targets down | `up == 0` |
| Node CPU % | `100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| Node memory % | `100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100)` |
| PVC usage | `kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes * 100` |
| OOM kills | `rate(node_vmstat_oom_kill[5m])` |
| Certificate expiry | `probe_ssl_earliest_cert_expiry - time()` |

### Prometheus Operations

| Action | Command |
|--------|---------|
| Check targets | `curl http://localhost:9090/api/v1/targets \| jq '.data.activeTargets[]'` |
| Check rules | `curl http://localhost:9090/api/v1/rules \| jq '.data.groups[]'` |
| Reload config | `curl -X POST http://localhost:9090/-/reload` |
| Check status | `curl http://localhost:9090/-/healthy` |
| Check ready | `curl http://localhost:9090/-/ready` |
| Query API | `curl 'http://localhost:9090/api/v1/query?query=up'` |
| Query range | `curl 'http://localhost:9090/api/v1/query_range?query=up&start=...&end=...&step=15s'` |
| List metrics | `curl http://localhost:9090/api/v1/label/__name__/values` |
| Series count | `curl http://localhost:9090/api/v1/status/tsdb \| jq '.data.numSeries'` |
| TSDB status | `curl http://localhost:9090/api/v1/status/tsdb` |
| Alertmanager status | `curl http://localhost:9090/api/v1/alertmanagers` |
| Runtime info | `curl http://localhost:9090/api/v1/status/runtimeinfo` |
| Build info | `curl http://localhost:9090/api/v1/status/buildinfo` |

### Prometheus CLI (promtool)

```bash
# Check config syntax
promtool check config /etc/prometheus/prometheus.yml

# Check rules syntax
promtool check rules /etc/prometheus/rules/*.yml

# Query from CLI
promtool query instant http://localhost:9090 'up'

# Unit test rules
promtool test rules test.yml
```

---

## Grafana

### API Usage

| Action | Command |
|--------|---------|
| Health check | `curl http://admin:admin@localhost:3000/api/health` |
| List datasources | `curl http://admin:admin@localhost:3000/api/datasources` |
| Create datasource | `curl -X POST http://admin:admin@localhost:3000/api/datasources -H "Content-Type: application/json" -d '{"name":"Prometheus","type":"prometheus","url":"http://prometheus:9090","access":"proxy"}'` |
| List dashboards | `curl http://admin:admin@localhost:3000/api/search` |
| Get dashboard | `curl http://admin:admin@localhost:3000/api/dashboards/uid/<uid>` |
| Import dashboard | `curl -X POST http://admin:admin@localhost:3000/api/dashboards/import -H "Content-Type: application/json" -d @dashboard.json` |
| List alerts | `curl http://admin:admin@localhost:3000/api/alerts` |
| List orgs | `curl http://admin:admin@localhost:3000/api/orgs` |
| List users | `curl http://admin:admin@localhost:3000/api/users` |
| Snapshot | `curl -X POST http://admin:admin@localhost:3000/api/snapshots -H "Content-Type: application/json" -d '{"dashboard":{...}}'` |

### Dashboard Import via UI
1. Navigate to **Dashboards → Import**
2. Upload JSON or paste content
3. Select datasource
4. Click **Import**

### Grafana CLI

```bash
# Reset admin password
grafana-cli admin reset-admin-password <password>

# List installed plugins
grafana-cli plugins ls

# Install plugin
grafana-cli plugins install <plugin-name>

# Restart Grafana
systemctl restart grafana-server
```

---

## Loki (LogQL)

### LogQL Examples

| Use Case | Query |
|----------|-------|
| All logs from app | `{app="nginx"}` |
| Filter by namespace | `{namespace="production"}` |
| Filter by pod | `{pod=~"nginx-.*"}` |
| Text search | `{app="nginx"} \|~ "error\|ERROR"` |
| Exclude pattern | `{app="nginx"} !~ "health\|metrics"` |
| JSON parsing | `{app="nginx"} \| json \| status_code >= 500` |
| Line format | `{app="nginx"} \| json \| line_format "{{.method}} {{.path}} {{.status}}"` |
| Rate of logs | `rate({app="nginx"}[5m])` |
| Count over time | `sum(count_over_time({app="nginx"}[5m]))` |
| Bytes rate | `bytes_rate({app="nginx"}[5m])` |
| Top label values | `topk(10, sum(count_over_time({app="nginx"}[5m])) by (path))` |
| Filter + unwrap | `{app="nginx"} \| json \| status_code >= 500 \| unwrap duration` |
| Multiple selectors | `{app="nginx", namespace="production"}` |
| Container logs | `{container_name="nginx", namespace="production"}` |

### Loki Operations

| Action | Command |
|--------|---------|
| Tail logs | `logcli query '{app="nginx"}' --tail` |
| Query range | `logcli query '{app="nginx"}' --since=1h` |
| Query with limit | `logcli query '{app="nginx"}' --limit=100` |
| Label values | `logcli labels app` |
| Label keys | `logcli labels` |
| Series | `logcli series '{app="nginx"}'` |
| Stats | `logcli stats '{app="nginx"}'` |
| Check readiness | `curl http://localhost:3100/ready` |
| Metrics | `curl http://localhost:3100/metrics` |
| Config | `curl http://localhost:3100/config` |

### LogCLI Setup
```bash
# Configure
logcli --addr=http://loki.monitoring.svc:3100 config set

# Query
logcli query '{namespace="production"}' --since=24h --limit=50

# Tail
logcli query '{app="nginx"}' --tail
```

---

## Alertmanager (amtool)

### amtool Commands

| Action | Command |
|--------|---------|
| Check config | `amtool check-config alertmanager.yml` |
| List alerts | `amtool alert query` |
| List alerts (filter) | `amtool alert query --alert.instance=web` |
| List alerts (receiver) | `amtool alert query --receiver=team-ops` |
| List silences | `amtool silence query` |
| List silences (filter) | `amtool silence query --state=active` |
| Add silence | `amtool silence add alertname=HighCPU --duration=2h` |
| Add silence (comment) | `amtool silence add alertname=HighCPU --comment="Maintenance"` |
| Expire silence | `amtool silence expire <silence-id>` |
| Expire silence (filter) | `amtool silence expire --alert-name=HighCPU` |
| Show routes | `amtool config routes show` |
| Test routes | `amtool config routes test severity=critical` |
| Show config | `amtool config show` |
| Reload config | `amtool reload` |

### Alertmanager API

| Action | Command |
|--------|---------|
| List alerts | `curl http://localhost:9093/api/v2/alerts` |
| List silences | `curl http://localhost:9093/api/v2/silences` |
| Create silence | `curl -X POST http://localhost:9093/api/v2/silences -H "Content-Type: application/json" -d '{"matchers":[{"name":"alertname","value":"HighCPU","isRegex":false}],"startsAt":"2024-01-01T00:00:00Z","endsAt":"2024-01-01T02:00:00Z","createdBy":"admin","comment":"Maintenance"}'` |
| Delete silence | `curl -X DELETE http://localhost:9093/api/v2/silence/<id>` |
| Status | `curl http://localhost:9093/api/v2/status` |
| Reload | `curl -X POST http://localhost:9093/-/reload` |

---

## Velero

### Backup Operations

| Action | Command |
|--------|---------|
| Create backup | `velero backup create <name>` |
| Backup specific namespace | `velero backup create <name> --include-namespaces=<ns>` |
| Backup all namespaces | `velero backup create <name> --include-namespaces='*'` |
| Backup with volumes | `velero backup create <name> --default-volumes-to-restic` |
| Backup with wait | `velero backup create <name> --wait` |
| Backup TTL | `velero backup create <name> --ttl=720h` |
| Describe backup | `velero backup describe <name>` |
| Describe with details | `velero backup describe <name> --details` |
| Backup logs | `velero backup logs <name>` |
| List backups | `velero backup get` |
| Delete backup | `velero backup delete <name>` |
| Download backup | `velero backup download <name>` |

### Restore Operations

| Action | Command |
|--------|---------|
| Restore from backup | `velero restore create <name> --from-backup <backup>` |
| Restore specific namespace | `velero restore create <name> --from-backup <backup> --include-namespaces=<ns>` |
| Namespace mapping | `velero restore create <name> --from-backup <backup> --namespace-mappings old:new` |
| Restore with volumes | `velero restore create <name> --from-backup <backup> --restore-volumes=true` |
| Describe restore | `velero restore describe <name>` |
| Restore logs | `velero restore logs <name>` |
| List restores | `velero restore get` |

### Schedule Operations

| Action | Command |
|--------|---------|
| Create schedule | `velero schedule create <name> --schedule="0 2 * * *" --include-namespaces=<ns>` |
| Create with TTL | `velero schedule create <name> --schedule="@daily" --ttl=720h` |
| Create with volumes | `velero schedule create <name> --schedule="@daily" --default-volumes-to-restic` |
| List schedules | `velero schedule get` |
| Describe schedule | `velero schedule describe <name>` |
| Delete schedule | `velero schedule delete <name>` |
| Suspend schedule | `velero schedule create <name> --schedule="@daily" --paused=true` |
| Trigger manually | `velero backup create <manual> --from-schedule <schedule>` |

### Storage & Plugin Operations

| Action | Command |
|--------|---------|
| Get backup location | `velero backup-location get` |
| Set default location | `velero backup-location set default --name=<name>` |
| Get snapshot location | `velero snapshot-location get` |
| Create snapshot location | `velero snapshot-location create <name> --provider aws --config region=us-east-1` |
| List plugins | `velero plugin get` |
| Add plugin | `velero plugin add velero/velero-plugin-for-aws:v1.8.0` |
| Get version | `velero version` |
| Get client version | `velero version --client-only` |

### Velero Troubleshooting

| Action | Command |
|--------|---------|
| Check pod logs | `kubectl logs -n velero deploy/velero` |
| Check restic logs | `kubectl logs -n velero <pod> -c restic` |
| Check backup status | `velero backup get --show-labels` |
| Check BSL status | `velero backup-location get` |
| Test S3 access | `aws s3 ls s3://bucket --endpoint-url=https://s3.internal` |
| Check node agent | `kubectl get pods -n velero -l name=node-agent` |

---

## Quick Port Forwarding

```bash
# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Alertmanager
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

# Loki
kubectl port-forward -n monitoring svc/loki 3100:3100

# Velero (no service, use pod directly)
kubectl port-forward -n velero deploy/velero 8080:8080
```
