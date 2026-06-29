# Architecture Overview

## Table of Contents

- [Design Rationale](#design-rationale)
- [Two-Cluster Architecture](#two-cluster-architecture)
- [Management Cluster](#management-cluster)
- [Application Cluster](#application-cluster)
- [Operations Servers](#operations-servers)
- [Ceph Storage Architecture](#ceph-storage-architecture)
- [Air-Gap Design](#air-gap-design)
- [External Load Balancer Design](#external-load-balancer-design)
- [High Availability Patterns](#high-availability-patterns)
- [Network Topology Overview](#network-topology-overview)

---

## Design Rationale

The two-cluster architecture separates **platform concerns** from **application workloads**, providing:

| Concern | Benefit |
|---------|---------|
| **Isolation** | Platform upgrades/downtime does not affect application workloads |
| **Security** | Management functions are on a dedicated, more tightly controlled cluster |
| **Scalability** | Each cluster can be scaled independently |
| **Operational Clarity** | Clear ownership boundaries between platform and application teams |
| **Compliance** | Easier to audit and enforce policies on separate clusters |
| **Resource Efficiency** | Platform tools don't compete with applications for resources |

### Why Not a Single Cluster?

A single cluster with namespace isolation does not provide:
- True fault isolation during control plane upgrades
- Separate credential management and RBAC boundaries
- Independent lifecycle management
- Clear cost allocation between platform and application teams

---

## Two-Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ENTERPRISE AIR-GAPPED ENVIRONMENT                 │
│                                                                             │
│  ┌──────────────────────────────┐    ┌──────────────────────────────┐      │
│  │     MANAGEMENT CLUSTER       │    │     APPLICATION CLUSTER      │      │
│  │                              │    │                              │      │
│  │  ┌─────┐ ┌─────┐ ┌─────┐   │    │  ┌─────┐ ┌─────┐ ┌─────┐   │      │
│  │  │ M1  │ │ M2  │ │ M3  │   │    │  │ M1  │ │ M2  │ │ M3  │   │      │
│  │  └─────┘ └─────┘ └─────┘   │    │  └─────┘ └─────┘ └─────┘   │      │
│  │  ┌─────┐ ┌─────┐           │    │  ┌─────┐ ┌─────┐           │      │
│  │  │ M4  │ │ M5  │ (Masters) │    │  │ M4  │ │ M5  │ (Masters) │      │
│  │  └─────┘ └─────┘           │    │  └─────┘ └─────┘           │      │
│  │                              │    │                              │      │
│  │  ┌─────┐ ┌─────┐ ┌─────┐   │    │  ┌─────┐ ┌─────┐ ┌─────┐   │      │
│  │  │ W1  │ │ W2  │ │ W3  │   │    │  │ W1  │ │ W2  │ │ W3  │   │      │
│  │  └─────┘ └─────┘ └─────┘   │    │  └─────┘ └─────┘ └─────┘   │      │
│  │  ┌─────┐ ┌─────┐           │    │  ┌─────┐ ┌─────┐           │      │
│  │  │ W4  │ │ W5  │ (Workers) │    │  │ W4  │ │ W5  │ (Workers) │      │
│  │  └─────┘ └─────┘           │    │  └─────┘ └─────┘           │      │
│  │                              │    │                              │      │
│  │  ┌─────┐ ┌─────┐           │    │  ┌─────┐ ┌─────┐           │      │
│  │  │MON1 │ │MON2 │  ... x5   │    │  │MON1 │ │MON2 │  ... x5   │      │
│  │  │OSD1 │ │OSD2 │  ... x5   │    │  │OSD1 │ │OSD2 │  ... x5   │      │
│  │  └─────┘ └─────┘  (Ceph)   │    │  └─────┘ └─────┘  (Ceph)   │      │
│  │                              │    │                              │      │
│  │  Platform Services:          │    │  Platform Services:          │      │
│  │  - Rancher, ArgoCD           │    │  - MetalLB, NGINX Ingress   │      │
│  │  - Prometheus, Grafana, Loki │    │  - CephFS CSI               │      │
│  │  - cert-manager, Gatekeeper  │    │  - cert-manager, Gatekeeper │      │
│  │  - Velero                    │    │                              │      │
│  └──────────────────────────────┘    └──────────────────────────────┘      │
│                                                                             │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────┐  ┌──────────┐       │
│  │ EXT LB (MGMT)  │  │ EXT LB (APP)   │  │OPS Linux │  │OPS Win   │       │
│  │ HAProxy +      │  │ HAProxy +      │  │(Ansible) │  │(Admin)   │       │
│  │ keepalived x2  │  │ keepalived x2  │  │          │  │          │       │
│  └────────────────┘  └────────────────┘  └──────────┘  └──────────┘       │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │              AIR-GAP INFRASTRUCTURE                               │      │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │      │
│  │  │    NEXUS     │  │   HARBOR     │  │  INTERNAL DNS/DHCP   │   │      │
│  │  │  (Artifacts) │  │  (Registry)  │  │  (BIND9/Windows DNS) │   │      │
│  │  └──────────────┘  └──────────────┘  └──────────────────────┘   │      │
│  └──────────────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Management Cluster

### Node Layout

| Role | Count | CPU (min) | RAM (min) | Disk | Network |
|------|-------|-----------|-----------|------|---------|
| Master | 5 | 8 cores | 16 GB | 100 GB OS + 50 GB etcd | 10GbE |
| Worker | 5 | 16 cores | 32 GB | 200 GB OS + Ceph OSDs | 10GbE |
| External LB | 2 | 4 cores | 8 GB | 100 GB SSD | 10GbE |
| Ceph MON | 5 | 4 cores | 8 GB | 100 GB SSD (RocksDB/WAL) | 10GbE |
| Ceph OSD | 5 | 8 cores | 16 GB | 100 GB OS + 1+ TB OSD disk | 10GbE/25GbE |

### Components Deployed

| Component | Namespace | Purpose | HA Mode |
|-----------|-----------|---------|---------|
| Rancher | cattle-system | Multi-cluster management UI | Active-Passive (2 replicas) |
| ArgoCD | argocd | GitOps CD, cluster management | Active-Active (3 replicas) |
| cert-manager | cert-manager | Automatic TLS certificates | Active-Passive (2 replicas) |
| Gatekeeper | gatekeeper-system | Policy enforcement (OPA) | Active-Active (3 replicas) |
| Prometheus | monitoring | Metrics collection | 2 replicas (HA pair) |
| Grafana | monitoring | Dashboards | Active-Passive (2 replicas) |
| Loki | logging | Log aggregation | Active-Active (3 replicas) |
| Velero | velero | Backup/restore | Single instance + scheduled backups |
| Rook-Ceph (or bare Ceph) | rook-ceph | Storage orchestration | 5 MONs, 5 OSDs |

### Master Node Configuration

- **etcd**: Dedicated 50 GB SSD partition per master (low-latency, high-IOPS)
- **kube-apiserver**: Accessed via external HAProxy VIP (port 6443)
- **kube-scheduler / kube-controller-manager**: Leader-elected
- **cloud-controller-manager**: Not used (bare-metal)

### Worker Node Configuration

- **containerd**: Container runtime with air-gap registry configuration
- **Calico**: VXLAN or BGP CNI
- **Ceph CSI**: RBD and CephFS provisioner
- **Node labels**: `role=platform`, `storage=ceph`

---

## Application Cluster

### Node Layout

| Role | Count | CPU (min) | RAM (min) | Disk | Network |
|------|-------|-----------|-----------|------|---------|
| Master | 5 | 8 cores | 16 GB | 100 GB OS + 50 GB etcd | 10GbE |
| Worker | 5 | 16 cores | 32 GB | 200 GB OS + Ceph OSDs | 10GbE |
| External LB | 2 | 4 cores | 8 GB | 100 GB SSD | 10GbE |
| Ceph MON | 5 | 4 cores | 8 GB | 100 GB SSD (RocksDB/WAL) | 10GbE |
| Ceph OSD | 5 | 8 cores | 16 GB | 100 GB OS + 1+ TB OSD disk | 10GbE/25GbE |

### Components Deployed

| Component | Namespace | Purpose | HA Mode |
|-----------|-----------|---------|---------|
| MetalLB | metallb-system | Bare-metal LoadBalancer | BGP/ARP mode |
| NGINX Ingress | ingress-nginx | HTTP/HTTPS ingress | DaemonSet (per-node) |
| CephFS CSI | kube-system | CephFS persistent volumes | Deployment (2 replicas) |
| cert-manager | cert-manager | Automatic TLS certificates | Active-Passive (2 replicas) |
| Gatekeeper | gatekeeper-system | Policy enforcement (OPA) | Active-Active (3 replicas) |
| bare Ceph (or Rook-Ceph) | ceph | Storage cluster | 5 MONs, 5 OSDs |

### Master Node Configuration

- Same as Management Cluster masters
- Accessed via separate HAProxy VIP

### Worker Node Configuration

- **MetalLB**: Configured with IP pool from service subnet
- **NGINX Ingress**: DaemonSet with hostNetwork or MetalLB LoadBalancer
- **Ceph CSI**: For dynamic provisioning of CephFS/RBD volumes
- **Node labels**: `role=application`, `storage=ceph`, `ingress=nginx`

---

## Operations Servers

### Linux Operations Server

| Specification | Value |
|---------------|-------|
| OS | Ubuntu 22.04 LTS |
| CPU | 8 cores minimum |
| RAM | 16 GB minimum |
| Disk | 500 GB SSD |
| Network | 10GbE |
| Purpose | KubeSpray/Ansible control node, deployment scripts, kubectl admin |

**Installed Tools:**
- Ansible $ANSIBLE_VERSION
- KubeSpray (cloned repository)
- kubectl $K8S_VERSION
- helm $HELM_VERSION
- Ceph CLI tools
- Python 3.x + pip packages
- Git

### Windows Operations Server

| Specification | Value |
|---------------|-------|
| OS | Windows Server 2022 |
| CPU | 4 cores minimum |
| RAM | 8 GB minimum |
| Disk | 256 GB SSD |
| Network | 10GbE |
| Purpose | Active Directory, Windows DNS, Windows admin tools |

**Installed Tools:**
- RSAT (Remote Server Administration Tools)
- Active Directory Users and Computers
- DNS Manager
- Windows Admin Center
- PowerShell 7.x

---

## Ceph Storage Architecture

### Design Principles

- **No Load Balancer for Ceph**: Ceph clients connect directly to MONs and OSDs
- **Separate Networks**: Public network (client ↔ cluster) and cluster network (OSD replication)
- **Minimum 3 MONs for quorum**: We use 5 for enhanced HA
- **CRUSH Map**: Custom failure domain (rack/host) for data distribution

### Ceph Cluster Layout (Per Cluster)

| Component | Count | Placement |
|-----------|-------|-----------|
| Ceph MON | 5 | Co-located on worker nodes or dedicated |
| Ceph MGR | 2 | Co-located with MONs |
| Ceph OSD | 5 | One per worker node (minimum) |
| Ceph MDS | 2 | For CephFS (active-passive) |
| RBD | Default | Block storage for PVCs |
| CephFS | Default | File storage for shared volumes |
| RGW | Optional | Object storage (S3-compatible) |

### Ceph Configuration

```ini
[global]
fsid = <cluster-uuid>
mon_initial_members = mon1,mon2,mon3,mon4,mon5
mon_host = 10.0.10.11,10.0.10.12,10.0.10.13,10.0.10.14,10.0.10.15
public_network = 10.0.10.0/24
cluster_network = 10.0.11.0/24
auth_cluster_required = cephx
auth_service_required = cephx
auth_client_required = cephx
osd_pool_default_size = 3
osd_pool_default_min_size = 2
osd_pool_default_pg_num = 128
osd_pool_default_pgp_num = 128
```

### Storage Classes

| Storage Class | Type | Use Case | Reclaim Policy |
|---------------|------|----------|----------------|
| ceph-rbd | Block (RBD) | Databases, stateful apps | Delete |
| cephfs | File (CephFS) | Shared volumes, CI/CD | Delete |
| ceph-rbd-ssd | Block (RBD, SSD pool) | High-performance DB | Retain |

---

## Air-Gap Design

### Artifact Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    AIR-GAP BOUNDARY                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              NEXUS REPOSITORY MANAGER                     │   │
│  │                                                         │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │   │
│  │  │  apt     │ │  docker  │ │  helm    │ │  generic │  │   │
│  │  │ (hosted) │ │ (hosted) │ │ (hosted) │ │ (hosted) │  │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘  │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐               │   │
│  │  │  pip     │ │  yum     │ │  raw     │               │   │
│  │  │ (hosted) │ │ (hosted) │ │ (hosted) │               │   │
│  │  └──────────┘ └──────────┘ └──────────┘               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 HARBOR REGISTRY                           │   │
│  │                                                         │   │
│  │  ┌────────────────┐ ┌────────────────┐                 │   │
│  │  │  k8s.gcr.io    │ │  quay.io       │                 │   │
│  │  │  (proxy repo)  │ │  (proxy repo)  │                 │   │
│  │  └────────────────┘ └────────────────┘                 │   │
│  │  ┌────────────────┐ ┌────────────────┐                 │   │
│  │  │  docker.io     │ │  gcr.io        │                 │   │
│  │  │  (proxy repo)  │ │  (proxy repo)  │                 │   │
│  │  └────────────────┘ └────────────────┘                 │   │
│  │  ┌────────────────┐                                    │   │
│  │  │  charts/       │  (Helm chart proxy)                │   │
│  │  └────────────────┘                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              INTERNAL DNS (BIND9 / Windows DNS)          │   │
│  │                                                         │   │
│  │  Zone: corp.internal                                    │   │
│  │  - nexus.corp.internal                                  │   │
│  │  - harbor.corp.internal                                 │   │
│  │  - *.apps.corp.internal                                 │   │
│  │  - api.mgmt.corp.internal                               │   │
│  │  - api.app.corp.internal                                │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Nexus Repository Types

| Repository Name | Type | Format | Purpose |
|----------------|------|--------|---------|
| ubuntu-22.04 | hosted | apt | Ubuntu packages |
| ubuntu-22.04-security | hosted | apt | Ubuntu security updates |
| ceph-reef | hosted | apt | Ceph Reef packages |
| ceph-quincy | hosted | apt | Ceph Quincy packages |
| docker-hosted | hosted | docker | Custom/internal images |
| k8s-gcr | proxy | docker | k8s.gcr.io mirror |
| quay-io | proxy | docker | quay.io mirror |
| docker-hub | proxy | docker | Docker Hub mirror |
-helm-charts | hosted | helm | Internal Helm charts |
| helm-proxy | proxy | helm | External Helm chart mirror |
| pypi-hosted | hosted | pip | Internal Python packages |
| pypi-proxy | proxy | pip | PyPI mirror |
| raw-hosted | hosted | raw | KubeSpray binaries, kubeadm, etc. |

### Harbor Project Structure

| Project | Purpose | Repositories |
|---------|---------|-------------|
| k8s | Kubernetes system images | 50+ images |
| ceph | Ceph storage images | 10+ images |
| platform | Platform tool images | 30+ images |
| system | OS-level tools, debugging | 20+ images |
| charts | Helm chart mirror | 15+ charts |

---

## External Load Balancer Design

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                 EXTERNAL LOAD BALANCER PAIR                      │
│                                                                 │
│  ┌─────────────────────────┐  ┌─────────────────────────┐      │
│  │      LB-MGMT-01         │  │      LB-MGMT-02         │      │
│  │                         │  │                         │      │
│  │  HAProxy (active)       │  │  HAProxy (standby)      │      │
│  │  keepalived (MASTER)    │  │  keepalived (BACKUP)    │      │
│  │  VIP: 10.0.1.10         │  │  VIP: 10.0.1.10         │      │
│  │  RIP: 10.0.1.11         │  │  RIP: 10.0.1.12         │      │
│  └─────────────────────────┘  └─────────────────────────┘      │
│                                                                 │
│  Services Load Balanced:                                        │
│  - K8s API Server (TCP 6443)                                   │
│  - Rancher UI (TCP 443)                                        │
│  - ArgoCD UI (TCP 443)                                         │
│  - Grafana (TCP 443)                                           │
│  - Prometheus (TCP 443)                                        │
│  - Harbor (TCP 443)                                            │
│  - Nexus (TCP 443)                                             │
└─────────────────────────────────────────────────────────────────┘
```

### HAProxy Configuration

```haproxy
global
    log /dev/log local0
    maxconn 4096
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client 30s
    timeout server 30s

# Kubernetes API Server
frontend k8s-api
    bind *:6443
    default_backend k8s-masters

backend k8s-masters
    balance roundrobin
    option tcp-check
    server mgmt-master1 10.0.2.11:6443 check
    server mgmt-master2 10.0.2.12:6443 check
    server mgmt-master3 10.0.2.13:6443 check
    server mgmt-master4 10.0.2.14:6443 check
    server mgmt-master5 10.0.2.15:6443 check

# HTTPS Services (TCP passthrough)
frontend https-services
    bind *:443
    mode tcp
    option tcplog
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    use_backend rancher if { req_ssl_sni -i rancher.corp.internal }
    use_backend argocd if { req_ssl_sni -i argocd.corp.internal }
    use_backend grafana if { req_ssl_sni -i grafana.corp.internal }
    use_backend prometheus if { req_ssl_sni -i prometheus.corp.internal }
    use_backend harbor if { req_ssl_sni -i harbor.corp.internal }
    use_backend nexus if { req_ssl_sni -i nexus.corp.internal }
    default_backend ingress-nginx

backend rancher
    mode tcp
    server rancher-vip 10.0.2.20:443 check

backend argocd
    mode tcp
    server argocd-vip 10.0.2.21:443 check

backend grafana
    mode tcp
    server grafana-vip 10.0.2.22:443 check

backend prometheus
    mode tcp
    server prometheus-vip 10.0.2.23:443 check

backend harbor
    mode tcp
    server harbor-vip 10.0.3.10:443 check

backend nexus
    mode tcp
    server nexus-vip 10.0.3.11:443 check

backend ingress-nginx
    mode tcp
    server app-worker1 10.0.4.21:443 check
    server app-worker2 10.0.4.22:443 check
    server app-worker3 10.0.4.23:443 check
    server app-worker4 10.0.4.24:443 check
    server app-worker5 10.0.4.25:443 check
```

### keepalived Configuration

```conf
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass <secret>
    }

    virtual_ipaddress {
        10.0.1.10/24
    }

    notify_master "/usr/local/bin/haproxy-notify.sh MASTER"
    notify_backup "/usr/local/bin/haproxy-notify.sh BACKUP"
    notify_fault "/usr/local/bin/haproxy-notify.sh FAULT"
}
```

---

## High Availability Patterns

### Control Plane HA

| Component | HA Mechanism | Failover Time |
|-----------|-------------|---------------|
| kube-apiserver | HAProxy + 5 instances | < 30s (health check interval) |
| kube-scheduler | Leader election | < 10s |
| kube-controller-manager | Leader election | < 10s |
| etcd | Raft consensus (5 members) | < 5s (with pre-vote) |
| CoreDNS | 2 replicas + HPA | Transparent |

### Data Plane HA

| Component | HA Mechanism | Failover Time |
|-----------|-------------|---------------|
| Ceph MON | 5-node quorum | < 30s |
| Ceph OSD | Replicated PGs (size=3) | < 60s (recovery) |
| Prometheus | 2 replicas + remote write | < 15s |
| ArgoCD | 3 replicas | < 10s |
| Rancher | 2 replicas | < 30s |
| MetalLB | BGP/ARP | < 5s |
| HAProxy | keepalived VRRP | < 3s |

### Failure Domains

| Domain | Impact | Mitigation |
|--------|--------|------------|
| Single master failure | No API disruption | 4 remaining masters |
| Single worker failure | Workloads rescheduled | Pod anti-affinity |
| Single LB failure | Traffic rerouted | keepalived VIP failover |
| Single MON failure | Ceph continues | 4/5 quorum maintained |
| Single OSD failure | PGs re-replicated | size=3, min_size=2 |
| Rack failure | Reduced capacity | CRUSH map host/rack rules |
| Network partition | Split-brain prevention | etcd quorum, STONITH |

---

## Network Topology Overview

### Subnet Allocation

| Subnet | CIDR | VLAN | Purpose |
|--------|------|------|---------|
| Management | 10.0.0.0/24 | 100 | Server management (IPMI/iDRAC/iLO) |
| Infrastructure | 10.0.1.0/24 | 101 | External LB VIPs, infrastructure services |
| Masters (Mgmt) | 10.0.2.0/24 | 102 | Management cluster master nodes |
| Workers (Mgmt) | 10.0.3.0/24 | 103 | Management cluster worker nodes |
| Masters (App) | 10.0.4.0/24 | 104 | Application cluster master nodes |
| Workers (App) | 10.0.5.0/24 | 105 | Application cluster worker nodes |
| Ceph Public | 10.0.10.0/24 | 110 | Ceph client communication |
| Ceph Cluster | 10.0.11.0/24 | 111 | Ceph OSD replication |
| Kubernetes Pod (Mgmt) | 10.1.0.0/16 | N/A | Pod network (Calico) |
| Kubernetes Pod (App) | 10.2.0.0/16 | N/A | Pod network (Calico) |
| Kubernetes Service (Mgmt) | 10.0.20.0/24 | N/A | ClusterIP range |
| Kubernetes Service (App) | 10.0.21.0/24 | N/A | ClusterIP range |
| MetalLB Pool | 10.0.30.0/24 | N/A | LoadBalancer IPs |

### Network Flows

| Flow | Path | Protocol |
|------|------|----------|
| kubectl → API | Client → HAProxy VIP → Master | TCP 6443 |
| Pod → API | Pod → Service → Master | TCP 6443 |
| External → Ingress | Client → HAProxy → NGINX Ingress → Pod | TCP 80/443 |
| Pod → Ceph | Pod → Ceph Public Network → OSD | Ceph Protocol |
| OSD → OSD | OSD → Ceph Cluster Network → OSD | Ceph Protocol |
| Monitoring scrape | Prometheus → Node Exporter | TCP 9100 |
| Log shipping | Promtail → Loki | HTTP 3100 |

---

## Summary

This architecture provides a production-grade, air-gapped Kubernetes deployment with:

- **Full redundancy** at every layer (compute, network, storage)
- **Clear separation** between platform and application concerns
- **Enterprise storage** via Ceph with network-level isolation
- **Zero external dependency** through Nexus + Harbor artifact management
- **Automated failover** via HAProxy + keepalived + Kubernetes HA mechanisms
- **Compliance-ready** with Gatekeeper policy enforcement
