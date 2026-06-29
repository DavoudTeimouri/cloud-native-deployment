#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# deploy-logging.sh — Deploy Loki + Promtail via Helm
# ============================================================================
# Usage: ./deploy-logging.sh [OPTIONS]
#
# Options:
#   --cluster-type    Cluster type: mgmt|app (default: mgmt)
#   --storage-class   Storage class for PVCs (default: cephfs)
#   --retention       Loki retention period in hours (default: 744 = 31 days)
#   --namespace       Namespace (default: monitoring)
#   --loki-size       PVC size for Loki (default: 50Gi)
#   --dry-run         Print values without deploying
#
# Examples:
#   ./deploy-logging.sh --cluster-type mgmt --storage-class cephfs
#   ./deploy-logging.sh --cluster-type app --retention 360
# ============================================================================

# --- Defaults ---
CLUSTER_TYPE="mgmt"
STORAGE_CLASS="cephfs"
RETENTION_HOURS=744
NAMESPACE="monitoring"
LOKI_SIZE="50Gi"
DRY_RUN=false
HARBOR="harbor.internal.example.com/platform"
NEXUS_REPO="https://nexus.internal.example.com/repository/helm-remote"
LOKI_VERSION="5.43.4"
PROMTAIL_VERSION="6.15.0"
LOKI_IMAGE_TAG="3.0.0"

# --- Parse Args ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --cluster-type)  CLUSTER_TYPE="$2"; shift 2 ;;
    --storage-class) STORAGE_CLASS="$2"; shift 2 ;;
    --retention)     RETENTION_HOURS="$2"; shift 2 ;;
    --namespace)     NAMESPACE="$2"; shift 2 ;;
    --loki-size)     LOKI_SIZE="$2"; shift 2 ;;
    --dry-run)       DRY_RUN=true; shift ;;
    -h|--help)
      head -20 "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

RETENTION_HOURS_STR="${RETENTION_HOURS}h"

echo "============================================"
echo "Deploying Loki + Promtail"
echo "  Cluster type:  ${CLUSTER_TYPE}"
echo "  Storage class: ${STORAGE_CLASS}"
echo "  Retention:     ${RETENTION_HOURS_STR}"
echo "  Loki PVC size: ${LOKI_SIZE}"
echo "  Namespace:     ${NAMESPACE}"
echo "  Harbor:        ${HARBOR}"
echo "============================================"

# --- Generate Loki Values ---
LOKI_VALUES="/tmp/loki-values-${CLUSTER_TYPE}.yaml"

if [[ "$CLUSTER_TYPE" == "mgmt" ]]; then
  cat > "$LOKI_VALUES" <<EOF
loki:
  image:
    repository: ${HARBOR}/loki
    tag: ${LOKI_IMAGE_TAG}
  deploymentMode: SimpleScalable
  simpleScalable:
    replicas: 3
  auth_enabled: false
  persistence:
    enabled: true
    size: ${LOKI_SIZE}
    storageClassName: ${STORAGE_CLASS}
    accessModes: ["ReadWriteOnce"]
  limits_config:
    retention_period: ${RETENTION_HOURS_STR}
    max_query_length: 721h
    reject_old_samples: true
    reject_old_samples_max_age: 168h
    ingestion_rate_mb: 20
    ingestion_burst_rate_mb: 30
  compactor:
    enabled: true
    working_directory: /loki/compactor
    compaction_interval: 10m
    retention_enabled: true
    retention_delete_delay: 2h
  ingester:
    chunk_idle_period: 5m
    wal:
      enabled: true
      dir: /loki/wal
  ruler:
    enabled: true
    storage:
      type: local
      local:
        directory: /loki/rules
    alertmanager_url: http://alertmanager.${NAMESPACE}.svc.cluster.local:9093
  table_manager:
    retention_deletes_enabled: true
    retention_period: ${RETENTION_HOURS_STR}
  resources:
    requests: { cpu: 500m, memory: 1Gi }
    limits:   { cpu: "2", memory: 4Gi }
monitoring:
  serviceMonitor:
    enabled: true
    labels: { release: kube-prometheus-stack }
  selfMonitoring:
    enabled: true
EOF
else
  # App cluster — smaller, single binary
  cat > "$LOKI_VALUES" <<EOF
