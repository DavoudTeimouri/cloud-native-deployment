# Component Upgrade Guide

> Helm-based upgrades for: ArgoCD, Rancher, Gatekeeper, cert-manager, NGINX Ingress, MetalLB, Prometheus/Grafana, Loki, Velero

---

## 1. ArgoCD Upgrade

### Pre-Checks
```bash
# Check current version
argocd version --client
kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check available versions
helm search repo argo/argocd --versions

# Backup
kubectl get applications -n argocd -o yaml > /backup/applications-$(date +%Y%m%d).yaml
```

### Upgrade
```bash
# Update repo
helm repo update argo

# Dry run
helm upgrade argocd argo/argo-cd -n argocd \
  --version 5.51.0 \
  --values values.yaml \
  --dry-run --debug

# Execute upgrade
helm upgrade argocd argo/argo-cd -n argocd \
  --version 5.51.0 \
  --values values.yaml \
  --wait --timeout 10m
```

### Post-Checks
```bash
kubectl get pods -n argocd
argocd version --server
argocd app list
```

### Rollback
```bash
helm history argocd -n argocd
helm rollback argocd <revision> -n argocd
```

---

## 2. Rancher Upgrade

### Pre-Checks
```bash
# Check current version
helm list -n cattle-system
kubectl get deployment rancher -n cattle-system -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check Rancher release notes for breaking changes
# https://github.com/rancher/rancher/releases

# Backup
helm get values rancher -n cattle-system > /backup/rancher-values-$(date +%Y%m%d).yaml
```

### Upgrade
```bash
# Update repo
helm repo update rancher-latest

# Upgrade Rancher
helm upgrade rancher rancher-latest/rancher \
  -n cattle-system \
  --version 2.8.0 \
  --set hostname=rancher.example.com \
  --set replicas=3 \
  --set bootstrapPassword=admin \
  --wait --timeout 10m
```

### Post-Checks
```bash
kubectl get pods -n cattle-system
kubectl get pods -n cattle-cluster-agent
# Verify UI loads
curl -k https://rancher.example.com/ping
```

### Rollback
```bash
helm history rancher -n cattle-system
helm rollback rancher <revision> -n cattle-system
```

---

## 3. Gatekeeper Upgrade

### Pre-Checks
```bash
helm list -n gatekeeper-system
kubectl get constrainttemplates | wc -l  # note count for comparison

# Backup constraints
kubectl get constraints -o yaml > /backup/gatekeeper-constraints-$(date +%Y%m%d).yaml
kubectl get constrainttemplates -o yaml > /backup/gatekeeper-templates-$(date +%Y%m%d).yaml
```

### Upgrade
```bash
helm repo update gatekeeper

helm upgrade gatekeeper gatekeeper/gatekeeper \
  -n gatekeeper-system \
  --version 3.14.0 \
  --set auditInterval=60 \
  --set constraintViolationsLimit=100 \
  --wait --timeout 5m
```

### Post-Checks
```bash
kubectl get pods -n gatekeeper-system
kubectl get constrainttemplates | wc -l  # should match pre-upgrade
kubectl get constraints  # verify no new violations
```

### Rollback
```bash
helm history gatekeeper -n gatekeeper-system
helm rollback gatekeeper <revision> -n gatekeeper-system
```

---

## 4. cert-manager Upgrade

### Pre-Checks
```bash
helm list -n cert-manager
kubectl get crd | grep cert-manager  # note CRDs

# Check for API version changes
kubectl get crd certificates.cert-manager.io -o yaml | grep -A 5 versions

# Backup
kubectl get certificates --all-namespaces -o yaml > /backup/certs-$(date +%Y%m%d).yaml
```

### Upgrade
```bash
# CRDs must be updated separately for cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.crds.yaml

helm repo update jetstack

helm upgrade cert-manager jetstack/cert-manager \
  -n cert-manager \
  --version v1.14.0 \
  --set installCRDs=false \
  --set prometheus.enabled=true \
  --wait --timeout 5m
```

### Post-Checks
```bash
kubectl get pods -n cert-manager
kubectl get certificates --all-namespaces
# Verify a test certificate issues
kubectl get certificaterequests --all-namespaces
```

### Rollback
```bash
helm history cert-manager -n cert-manager
helm rollback cert-manager <revision> -n cert-manager
# May need to revert CRDs manually
```

---

## 5. NGINX Ingress Upgrade

### Pre-Checks
```bash
helm list -n ingress-nginx
kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Check for breaking changes in changelog
# https://github.com/kubernetes/ingress-nginx/releases

# Note current config
helm get values ingress-nginx -n ingress-nginx > /backup/nginx-values-$(date +%Y%m%d).yaml
```

### Upgrade
```bash
helm repo update ingress-nginx

helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --version 4.9.0 \
  --set controller.replicaCount=2 \
  --set controller.service.type=LoadBalancer \
  --set controller.metrics.enabled=true \
  --wait --timeout 5m
```

### Post-Checks
```bash
kubectl get pods -n ingress-nginx
kubectl get ingress --all-namespaces
# Test an ingress endpoint
curl -v -H "Host: test.example.com" http://<ingress-ip>/
```

