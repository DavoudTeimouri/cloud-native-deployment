# Component Upgrade Guide

## Overview

This guide covers upgrading individual platform components in the cloud-native deployment. Each component can be upgraded independently using Helm, with specific considerations for air-gapped environments.

## Prerequisites for All Upgrades

- Helm 3.x installed and configured
- Access to Nexus Helm repository (air-gap)
- kubectl configured to target the correct cluster
- Current release notes reviewed for breaking changes
- Backup of critical configuration (where applicable)
- Non-production testing recommended

## Upgrade Process Template

For each component, follow this pattern:

1. **Pre-upgrade checks**
   - Review release notes
   - Check current version
   - Backup configuration (if applicable)
   - Verify prerequisites

2. **Prepare upgrade values**
   - Update Helm values if needed
   - Adjust for breaking changes
   - Set image repository to Harbor/Nexus

3. **Perform upgrade**
   ```bash
   helm upgrade <release> <chart> \
     --namespace <namespace> \
     --version <chart-version> \
     --values <values-file> \
     [--reuse-values] \
     [--reset-values] \
     --wait --timeout 10m
   ```

4. **Post-upgrade verification**
   - Check pod status
   - Verify functionality
   - Review logs for errors
   - Confirm version updated

---

## 1. ArgoCD Upgrade

### Current Version Check
```bash
helm list -n argocd
```