loki:
  image:
    repository: ${HARBOR}/loki
    tag: ${LOKI_IMAGE_TAG}
  deploymentMode: SingleBinary
  singleBinary:
    replicas: 1
  persistence:
    enabled: true
    size: 20Gi
    storageClassName: ${STORAGE_CLASS}
  limits_config:
    retention_period: ${RETENTION_HOURS_STR}
  compactor:
    enabled: true
    retention_enabled: true
  resources:
    requests: { cpu: 200m, memory: 512Mi }
    limits:   { cpu: "1", memory: 1Gi }
monitoring:
  serviceMonitor:
    enabled: true
    labels: { release: kube-prometheus-stack }
EOF
fi

# --- Generate Promtail Values ---
PROMTAIL_VALUES="/tmp/promtail-values-${CLUSTER_TYPE}.yaml"

LOKI_URL="http://loki.${NAMESPACE}.svc.cluster.local:3100"
if [[ "$CLUSTER_TYPE" == "app" ]]; then
  # App cluster: push to mgmt cluster Loki
  LOKI_URL="https://loki-mgmt.example.com"
fi

cat > "$PROMTAIL_VALUES" <<EOF
config:
  clients:
  - url: ${LOKI_URL}/loki/api/v1/push
    external_labels:
      cluster: ${CLUSTER_TYPE}-cluster
  snippets:
    pipelineStages:
    - cri: {}

daemonset:
  image:
    repository: ${HARBOR}/promtail
    tag: ${LOKI_IMAGE_TAG}
  resources:
    requests: { cpu: 100m, memory: 128Mi }
    limits:   { cpu: 500m, memory: 256Mi }

serviceMonitor:
  enabled: true
  labels: { release: kube-prometheus-stack }
EOF

if [[ "$DRY_RUN" == true ]]; then
  echo "--- Loki Values ---"
  cat "$LOKI_VALUES"
  echo ""
  echo "--- Promtail Values ---"
  cat "$PROMTAIL_VALUES"
  exit 0
fi

# --- Add Helm Repo ---
echo "Adding Helm repository..."
helm repo add grafana "${NEXUS_REPO}" --force-update 2>/dev/null || true
helm repo update

# --- Deploy Loki ---
echo "Deploying Loki..."
helm upgrade --install loki grafana/loki \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  -f "${LOKI_VALUES}" \
  --timeout 10m

# --- Deploy Promtail ---
echo "Deploying Promtail..."
helm upgrade --install promtail grafana/promtail \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  -f "${PROMTAIL_VALUES}" \
  --timeout 5m

# --- Verify ---
echo "Verifying deployment..."

if [[ "$CLUSTER_TYPE" == "mgmt" ]]; then
  kubectl rollout status statefulset/loki -n "${NAMESPACE}" --timeout=5m 2>/dev/null || \
    kubectl rollout status deployment/loki -n "${NAMESPACE}" --timeout=5m
else
  kubectl rollout status statefulset/loki -n "${NAMESPACE}" --timeout=5m 2>/dev/null || \
    kubectl rollout status deployment/loki -n "${NAMESPACE}" --timeout=5m
fi

kubectl rollout status daemonset/promtail -n "${NAMESPACE}" --timeout=5m

# --- Quick Health Check ---
echo "Checking Loki health..."
LOKI_HEALTH=$(kubectl exec -n "${NAMESPACE}" statefulset/loki -- curl -s http://localhost:3100/ready 2>/dev/null || \
              kubectl exec -n "${NAMESPACE}" deployment/loki -- curl -s http://localhost:3100/ready 2>/dev/null || echo "unreachable")
echo "  Loki /ready: ${LOKI_HEALTH}"

echo ""
echo "✅ Logging stack deployed successfully!"
echo ""
echo "Endpoints:"
echo "  Loki:    http://loki.${NAMESPACE}.svc.cluster.local:3100"
echo "  Promtail: DaemonSet on all nodes"
echo ""
echo "Next steps:"
echo "  1. Add Loki datasource in Grafana"
echo "  2. Configure log-based alert rules (Loki ruler)"
echo "  3. Verify log flow: kubectl logs -n ${NAMESPACE} -l app=promtail"
