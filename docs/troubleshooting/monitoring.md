# Monitoring & Backup Troubleshooting Guide

> Covers: Prometheus, Grafana, Loki, Velero, Alertmanager

---

## 1. Prometheus Issues

### 1.1 Targets Down

**Symptom:** Prometheus UI shows targets as `DOWN` or `Unknown`

**Possible Causes:**
- Service not running on target pod
- Network policy blocking metrics port
- Incorrect scrape config / relabeling
- Certificate issues (mTLS)
- Firewall blocking port

**Diagnostic Commands:**
```bash
# Check Prometheus targets in UI
# Navigate to: Status → Targets

# Check Prometheus logs
kubectl logs -n monitoring -l app=prometheus --tail=100
# or for Prometheus Operator:
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=100

# Test metrics endpoint directly
kubectl port-forward -n <namespace> svc/<service> 8080:8080
curl http://localhost:8080/metrics

# Check ServiceMonitor / PodMonitor
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor <sm> -n monitoring

# Check if service endpoints exist
kubectl get endpoints -n <namespace> <service>

# Test from Prometheus pod
kubectl exec -it -n monitoring <prometheus-pod> -- \
  wget -qO- http://<service>.<namespace>.svc:port/metrics | head -20
```

**Resolution:**
```bash
# Fix ServiceMonitor selector to match service labels
kubectl edit servicemonitor <sm> -n monitoring
# Ensure spec.selector.matchLabels matches service metadata.labels

# Check for network policy blocking
kubectl get networkpolicies -n monitoring
kubectl get networkpolicies -n <target-namespace>

# Add allow rule for Prometheus scrape
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus
  namespace: <target-namespace>
spec:
  podSelector:
    matchLabels:
      app: <app>
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - port: 8080
      protocol: TCP
EOF

# Fix scrape interval/timeout
kubectl edit prometheus -n monitoring  # for Prometheus Operator
# spec:
#   scrapeInterval: 30s
#   scrapeTimeout: 10s
```

---

### 1.2 Prometheus OOM

**Symptom:** Prometheus pod restarting, OOMKilled events

**Diagnostic Commands:**
```bash
# Check current memory usage
kubectl top pod -n monitoring -l app=prometheus

# Check memory limits
kubectl get pod -n monitoring <prometheus-pod> -o jsonpath='{.spec.containers[0].resources}'

# Check OOM events
kubectl get events -n monitoring --field-selector reason=OOMKilling

# Check time series count (cardinality)
curl -s http://localhost:9090/api/v1/status/tsdb | jq '.data.numSeries'
curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data | length'  # metric count
```

**Resolution:**
```bash
# Increase memory limits
kubectl patch prometheus -n monitoring k8s --type='merge' -p '{"spec":{"resources":{"limits":{"memory":"8Gi"}}}}'

# Or direct patch
kubectl set resources statefulset prometheus -n monitoring \
  --limits=memory=8Gi

# Reduce retention if storage-bound
# --storage.tsdb.retention.time=15d
# --storage.tsdb.retention.size=50GB

# Check for high cardinality metrics (see 1.4)
# Drop high-cardinality metrics in relabel_configs
```

---

### 1.3 Remote Write Failiness

**Symptom:** Remote write failing, data not reaching external storage

**Diagnostic Commands:**
```bash
# Check remote write config
kubectl get secret -n monitoring prometheus-prometheus -o jsonpath='{.data.prometheus\.yaml}' | base64 -d | grep -A 20 remote_write

# Check Prometheus logs for write errors
kubectl logs -n monitoring <prometheus-pod> --tail=100 | grep -i "remote\|write\|error"

# Check remote write endpoint
curl -I https://remote-write-endpoint/api/v1/write
```

**Resolution:**
```bash
# Fix remote write URL or credentials
kubectl edit prometheus k8s -n monitoring
# spec:
#   remoteWrite:
#   - url: https://receiver.example.com/api/v1/write
#     queueConfig:
#       maxSamplesPerSend: 1000
#       capacity: 5000
#       maxShards: 30

# Check for TLS issues
# Add tls_config if needed
# insecureSkipVerify: true  # NOT for production
```

---

### 1.4 High Cardinality Issues

