---
layout: default
title: Technology Wiki
permalink: /technology-wiki.html
---

# Technology Wiki

> Understanding the technologies behind the deployment stack

---

## 1. Kubernetes

### What Is Kubernetes?

Kubernetes (K8s) is an open-source container orchestration platform that automates the deployment, scaling, and management of containerized applications. It was originally developed by Google and is now maintained by the CNCF (Cloud Native Computing Foundation).

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Pod** | Smallest deployable unit — one or more containers sharing network/storage |
| **Deployment** | Declarative updates for pods with rollout/rollback |
| **StatefulSet** | Like Deployment but for stateful apps (stable network IDs, persistent storage) |
| **DaemonSet** | Ensures one pod per node (logging, monitoring agents) |
| **Service** | Stable network endpoint for a set of pods |
| **Ingress** | HTTP/HTTPS routing to services |
| **ConfigMap** | Non-sensitive configuration data |
| **Secret** | Sensitive data (passwords, keys) |
| **Namespace** | Virtual cluster for resource isolation |
| **PersistentVolume** | Cluster-wide storage resource |
| **PersistentVolumeClaim** | User's request for storage |
| **StorageClass** | Defines storage types (SSD, HDD, etc.) |

### Architecture

```
┌─────────────────────────────────────────────────────┐
│ Control Plane                                       │
│                                                     │
│ ┌──────────────────┐                                │
│ │ API Server       │ ← kubectl, dashboard, other   │
│ └──────────────────┘                                │
│ ┌──────────────────┐                                │
│ │ etcd             │ ← Cluster state database       │
│ └──────────────────┘                                │
│ ┌──────────────────┐                                │
│ │ Scheduler        │ ← Assigns pods to nodes        │
│ └──────────────────┘                                │
│ ┌──────────────────┐                                │
│ │ Controller Mgr   │ ← Reconciles desired state     │
│ └──────────────────┘                                │
└─────────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌──────────────────┐  ┌──────────────────┐
│ Worker Node 1    │  │ Worker Node 2    │
│ ┌──────────────┐ │  │ ┌──────────────┐ │
│ │ Kubelet      │ │  │ │ Kubelet      │ │
│ └──────────────┘ │  │ └──────────────┘ │
│ ┌──────────────┐ │  │ ┌──────────────┐ │
│ │ kube-proxy   │ │  │ │ kube-proxy   │ │
│ └──────────────┘ │  │ └──────────────┘ │
│ ┌──────────────┐ │  │ ┌──────────────┐ │
│ │ Container    │ │  │ │ Container    │ │
│ │ Runtime      │ │  │ │ Runtime      │ │
│ └──────────────┘ │  │ └──────────────┘ │
└──────────────────┘  └──────────────────┘
```

---

## 2. Ceph Storage

### What Is Ceph?

Ceph is a unified, distributed storage system designed for excellent performance, reliability, and scalability. It provides object, block, and file storage in a single platform.

### Core Components

| Component | Role |
|-----------|------|
| **MON** (Monitor) | Cluster map, membership, health |
| **MGR** (Manager) | Metrics, dashboard, orchestration |
| **OSD** (Object Storage Daemon) | Stores data, handles replication/recovery |
| **MDS** (Metadata Server) | Metadata for CephFS (file storage) |
| **RGW** (RADOS Gateway) | S3/Swift-compatible object storage API |

### Ceph in Kubernetes (Rook)

```
┌─────────────────────────────────────────────┐
│ Rook Operator                               │
│ ┌─────────────────────────────────────────┐ │
│ │ CephCluster CR                          │ │
│ │ ┌─────────┐ ┌─────────┐ ┌─────────┐     │ │
│ │ │ MON 1   │ │ MON 2   │ │ MON 3   │     │ │
│ │ └─────────┘ └─────────┘ └─────────┘     │ │
│ │ ┌─────────┐ ┌─────────┐ ┌─────────┐     │ │
│ │ │ MGR 1   │ │ MGR 2   │            │     │ │
│ │ └─────────┘ └─────────┘             │     │ │
│ │ ┌─────────┐ ┌─────────┐ ┌─────────┐     │ │
│ │ │ OSD 1   │ │ OSD 2   │ │ OSD 3   │ ... │ │
│ │ └─────────┘ └─────────┘ └─────────┘     │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### Storage Classes

| Storage Class | Use Case |
|---------------|----------|
| `ceph-block` | RBD block storage (databases, VMs) |
| `ceph-block-ec` | Erasure-coded block (cost-efficient) |
| `ceph-filesystem` | CephFS shared file storage |
| `ceph-bucket` | RGW object storage (S3 API) |

---

## 3. MetalLB Load Balancer

### What Is MetalLB?

MetalLB provides a network load-balancer implementation for Kubernetes clusters running on bare metal, without cloud provider support.

### Modes

| Mode | Description |
|------|-------------|
| **Layer 2** | ARP/NDP-based, single-node leader, simple |
| **BGP** | True BGP peering with routers, HA, scalable |

### Configuration Example

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: production-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.100.200-192.168.100.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: production-l2
  namespace: metallb-system
```

---

## 4. HAProxy / Keepalived

### High Availability Load Balancing

| Component | Purpose |
|-----------|---------|
| **HAProxy** | TCP/HTTP load balancing, health checks, SSL termination |
| **Keepalived** | VRRP for virtual IP failover, master/backup election |

### Architecture

