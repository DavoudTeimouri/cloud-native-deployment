# Technology Wiki

> Understanding the technologies behind the deployment stack

---

## 1. Kubernetes

### What Is Kubernetes?

Kubernetes (K8s) is an open-source container orchestration platform that
automates the deployment, scaling, and management of containerized
applications. It was originally developed by Google and is now maintained by
the CNCF (Cloud Native Computing Foundation).

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
│ Control Plane │
│ │
│ ┌──────────────────┐ │
│ │ API Server │ ← kubectl, dashboard, other components │
│ └──────────────────┘ │
│ ┌──────────────────┐ │
│ │ etcd │ ← Cluster state database │
│ └──────────────────┘ │
│ ┌──────────────────┐ │
│ │ Scheduler │ ← Assigns pods to nodes │
│ └──────────────────┘ │
│ ┌──────────────────┐ │
│ │ Controller Mgr │ ← Reconciles desired state │
│ └──────────────────┘ │
└─────────────────────────────────────────────────────┘
│
┌─────────────────────────────────────────────────────┐
│ Worker Node │
│ │
│ ┌──────────────────┐ │
│ │ kubelet │ ← Talks to API server, manages pods │
│ └──────────────────┘ │
│ ┌──────────────────┐ │
│ │ kube-proxy │ ← Network rules (iptables/IPVS) │
│ └──────────────────┘ │
│ ┌──────────────────┐ │
│ │ Container Runtime │ ← containerd, CRI-O │
│ └──────────────────┘ │
│ │
│ ┌─────┐ ┌─────┐ ┌─────┐ │
│ │Pod 1│ │Pod 2│ │Pod 3│ │
│ └─────┘ └─────┘ └─────┘ │
└─────────────────────────────────────────────────────┘
```

### Why KubeSpray?

KubeSpray uses Ansible to deploy Kubernetes. It's chosen because:

- **Bare-metal/VM focused**: Works on any infrastructure
- **Highly configurable**: Every component is customizable
- **Supports any CNI**: Calico, Cilium, Flannel, etc.
- **Production-grade**: Used by enterprises worldwide
- **Air-gap friendly**: Can deploy without internet access
- **CNCF certified**: Passes conformance tests

### Why Not Other Installers?

| Installer | Why Not Using |
|-----------|--------------|
| kubeadm | Manual, no automation for multiple nodes |
| RKE/RKE2 | Tied to Rancher ecosystem |
| EKS/AKS/GKE | Cloud-only, not for air-gapped |
| OpenShift | Heavier, licensing costs |
| K3s | Lightweight but limited for large production |

---

## 2. Ceph

### What Is Ceph?

Ceph is a distributed storage platform that provides object, block, and
file storage from a single cluster. It's designed for scalability,
reliability, and performance without a single point of failure.

### Core Concepts

| Concept | Description |
|---------|-------------|
| **OSD** | Object Storage Daemon — stores data, handles replication |
| **MON** | Monitor — maintains cluster map and health |
| **MDS** | Metadata Server — for CephFS (filesystem) |
| **PG** | Placement Group — how data is distributed across OSDs |
| **Pool** | Logical partition of storage |
| **RBD** | RADOS Block Device — block storage for VMs/containers |
| **CephFS** | POSIX-compliant filesystem |
| **RGW** | RADOS Gateway — S3-compatible object storage |
| **CRUSH** | Algorithm that determines data placement |

### Architecture

```
┌─────────────────────────────────────────────────────┐
│ Ceph Client │
│ (RBD, CephFS, RGW) │
└──────────────────────┬──────────────────────────────┘
│
┌──────────────────────┴──────────────────────────────┐
│ Ceph Cluster │
│ │
│ ┌─────┐ ┌─────┐ ┌─────┐ │
│ │MON 1│ │MON 2│ │MON 3│ ← Cluster state, consensus │
│ └─────┘ └─────┘ └─────┘ │
│ │
│ ┌──────────────────────────────────────────────┐ │
│ │ CRUSH Map │ ← Data placement rules │
│ └──────────────────────────────────────────────┘ │
│ │
│ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ │
│ │OSD 1│ │OSD 2│ │OSD 3│ │OSD 4│ │OSD 5│ ← Data storage │
│ │HDD │ │HDD │ │SSD │ │SSD │ │NVMe │ │
│ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ │
│ │
│ ┌─────┐ ┌─────┐ │
│ │MDS 1│ │MDS 2│ ← CephFS metadata │
│ └─────┘ └─────┘ │
│ │
│ ┌─────┐ │
│ │RGW │ ← S3-compatible object storage │
│ └─────┘ │
└─────────────────────────────────────────────────────┘
```

### Why Ceph?

| Feature | Benefit |
|---------|---------|
| **Unified storage** | Block (RBD), file (CephFS), object (RGW) in one cluster |
| **Self-healing** | Automatic data rebalancing when OSD fails |
| **Scalability** | Petabytes+ with no single point of failure |
| **No vendor lock-in** | Open source, runs on commodity hardware |
| **Kubernetes integration** | CSI driver for persistent volumes |
| **Tiering** | SSD for hot data, HDD for cold data |

### Alternatives

| Alternative | When to Use |
|-------------|-------------|
| **MinIO** | Object-only storage, simpler, lighter |
| **Longhorn** | Lightweight block storage for K8s only |
| **GlusterFS** | File storage only, simpler than Ceph |
| **NFS** | Simple shared storage, no replication |
| **Local Path** | Single-node storage, no replication |

---

## 3. Calico

### What Is Calico?

Calico is a container networking interface (CNI) plugin that provides
networking and network policy enforcement for Kubernetes. It's the most
widely used CNI in production.

### How It Works

```
Without Calico:
  Pod A (Node 1) ──X── Pod B (Node 2)  (no cross-node communication)

