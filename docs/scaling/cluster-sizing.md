# Cluster Sizing & Scaling Guide

## Overview

This guide helps you size your clusters based on workload requirements and provides scaling procedures for adding or removing nodes.

> The standard deployment uses 5 masters + 5 workers + 2 LBs per cluster. This guide covers configurations from small (3+2+1) to large (7+10+2).

---

## Cluster Sizing Tiers

### Management Cluster

| Tier | Masters | Workers | LBs | Ceph Mon | Ceph OSD | Use Case |
|------|---------|---------|-----|----------|----------|----------|
| **Minimal** | 3 | 2 | 1 | 3 | 3 | Dev/test, POC |
| **Small** | 3 | 3 | 2 | 3 | 3 | Small production |
| **Standard** | 5 | 5 | 2 | 5 | 5 | Production (default) |
| **Large** | 5 | 10 | 2 | 5 | 10 | High workload |
| **Enterprise** | 7 | 15+ | 2 | 7 | 15+ | Mission-critical |

### Application Cluster

| Tier | Masters | Workers | LBs | Ceph Mon | Ceph OSD | Use Case |
|------|---------|---------|-----|----------|----------|----------|
| **Minimal** | 3 | 3 | 1 | 3 | 3 | Dev/test, POC |
| **Small** | 3 | 5 | 2 | 3 | 3 | Small production |
| **Standard** | 5 | 5 | 2 | 5 | 5 | Production (default) |
| **Large** | 5 | 15 | 2 | 5 | 10 | Many workloads |
| **Enterprise** | 7 | 25+ | 2 | 7 | 15+ | Massive scale |

---

## Node Hardware Sizing

### Master Node Sizing

| Component | Minimal | Standard | Enterprise |
|-----------|---------|----------|------------|
| **CPU** | 4 cores | 8 cores | 16 cores |
| **RAM** | 8 GB | 16 GB | 32 GB |
| **OS Disk** | 50 GB SSD | 100 GB SSD | 200 GB SSD |
| **etcd Disk** | 10 GB SSD | 20 GB NVMe | 50 GB NVMe |
| **Network** | 1 GbE | 10 GbE | 25 GbE |

> **Critical**: etcd disk MUST be on a separate LV/disk. NVMe is strongly recommended. Shared disk with OS causes API server latency under load.

### Worker Node Sizing

| Component | Minimal | Standard | Enterprise |
|-----------|---------|----------|------------|
| **CPU** | 8 cores | 16 cores | 32+ cores |
| **RAM** | 16 GB | 32 GB | 64+ GB |
| **OS Disk** | 50 GB SSD | 100 GB SSD | 200 GB SSD |
| **Data Disk** | — | Optional (Ceph) | Ceph OSD disks |
| **Network** | 1 GbE | 10 GbE | 25 GbE |

### Ceph Monitor Node

| Component | Minimal | Standard | Enterprise |
|-----------|---------|----------|------------|
| **CPU** | 4 cores | 4 cores | 8 cores |
| **RAM** | 8 GB | 16 GB | 32 GB |
| **OS Disk** | 50 GB SSD | 100 GB SSD | 200 GB SSD |
| **Mon Disk** | 10 GB SSD | 20 GB SSD | 50 GB NVMe |
| **Network** | 1 GbE | 10 GbE | 25 GbE |

### Ceph OSD Node

| Component | Minimal | Standard | Enterprise |
|-----------|---------|----------|------------|
| **CPU** | 4 cores | 8 cores | 16 cores |
| **RAM** | 8 GB (1 GB per OSD) | 16 GB | 32+ GB |
| **OS Disk** | 50 GB SSD | 100 GB SSD | 200 GB SSD |
| **OSD Disks** | 1× HDD | 2× HDD + SSD WAL | 4+ HDD + NVMe WAL |
| **WAL/DB Disk** | Shared with OSD | 1 SSD (RocksDB) | 1 NVMe (RocksDB) |
| **Network** | 10 GbE | 10 GbE | 25 GbE |

> **Rule of thumb**: 1 GB RAM per OSD, 0.5 CPU core per OSD. Add 4 GB base for OS.

### Load Balancer Node

| Component | Minimal | Standard | Enterprise |
|-----------|---------|----------|------------|
| **CPU** | 2 cores | 4 cores | 8 cores |
| **RAM** | 4 GB | 8 GB | 16 GB |
| **OS Disk** | 50 GB SSD | 100 GB SSD | 200 GB SSD |
| **Network** | 1 GbE | 10 GbE | 25 GbE |

---

## Resource Allocation by Component

### Management Cluster Resource Estimates