```
                    ┌──────────────────┐
                    │  Virtual IP      │
                    │  (VIP: 10.0.0.10)│
                    └────────┬─────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
       ┌──────────────┐               ┌──────────────┐
       │ HAProxy      │               │ HAProxy      │
       │ (Master)     │               │ (Backup)     │
       │ Keepalived   │               │ Keepalived   │
       │ STATE=MASTER │               │ STATE=BACKUP │
       └──────┬───────┘               └──────┬───────┘
              │                              │
              └──────────────┬───────────────┘
                             ▼
                    ┌──────────────────┐
                    │ Backend Servers  │
                    │ (K8s API, Apps)  │
                    └──────────────────┘
```

---

## 5. Monitoring Stack

### Prometheus + Grafana + Alertmanager

| Tool | Role |
|------|------|
| **Prometheus** | Metrics collection, storage, querying (PromQL) |
| **Grafana** | Dashboards, visualization, alerting UI |
| **Alertmanager** | Alert routing, deduplication, silencing |
| **Node Exporter** | Host-level metrics (CPU, memory, disk, network) |
| **kube-state-metrics** | Kubernetes object state metrics |
| **Blackbox Exporter** | Endpoint probing (HTTP, TCP, DNS, ICMP) |

### Key Dashboards

| Dashboard | Purpose |
|-----------|---------|
| Kubernetes Cluster | Cluster health, resource usage, pod status |
| Node Exporter Full | Per-node system metrics |
| Ceph Cluster | OSD health, PG status, capacity |
| MetalLB | IP pool usage, advertisement status |

---

## 6. Security & Compliance

### vSphere Compliance Manager

Automated compliance checking for vSphere environments against:
- **STIG** (Security Technical Implementation Guides)
- **CIS Benchmarks** (Center for Internet Security)
- **PCI-DSS** (Payment Card Industry Data Security Standard)
- **HIPAA** (Health Insurance Portability and Accountability Act)

### Key Features

- Agentless scanning via vSphere API
- Remediation playbooks (Ansible)
- Continuous compliance monitoring
- Drift detection and reporting
- Integration with CI/CD pipelines

---

## 7. Network Topology

### Multi-Segment Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Management Network                       │
│  192.168.100.0/24  (VIPs, HAProxy, Monitoring)              │
└─────────────────────────────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ Control Plane │    │ Worker Nodes  │    │ Storage       │
│ 192.168.10.0/24│    │ 192.168.20.0/24│    │ 192.168.30.0/24│
│               │    │               │    │               │
│ Master 1-3    │    │ Worker 1-N    │    │ Ceph OSDs     │
│ etcd Cluster  │    │ Pods/Services │    │ MON/MGR/MDS   │
│ API Server    │    │ Ingress       │    │ RGW (S3)      │
└───────────────┘    └───────────────┘    └───────────────┘
```

### IP Assignment Strategy

| Segment | CIDR | Purpose |
|---------|------|---------|
| Management | 192.168.100.0/24 | VIPs, LB, Monitoring, GitOps |
| Control Plane | 192.168.10.0/24 | Masters, etcd, API |
| Workers | 192.168.20.0/24 | Worker nodes, workloads |
| Storage | 192.168.30.0/24 | Ceph cluster, replication |
| MetalLB | 192.168.100.200/28 | Service load balancer IPs |

---

## 8. Deployment Workflow

### One-Touch Deployment (Wizard → Production)

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ 1. Wizard    │───▶│ 2. Generate  │───▶│ 3. Ansible   │───▶│ 4. Deploy    │
│ Configure    │    │ Config Files │    │ Playbooks    │    │ Validate     │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
       │                   │                   │                   │
       ▼                   ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ IP Mapping   │    │ YAML Output  │    │ inventory/   │    │ Health       │
│ Per Segment  │    │ (download)   │    │ group_vars/  │    │ Checks       │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
```

### Generated Artifacts

| File | Description |
|------|-------------|
| `inventory/hosts.yml` | Ansible inventory with resolved IPs |
| `group_vars/k8s-cluster.yml` | Kubernetes version, CNI, registry |
| `group_vars/ceph-cluster.yml` | Ceph version, storage devices, pools |
| `group_vars/network.yml` | MetalLB pools, VIPs, DNS |
| `group_vars/security.yml` | STIG profile, hardening level |

---

## 9. Useful Commands

### Cluster Health

```bash
# Kubernetes
kubectl get nodes -o wide
kubectl get pods -A --field-selector=status.phase!=Running

# Ceph
ceph -s
ceph osd tree
ceph df

# MetalLB
kubectl get ipaddresspools -n metallb-system
kubectl get l2advertisements -n metallb-system

# HAProxy/Keepalived
systemctl status haproxy keepalived
ip addr show | grep -A2 "vrrp"
```

### Troubleshooting

```bash
# Check Ansible connectivity
ansible all -m ping -i inventory/hosts.yml

# View playbook output
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v

# Prometheus queries
kubectl port-forward -n monitoring svc/prometheus-operated 9090
# Then query: up{job="kubernetes-nodes"}
```

---

## 10. References

- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [Ceph Documentation](https://docs.ceph.com/)
- [MetalLB Documentation](https://metallb.universe.tf/)
- [Rook Documentation](https://rook.io/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [vSphere Compliance Manager](https://github.com/DavoudTeimouri/vsphere-compliance-manager)

---

*Last updated: {{ site.time | date: "%Y-%m-%d" }}*