With Calico:
  Pod A (Node 1) ──tunnel── Pod B (Node 2)  (routed via BGP/IPIP)
```

### Key Features

| Feature | Description |
|---------|-------------|
| **BGP peering** | Routes pod traffic between nodes using Border Gateway Protocol |
| **Network policies** | Fine-grained traffic control (who can talk to whom) |
| **IPIP tunneling** | Encapsulates traffic between subnets |
| **VXLAN** | Alternative overlay for cloud environments |
| **eBPF mode** | High-performance datapath (alternative to iptables) |
| **WireGuard** | Encryption of node-to-node traffic |

### Why Calico?

| Feature | Calico | Flannel | Cilium |
|---------|--------|---------|--------|
| Network policies | ✅ Full | ❌ | ✅ Full |
| BGP support | ✅ | ❌ | ✅ |
| Performance | High | High | Highest (eBPF) |
| Complexity | Medium | Low | Medium-High |
| Maturity | Very mature | Mature | Growing |

---

## 4. Ansible

### What Is Ansible?

Ansible is an open-source automation tool for configuration management,
application deployment, and orchestration. It uses YAML playbooks and
connects to target machines via SSH.

### How It Works

```
┌──────────────────┐
│ Control Node │
│ │
│ ┌──────────────┐ │
│ │ Playbook │ │
│ │ (YAML) │ │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Inventory │ │
│ │ (hosts) │ │
│ └──────────────┘ │
└────────┬─────────┘
│ SSH
┌────────┴─────────┐
│ Target Nodes │
│ │
│ ┌─────┐ ┌─────┐ │
│ │Node 1│ │Node 2│ │
│ └─────┘ └─────┘ │
└──────────────────┘
```

### Why Ansible?

| Feature | Benefit |
|---------|---------|
| **Agentless** | No software to install on targets (uses SSH) |
| **YAML syntax** | Human-readable, easy to learn |
| **Idempotent** | Running same playbook twice = same result |
| **Modular** | 3000+ modules for any task |
| **Air-gap friendly** | No internet required during execution |
| **Community** | Huge ecosystem of roles and collections |

---

## 5. Prometheus & Grafana

### Prometheus

Prometheus is a monitoring and alerting toolkit. It collects metrics from
instrumented targets, stores time-series data, and provides a query language
(PromQL).

```
┌─────────────────────────────────────────────────────┐
│ Prometheus Server │
│ │
│ ┌──────────────┐ │
│ │ Scraper │ ← Pulls metrics from targets │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ TSDB │ ← Time-series database │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ PromQL │ ← Query language │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Alertmanager │ ← Sends alerts │
│ └──────────────┘ │
└─────────────────────────────────────────────────────┘
│
│ Pulls metrics from:
│
┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
│Node │ │Kube │ │Ceph │ │App │
│Exp. │ │State │ │Exp. │ │App. │
└──────┘ └──────┘ └──────┘ └──────┘
```

### Grafana

Grafana is a visualization platform that connects to Prometheus (and other
datasources) to create dashboards.

### Why Prometheus + Grafana?

| Feature | Benefit |
|---------|---------|
| **Pull-based** | Prometheus scrapes metrics (no need to push) |
| **Dimensional data** | Metrics with labels (namespace, pod, node, etc.) |
| **Powerful queries** | PromQL for complex aggregation and filtering |
| **Service discovery** | Auto-discovers K8s pods, services, nodes |
| **Alerting** | Alertmanager for routing, grouping, silencing |
| **Dashboards** | Grafana for visualization, K8s dashboard for quick view |

---

## 6. Loki

### What Is Loki?

Loki is a horizontally scalable, highly available log aggregation system
inspired by Prometheus. It indexes labels (like Prometheus) not full text,
making it much cheaper to operate.

### Architecture

```
┌─────────────────────────────────────────────────────┐
│ Loki │
│ │
│ ┌──────────────┐ │
│ │ Promtail │ ← Collects logs from containers │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Distributor │ ← Receives log streams │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Ingester │ ← Writes to storage │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Querier │ ← Handles LogQL queries │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Storage │ ← S3/MinIO/GCS │
│ └──────────────┘ │
└─────────────────────────────────────────────────────┘
```

### Why Loki Over ELK?

| Feature | Loki | ELK (Elasticsearch) |
|---------|------|---------------------|
| **Resource usage** | Low | High (JVM heap) |
| **Log indexing** | Labels only | Full text |
| **Query language** | LogQL | Lucene/Kibana |
| **Complexity** | Low | High |
| **Storage** | Object storage | Local SSD |
| **K8s integration** | Native (Promtail) | Manual |

---

## 7. Velero

### What Is Velero?

Velero is a backup and disaster recovery tool for Kubernetes. It backs up
cluster resources and persistent volumes, and can restore to the same or
different cluster.

### How It Works

```
┌─────────────────────────────────────────────────────┐
│ Velero Server │
│ │
│ ┌──────────────┐ │
│ │ Backup │ ← Backs up K8s resources + volumes │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Schedule │ ← Cron-based automatic backups │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Restore │ ← Restores from backup │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Restic │ ← Backs up PV data to S3 │
│ └──────────────┘ │
└──────────────────────┬──────────────────────────────┘
│
│ Writes to:
│
┌──────────────────────┴──────────────────────────────┐
│ Object Storage (S3) │
│ │
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│ │Backups │ │Manifests │ │Volumes │ │
│ └──────────┘ └──────────┘ └──────────┘ │
└─────────────────────────────────────────────────────┘
```

---

## 8. Rancher

### What Is Rancher?

Rancher is a complete software platform for organizations that deploy
containers in production. It makes it easy to manage multiple Kubernetes
clusters across different infrastructures.

### Key Features

| Feature | Description |
|---------|-------------|
| **Multi-cluster management** | Manage many clusters from one UI |
| **Cluster provisioning** | Create EKS, GKE, AKS, or custom clusters |
| **RBAC** | Role-based access control per cluster/project |
| **Catalogs** | Helm chart catalog for one-click deploys |
| **Monitoring** | Built-in Prometheus/Grafana |
| **Istio** | Service mesh integration |
| **Fleet** | GitOps at scale across clusters |

---

## 9. ArgoCD

### What Is ArgoCD?

ArgoCD is a declarative GitOps continuous delivery tool for Kubernetes.
It watches a Git repository and automatically syncs the desired state to
the cluster.

### How It Works

```
Git Repository (desired state)
        │
        │ (watches via webhook or polling)
        ▼