### Pre-upgrade Checks
- Review [ArgoCD release notes](https://argoproj.github.io/argo-cd/release_notes/)
- Check for breaking changes in v2.12+ (RBAC changes)
- Ensure Redis persistence if using HA
- Verify ApplicationSet controller compatibility

### Upgrade Command
```bash
helm upgrade argocd argo/argo-cd \
  --namespace argocd \
  --version 7.7.16 \
  --values helm-values/argocd-values.yaml \
  --wait --timeout 10m
```

### Post-verification
```bash
# Check pods
kubectl -n argocd get pods

# Check version
argocd version --client
argocd version --server

# Test API
argocd app list
```

### Rollback
```bash
helm rollback argocd <revision> -n argocd
```

---

## 2. Rancher Upgrade

### Current Version Check
```bash
helm list -n cattle-system
```

### Pre-upgrade Checks
- Review [Rancher release notes](https://ranchermarketplace.com/docs/rancher/)
- Backup etcd if running embedded etcd (we use external)
- Check for required cert-manager version
- Verify system chart compatibility

### Upgrade Command
```bash
helm upgrade rancher rancher/rancher \
  --namespace cattle-system \
  --version 2.10.3 \
  --values helm-values/rancher-values.yaml \
  --wait --timeout 15m
```

### Post-verification
```bash
# Check pods
kubectl -n cattle-system get pods

# Access UI and verify version in footer
# Check API
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://rancher.mgmt.internal/v3/version
```

### Rollback
```bash
helm rollback rancher <revision> -n cattle-system
```

---

## 3. cert-manager Upgrade

### Current Version Check
```bash
helm list -n cert-manager
```

### Pre-upgrade Checks
- Review [cert-manager release notes](https://cert-manager.io/docs/release-notes/)
- Check for CRD changes (may need manual pruning)
- Ensure webhook timeout settings are appropriate
- Verify CA issuer configurations

### Upgrade Command
```bash
helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version 1.16.2 \
  --values helm-values/cert-manager-values.yaml \
  --wait --timeout 10m
```

### Post-verification
```bash
# Check pods
kubectl -n cert-manager get pods

# Test certificate issuance
kubectl apply -f test-cert.yaml
kubectl describe certificate test-cert

# Check webhook status
kubectl get validatingwebhookconfiguration
```

### Rollback
```bash
helm rollback cert-manager <revision> -n cert-manager
```

---

## 4. NGINX Ingress Controller Upgrade

### Current Version Check
```bash
helm list -n ingress-nginx
```

### Pre-upgrade Checks
- Review [NGINX Ingress release notes](https://kubernetes.github.io/ingress-nginx/changelog/)
- Check for configuration changes in ConfigMap
- Verify custom annotations still valid
- Ensure hostNetwork tolerations still needed

### Upgrade Command
```bash
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --version 4.12.1 \
  --values helm-values/nginx-ingress-values.yaml \
  --wait --timeout 10m
```

### Post-verification
```bash
# Check pods
kubectl -n ingress-nginx get pods -o wide
# Should show hostNetwork: true

# Test HTTP endpoint
curl -I http://your-app.internal

# Test HTTPS endpoint (if TLS configured)
curl -I https://your-app.internal

# Check config
kubectl -n ingress-nginx get configmap ingress-nginx-controller -o yaml
```

### Rollback
```bash
helm rollback ingress-nginx <revision> -n ingress-nginx
```

---

## 5. MetalLB Upgrade (App Cluster Only)

### Current Version Check
```bash
helm list -n metallb-system
```

### Pre-upgrade Checks
- Review [MetalLB release notes](https://metallb.universe.tf/configuration/)
- Check for IPAddressPool API changes
- Verify BGP peer configurations (if using BGP mode)
- Ensure no IP conflicts in pools

### Upgrade Command
```bash
helm upgrade metallb metallb/metallb \
  --namespace metallb-system \
  --version 0.14.9 \
  --values helm-values/metallb-values.yaml \
  --wait --timeout 10m
```

### Post-verification
```bash
# Check pods
kubectl -n metallb-system get pods

# Verify IP assignment
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# Test service with LoadBalancer type
kubectl get svc -n <namespace> | grep LoadBalancer
```

### Rollback
```bash
helm rollback metallb <revision> -n metallb-system
```

---

## 6. Prometheus/Grafana Stack (kube-prometheus-stack) Upgrade

### Current Version Check
```bash
helm list -n monitoring
```

### Pre-upgrade Checks
- Review [kube-prometheus-stack release notes](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- Check for Prometheus rule changes
- Verify Grafana dashboard compatibility
- Check Alertmanager receiver changes
- Ensure storage class still valid

### Upgrade Command
```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 67.5.0 \
  --values helm-values/prometheus-values.yaml \
  --wait --timeout 15m
```

### Post-verification
```bash
# Check pods
kubectl -n monitoring get pods

# Verify Prometheus targets
curl -s http://prometheus.monitoring:9090/api/v1/targets | jq .

# Check Grafana
kubectl -n monitoring get svc
# Then port-forward and login
# kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

# Check Alertmanager
curl -s http://alertmanager.monitoring:9093/api/v1/status
```

### Rollback
```bash
helm rollback kube-prometheus-stack <revision> -n monitoring
```

---

## 7. Loki Stack Upgrade

### Current Version Check
```bash
helm list -n monitoring
```

### Pre-upgrade Checks
- Review [Grafana Loki release notes](https://grafana.com/docs/loka/latest/releases/)
- Check for Loki schema changes
- Verify Compactor and Ring configurations
- Ensure retention settings are preserved

### Upgrade Command
```bash
helm upgrade loki-stack grafana/loki-stack \
  --namespace monitoring \
  --version 6.25.0 \
  --values helm-values/loki-values.yaml \
  --wait --timeout 10m
```

### Post-verification
```bash
# Check pods
kubectl -n monitoring get pods -l app.kubernetes.io/name=loki

# Test Loki ingestion
# Port-forward and use Loki API
kubectl -n monitoring port-forward svc/loki-stack 3100:3100 &
curl -XPOST "http://localhost:3100/loki/api/v1/push" \
  -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"job":"test"},"values":[["'"$(date +%s)900000000"'","test message"]]}]}'

# Query logs
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"test\"}" | jq .
```

### Rollback
```bash
helm rollback loki-stack <revision> -n monitoring
```

---

## 8. Velero Upgrade

### Current Version Check
```bash
helm list -n velero
```

### Pre-upgrade Checks
- Review [Velero release notes](https://velero.io/docs/v1.12/release-notes/)
- Check for plugin compatibility
- Verify CRD changes
- Ensure BackupStorageLocation and VolumeSnapshotLocation still valid
- Check for default storage class changes

### Upgrade Command
```bash
helm upgrade velero vmware-tanzu/velero \
  --namespace velero \
  --version 8.1.1 \
  --values helm-values/velero-values.yaml \
  --wait --timeout 10m
```

### Post-verification
```bash
# Check pods
kubectl -n velero get pods

# Verify version
velero version

# Check backup locations
velero backup-location get

# Test backup (if window allows)
velero backup create test-backup --wait
velero backup get test-backup
velero backup delete test-backup --confirm
```

### Rollback
```bash
helm rollback velero <revision> -n velero
```

---

## 9. Gatekeeper Upgrade

### Current Version Check
```bash
helm list -n gatekeeper-system
```

### Pre-upgrade Checks
- Review [Gatekeeper release notes](https://open-policy-agent.github.io/gatekeeper/website/docs/releases/)
- Check for ConstraintTemplate API changes
- Validate existing constraints still compile
- Check audit logging changes
- Ensure externaldata provider configuration still valid

### Upgrade Command
```bash
helm upgrade gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --version 3.17.1 \
  --values helm-values/gatekeeper-values.yaml \
  --wait --timeout 10m
```

### Post-verification
```bash
# Check pods
kubectl -n gatekeeper-system get pods

# Test constraint creation
kubectl apply -f test-constraint.yaml
kubectl get constraints

# Test violation
kubectl apply -f test-violation.yaml
kubectl get constraints -o wide

# Check audit events
kubectl get events --field-selector involvedObject.kind=Constraint
```

### Rollback
```bash
helm rollback gatekeeper <revision> -n gatekeeper-system
```

---

## 10. Harbor Upgrade

### Current Version Check
```bash
# For Harbor deployed via Helm
helm list -n harbor
# Or for docker-compose/docker install:
docker-compose ps
# Check Harbor version in UI footer
```

### Pre-upgrade Checks
- Review [Harbor release notes](https://goharbor.io/docs/2.5.0/install-config/upgrade/)
- Backup database and /data volume
- Check for database schema changes
- Verify proxy/cache configuration compatibility
- Check for Notary v2 to Notary signer migration (if applicable)
- Ensure Trivy vulnerability scanner compatibility

### Upgrade Methods

#### Helm-based Harbor
```bash
helm upgrade harbor harbor/harbor \
  --namespace harbor \
  --version 2.5.0 \
  --values harbor-values.yaml \
  --wait --timeout 20m
```

#### Docker-compose based Harbor (on Ops Linux)
```bash
# Download new version from Nexus (air-gap)
docker-compose pull
docker-compose up -d
docker-compose exec core /usr/local/bin/migration
```

### Post-verification
```bash
# Check UI version
# Login and check footer

# Check API
curl -sk -u "admin:HarborAdmin123!" \
  https://harbor.internal/api/v2.0/systeminfo | jq .

# Test push/pull
docker login harbor.internal
docker pull harbor.io/library/hello-world:latest
docker tag hello-world harbor.internal/library/hello-world:test
docker push harbor.internal/library/hello-world:test
docker rmi harbor.internal/library/hello-world:test
```

### Rollback
For Helm:
```bash
helm rollback harbor <revision> -n harbor
```

For docker-compose: Restore from backup and redeploy previous version.

---

## 11. Nexus Repository Manager Upgrade

### Current Version Check
- Check footer in UI
- Or: `curl -s http://nexus.internal:8081/service/rest/v1/status`

### Pre-upgrade Checks
- Review [Sonatype Nexus release notes](https://help.sonatype.com/repomanager3/product-information/release-notes)
- Backup /nexus-data directory
- Check for database schema changes (requires upgrade script)
- Verify blob store compatibility
- Check for Elasticsearch/Optigrey upgrade requirements (if using)

### Upgrade Process (Docker-based)
```bash
# Pull new image from Nexus (air-gap)
docker pull nexus.internal/nexus/nexus3:3.68.0

# Stop current container
docker stop nexus
docker rm nexus

# Run new version with same volume
docker run -d \
  --name nexus \
  -p 8081:8080 \
  -p 8082:8081 \
  -v nexus-data:/nexus-data \
  nexus.internal/nexus/nexus3:3.68.0

# Wait for startup and run migration if needed
# First startup after version change may take longer
```

### Post-verification
```bash
# Check UI
# Verify version in footer

# Test API
curl -s -u "admin:password" \
  http://nexus.internal:8081/service/rest/v1/status | jq .

# Test repository access
# Try pulling/pushing a known image

# Check logs
docker logs -f nexus
```

### Rollback
Stop new container, restore volume backup, start old container.

---

## General Air-Gap Considerations

### Image Management
1. Before upgrading, pull new images to Harbor:
   ```bash
   # On internet-connected machine
   docker pull repo.org/image:newversion
   docker tag repo.org/image:newversion harbor.internal/project/image:newversion
   docker push harbor.internal/project/image:newversion
   ```

2. Update Helm values to point to Harbor:
   ```yaml
   image:
     repository: harbor.internal/project/image
     tag: newversion
   ```

### Helm Chart Sources
In air-gap, Helm charts come from Nexus:
```bash
# Add Nexus Helm repo
helm repo add nexus http://nexus.internal:8081/repository/helm-hosted/
helm repo update

# Then install from there
helm upgrade myrelease nexus/mychart --version 1.2.3
```

### Database Backup
For components with databases (Harbor, GitLab, etc.):
```bash
# Example for Harbor
docker exec harbor-core /usr/local/bin/backup.sh
# Copies /data/database to backup location
```

### Resource Planning
During upgrade, ensure:
- Sufficient memory for new versions (some use more resources)
- Disk space for temporary containers/images
- Network bandwidth for image pulls (internal registry)

## Troubleshooting Upgrades

### Helm Release Not Found
```bash
# Release might be in different namespace
helm list --all-namespaces | grep myrelease
```

### CrashLoopBackOff After Upgrade
```bash
# Check logs
kubectl -n namespace logs pod-name

# Common causes:
# 1. Configuration incompatibility
# 2. Missing dependencies
# 3. Resource limits too low
# 4. Volume permission issues
```

### Upgrade Timed Out
```bash
# Increase timeout
helm upgrade ... --timeout 20m

# Check if pod is stuck in Pending
kubectl get pods -n namespace -w

# Check events
kubectl describe pod -n namespace pod-name
```

### Rollback Failed
Sometimes rollback fails if:
1. CRDs were changed and can't be downgraded
2. Data migration is not reversible
3. Configuration format changed incompatibly

In these cases, you may need to:
- Restore from backup
- Manually fix incompatible resources
- Skip problematic components temporarily

## Maintenance Window Recommendations

| Component | Estimated Downtime | Notes |
|-----------|-------------------|-------|
| ArgoCD | 2-5 min | API downtime only |
| Rancher | 5-10 min | UI/API downtime |
| cert-manager | 1-2 min | Minimal, webhook restart |
| NGINX Ingress | 0-1 min | Rolling update if DaemonSet |
| MetalLB | <1 min | Minimal disruption |
| Prometheus Stack | 3-5 min | TSDB reload may pause scraping |
| Loki | 2-4 min | Index updates may block writes |
| Velero | <1 min | Controller restart only |
| Gatekeeper | 1-2 min | Audit webhook restart |
| Harbor | 10-20 min | DB migration possible |
| Nexus | 5-15 min | Blob store upgrades may take time |

## Version Pinning Strategy

For production environments, consider:

1. **Document exact versions** in a VERSIONS.md file
2. **Use Helm --version** flag strictly (never rely on latest)
3. **Test upgrades** in staging cluster first
4. **Maintain override values** in GitLab repo
5. **Schedule regular upgrade reviews** (monthly/quarterly)

## Appendix: Useful Commands

### List all Helm releases
```bash
helm ls --all-namespaces
```

### Get helm release notes
```bash
helm show readme bitnami/mysql
helm show values bitnami/mysql
```

### Check for available updates
```bash
helm repo update
helm list --all-namespaces | while read release ns chart version; do
  latest=$(helm search repo "$chart" --versions | head -1 | awk '{print $2}')
  if [[ "$version" != "$latest" ]]; then
    echo "$ns/$release: $chart $version -> $latest available"
  fi
done
```

### Template render to see what will change
```bash
helm upgrade --install --dry-run --debug myrelease ./mychart
```

### Get manifest of current release
```bash
helm get manifest myrelease -n namespace
```