**Symptom:** Prometheus slow, high memory usage, queries timing out

**Diagnostic Commands:**
```bash
# Find high-cardinality metrics
curl -s http://localhost:9090/api/v1/status/tsdb | jq '.data'

# Find metrics with most series
curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data[]' | while read metric; do
  count=$(curl -s "http://localhost:9090/api/v1/series?match[]=$metric" | jq '.data | length')
  echo "$count $metric"
done | sort -rn | head -20
```

**Resolution:**
```bash
# Drop high-cardinality metrics in scrape config
# In ServiceMonitor or prometheus.yml:
# relabel_configs:
# - source_labels: [__name__]
#   regex: 'high_cardinality_metric.*'
#   action: drop

# Use metric_relabel_configs to drop labels
# - source_labels: [__name__]
#   regex: 'http_requests_total'
#   target_label: instance
#   replacement: ''
#   action: labeldrop
```

---

## 2. Grafana Issues

### 2.1 Dashboard Loading Issues

**Symptom:** Dashboards stuck loading or showing errors

**Diagnostic Commands:**
```bash
# Check Grafana pod
kubectl get pods -n monitoring -l app=grafana
kubectl logs -n monitoring -l app=grafana --tail=100

# Check datasource connectivity
# Navigate to: Configuration → DataSources → Test

# Check Grafana config
kubectl get configmap -n monitoring grafana-datasources -o yaml

# Check provisioned dashboards
kubectl get configmap -n monitoring -l grafana_dashboard=1
```

**Resolution:**
```bash
# Restart Grafana
kubectl rollout restart deployment grafana -n monitoring

# Fix datasource URL
kubectl edit configmap grafana-datasources -n monitoring
# Ensure URL points to Prometheus service:
# url: http://prometheus-operated.monitoring.svc:9090

# Clear Grafana cache (if using SQLite)
kubectl exec -it -n monitoring <grafana-pod> -- \
  grafana-cli admin reset-admin-password <password>
```

---

### 2.2 Datasource Errors

**Symptom:** `Datasource named "Prometheus" not found` or connection errors

**Resolution:**
```bash
# Recreate datasource
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-operated.monitoring.svc:9090
      access: proxy
      isDefault: true
EOF

# Restart Grafana to pick up changes
kubectl rollout restart deployment grafana -n monitoring
```

---

## 3. Loki Issues

### 3.1 Ingestion Errors

**Symptom:** Logs not appearing in Grafana/Loki

**Possible Causes:**
- Promtail not shipping logs
- Loki distributor down
- Label cardinality too high
- Storage full

**Diagnostic Commands:**
```bash
# Check Loki pods
kubectl get pods -n monitoring -l app=loki
kubectl logs -n monitoring -l app=loki --tail=100

# Check Promtail
kubectl get pods -n monitoring -l app=promtail
kubectl logs -n monitoring -l app=promtail --tail=100

# Check Loki metrics
curl -s http://loki.monitoring.svc:3100/metrics | grep -i "error\|rate"

# Test log push
curl -X POST http://loki.monitoring.svc:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s%N)'","test log"]]}]}'

# Check storage
kubectl exec -it -n monitoring <loki-pod> -- df -h /data
```

**Resolution:**
```bash
# Restart Promtail
kubectl rollout restart daemonset promtail -n monitoring

# Check Promtail config for correct Loki URL
kubectl get configmap -n monitoring promtail -o yaml | grep -A 5 clients

# Fix storage limits
kubectl edit loki -n monitoring  # if using Loki Operator
# spec:
#   storage:
#     object:
#       endpoint: s3://bucket
#   limits:
#     retention_period: 720h

# Check for label limit exceeded
kubectl logs -n monitoring -l app=loki | grep "max_label_per_series"
# Reduce labels in Promtail pipeline
```

---

### 3.2 Query Timeouts

**Symptom:** Grafana shows `context deadline exceeded` for log queries

**Diagnostic Commands:**
```bash
# Check Loki query performance
curl -s "http://loki.monitoring.svc:3100/loki/api/v1/query_range?query={job=\"nginx\"}&limit=10&direction=backward"

# Check Loki resource usage
kubectl top pods -n monitoring -l app=loki

# Check ingester memory
curl -s http://loki.monitoring.svc:3100/metrics | grep ingester_memory
```