┌──────────────────┐
│ ArgoCD │
│ │
│ ┌──────────────┐ │
│ │ Application │ ← Defines source + destination │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Repo Server │ ← Renders Helm/Kustomize │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ App Controller│ ← Syncs desired → actual │
│ └──────────────┘ │
└──────────────────┘
        │
        │ (deploys to)
        ▼
Kubernetes Cluster (actual state)
```

### Why GitOps?

| Feature | Benefit |
|---------|---------|
| **Git as single source of truth** | All changes tracked in Git |
| **Automatic sync** | Drift detection and correction |
| **Rollback** | Git revert = instant rollback |
| **Audit trail** | Who changed what, when (Git history) |
| **Declarative** | Describe desired state, system makes it happen |

---

## 10. cert-manager

### What Is cert-manager?

cert-manager is a Kubernetes addon to automate the management and issuance
of TLS certificates from various issuing sources (Let's Encrypt, Vault,
self-signed, etc.).

### How It Works

```
┌─────────────────────────────────────────────────────┐
│ cert-manager │
│ │
│ ┌──────────────┐ │
│ │ Certificate │ ← K8s resource requesting a cert │
│ │ CRD │ │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Issuer │ ← Who issues the cert │
│ │ │ │
│ │ - Let's Encrypt │ │
│ │ - Vault │ │
│ │ - Self-signed │ │
│ │ - CA │ │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Order/Challenge│ ← ACME protocol │
│ └──────────────┘ │
└─────────────────────────────────────────────────────┘
```

---

## 11. MetalLB

### What Is MetalLB?

MetalLB is a load-balancer implementation for bare-metal Kubernetes clusters.
It provides LoadBalancer type services (normally only available in cloud
providers).

### How It Works

```
Without MetalLB:
  Service type: ClusterIP (internal only)
  External clients cannot reach services

