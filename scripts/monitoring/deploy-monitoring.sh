#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# deploy-monitoring.sh — Deploy kube-prometheus-stack via Helm
# ============================================================================
# Usage: ./deploy-monitoring.sh [OPTIONS]
#
# Options:
#   --cluster-type    Cluster type: mgmt|app (default: mgmt)
#   --storage-class   Storage class for PVCs (default: cephfs)
#   --retention       Prometheus retention period (default: 30d for mgmt, 15d for app)
#   --namespace       Namespace (default: monitoring)
#   --dry-run         Print values without deploying
#
# Examples:
#   ./deploy-monitoring.sh --cluster-type mgmt --storage-class cephfs --retention 30d
#   ./deploy-monitoring.sh --cluster-type app --retention 15d
# ============================================================================

# --- Defaults ---
CLUSTER_TYPE="mgmt"
STORAGE_CLASS="cephfs"
RETENTION=""
NAMESPACE="monitoring"
DRY_RUN=false
HARBOR="harbor.internal.example.com/platform"
NEXUS_REPO="https://nexus.internal.example.com/repository/helm-remote"
CHART_VERSION="58.2.2"
PROMETHEUS_VERSION="v2.52.0"
GRAFANA_VERSION="11.1.0"
ALERTMANAGER_VERSION="v0.27.0"

# --- Parse Args ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --cluster-type)  CLUSTER_TYPE="$2"; shift 2 ;;
    --storage-class) STORAGE_CLASS="$2"; shift 2 ;;
    --retention)     RETENTION="$2"; shift 2 ;;
    --namespace)     NAMESPACE="$2"; shift 2 ;;
    --dry-run)       DRY_RUN=true; shift ;;
    -h|--help)
      head -20 "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Set retention based on cluster type if not specified
if [[ -z "$RETENTION" ]]; then
  if [[ "$CLUSTER_TYPE" == "mgmt" ]]; then
    RETENTION="30d"
  else
    RETENTION="15d"
  fi
fi

echo "============================================"
echo "Deploying kube-prometheus-stack"
echo "  Cluster type:  ${CLUSTER_TYPE}"
echo "  Storage class: ${STORAGE_CLASS}"
echo "  Retention:     ${RETENTION}"
echo "  Namespace:     ${NAMESPACE}"
echo "  Harbor:        ${HARBOR}"
echo "============================================"

# --- Generate Values File ---
VALUES_FILE="/tmp/monitoring-values-${CLUSTER_TYPE}.yaml"

if [[ "$CLUSTER_TYPE" == "mgmt" ]]; then
  cat > "$VALUES_FILE" <<EOF
namespaceOverride: ${NAMESPACE}

prometheus:
  prometheusSpec:
    retention: ${RETENTION}
    retentionSize: 90GB
    enableRemoteWriteReceiver: true
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: ${STORAGE_CLASS}
          accessModes: ["ReadWriteOnce"]
          resources:
            requests: { storage: 100Gi }
    resources:
      requests: { cpu: 500m, memory: 2Gi }
      limits:   { cpu: "2", memory: 4Gi }
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts: [prometheus.example.com]

alertmanager:
  alertmanagerSpec:
    retention: 120h
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: ${STORAGE_CLASS}
          resources:
            requests: { storage: 10Gi }
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts: [alertmanager.example.com]

grafana:
  adminPassword: "\${GRAFANA_ADMIN_PASSWORD}"
  persistence:
    enabled: true
    storageClassName: ${STORAGE_CLASS}
    size: 10Gi
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts: [grafana.example.com]
  resources:
    requests: { cpu: 100m, memory: 128Mi }
    limits:   { cpu: 500m, memory: 512Mi }
EOF
else
  # Application cluster — remote writes to mgmt
  cat > "$VALUES_FILE" <<EOF
namespaceOverride: ${NAMESPACE}

prometheus:
  prometheusSpec:
    retention: ${RETENTION}
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: ${STORAGE_CLASS}
          resources:
            requests: { storage: 50Gi }
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
  enabled: false

grafana:
  enabled: false
EOF
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "--- Values file (${VALUES_FILE}) ---"
  cat "$VALUES_FILE"
  exit 0
fi

# --- Add Helm Repo ---
echo "Adding Helm repository..."
helm repo add prometheus-community "${NEXUS_REPO}" --force-update 2>/dev/null || true
helm repo update

# --- Deploy ---
echo "Deploying kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  -f "${VALUES_FILE}" \
  --timeout 10m

# --- Deploy Essential Dashboard ConfigMaps ---
echo "Deploying essential dashboards..."
DASHBOARDS_DIR="$(dirname "$0")/dashboards"
if [[ -d "$DASHBOARDS_DIR" ]]; then
  for dash in "${DASHBOARDS_DIR}"/*.json; do
    name=$(basename "$dash" .json)
    kubectl create configmap "dashboard-${name}" \
      --from-file="${name}.json=${dash}" \
      --namespace "${NAMESPACE}" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "  Imported dashboard: ${name}"
  done
fi

# --- Verify ---
echo "Verifying deployment..."
kubectl rollout status deployment/kube-prometheus-stack-grafana -n "${NAMESPACE}" --timeout=5m
kubectl rollout status statefulset/prometheus-kube-prometheus-stack-prometheus -n "${NAMESPACE}" --timeout=5m

if [[ "$CLUSTER_TYPE" == "mgmt" ]]; then
  kubectl rollout status statefulset/alertmanager-kube-prometheus-stack-alertmanager -n "${NAMESPACE}" --timeout=5m
fi

echo ""
echo "✅ Monitoring stack deployed successfully!"
echo ""
echo "Access endpoints:"
if [[ "$CLUSTER_TYPE" == "mgmt" ]]; then
  echo "  Grafana:      https://grafana.example.com"
  echo "  Prometheus:   https://prometheus.example.com"
  echo "  Alertmanager: https://alertmanager.example.com"
else
  echo "  Remote write: https://prometheus-mgmt.example.com/api/v1/write"
  echo "  (Grafana on mgmt cluster: https://grafana.example.com)"
fi
echo ""
echo "Next steps:"
echo "  1. Configure Alertmanager receivers"
echo "  2. Import application-specific dashboards"
echo "  3. Set up remote write (app cluster only)"