**Resolution:**
```bash
# Increase query limits
# In Loki config:
# limits_config:
#   max_entries_limit_per_query: 5000
#   max_query_length: 721h
#   query_timeout: 30s

# Increase Loki resources
kubectl set resources statefulset loki -n monitoring \
  --limits=memory=4Gi,cpu=2

# Use more specific label selectors in queries
# Instead of: {job="nginx"}
# Use: {job="nginx", namespace="production", pod="nginx-xxx"}
```

---

### 3.3 Compaction Failies

**Symptom:** Storage growing unbounded, old data not cleaned up

**Diagnostic Commands:**
```bash
# Check compaction status
curl -s http://loki.monitoring.svc:3100/metrics | grep compactor

# Check retention settings
kubectl get configmap -n monitoring loki -o yaml | grep -A 10 retention

# Check storage usage
kubectl exec -it -n monitoring <loki-pod> -- du -sh /data/*
```

**Resolution:**
```bash
# Enable/configure compaction
# In Loki config:
# compactor:
#   working_directory: /data/compactor
#   shared_store: s3
#   compaction_interval: 10m
# retention_enabled: true
# retention_delete_delay: 2h

# Force retention run
curl -X POST http://loki.monitoring.svc:3100/loki/api/v1/delete \
  -H "Content-Type: application/json" \
  -d '{"query":"{job=\"test\"}", "start": 0, "end": '$(date -d '7 days ago' +%s)'000000000}'
```

---

## 4. Velero Issues

### 4.1 Backup Failures

**Symptom:** Backup shows `PartiallyFailed` or `Failed` status

**Possible Causes:**
- S3 connectivity issues
- Insufficient permissions
- Volume snapshot provider issues
- Resource timeout
- Namespace exclusion

**Diagnostic Commands:**
```bash
# Check backup status
velero backup get
velero backup describe <backup-name> --details

# Check backup logs
velero backup logs <backup-name>

# Check Velero pod logs
kubectl logs -n velero deployment/velero --tail=100

# Check backup storage location
velero backup-location get
velero backup-location describe default

# Check volume snapshots
velero snapshot get
```

**Resolution:**
```bash
# Fix S3 credentials
kubectl create secret generic cloud-credentials -n velero \
  --from-file=cloud=/path/to/credentials \
  --dry-run=client -o yaml | kubectl apply -f -

# Check S3 bucket access
aws s3 ls s3://velero-backups/ --endpoint-url=https://s3.internal

# Fix backup storage location
kubectl patch backupstoragelocation default -n velero --type='merge' \
  -p '{"spec":{"config":{"s3ForcePathStyle":"true"}}}'

# Retry backup
velero backup create <new-backup> --from-backup <failed-backup>

# Check for resource-specific errors
velero backup logs <backup-name> | grep -i "error\|fail\|timeout"

# Increase default item operation timeout
velero backup create <backup> --default-volumes-to-restic --item-operation-timeout 4h
```

---

### 4.2 Restore Errors

**Symptom:** Restore shows `PartiallyFailed` or resources not restored

**Diagnostic Commands:**
```bash
# Check restore status
velero restore get
velero restore describe <restore-name> --details
velero restore logs <restore-name>

# Check for namespace mapping issues
velero restore describe <restore-name> | grep -i "namespace\|error"
```

**Resolution:**
```bash
# Restore with namespace mapping
velero restore create <restore> --from-backup <backup> \
  --namespace-mappings old-ns:new-ns

# Restore specific resources only
velero restore create <restore> --from-backup <backup> \
  --include-resources deployments,services,configmaps

# Restore to different cluster
# Ensure Velero is configured with same BSL
velero restore create <restore> --from-backup <backup>

# Fix PVC restore issues
velero restore create <restore> --from-backup <backup> \
  --restore-volumes=true
```

---

### 4.3 S3 Connectivity Issues

**Symptom:** `Access Denied`, `NoSuchBucket`, or timeout errors