With MetalLB:
  Service type: LoadBalancer
  MetalLB assigns an IP from the pool
  External clients can reach services via that IP
```

### Modes

| Mode | Protocol | Use Case |
|------|----------|----------|
| **Layer 2** | ARP/NDP | Simple, works on any network |
| **BGP** | Border Gateway Protocol | Production, scalable, multi-router |

---

## 12. NGINX Ingress

### What Is Ingress?

Ingress is a Kubernetes resource that manages external access to services
in a cluster, typically HTTP/HTTPS. An Ingress controller (NGINX) implements
the rules.

### Key Features

| Feature | Description |
|---------|-------------|
| **Host-based routing** | Route traffic by hostname |
| **Path-based routing** | Route traffic by URL path |
| **TLS termination** | SSL/TLS at the edge |
| **Rate limiting** | Limit requests per client |
| **Rewrite rules** | Modify request paths |
| **Authentication** | Basic auth, OAuth, OIDC |

---

## 13. Kyverno / Gatekeeper

### What Are Policy Engines?

Policy engines enforce rules about what can run in your cluster. They can
validate (block bad resources) and mutate (modify resources before creation).

### Comparison

| Feature | Kyverno | Gatekeeper |
|---------|---------|------------|
| **Language** | YAML | Rego (OPA) |
| **Mutating** | ✅ Built-in | Separate extension |
| **Generating** | ✅ Built-in | ❌ |
| **Background scan** | ✅ | ✅ |
| **Learning curve** | Low | High |
| **Expressiveness** | Medium | Very high |

---

## 14. GitLab

### What Is GitLab?

GitLab is a complete DevOps platform delivered as a single application. It
provides source control, CI/CD, container registry, security scanning, and
more.

### Key Components

| Component | Description |
|-----------|-------------|
| **Git** | Source control management |
| **CI/CD** | Pipelines for build, test, deploy |
| **Container Registry** | Built-in Docker registry |
| **Pages** | Static website hosting |
| **Wiki** | Documentation per project |
| **Issues** | Issue tracking |
| **Merge Requests** | Code review workflow |

---

## 15. Nexus & Harbor

### Nexus Repository Manager

Nexus is a repository manager that proxies and caches artifacts from public
repositories (Maven, npm, Docker, apt, yum, etc.).

### Harbor Registry

Harbor is an open-source container registry that stores, signs, and scans
container images for vulnerabilities.

### Why Both?

| Tool | Purpose |
|------|---------|
| **Nexus** | Package manager repos (apt, npm, Maven, PyPI, Docker proxy) |
| **Harbor** | Container registry (store, sign, scan images) |

---

## 16. Container Runtime (containerd)

### What Is containerd?

containerd is an industry-standard container runtime focused on simplicity,
robustness, and portability. It manages the complete container lifecycle
on its host system.

### Architecture

```
┌─────────────────────────────────────────────────────┐
│ Kubernetes (kubelet) │
└──────────────────────┬──────────────────────────────┘
│ CRI (Container Runtime Interface)
┌──────────────────────┴──────────────────────────────┐
│ containerd │
│ │
│ ┌──────────────┐ │
│ │ containerd-shim│ ← Manages container process │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ runc │ ← Runs the container │
│ └──────────────┘ │
│ │
│ ┌──────────────┐ │
│ │ Namespaces │ ← Isolation │
│ └──────────────┘ │
└─────────────────────────────────────────────────────┘
```

---

## 17. Reverse Proxy (NGINX)

### What Is a Reverse Proxy?

A reverse proxy sits in front of backend servers and forwards client requests
to the appropriate backend. It provides:

- **Load balancing** — Distribute traffic across backends
- **SSL termination** — Handle HTTPS at the proxy level
- **Caching** — Cache responses to reduce backend load
- **Path routing** — Route by URL path to different backends
- **Security** — Hide backend infrastructure

### How It Works

```
Client → https://nexus.internal.lan/repository/ubuntu/noble/...
              │
              ▼
