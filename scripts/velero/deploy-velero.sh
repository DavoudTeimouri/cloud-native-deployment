#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# deploy-velero.sh — Deploy Velero + Velero UI with S3 backend
# ============================================================================
# Usage: ./deploy-velero.sh [OPTIONS]
#
# Options:
#   --s3-endpoint      S3 endpoint URL (required)
#   --s3-bucket        S3 bucket name (default: velero-backup)
#   --s3-access-key    S3 access key (required)
#   --s3-secret-key    S3 secret key (required)
#   --s3-region        S3 region (default: default)
#   --cluster-name     Cluster name for backup prefix (default: current-context)
#   --schedule-daily   Daily backup schedule cron (default: "0 2 * * *")
#   --schedule-weekly  Weekly backup schedule cron (default: "0 1 * * 0")
#   --namespace        Namespace (default: velero)
#   --enable-csi       Enable CSI snapshot plugin (default: false)
#   --enable-ui        Deploy Velero UI (default: true)
#   --dry-run          Print values without deploying
#
# Examples:
#   ./deploy-velero.sh \
#     --s3-endpoint https://s3.internal.example.com \
#     --s3-bucket velero-backup \
#     --s3-access-key ABCD \
#     --s3-secret-key EFGH
#
#   ./deploy-velero.sh \
#     --s3-endpoint https://minio.internal.example.com \
#     --s3-bucket velero-backup \
#     --s3-access-key minioadmin \
#     --s3-secret-key minioadmin \
#     --enable-csi
# ============================================================================

# --- Defaults ---
S3_ENDPOINT=""
S3_BUCKET="velero-backup"
S3_ACCESS_KEY=""
S3_SECRET_KEY=""
S3_REGION="default"
CLUSTER_NAME=""
SCHEDULE_DAILY="0 2 * * *"
SCHEDULE_WEEKLY="0 1 * * 0"
NAMESPACE="velero"
ENABLE_CSI=false
ENABLE_UI=true
DRY_RUN=false
HARBOR="harbor.internal.example.com/platform"
NEXUS_REPO="https://nexus.internal.example.com/repository/helm-remote"
VELERO_VERSION="v1.11.0"
VELERO_CHART_VERSION="6.0.0"

# --- Parse Args ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --s3-endpoint)     S3_ENDPOINT="$2"; shift 2 ;;
    --s3-bucket)       S3_BUCKET="$2"; shift 2 ;;
    --s3-access-key)   S3_ACCESS_KEY="$2"; shift 2 ;;
    --s3-secret-key)   S3_SECRET_KEY="$2"; shift 2 ;;
    --s3-region)       S3_REGION="$2"; shift 2 ;;
    --cluster-name)    CLUSTER_NAME="$2"; shift 2 ;;
    --schedule-daily)  SCHEDULE_DAILY="$2"; shift 2 ;;
    --schedule-weekly) SCHEDULE_WEEKLY="$2"; shift 2 ;;
    --namespace)       NAMESPACE="$2"; shift 2 ;;
    --enable-csi)      ENABLE_CSI=true; shift ;;
    --enable-ui)       ENABLE_UI=true; shift ;;
    --no-ui)           ENABLE_UI=false; shift ;;
    --dry-run)         DRY_RUN=true; shift ;;
    -h|--help)
      head -25 "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Validate required args ---
if [[ -z "$S3_ENDPOINT" || -z "$S3_ACCESS_KEY" || -z "$S3_SECRET_KEY" ]]; then
  echo "ERROR: --s3-endpoint, --s3-access-key, and --s3-secret-key are required"
  exit 1
fi

# Auto-detect cluster name
if [[ -z "$CLUSTER_NAME" ]]; then
  CLUSTER_NAME=$(kubectl config current-context | sed 's/_/-/g')
fi

echo "============================================"
echo "Deploying Velero"
echo "  Cluster:      ${CLUSTER_NAME}"
echo "  S3 endpoint:  ${S3_ENDPOINT}"
echo "  S3 bucket:    ${S3_BUCKET}"
echo "  S3 region:    ${S3_REGION}"
echo "  Daily:        ${SCHEDULE_DAILY}"
echo "  Weekly:       ${SCHEDULE_WEEKLY}"
echo "  CSI:          ${ENABLE_CSI}"
echo "  UI:           ${ENABLE_UI}"
echo "  Namespace:    ${NAMESPACE}"
echo "============================================"

# --- Generate Values File ---
VALUES_FILE="/tmp/velero-values-${CLUSTER_NAME}.yaml"

# Build plugins list
PLUGINS=""
PLUGINS+="- name: aws\n  from: ${HARBOR}/velero-plugin-for-aws:v1.8.0\n"
if [[ "$ENABLE_CSI" == true ]]; then
  PLUGINS+="- name: csi\n  from: ${HARBOR}/velero-plugin-for-csi:v0.6.0\n"
fi

cat > "$VALUES_FILE" <<EOF
image:
  repository: ${HARBOR}/velero
  tag: ${VELERO_VERSION}

restic:
  install: true
  image: ${HARBOR}/velero-restic-restore-helper:${VELERO_VERSION}

