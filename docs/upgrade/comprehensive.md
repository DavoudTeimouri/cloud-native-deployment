# Comprehensive Upgrade Guide

> Upgrade procedures for ALL components — Kubernetes, Ceph, OS, and all platform components

---

## 1. Pre-Upgrade Checklist

Before upgrading **anything**, complete these steps:

```bash
# 1. Backup etcd (Kubernetes)
kubectl exec -it etcd-master-1 -n kube-system -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-backup-$(date +%Y%m%d).db

# 2. Backup all manifests
kubectl get all --all-namespaces -o yaml > /backup/manifests-$(date +%Y%m%d).yaml

# 3. Verify current versions
kubectl version --short
ceph -v
kubeadm version
kubectl get nodes -o wide

# 4. Check component health
kubectl get pods --all-namespaces
ceph -s

# 5. Verify Velero backups
velero backup get
velero backup create pre-upgrade-$(date +%Y%m%d) --wait
```

---

## 2. Operating System Upgrade

### 2.1 Ubuntu 22.04 → 24.04 (In-Place)

```bash
# Pre-upgrade
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get dist-upgrade -y
sudo apt-get autoremove -y

# Backup critical configs
sudo tar -czf /backup/etc-$(date +%Y%m%d).tar.gz /etc/

# Upgrade
sudo apt-get install -y update-manager-core
sudo do-release-upgrade

# Reboot
sudo reboot

# Verify
lsb_release -a
uname -r
```

### 2.2 Ubuntu In-Place (Same Version, Package Update)

```bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get dist-upgrade -y
sudo apt-get autoremove -y

# Reboot if kernel updated
if [ -f /var/run/reboot-required ]; then
    sudo reboot
fi
```

### 2.3 Rocky Linux / Oracle Linux Upgrade

```bash
# Rocky Linux 8 → 9
sudo dnf upgrade -y
sudo dnf install -y dnf-plugin-system-upgrade
sudo dnf system-upgrade download --releasever=9
sudo dnf system-upgrade reboot

# Oracle Linux 8 → 9
sudo dnf upgrade -y
sudo dnf install -y oraclelinux-release-el9
sudo dnf distro-sync -y
```

### 2.4 Post-OS-Upgrade Verification

```bash
# Verify OS version
cat /etc/os-release
lsb_release -a

# Verify kernel
uname -r

# Verify services
systemctl is-active kubelet
systemctl is-active containerd
systemctl is-active chrony

# Verify swap still disabled
free -h | grep Swap

# Verify kernel modules
lsmod | grep -E "br_netfilter|overlay"

# Verify sysctl
sysctl net.ipv4.ip_forward
sysctl net.bridge.bridge-nf-call-iptables
```

---

## 3. Kubernetes Upgrade

### 3.1 KubeSpray Upgrade (Recommended)

```bash
# Update KubeSpray
cd /path/to/kubespray
git fetch --all --tags
git checkout v2.25.0  # or target version

# Update inventory
vim inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
# Change: kube_version: v1.30.0

# Run upgrade
ansible-playbook -i inventory/mycluster/hosts.yaml upgrade-cluster.yml \
  -e "kube_version=v1.30.0" \
  -b
```

### 3.2 Manual Rolling Upgrade

```bash
# Upgrade first master
ssh master-1
apt-get update
apt-get install -y kubeadm=1.30.0-00
kubeadm upgrade apply v1.30.0
apt-get install -y kubelet=1.30.0-00 kubectl=1.30.0-00
systemctl daemon-reload
systemctl restart kubelet

# Upgrade remaining masters (one at a time)
ssh master-2
apt-get install -y kubeadm=1.30.0-00
kubeadm upgrade node
apt-get install -y kubelet=1.30.0-00 kubectl=1.30.0-00
systemctl daemon-reload
systemctl restart kubelet

# Upgrade workers (one at a time)
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data
ssh worker-1
apt-get install -y kubeadm=1.30.0-00
kubeadm upgrade node
apt-get install -y kubelet=1.30.0-00 kubectl=1.30.0-00
systemctl daemon-reload
systemctl restart kubelet
kubectl uncordon worker-1
```

### 3.3 K3s Upgrade

```bash
# Server
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--version=v1.29.0" sh -

# Agents (automatic when server upgrades)
# Or manually:
curl -sfL https://get.k3s.io | K3S_URL=https://<server>:6443 K3S_TOKEN=<token> sh -
```

### 3.4 Post-Kubernetes-Upgrade Verification

```bash
kubectl version --short
kubectl get nodes -o wide
kubectl get pods --all-namespaces
kubeadm certs check-expiration
```

---

## 4. Ceph Upgrade

### 4.1 Ceph Rolling Upgrade (cephadm)

