# Kubernetes Upgrade Guide

## Overview

This guide covers upgrading Kubernetes clusters deployed with KubeSpray in an air-gapped environment. It includes pre-upgrade checks, upgrade procedures, post-upgrade verification, and rollback steps.

> **Important**: Always test upgrades in a non-production environment first.

## Prerequisites

- Access to the KubeSpray repository and inventory files
- Administrative access to all cluster nodes
- etcd backup procedure tested and verified
- Air-gap: Updated container images in Harbor before upgrade
- Maintenance window scheduled

## Supported Upgrade Paths

KubeSpray supports upgrades between minor versions (e.g., v1.29 → v1.30, v1.30 → v1.31). 
Check [KubeSpray release notes](https://github.com/kubernetes-sigs/kubespray/releases) for specific compatibility.

## Phase 1: Pre-Upgrade Preparation

### 1.1 Backup etcd

```bash
# On any master node
ETCDCTL_API=3 etcdctl --endpoints=https://[MASTER_IP]:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/etcd-backup/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db

# Verify backup
ETCDCTL_API=3 etcdctl --write-out=table snapshot status /var/etcd-backup/etcd-snapshot-*.db
```

### 1.2 Backup etcd data directory (optional but recommended)

```bash
# On each master node
systemctl stop etcd
tar -czf /var/etcd-backup/etcd-data-$(hostname)-$(date +%Y%m%d-%H%M%S).tar.gz /var/lib/etcd/
systemctl start etcd
```

### 1.3 Verify Cluster Health

```bash
# Check node status
kubectl get nodes

# Check pod status
kubectl get pods -A -o wide | grep -v Running | grep -v Completed

# Check etcd health
ETCDCTL_API=3 etcdctl --endpoints=https://[MASTER_IP]:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health --cluster

# Check application functionality
# Run smoke tests against critical applications
```

### 1.4 Review Release Notes and Deprecations

1. Check Kubernetes [CHANGELOG](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.31.md) for version you're upgrading to
2. Review [KubeSpray release notes](https://github.com/kubernetes-sigs/kubespray/releases) for your target version
3. Identify deprecated APIs that your workloads might be using:
   ```bash
   # Check for deprecated API usage in the last 7 days
   kubectl get --raw="/apis/apiserver.k8s.io/v1alpha1/removedapi" | jq .
   ```

### 1.5 Prepare Air-Gap Registry

Before upgrading, ensure Harbor contains the new images:

```bash
# Update KubeSpray version
export KUBESPRAY_VERSION="v2.27.0"  # Target version

# Pull new KubeSpray (from internet-connected machine or use existing)
git clone --branch $KUBESPRAY_VERSION --depth 1 https://github.com/kubernetes-sigs/kubespray.git
cd kubespray

# Build container images (if not pre-built)
# In air-gap, use pre-built images from your CI/CD pipeline
# Otherwise:
container/build.py  # Requires internet - do this on connected machine

# Push images to Harbor
# Example script:
for image in $(cat images.txt); do
  docker pull $image
  docker tag $image harbor.internal/$image
  docker push harbor.internal/$image
done
```

### 1.6 Download Required Packages (if not already in Nexus)

Ensure these are available in your Nexus repositories for the target Kubernetes version:
- containerd
- runc
- cni-plugins
- socat, conntrack, ipset, etc.

## Phase 2: Upgrade Procedure

### 2.1 Update KubeSpray

```bash
# Update to target version (on your management/workstation)
cd /path/to/kubespray
git fetch --all
git checkout $KUBESPRAY_VERSION
git pull

# Install/update dependencies
pip install -r requirements.txt

# Copy your inventory to the new version (if upgrading from older clone)
cp -r /path/to/old/inventory/my-cluster ./inventory/
```

### 2.2 Review and Update Inventory Variables

Compare `inventory/sample/group_vars/k8s_cluster.yml` with your existing configuration.
Pay special attention to:
- `kube_version` (should match target Kubernetes version)
- Newly added variables
- Changed variable names or defaults

### 2.3 Run Pre-Upgrade Checks

```bash
# Run the upgrade-check playbook
ansible-playbook -i inventory/my-cluster/hosts.yml \
  upgrade-cluster.yml \
  --tags=prechecks
```

Review the output and fix any issues reported.

### 2.4 Execute Upgrade (Control Plane First)

**Upgrade one master node at a time** to maintain etcd quorum.

```bash
# Upgrade first master (example: master-01)
ansible-playbook -i inventory/my-cluster/hosts.yml \
  upgrade-cluster.yml \
  --limit=etcd[0] \
  --tags=control-plane,node
```

Verify the node is ready:
```bash
kubectl get nodes
# Should show master-01 as Ready
```

Repeat for each remaining master node:
```bash
# For each additional master
ansible-playbook -i inventory/my-cluster/hosts.yml \
  upgrade-cluster.yml \
  --limit=etcd[1] \
  --tags=control-plane,node
```

### 2.5 Upgrade etcd (if version changed)

If the etcd version is changing between Kubernetes versions:
```bash
ansible-playbook -i inventory/my-cluster/hosts.yml \
  upgrade-cluster.yml \
  --tags=etcd
```

### 2.6 Upgrade Worker Nodes

Upgrade workers in batches (max 20% at a time for large clusters):
```bash
# Update first 20% of workers
ansible-playbook -i inventory/my-cluster/hosts.yml \
  upgrade-cluster.yml \
  --limit=kube_node[0:4] \
  --tags=node
```

Monitor progress:
```bash
watch -n 5 "kubectl get nodes | grep -E '(NotReady|Ready)'"
```

Continue with remaining batches until all workers are upgraded.

### 2.7 Upgrade Network Plugin and Other Components

```bash
# Update CNI (Calico in our case)
ansible-playbook -i inventory/my-cluster/hosts.yml \
  upgrade-cluster.yml \
  --tags=network-node

# Update kube-proxy
ansible-playbook -i inventory/my-cluster/hosts.yml \
  upgrade-cluster.yml \
  --tags=kube-proxy
```

## Phase 3: Post-Upgrade Verification

### 3.1 Verify Node Status

```bash
kubectl get nodes
# All nodes should show Ready
kubectl get nodes -o wide
# Check Kubelet and Kube-proxy versions
```

### 3.2 Verify System Pods

```bash
kubectl get pods -n kube-system
# All should be Running or Completed
```

### 3.3 Verify CoreDNS

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl run -it --rm --restart=Never --image=alpine:3.18 dns-test -- nslookup kubernetes.default.svc.cluster.local
```

### 3.4 Verify kube-proxy

```bash
# Check iptables rules on a node
ssh node-01 "iptables -L -t nat | grep KUBE-SVC"
```

### 3.5 Verify Application Functionality

Run your smoke tests or validation scripts:
```bash
# Example: check that ingress controller is working
curl -I https://your-app.internal
# Should return 200 or appropriate redirect

# Check that monitoring is scraping
curl -s http://prometheus.monitoring:9090/api/v1/targets | jq .
```

### 3.6 Verify etcd Version

```bash
ETCDCTL_API=3 etcdctl --endpoints=https://[MASTER_IP]:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  version
```

## Phase 4: Rollback Procedure (If Needed)

> **Warning**: Rollback is complex and should be a last resort. Prefer fixing forward if possible.

### 4.1 When to Rollback
- Control plane instability
- etcd corruption
- Major application incompatibility
- Multiple node failures post-upgrade

### 4.2 Rollback Steps

#### 4.2.1 Stop Kubernetes Services
```bash
# On all nodes
systemctl stop kubelet
systemctl stop containerd
```

#### 4.2.2 Restoref
# Restore etcd data from pre-upgrade backup
# On each master node:
systemctl stop etcd
rm -rf /var/lib/etcd/*
tar -xzf /var/etcd-backup/etcd-data-<hostname>-<timestamp>.tar.gz -C /
systemctl start etcd
```

#### 4.2.3 Revert to Previous KubeSpray Version
```bash
cd /path/to/kubespray
git checkout <previous-version>
git pull
```

#### 4.2.4 Re-run Deployment with Previous Version
```bash
ansible-playbook -i inventory/my-cluster/hosts.yml cluster.yml
```

#### 4.2.5 Validate
Repeat verification steps from Section 3.

## Version-Specific Notes

### v1.29 → v1.30
- Deprecated APIs: 
  - `PodDisruptionBus` policy/v1beta1 → policy/v1
  - `IPAddress` policy/v1alpha1 → removed
- Feature gates changed
- containerd update to v1.7.x

### v1.30 → v1.31
- Dockershim removed long ago, but check for any residual Docker usage
- CSI migration advances
- API priority and fairness graduated to GA
- etcd upgraded to v3.5.x

## Troubleshooting

### Failed Node Join
```bash
# Common causes:
# 1. Certificate mismatch
kubeadm alpha phase certs all
# 2. Container runtime version mismatch
crictl version
# 3. CNI plugin not installed
ls /opt/cni/bin/
# 4. kubelet configuration issues
journalctl -u kubelet -f
```

### etcd Quorum Loss
If you lose quorum during upgrade:
1. Restore from etcd snapshot
2. Rebuild cluster with `--reset=true` if needed
3. Rejoin nodes one by one

### Application Issues Post-Upgrade
1. Check for deprecated API usage in logs
2. Verify PodSecurityPolicy → PodSecurity Standards migration
3. Check admission webhook configurations
4. Validate CNI plugin compatibility

## Maintenance Tips

1. **Regular etcd snapshots**: Automate with cron
2. **Version pinning**: Keep track of exact versions in use
3. **Test upgrades**: Maintain a staging cluster that mirrors production
4. **Document everything**: Keep runbooks updated
5. **Monitor upgrade notifications**: Subscribe to Kubernetes and KubeSpray release announcements

## Appendix: Useful Commands

### Check Component Versions
```bash
# kubelet
kubelet --version
# kubectl
kubectl version --client
# kube-proxy
kube-proxy --version
# containerd
ctr version
# cni
ls /opt/cni/bin/
```

### View Kubernetes Version Skew
```bash
kubectl version
# Shows client and server version
```

### List Nodes by Version
```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{\"\t\"}{.status.nodeInfo.kubeletVersion}{\"\n\"}{end}'
```