### Rollback
```bash
helm history ingress-nginx -n ingress-nginx
helm rollback ingress-nginx <revision> -n ingress-nginx
```

---

## 6. MetalLB Upgrade

### Pre-Checks
```bash
helm list -n metallb-system
kubectl get ipaddresspool -n metallb-system -o yaml > /backup/metallb-pools-$(date +%Y%m%d).yaml
kubectl get l2advertisement -n metallb-system -o yaml > /backup/metallb-ads-$(date +%Y%m%d).yaml
```

### Upgrade
```bash
helm repo update metallb

helm upgrade metallb metallb/metallb \
  -n metallb-system \
  --version 0.14.0 \
  --wait --timeout 5m
```

### Post-Checks
```bash
kubectl get pods -n metallb-system
kubectl get svc --all-namespaces -o wide | grep LoadBalancer
# Verify external IPs are assigned
```

### Rollback
```bash
helm history metallb -n metallb-system
helm rollback metallb <revision> -n metallb-system
```

---

## 7. Prometheus/Grafana Stack Upgrade

### Pre-Checks
```bash
helm list -n monitoring

# Backup
helm get values kube-prometheus-stack -n monitoring > /backup/prometheus-values-$(date +%Y%m%d).yaml
kubectl get prometheusrules -n monitoring -o yaml > /backup/prometheus-rules-$(date +%Y%m%d).yaml

# Check for CRD changes
kubectl get crd | grep monitoring.coreos.com
```

### Upgrade
```bash
helm repo update prometheus-community

# Check for CRD updates
helm search repo prometheus-community/kube-prometheus-stack --versions

helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --version 56.0.0 \
  --values values.yaml \
  --set prometheus.prometheusSpec.retention=30d \
  --set grafana.adminPassword=admin \
  --wait --timeout 15m
```

### Post-Checks
```bash
kubectl get pods -n monitoring
# Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Navigate to Status → Targets

# Check Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Verify alerts
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts'
```

### Rollback
```bash
helm history kube-prometheus-stack -n monitoring
helm rollback kube-prometheus-stack <revision> -n monitoring
```

---

## 8. Loki Upgrade

### Pre-Checks
```bash
helm list -n monitoring
helm get values loki -n monitoring > /backup/loki-values-$(date +%Y%m%d).yaml

# Check storage usage
kubectl exec -n monitoring <loki-pod> -- du -sh /data
```

### Upgrade
```bash
helm repo update grafana

helm upgrade loki grafana/loki-stack \
  -n monitoring \
  --version 2.9.0 \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=100Gi \
  --wait --timeout 10m
```

### Post-Checks
```bash
kubectl get pods -n monitoring -l app=loki
kubectl get pods -n monitoring -l app=promtail

# Test log query
kubectl port-forward -n monitoring svc/loki 3100:3100
curl -s "http://localhost:3100/loki/api/v1/query_range?query={job=\"nginx\"}" | jq '.data.result'
```

### Rollback
```bash
helm history loki -n monitoring
helm rollback loki <revision> -n monitoring
```

---

## 9. Velero Upgrade

### Pre-Checks
```bash
velero version --namespace velero
velero backup-location get

# Backup schedules
velero schedule get -o yaml > /backup/velero-schedules-$(date +%Y%m%d).yaml

# Check for plugin changes
velero plugin get
```

### Upgrade
```bash
# Update Velero CLI to match server version
# Download from https://github.com/vmware-tanzu/velero/releases

# Upgrade server
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=minio,s3ForcePathStyle=true,s3Url=https://s3.internal:9000 \
  --use-restic \
  --wait

# Or if using Helm:
helm repo update vmware-tanzu

helm upgrade velero vmware-tanzu/velero \
  -n velero \
  --version 5.2.0 \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=velero-backups \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.8.0 \
  --wait --timeout 5m
```

### Post-Checks
```bash
velero version
velero backup-location get
# Test backup
velero backup create test-upgrade --default-volumes-to-restic --wait
velero backup describe test-upgrade --details
velero backup delete test-upgrade
```

### Rollback
```bash
helm history velero -n velero
helm rollback velero <revision> -n velero
```

---

## 10. General Upgrade Best Practices

### For All Components

1. **Always backup before upgrading**
2. **Read release notes** for breaking changes
3. **Test in staging** first
4. **Use `--dry-run`** to preview changes
5. **Upgrade during maintenance windows**
6. **Monitor after upgrade** for at least 30 minutes
7. **Keep previous Helm revision** for quick rollback

### Helm Upgrade Template
```bash
# 1. Update repos
helm repo update

# 2. Check current state
helm list -n <namespace>
helm get values <release> -n <namespace> > backup-values.yaml

# 3. Dry run
helm upgrade <release> <chart> -n <namespace> \
  --version <new-version> \
  --values values.yaml \
  --dry-run --debug

# 4. Execute
helm upgrade <release> <chart> -n <namespace> \
  --version <new-version> \
  --values values.yaml \
  --wait --timeout 10m

# 5. Verify
kubectl get pods -n <namespace>
helm test <release> -n <namespace>  # if tests exist

# 6. Rollback if needed
helm history <release> -n <namespace>
helm rollback <release> <revision> -n <namespace>
```