**Diagnostic Commands:**
```bash
# Test S3 access from Velero pod
kubectl exec -it -n velero deploy/velero -- \
  aws s3 ls s3://velero-backups/ --endpoint-url=https://s3.internal

# Check credentials
kubectl exec -it -n velero deploy/velero -- cat /credentials/cloud

# Check BSL config
kubectl get backupstoragelocation default -n velero -o yaml
```

**Resolution:**
```bash
# Update credentials
kubectl create secret generic cloud-credentials -n velero \
  --from-literal=cloud="[default]
aws_access_key_id=AKIAIOSFODNN7EXAMPLE
aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# Fix BSL for MinIO or non-AWS S3
kubectl edit backupstoragelocation default -n velero
# spec:
#   provider: aws
#   objectStorage:
#     bucket: velero-backups
#     prefix: cluster1
#   config:
#     region: us-east-1
#     s3Url: https://minio.internal:9000
#     s3ForcePathStyle: "true"
```

---

## 5. Alertmanager Issues

### 5.1 Alerts Not Firing

**Symptom:** Expected alerts not appearing in Alertmanager

**Possible Causes:**
- Alert rule not matching
- Prometheus not evaluating rule
- Alertmanager not receiving alerts
- Silences blocking alerts
- Inhibition rules suppressing

**Diagnostic Commands:**
```bash
# Check Prometheus rules
kubectl get prometheusrules -n monitoring
kubectl describe prometheusrule <rule> -n monitoring

# Check if alert is firing in Prometheus
# Navigate to: Alerts tab in Prometheus UI

# Check Alertmanager targets
curl -s http://alertmanager.monitoring.svc:9093/api/v2/alerts
curl -s http://alertmanager.monitoring.svc:9093/api/v2/silences

# Check Alertmanager logs
kubectl logs -n monitoring -l app=alertmanager --tail=100

# Check Alertmanager config
kubectl get secret -n monitoring alertmanager-alertmanager -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
```

**Resolution:**
```bash
# Verify alert expression in Prometheus UI
# Run the PromQL query manually to check if it returns data

# Check for silences
amtool --alertmanager.url=http://alertmanager.monitoring.svc:9093 silence query

# Check inhibition rules
# In alertmanager.yml:
# inhibit_rules:
# - source_match:
#     severity: 'critical'
#   target_match:
#     severity: 'warning'
#   equal: ['alertname']

# Reload Alertmanager config
curl -X POST http://alertmanager.monitoring.svc:9093/-/reload

# Test alert routing
amtool --alertmanager.url=http://alertmanager.monitoring.svc:9093 config check /tmp/alertmanager.yml
```

---

### 5.2 Alert Routing Issues

**Symptom:** Alerts going to wrong receiver or not being grouped

**Diagnostic Commands:**
```bash
# Check routing tree
amtool --alertmanager.url=http://alertmanager.monitoring.svc:9093 config routes show

# Test routing
amtool --alertmanager.url=http://alertmanager.monitoring.svc:9093 config routes test severity=critical
```

**Resolution:**
```bash
# Fix routing config
kubectl edit secret alertmanager-alertmanager -n monitoring
# Or for Prometheus Operator:
kubectl edit alertmanager -n monitoring
# spec:
#   alertmanagerConfiguration:
#     name: alertmanager-config
#     key: alertmanager.yaml

# Reload
curl -X POST http://alertmanager.monitoring.svc:9093/-/reload
```

---

### 5.3 Silence Not Working

**Symptom:** Silenced alerts still being sent

**Diagnostic Commands:**
```bash
# List active silences
amtool --alertmanager.url=http://alertmanager.monitoring.svc:9093 silence query

# Check silence details
amtool --alertmanager.url=http://alertmanager.monitoring.svc:9093 silence query --id=<silence-id>
```

**Resolution:**
```bash
# Create silence with correct matchers
amtool --alertmanager.url=http://alertmanager.monitoring.svc:9093 silence add \
  alertname=HighMemoryUsage \
  namespace=production \
  --comment="Planned maintenance" \
  --duration=2h

# Verify silence matches alert
amtool --alertmanager.url=http://alertmanager.monitoring.svc:9093 silence query alertname=HighMemoryUsage

# Expire incorrect silence
amtool --alertmanager.url=http://alertmanager.monitoring.svc:9093 silence expire <silence-id>
```