┌─────────────────────────┐
│ NGINX Reverse Proxy │
│ │
│ /nexus/* → Nexus:8081 │
│ /harbor/* → Harbor:8443│
│ /repository/* → Nexus │
│ /v2/* → Harbor/Nexus │
└─────────────────────────┘
```

---

## 18. LDAP/Active Directory

### What Is LDAP?

LDAP (Lightweight Directory Access Protocol) is a protocol for accessing
and maintaining distributed directory information services. Active
Directory (AD) is Microsoft's implementation.

### Why Use LDAP/AD?

| Feature | Benefit |
|---------|---------|
| **Single sign-on** | One login for all services |
| **Centralized users** | Manage users in one place |
| **Group-based access** | Assign permissions by group |
| **Compliance** | Audit trail for access |

### Integration Points

| Service | LDAP Support |
|---------|-------------|
| Rancher | ✅ Native |
| GitLab | ✅ Native |
| ArgoCD | ✅ Native |
| Harbor | ✅ Native |
| Nexus | ✅ Native |
| Kubernetes | ✅ Via OIDC/LDAP webhook |
| AWX/Tower | ✅ Native |
| Velero | N/A (no user auth) |

---

## 19. Operating Systems

### Ubuntu Server

| Feature | Details |
|---------|---------|
| **Package manager** | APT (deb) |
| **Release cycle** | LTS every 2 years (5-year support) |
| **Kernel** | Linux 6.x (22.04 LTS) |
| **Container support** | Excellent (native, containerd, Docker) |
| **K8s support** | Officially supported by all installers |
| **Air-gap** | Full offline package management via apt-mirror/Nexus |

### CentOS Stream / Rocky Linux / Oracle Linux

| Feature | Details |
|---------|---------|
| **Package manager** | DNF/YUM (rpm) |
| **Release cycle** | Stream (rolling) or RHEL clone (stable) |
| **Kernel** | Linux 6.x |
| **Container support** | Excellent |
| **K8s support** | Officially supported |
| **Air-gap** | Full offline via createrepo/Nexus |

### Comparison

| Feature | Ubuntu | Rocky Linux | Oracle Linux |
|---------|--------|-------------|--------------|
| **Package format** | .deb | .rpm | .rpm |
| **Default shell** | bash | bash | bash |
| **Firewall** | ufw/iptables | firewalld | firewalld |
| **SELinux** | AppArmor | SELinux | SELinux |
| **K8s support** | ✅ | ✅ | ✅ |
| **Ceph support** | ✅ | ✅ | ✅ |
| **Enterprise support** | Canonical | Community | Oracle |
| **Air-gap friendly** | ✅ | ✅ | ✅ |

---

## 20. Virtualization vs Containers vs Bare Metal

### Comparison

| Feature | Physical Server | Virtual Machine | Container |
|---------|-----------------|-----------------|-----------|
| **Isolation** | Hardware | Hypervisor | Namespace |
| **Resource overhead** | None | 5-15% | 1-3% |
| **Startup time** | Minutes | Seconds | Milliseconds |
| **Density** | 1 app per host | 10-50 VMs | 100-500 containers |
| **Migration** | Hard | Live migration | Re-create anywhere |
| **Storage** | Local disks | Virtual disks | Layered filesystem |
| **Networking** | Physical NICs | Virtual NICs | veth pairs + bridge |
| **Best for** | GPU, high I/O | Multi-tenant, isolation | Microservices, scale |

### Why VMs + Containers?

The deployment stack uses:
- **Physical servers** for storage nodes (Ceph) — direct disk access
- **VMs** for Kubernetes nodes — flexibility, easy management
- **Containers** for applications — fast, scalable, portable
