# Kubernetes Upgrade Guide

> Covers KubeSpray-based upgrades with air-gap considerations

---

## 1. Pre-Upgrade Checks

### 1.1 Version Compatibility

```bash
# Check current version
kubectl version --short
kubelet --version

# Verify target version is supported
# KubeSpray supports N-1 minor version upgrades
# e.g., 1.28 → 1.29 is supported, 1.27 → 1.29 is NOT

# Check KubeSpray release notes
# https://github.com/kubernetes-sigs/kubespray/releases
```

### 1.2 etcd Backup (CRITICAL)

```bash
# Backup etcd before any upgrade
kubectl exec -it etcd-master-0 -n kube-system -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-backup-$(date +%Y%m%d).db

# Copy backup to safe location
kubectl cp kube-system/etcd-master-0:/tmp/etcd-backup-$(date +%Y%m%d).db \
  /backup/etcd/etcd-backup-$(date +%Y%m%d).db

# Verify backup
etcdctl snapshot status /backup/etcd/etcd-backup-$(date +%Y%m%d).db --write-out=table
```

### 1.3 Node Health Check

```bash
# All nodes should be Ready
kubectl get nodes

# No pods in CrashLoopBackOff or Pending
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# No ongoing disruptions
kubectl get poddisruptionbudgets --all-namespaces

# Check certificate expiry (must not expire during upgrade)
kubeadm certs check-expiration
```

### 1.4 Resource Check

```bash
# Ensure sufficient resources for rolling upgrades
kubectl top nodes

# Check PDBs that might block drain
kubectl get pdb --all-namespaces

# Verify cluster autoscaler is disabled (if applicable)
```

---

## 2. KubeSpray Upgrade Procedure

### 2.1 Update KubeSpray Code

```bash
cd /path/to/kubespray

# Fetch latest tags
git fetch --all --tags

# Checkout target version
git checkout v2.24.0  # or target version

# Update submodules
git submodule update --init --recursive
```

### 2.2 Update Inventory Variables

```bash
# Edit inventory variables
vim inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml

# Update Kubernetes version
kube_version: v1.29.0

# Update etcd version if needed
etcd_version: v3.5.10

# Update CNI version
calico_version: v3.27.0
```

### 2.3 Air-Gap: Update Images in Harbor

```bash
# Download new Kubernetes images on internet-connected machine
ansible-playbook -i inventory/mycluster/hosts.yaml \
  download.yml \
  -e "download_container=true" \
  -e "download_localhost=true" \
  -e "download_run_once=true" \
  -e "kube_version=v1.29.0"

# Upload to Harbor
for image in $(cat /tmp/kubespray_images.txt); do
  docker pull $image
  # Replace registry prefix
  harbor_image=$(echo $image | sed 's|k8s.gcr.io|harbor.internal/library|g')
  docker tag $image $harbor_image
  docker push $harbor_image
done

# Verify images in Harbor
curl -u admin:password "https://harbor.internal/api/v2.0/projects/library/repositories" | jq '.[].name'
```

### 2.4 Run Upgrade Playbook

```bash
# Dry run first
ansible-playbook -i inventory/mycluster/hosts.yaml upgrade-cluster.yml \
  --check --diff

# Execute upgrade (one master at a time, then workers)
ansible-playbook -i inventory/mycluster/hosts.yaml upgrade-cluster.yml \
  -e "upgrade_node_confirm=true" \
  -b

# For specific version
ansible-playbook -i inventory/mycluster/hosts.yaml upgrade-cluster.yml \
  -e "kube_version=v1.29.0" \
  -b
```

### 2.5 Upgrade Process (What Happens)

KubeSpray upgrades in this order:
1. **etcd** — upgraded on all masters
2. **First master** — kube-apiserver, kube-scheduler, kube-controller-manager
3. **Remaining masters** — one at a time
4. **Workers** — one at a time (drain → upgrade → uncordon)
5. **CNI** — Calico/other CNI components
6. **Add-ons** — CoreDNS, metrics-server, etc.

---

## 3. Rolling Upgrade Process (Manual)

If not using KubeSpray upgrade-cluster.yml:

### 3.1 Upgrade First Master

```bash
# Upgrade kubeadm
apt-get update
apt-get install -y kubeadm=1.29.0-00

# Plan upgrade
kubeadm upgrade plan

# Apply upgrade
kubeadm upgrade apply v1.29.0

# Upgrade kubelet and kubectl
apt-get install -y kubelet=1.29.0-00 kubectl=1.29.0-00

# Restart kubelet
systemctl daemon-reload
systemctl restart kubelet
```