| Component | CPU Request | CPU Limit | RAM Request | RAM Limit | Storage |
|-----------|------------|-----------|-------------|-----------|---------|
| etcd (per master) | 200m | 1 | 512Mi | 2Gi | 20Gi (dedicated disk) |
| K8s API (per master) | 250m | 1 | 512Mi | 2Gi | — |
| K8s Scheduler | 100m | 500m | 256Mi | 1Gi | — |
| K8s Controller Mgr | 200m | 1 | 512Mi | 2Gi | — |
| Calico (per node) | 100m | 500m | 256Mi | 512Mi | — |
| Rancher | 500m | 2 | 1Gi | 4Gi | — |
| ArgoCD Server | 250m | 1 | 512Mi | 2Gi | — |
| ArgoCD Repo Server | 250m | 1 | 512Mi | 2Gi | — |
| ArgoCD Redis | 100m | 500m | 256Mi | 1Gi | — |
| cert-manager | 100m | 500m | 256Mi | 512Mi | — |
| Gatekeeper | 200m | 1 | 512Mi | 1Gi | — |
| Prometheus | 500m | 2 | 2Gi | 8Gi | 50Gi (CephFS PVC) |
| Grafana | 100m | 500m | 256Mi | 1Gi | 5Gi |
| Loki | 250m | 1 | 1Gi | 4Gi | 100Gi (CephFS PVC) |
| Promtail (per node) | 50m | 200m | 128Mi | 256Mi | — |
| Velero | 100m | 500m | 256Mi | 512Mi | — |
| **Total (5-worker)** | ~18 cores | ~45 cores | ~36 Gi | ~120 Gi | ~155 Gi |

### Application Cluster Resource Estimates

| Component | CPU Request | CPU Limit | RAM Request | RAM Limit | Storage |
|-----------|------------|-----------|-------------|-----------|---------|
| etcd (per master) | 200m | 1 | 512Mi | 2Gi | 20Gi |
| K8s Control Plane | 550m | 2.5 | 1.25Gi | 5Gi | — |
| Calico (per node) | 100m | 500m | 256Mi | 512Mi | — |
| MetalLB | 100m | 500m | 256Mi | 512Mi | — |
| NGINX Ingress | 250m | 1 | 512Mi | 2Gi | — |
| cert-manager | 100m | 500m | 256Mi | 512Mi | — |
| Gatekeeper | 200m | 1 | 512Mi | 1Gi | — |
| CephFS CSI | 100m | 500m | 256Mi | 512Mi | — |
| Ceph CSI Provisioner | 100m | 500m | 256Mi | 512Mi | — |
| Prometheus | 500m | 2 | 2Gi | 8Gi | 50Gi |
| Loki | 250m | 1 | 1Gi | 4Gi | 100Gi |
| Promtail (per node) | 50m | 200m | 128Mi | 256Mi | — |
| Velero | 100m | 500m | 256Mi | 512Mi | — |
| **Workloads reserved** | 10+ cores | 20+ cores | 20+ Gi | 40+ Gi | Variable |
| **Total (5-worker)** | ~14 cores | ~32 cores | ~27 Gi | ~66 Gi | ~170 Gi |

---

## Scaling Procedures

### Adding Worker Nodes

#### 1. Prepare the New Node (OS Hardening)

```bash
# Run on new node or via Ansible
./scripts/os-prep/linux-hardening.sh
```

#### 2. Update KubeSpray Inventory

```yaml
# ansible/inventory/app-cluster/hosts.yml
all:
  hosts:
    # ... existing nodes ...
    worker-06:
      ansible_host: 10.0.2.16
      ip: 10.0.2.16
      access_ip: 10.0.2.16
    worker-07:
      ansible_host: 10.0.2.17
      ip: 10.0.2.17
      access_ip: 10.0.2.17
  children:
    kube_node:
      hosts:
        worker-01:
        worker-02:
        worker-03:
        worker-04:
        worker-05:
        worker-06:  # NEW
        worker-07:  # NEW
```

#### 3. Run KubeSpray Scale Playbook

```bash
cd kubespray

# Scale only the new nodes
ansible-playbook -i ../ansible/inventory/app-cluster/hosts.yml \
  --limit worker-06,worker-07 \
  scale.yml
```

#### 4. Label New Nodes

```bash
kubectl label nodes worker-06 node-role.kubernetes.io/worker=true
kubectl label nodes worker-07 node-role.kubernetes.io/worker=true
```

#### 5. Verify

```bash
kubectl get nodes
kubectl describe node worker-06 | grep -A5 "Allocated resources"
```

### Adding Master Nodes (3 → 5)

> **Caution**: Adding masters changes etcd quorum. Plan carefully.

```bash
# 1. Update inventory with new master nodes
# 2. Run KubeSpray scale playbook
ansible-playbook -i ../ansible/inventory/mgmt-cluster/hosts.yml \
  --limit master-04,master-05 \
  scale.yml

# 3. Verify etcd cluster health
kubectl get pods -n kube-system -l component=etcd
ETCDCTL_API=3 etcdctl --endpoints=https://10.0.1.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health --cluster

# 4. Verify API server load balancing
# Check HAProxy stats page for new backends
```

### Adding Ceph OSD Nodes