backupStorageLocation:
- name: default
  provider: aws
  default: true
  config:
    region: ${S3_REGION}
    s3_url: ${S3_ENDPOINT}
    s3_force_path_style: true
  objectStorage:
    bucket: ${S3_BUCKET}
    prefix: ${CLUSTER_NAME}/velero
  credential:
    name: velero-s3-credentials
    key: cloud

volumeSnapshotLocation:
- name: default
  config:
    region: ${S3_REGION}

schedules:
  daily-cluster-backup:
    schedule: "${SCHEDULE_DAILY}"
    template:
      ttl: 720h
      storageLocation: default
      includedNamespaces:
      - kube-system
      - cert-manager
      - gatekeeper-system
      - cattle-system
      - argocd
      - monitoring
      - logging
      - ingress-nginx
  weekly-full-backup:
    schedule: "${SCHEDULE_WEEKLY}"
    template:
      ttl: 2160h
      storageLocation: default
      defaultVolumesToFsBackup: true

resources:
  requests: { cpu: 500m, memory: 512Mi }
  limits:   { cpu: "2", memory: 2Gi }

serviceMonitor:
  enabled: true
  labels: { release: kube-prometheus-stack }
EOF

if [[ "$DRY_RUN" == true ]]; then
  echo "--- Values file ---"
  cat "$VALUES_FILE"
  exit 0
fi

# --- Create Namespace ---
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# --- Create S3 Credentials Secret ---
echo "Creating S3 credentials secret..."
S3_CREDS_FILE="/tmp/velero-s3-credentials.ini"
cat > "$S3_CREDS_FILE" <<EOF
[default]
aws_access_key_id=${S3_ACCESS_KEY}
aws_secret_access_key=${S3_SECRET_KEY}
EOF

kubectl create secret generic velero-s3-credentials \
  --from-file=cloud="${S3_CREDS_FILE}" \
  --namespace "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

rm -f "$S3_CREDS_FILE"

# --- Add Helm Repo ---
echo "Adding Helm repository..."
helm repo add vmware-tanzu "${NEXUS_REPO}" --force-update 2>/dev/null || true
helm repo update

# --- Deploy Velero ---
echo "Deploying Velero..."
helm upgrade --install velero vmware-tanzu/velero \
  --namespace "${NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --timeout 10m

# --- Deploy Velero UI ---
if [[ "$ENABLE_UI" == true ]]; then
  echo "Deploying Velero UI..."
  UI_VALUES="/tmp/velero-ui-values.yaml"
  cat > "$UI_VALUES" <<EOF
image:
  repository: ${HARBOR}/velero-ui
  tag: 0.3.0
ingress:
  enabled: true
  hosts: { velero-ui.example.com: / }
  tls:
  - hosts: [velero-ui.example.com]
EOF

  helm upgrade --install velero-ui backube/velero-ui \
    --namespace "${NAMESPACE}" \
    -f "${UI_VALUES}" \
    --timeout 5m 2>/dev/null || echo "  (Velero UI chart not found in repo — skipping)"
fi

# --- Verify ---
echo "Verifying Velero deployment..."
kubectl rollout status deployment/velero -n "${NAMESPACE}" --timeout=5m
kubectl rollout status deployment/velero-restic -n "${NAMESPACE}" --timeout=5m 2>/dev/null || true

# --- Verify S3 Connection ---
echo "Verifying backup storage location..."
velero backup-location get 2>/dev/null || \
  kubectl get backupstoragelocation -n "${NAMESPACE}"

# --- Test Backup ---
echo "Creating test backup..."
TEST_BACKUP_NAME="test-backup-$(date +%Y%m%d-%H%M%S)"
velero backup create "${TEST_BACKUP_NAME}" \
  --include-namespaces "${NAMESPACE}" \
  --ttl 1h \
  --wait 2>/dev/null || \
  kubectl create -f - <<EOF 2>/dev/null
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: ${TEST_BACKUP_NAME}
  namespace: ${NAMESPACE}
spec:
  includedNamespaces: ["${NAMESPACE}"]
  ttl: 1h
EOF

echo "Checking test backup status..."
sleep 5
velero backup describe "${TEST_BACKUP_NAME}" 2>/dev/null || \
  kubectl describe backup "${TEST_BACKUP_NAME}" -n "${NAMESPACE}"

# --- Schedule Verification ---
echo "Verifying schedules..."
velero schedule get 2>/dev/null || \
  kubectl get schedule -n "${NAMESPACE}"

echo ""
echo "✅ Velero deployed successfully!"
echo ""
echo "Endpoints:"
echo "  Velero:   namespace ${NAMESPACE}"
if [[ "$ENABLE_UI" == true ]]; then
  echo "  UI:       https://velero-ui.example.com"
fi
echo ""
echo "S3:"
echo "  Endpoint: ${S3_ENDPOINT}"
echo "  Bucket:   ${S3_BUCKET}"
echo "  Prefix:   ${CLUSTER_NAME}/velero"
echo ""
echo "Schedules:"
echo "  Daily:    ${SCHEDULE_DAILY}"
echo "  Weekly:   ${SCHEDULE_WEEKLY}"
echo ""
echo "Next steps:"
echo "  1. Verify daily backup runs: velero backup get"
echo "  2. Test restore: velero restore create --from-backup ${TEST_BACKUP_NAME}"
echo "  3. Clean test backup: velero backup delete ${TEST_BACKUP_NAME}"
echo "  4. Configure backup annotations on application pods"