```bash
# Check current version
ceph -v

# Upgrade
ceph orch upgrade start --ceph-version 18.2.2

# Monitor
ceph orch upgrade status
ceph -s
```

### 4.2 Manual Ceph Upgrade

```bash
# Upgrade MONs (one at a time)
systemctl stop ceph-mon@<mon-id>
apt-get install -y ceph-mon=18.2.2-*
systemctl start ceph-mon@<mon-id>

# Upgrade MGRs (one at a time)
systemctl stop ceph-mgr@<mgr-id>
apt-get install -y ceph-mgr=18.2.2-*
systemctl start ceph-mgr@<mgr-id>

# Upgrade OSDs (one host at a time)
ceph osd set noout
for osd in $(ceph osd ls-tree <hostname>); do
    ceph osd out $osd
done
apt-get install -y ceph-osd=18.2.2-*
systemctl restart ceph-osd.target
for osd in $(ceph osd ls-tree <hostname>); do
    ceph osd in $osd
done
ceph osd unset noout

# Upgrade MDSs
ceph mds fail <mds-id>
apt-get install -y ceph-mds=18.2.2-*
systemctl restart ceph-mds@<mds-id>

# Upgrade RGWs
systemctl stop ceph-radosgw@rgw.<id>
apt-get install -y radosgw=18.2.2-*
systemctl start ceph-radosgw@rgw.<id>
```

### 4.3 Post-Ceph-Upgrade Verification

```bash
ceph -s
ceph health detail
ceph osd tree
ceph osd dump | grep -E "down|out"
ceph pg stat
```

---

## 5. Platform Components Upgrade

### 5.1 ArgoCD Upgrade

```bash
# Update repo
helm repo update argo

# Upgrade
helm upgrade argocd argo/argo-cd \
  -n argocd \
  --version 5.55.0 \
  --values values.yaml \
  --wait --timeout 10m

# Verify
argocd version --server
kubectl get pods -n argocd
```

### 5.2 Rancher Upgrade

```bash
# Update repo
helm repo update rancher-latest

# Backup current values
helm get values rancher -n cattle-system > /backup/rancher-values.yaml

# Upgrade
helm upgrade rancher rancher-latest/rancher \
  -n cattle-system \
  --version 2.8.5 \
  --set hostname=rancher.internal.lan \
  --wait --timeout 10m

# Verify
kubectl get pods -n cattle-system
curl -k https://rancher.internal.lan/ping
```

### 5.3 Gatekeeper Upgrade

```bash
helm repo update gatekeeper

helm upgrade gatekeeper gatekeeper/gatekeeper \
  -n gatekeeper-system \
  --version 3.15.0 \
  --wait --timeout 5m

# Verify
kubectl get pods -n gatekeeper-system
kubectl get constrainttemplates
```

### 5.4 cert-manager Upgrade

```bash
# Update CRDs first
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.crds.yaml

helm repo update jetstack

helm upgrade cert-manager jetstack/cert-manager \
  -n cert-manager \
  --version v1.14.0 \
  --set installCRDs=false \
  --wait --timeout 5m

# Verify
kubectl get pods -n cert-manager
kubectl get certificates --all-namespaces
```

### 5.5 NGINX Ingress Upgrade

```bash
helm repo update ingress-nginx

helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --version 4.10.0 \
  --wait --timeout 5m

# Verify
kubectl get pods -n ingress-nginx
kubectl get ingress --all-namespaces
```

### 5.6 MetalLB Upgrade

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.1/config/manifests/metallb-native.yaml

# Verify
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
```

---

## 6. Monitoring Stack Upgrade

### 6.1 Prometheus/Grafana Upgrade

```bash
helm repo update prometheus-community

helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --version 57.0.0 \
  --values values.yaml \
  --wait --timeout 15m

# Verify
kubectl get pods -n monitoring
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
```

### 6.2 Loki Upgrade

```bash
helm repo update grafana

helm upgrade loki grafana/loki-stack \
  -n monitoring \
  --version 2.9.11 \
  --set promtail.enabled=true \
  --wait --timeout 10m