#### Bare-Metal Ceph

```bash
# On new OSD node, install Ceph packages from Nexus
apt install ceph-osd ceph-common

# Copy ceph.conf and keyring from existing node
scp mon-01:/etc/ceph/ceph.conf /etc/ceph/
scp mon-01:/etc/ceph/ceph.client.admin.keyring /etc/ceph/

# Zap and prepare the OSD disk
ceph-volume lvm zap /dev/sdb --destroy

# Create OSD
ceph-volume lvm create --data /dev/sdb

# Start OSD service
systemctl enable --now ceph-osd@0

# Verify
ceph osd tree
ceph -s
```

#### Rook-Ceph

```yaml
# Update CephCluster CRD to add OSD nodes
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  storage:
    useAllNodes: false
    nodes:
    - name: worker-01
    - name: worker-02
    - name: worker-03
    - name: worker-04
    - name: worker-05
    - name: worker-06  # NEW
    - name: worker-07  # NEW
      devices:
      - name: "sdb"
```

### Removing Nodes

#### Drain and Remove Worker

```bash
# 1. Cordon the node
kubectl cordon worker-06

# 2. Drain workloads
kubectl drain worker-06 --ignore-daemonsets --delete-emptydir-data --grace-period=60

# 3. Verify no workloads remain (except DaemonSets)
kubectl get pods --all-namespaces -o wide | grep worker-06

# 4. Remove from cluster
kubectl delete node worker-06

# 5. Update KubeSpray inventory (remove from hosts.yml)

# 6. Clean up the node (optional)
kubeadm reset -f
rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet
```

---

## Kubernetes Object Limits

### Namespace Resource Quotas

```yaml
# Example: Production namespace quota
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "40"
    requests.memory: 80Gi
    limits.cpu: "80"
    limits.memory: 160Gi
    pods: "200"
    services: "50"
    persistentvolumeclaims: "100"
    requests.storage: "2Ti"
```

### Pod Disruption Budgets (Best Practice)

```yaml
# Every critical deployment should have a PDB
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: rancher-pdb
  namespace: cattle-system
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: rancher
```

---

## Ceph Capacity Planning

### PG Calculator

| OSDs | Replication | PGs per Pool | Total PGs |
|------|------------|-------------|-----------|
| 3 | 3 | 128 | 384 |
| 5 | 3 | 128 | 640 |
| 10 | 3 | 256 | 2560 |
| 15 | 3 | 256 | 3840 |

**Target**: 100-200 PGs per OSD.

### Pool Sizing Examples

| Pool | Purpose | Size | Min Size | PGs (5 OSD) |
|------|---------|------|----------|-------------|
| .mgr | Manager | 3 | 2 | 32 |
| .rgw.root | RGW metadata | 3 | 2 | 32 |
| rbd | K8s block storage | 3 | 2 | 128 |
| cephfs_metadata | CephFS meta | 3 | 2 | 64 |
| cephfs_data | CephFS data | 3 | 2 | 128 |
| rgw.buckets.data | S3 objects | 3 | 2 | 128 |
| rgw.buckets.index | S3 index | 3 | 2 | 64 |

### Raw vs Usable Capacity

```
Usable = Raw × (1 / Replication Factor)

Example: 5 OSDs × 4TB = 20 TB raw
Usable (3x replication) = 20 / 3 = ~6.67 TB
Usable (2x replication) = 20 / 2 = 10 TB (not recommended for production)

With erasure coding (4+2):
Usable = 20 × (4/6) = ~13.3 TB
```

---

## Network IP Planning

### IP Ranges per Cluster

| Network | CIDR | Purpose | Addresses Needed |
|---------|------|---------|-----------------|
| Node Network | 10.0.1.0/24 | Physical nodes | 16-62 |
| K8s Service CIDR | 10.96.0.0/12 | ClusterIP services | 1,048,576 |
| K8s Pod CIDR | 10.244.0.0/16 | Pod IPs | 65,536 |
| MetalLB Pool | 10.0.1.128/25 | LoadBalancer IPs | 128 |
| Ceph Public | 10.0.1.0/24 | Ceph client traffic | Same as node net |
| Ceph Cluster | 10.0.3.0/24 | OSD replication | Separate preferred |

### Multi-Cluster IP Planning

Ensure **no overlap** between clusters:

| Cluster | Node Network | Service CIDR | Pod CIDR |
|---------|-------------|-------------|----------|
| Mgmt Cluster (DC-1) | 10.1.0.0/16 | 10.96.0.0/12 | 10.244.0.0/16 |
| App Cluster (DC-1) | 10.2.0.0/16 | 10.112.0.0/12 | 10.245.0.0/16 |
| Mgmt Cluster (DC-2) | 10.3.0.0/16 | 10.96.0.0/12 | 10.246.0.0/16 |
| App Cluster (DC-2) | 10.4.0.0/16 | 10.112.0.0/12 | 10.247.0.0/16 |