### 3.2 Upgrade Additional Masters

```bash
# On each additional master
apt-get update
apt-get install -y kubeadm=1.29.0-00

kubeadm upgrade node

apt-get install -y kubelet=1.29.0-00 kubectl=1.29.0-00
systemctl daemon-reload
systemctl restart kubelet
```

### 3.3 Upgrade Workers

```bash
# Drain node (from control plane)
kubectl drain <worker-node> --ignore-daemonsets --delete-emptydir-data

# On the worker node
apt-get update
apt-get install -y kubeadm=1.29.0-00

kubeadm upgrade node

apt-get install -y kubelet=1.29.0-00 kubectl=1.29.0-00
systemctl daemon-reload
systemctl restart kubelet

# Uncordon (from control plane)
kubectl uncordon <worker-node>
```

---

## 4. Post-Upgrade Verification

```bash
# Verify all nodes upgraded
kubectl get nodes -o wide

# Verify all system pods running
kubectl get pods -n kube-system

# Verify cluster functionality
kubectl get --raw '/healthz'
kubectl get --raw '/livez'
kubectl get --raw '/readyz'

# Verify CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl run test --image=busybox:1.28 --restart=Never -it --rm -- nslookup kubernetes.default

# Verify Calico
kubectl get pods -n kube-system -l k8s-app=calico-node
calicoctl node status

# Check for deprecated API usage
kubectl get --raw "/metrics" | grep apiserver_requested_deprecated_apis

# Verify workloads
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# Check etcd health
kubectl exec -it etcd-master-0 -n kube-system -- etcdctl endpoint health --cluster
```

---

## 5. Rollback Procedure

### 5.1 Rollback etcd

```bash
# Restore from snapshot
etcdctl snapshot restore /backup/etcd/etcd-backup-<date>.db \
  --data-dir=/var/lib/etcd-restored

# Update etcd manifest to use restored data
# Edit /etc/kubernetes/manifests/etcd.yaml
# Change data-dir to /var/lib/etcd-restored
```

### 5.2 Rollback Control Plane

```bash
# Downgrade kubeadm
apt-get install -y kubeadm=1.28.0-00

# Revert upgrade
kubeadm upgrade apply v1.28.0 --force

# Downgrade kubelet and kubectl
apt-get install -y kubelet=1.28.0-00 kubectl=1.28.0-00
systemctl daemon-reload
systemctl restart kubelet
```

### 5.3 Rollback Worker

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# On worker
apt-get install -y kubeadm=1.28.0-00
kubeadm upgrade node
apt-get install -y kubelet=1.28.0-00 kubectl=1.28.0-00
systemctl daemon-reload
systemctl restart kubelet

kubectl uncordon <node>
```

---

## 6. Version-Specific Considerations

### 6.1 API Deprecations

```bash
# Check for deprecated APIs before upgrade
kube-no-trees  # or similar tool
pluto detect-helm-releases
pluto detect-files -d /manifests/

# Common deprecations to watch:
# - PodSecurityPolicy → Pod Security Standards (removed in 1.25)
# - Ingress extensions/v1beta1 → networking.k8s.io/v1 (removed in 1.22)
# - CronJob batch/v1beta1 → batch/v1 (removed in 1.25)
# - CRD apiextensions.k8s.io/v1beta1 → v1 (removed in 1.22)
```

### 6.2 Feature Gates

```bash
# Check feature gates that may change defaults
kubectl get --raw /metrics | grep feature_gate

# Common changes:
# - CSIMigration: enabled by default in 1.25+
# - EphemeralContainers: GA in 1.25+
# - PodSecurity: GA in 1.25+
```

---

## 7. Air-Gap Upgrade Checklist

- [ ] Download all new container images to local machine
- [ ] Push images to Harbor registry
- [ ] Update `download_image_tag` and related vars in inventory
- [ ] Update `registry_host` to point to Harbor
- [ ] Verify image pull secrets are configured
- [ ] Test image pull on one node: `crictl pull harbor.internal/library/kube-apiserver:v1.29.0`
- [ ] Run upgrade with `-e "download_run_once=false"` to use local registry
- [ ] Verify all images resolve: `ansible-playbook -i inventory/mycluster/hosts.yaml download.yml --check`