# Verify
kubectl get pods -n monitoring -l app=loki
```

---

## 7. Backup & Security Upgrade

### 7.1 Velero Upgrade

```bash
# Update CLI
VELERO_VERSION=1.13.0
curl -sL "https://github.com/vmware-tanzu/velero/releases/download/v${VELERO_VERSION}/velero-v${VELERO_VERSION}-linux-amd64.tar.gz" | tar xz
sudo mv velero-v${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/

# Update server
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=minio,s3ForcePathStyle=true,s3Url=http://minio.internal:9000 \
  --use-restic \
  --wait

# Verify
velero version
velero backup-location get
```

### 7.2 Kyverno Upgrade

```bash
helm repo update kyverno

helm upgrade kyverno kyverno/kyverno \
  --namespace kyverno \
  --version 3.1.0 \
  --wait --timeout 5m

# Verify
kubectl get pods -n kyverno
kubectl get cpol
```

---

## 8. Development Tools Upgrade

### 8.1 GitLab Upgrade

```bash
# Update repo
helm repo update gitlab

# Check current version
helm list -n gitlab

# Upgrade
helm upgrade gitlab gitlab/gitlab \
  -n gitlab \
  --version 7.2.0 \
  --set global.hosts.domain=gitlab.internal.lan \
  --wait --timeout 15m

# Verify
kubectl get pods -n gitlab
```

### 8.2 Harbor Upgrade

```bash
helm repo update goharbor

helm upgrade harbor goharbor/harbor \
  -n harbor \
  --version 2.10.1 \
  --set externalURL=https://harbor.internal.lan \
  --wait --timeout 10m

# Verify
kubectl get pods -n harbor
curl -k https://harbor.internal/api/v2.0/health
```

### 8.3 Nexus Upgrade

```bash
# Docker container
docker pull sonatype/nexus3:3.68.0
docker stop nexus && docker rm nexus
docker run -d --name nexus \
  -p 9091:8081 -p 9443:8443 -p 5000:5000 \
  -v /opt/nexus/data:/nexus-data \
  sonatype/nexus3:3.68.0

# Verify
curl -s http://localhost:9091/service/rest/v1/status
```

---

## 9. Container Services Upgrade

### 9.1 PostgreSQL Upgrade

```bash
# Docker
docker pull postgres:16-alpine
docker stop postgres && docker rm postgres
docker run -d --name postgres \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=*** \
  -v /opt/postgres/data:/var/lib/postgresql/data \
  postgres:16-alpine

# Verify
docker exec -it postgres psql -U postgres -c "SELECT version();"
```

### 9.2 Redis Upgrade

```bash
# Docker
docker pull redis:7.2-alpine
docker stop redis && docker rm redis
docker run -d --name redis \
  -p 6379:6379 \
  -v /opt/redis/data:/data \
  redis:7.2-alpine redis-server --requirepass ***

# Verify
docker exec -it redis redis-cli -a *** ping
```

---

## 10. Network Upgrade

### 10.1 Calico Upgrade

```bash
# Operator-based
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml

# Verify
calicoctl node status
kubectl get pods -n calico-system
```

### 10.2 CoreDNS Upgrade

```bash
# Rolling restart
kubectl rollout restart deployment coredns -n kube-system

# Verify
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

---

## 11. Upgrade Order

```
Phase 1: Backup everything
    │
Phase 2: Upgrade OS (if needed)
    │
Phase 3: Upgrade Kubernetes
    │
Phase 4: Upgrade Ceph
    │
Phase 5: Upgrade Network (Calico, CoreDNS)
    │
Phase 6: Upgrade Platform Components
    │   ├── ArgoCD
    │   ├── Rancher
    │   ├── Gatekeeper
    │   ├── cert-manager
    │   ├── NGINX Ingress
    │   └── MetalLB
    │
Phase 7: Upgrade Monitoring
    │   ├── Prometheus/Grafana
    │   └── Loki
    │
Phase 8: Upgrade Backup & Security
    │   ├── Velero
    │   └── Kyverno
    │
Phase 9: Upgrade Development Tools
    │   ├── GitLab
    │   ├── Harbor
    │   └── Nexus
    │
Phase 10: Upgrade Container Services
    │   ├── PostgreSQL
    │   └── Redis
    │
Phase 11: Verify everything
```

---

## 12. Rollback Procedures

### 12.1 Kubernetes Rollback

```bash
# If upgrade fails on a node
apt-get install -y kubeadm=<previous-version>
kubeadm upgrade apply <previous-version> --force
apt-get install -y kubelet=<previous-version> kubectl=<previous-version>
systemctl restart kubelet

# Restore etcd
etcdctl snapshot restore /backup/etcd-backup-<date>.db \
  --data-dir=/var/lib/etcd-restored
```

### 12.2 Helm Rollback

```bash
# Check history
helm history <release> -n <namespace>

# Rollback
helm rollback <release> <revision> -n <namespace>

# Example
helm rollback rancher 2 -n cattle-system
```

### 12.3 Ceph Rollback

```bash
# Downgrade packages
apt-get install ceph-mon=<previous-version> ceph-osd=<previous-version>
systemctl restart ceph.target
```

---

## 13. Post-Upgrade Verification

```bash
# Full health check
./scripts/health-check.sh

# Or manually
kubectl get nodes
kubectl get pods --all-namespaces
kubectl top nodes
ceph -s
velero backup-location get
kubectl get certificates --all-namespaces
```
