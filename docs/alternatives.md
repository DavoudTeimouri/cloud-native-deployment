# Alternatives Guide

> Alternative technologies and tools for each component — with pros, cons, and when to use them

---

## 1. Container Orchestration (Kubernetes Alternatives)

### 1.1 K3s

| Aspect | Details |
|--------|---------|
| **What** | Lightweight Kubernetes by Rancher |
| **Size** | ~50MB single binary |
| **Best for** | Edge, IoT, small clusters, development |
| **Pros** | Extremely lightweight, easy to install, single binary |
| **Cons** | Limited scalability, fewer features, not for large production |
| **When to use** | < 10 nodes, edge computing, CI/CD runners |

```bash
# Install K3s (single command)
curl -sfL https://get.k3s.io | sh -

# Air-gap install
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--system-default-registry=harbor.internal" sh -
```

### 1.2 K0s

| Aspect | Details |
|--------|---------|
| **What** | Zero-friction Kubernetes by Mirantis |
| **Best for** | Any size cluster, fully conformant |
| **Pros** | Single binary, easy upgrade, vendor-neutral |
| **Cons** | Smaller community than K3s |

### 1.3 Nomad (HashiCorp)

| Aspect | Details |
|--------|---------|
| **What** | Simple orchestrator for containers AND VMs |
| **Best for** | Mixed workloads (containers + non-containers) |
| **Pros** | Simple, supports VMs natively, integrates with Consul/Vault |
| **Cons** | Smaller ecosystem, fewer integrations than K8s |

### 1.4 Docker Swarm

| Aspect | Details |
|--------|---------|
| **What** | Docker's built-in orchestration |
| **Best for** | Simple container deployments, small clusters |
| **Pros** | Built into Docker, zero additional install |
| **Cons** | Limited features, Docker-only, declining community |

### 1.5 Comparison

| Feature | K3s | K0s | Nomad | Swarm | Full K8s |
|---------|-----|-----|-------|-------|----------|
| **Complexity** | Very low | Low | Medium | Low | High |
| **Scalability** | <100 nodes | Any size | Any size | <50 nodes | Any size |
| **CNCF certified** | ✅ | ✅ | ❌ | ❌ | ✅ |
| **Helm support** | ✅ | ✅ | Partial | ❌ | ✅ |
| **CSI support** | ✅ | ✅ | ✅ | ❌ | ✅ |
| **Service mesh** | ✅ | ✅ | ✅ (Consul) | ❌ | ✅ |
| **Air-gap friendly** | ✅ | ✅ | ✅ | ✅ | ✅ |

**Recommendation**: Use **full Kubernetes** for production (>10 nodes). Use **K3s** for edge/CI/small clusters.

---

## 2. Container Runtime Alternatives

### 2.1 Podman

| Aspect | Details |
|--------|---------|
| **What** | Daemonless container engine by Red Hat |
| **Best for** | Rootless containers, security-focused environments |
| **Key feature** | No daemon, daemonless, systemd-native |
| **Docker compatible** | Yes (`alias docker=podman`) |
| **K8s integration** | Not directly (K8s uses CRI-O or containerd) |

```bash
# Podman commands (identical to Docker)
podman run -d --name nginx -p 80:80 nginx:1.25
podman build -t my-app:v1.0 .
podman push my-app:v1.0 harbor.internal/my-project/my-app:v1.0

# Rootless (no root required)
podman run --userns=keep-id -d nginx:1.25
```

**Why Podman over Docker?**
- No daemon = smaller attack surface
- Rootless containers = better security
- systemd integration (`podman generate systemd`)
- No daemon to crash or misconfigure

**Why Docker over Podman?**
- More documentation and community
- Docker Compose (though Podman supports it)
- Better tooling integration

### 2.2 CRI-O

| Aspect | Details |
|--------|---------|
| **What** | Lightweight container runtime for Kubernetes only |
| **Best for** | Kubernetes-only environments |
| **Key feature** | Implements CRI (Container Runtime Interface) |
| **Used by** | OpenShift, many CNCF projects |

### 2.3 LXC / LXD

| Aspect | Details |
|--------|---------|
| **What** | System containers (not application containers) |
| **Best for** | Running full OS in containers, VM-like isolation |
| **Key feature** | Systemd inside container, full OS, persistent |
| **Difference from Docker** | Docker = app containers, LXC = system containers |

```bash
# LXD examples
lxc launch ubuntu:22.04 my-container
lxc exec my-container -- bash
lxc config set my-container limits.cpu 2
lxc config set my-container limits.memory 2GB
```

**LXC vs Docker:**

| Feature | LXC/LXD | Docker/containerd |
|---------|---------|-------------------|
| **Type** | System container | Application container |
| **Runs** | Full OS (systemd) | Single process |
| **Persistence** | Persistent | Ephemeral (by design) |
| **Use case** | VM replacement | Microservices |
| **K8s support** | ❌ | ✅ |
| **Image size** | ~200MB (full OS) | ~5MB (alpine) |

**When to use LXC:**
- When you need a container that behaves like a VM
- When you need systemd inside the container
- When you need persistent state without volumes
- For running legacy applications that need full OS

### 2.4 Comparison

| Feature | containerd | Podman | CRI-O | LXC/LXD |
|---------|-----------|--------|-------|---------|
| **K8s support** | ✅ Native | ❌ | ✅ Native | ❌ |
| **Daemon** | Yes | No | Yes | Yes (lxd) |
| **Rootless** | Partial | ✅ | Partial | ✅ |
| **System containers** | ❌ | ❌ | ❌ | ✅ |
| **App containers** | ✅ | ✅ | ✅ | ✅ |
| **Docker compatible** | Mostly | ✅ | No | No |
| **Air-gap** | ✅ | ✅ | ✅ | ✅ |

**Recommendation**: Use **containerd** for Kubernetes nodes. Use **Podman** for development servers. Use **LXC** for VM-like workloads.

---

## 3. CNI (Networking) Alternatives

### 3.1 Cilium

| Aspect | Details |
|--------|---------|
| **What** | eBPF-based networking, security, and observability |
| **Best for** | High-performance, observability-focused |
| **Key feature** | Kernel-level (eBPF), no iptables, built-in observability (Hubble) |
| **Pros** | Fastest performance, deep observability, network policies |
| **Cons** | Requires kernel 5.10+, steeper learning curve |

### 3.2 Flannel

| Aspect | Details |
|--------|---------|
| **What** | Simple overlay network |
| **Best for** | Basic networking, minimal configuration |
| **Pros** | Very simple, lightweight |
| **Cons** | No network policies, no BGP |

### 3.3 Weave Net

| Aspect | Details |
|--------|---------|
| **What** | Simple mesh networking |
| **Best for** | Small clusters, quick setup |
| **Pros** | Easy setup, encryption built-in |
| **Cons** | Performance, scalability |

### 3.4 Comparison

| Feature | Calico | Cilium | Flannel | Weave |
|---------|--------|--------|---------|-------|
| **Performance** | High | Highest | Medium | Medium |
| **Network policies** | ✅ Full | ✅ Full | ❌ | ✅ Basic |
| **BGP** | ✅ | ✅ | ❌ | ❌ |
| **Encryption** | WireGuard | WireGuard/IPsec | ❌ | ✅ |
| **Observability** | Basic | Hubble (excellent) | ❌ | Basic |
| **Complexity** | Medium | Medium-High | Low | Low |
| **Kernel requirement** | Any | 5.10+ | Any | Any |

**Recommendation**: **Calico** for most deployments. **Cilium** if you need deep observability or highest performance.

---

## 4. Storage Alternatives

### 4.1 MinIO

| Aspect | Details |
|--------|---------|
| **What** | High-performance S3-compatible object storage |
| **Best for** | Object-only storage, simplicity |
| **Pros** | Simple, lightweight, S3-compatible, great for backups |
| **Cons** | No block storage, no filesystem |

### 4.2 Longhorn

| Aspect | Details |
|--------|---------|
| **What** | Lightweight distributed block storage for Kubernetes |
| **Best for** | K8s-only persistent volumes |
| **Pros** | Built-in backup, snapshot, replication |
| **Cons** | Block only, no object/filesystem |

### 4.3 Rook-Ceph

| Aspect | Details |
|--------|---------|
| **What** | Kubernetes operator for Ceph |
| **Best for** | Running Ceph inside Kubernetes |
| **Pros** | Unified storage, K8s-native |
| **Cons** | Complex, resource-heavy |

### 4.4 NFS

| Aspect | Details |
|--------|---------|
| **What** | Network File System |
| **Best for** | Simple shared storage |
| **Pros** | Simple, no special hardware |
| **Cons** | Single point of failure, no replication |

### 4.5 Comparison

| Feature | Ceph | MinIO | Longhorn | NFS |
|---------|------|-------|----------|-----|
| **Block storage** | ✅ | ❌ | ✅ | ❌ |
| **Object storage** | ✅ (RGW) | ✅ | ❌ | ❌ |
| **Filesystem** | ✅ (CephFS) | ❌ | ❌ | ✅ |
| **Replication** | ✅ | ✅ (erasure coding) | ✅ | ❌ |
| **Self-healing** | ✅ | ✅ | ✅ | ❌ |
| **K8s CSI** | ✅ | ✅ | ✅ | ✅ |
| **Complexity** | High | Low | Medium | Low |
| **Scalability** | Petabytes | Petabytes | Terabytes | Terabytes |

**Recommendation**: **Ceph** for unified storage (block + object + file). **MinIO** for object-only (backups, S3).

---

## 5. Monitoring Alternatives

### 5.1 Datadog

| Aspect | Details |
|--------|---------|
| **What** | SaaS monitoring platform |
| **Best for** | Teams wanting managed monitoring |
| **Pros** | Beautiful UI, APM, logs, metrics in one |
| **Cons** | Expensive, data leaves your network (not air-gap friendly) |

### 5.2 New Relic

| Aspect | Details |
|--------|---------|
| **What** | Application performance monitoring |
| **Best for** | Application-level monitoring |
| **Cons** | SaaS only, expensive, not air-gap friendly |

### 5.3 Zabbix

| Aspect | Details |
|--------|---------|
| **What** | Enterprise monitoring solution |
| **Best for** | Infrastructure monitoring (pre-K8s) |
| **Pros** | Mature, agent-based, good for physical servers |
| **Cons** | Complex setup, less K8s-native |

### 5.4 Comparison

| Feature | Prometheus/Grafana | Datadog | Zabbix |
|---------|-------------------|---------|--------|
| **Air-gap** | ✅ | ❌ (SaaS) | ✅ |
| **K8s native** | ✅ | ✅ | Partial |
| **Cost** | Free | $$$ | Free |
| **APM** | Via Jaeger | ✅ Built-in | Partial |
| **Logs** | Loki | ✅ Built-in | Partial |
| **Self-hosted** | ✅ | ❌ | ✅ |

**Recommendation**: **Prometheus/Grafana** for air-gap. **Datadog** if you have internet and budget.

---

## 6. GitOps / CD Alternatives

### 6.1 Flux

| Aspect | Details |
|--------|---------|
| **What** | GitOps tool by Weaveworks (CNCF) |
| **Best for** | Pure GitOps, minimal UI |
| **Pros** | Lightweight, CNCF graduated, multi-tenancy |
| **Cons** | No built-in UI (needs Grafana dashboard) |

### 6.2 Jenkins X

| Aspect | Details |
|--------|---------|
| **What** | CI/CD with GitOps |
| **Best for** | Teams wanting CI + CD together |
| **Cons** | Complex, heavy resource usage |

### 6.3 Spinnaker

| Aspect | Details |
|--------|---------|
| **What** | Multi-cloud CD platform |
| **Best for** | Complex deployment strategies |
| **Cons** | Heavy, Netflix-scale complexity |

### 6.4 Comparison

| Feature | ArgoCD | Flux | Jenkins X | Spinnaker |
|---------|--------|------|-----------|-----------|
| **GitOps** | ✅ | ✅ | ✅ | Partial |
| **Built-in UI** | ✅ | ❌ | ✅ | ✅ |
| **Multi-tenancy** | ✅ | ✅ | ❌ | ✅ |
| **Complexity** | Medium | Low | High | High |
| **Air-gap** | ✅ | ✅ | ✅ | ✅ |
| **CNCF** | ✅ | ✅ | ❌ | ❌ |

**Recommendation**: **ArgoCD** for most teams (great UI, easy). **Flux** if you want minimal.

---

## 7. Policy Engine Alternatives

### 7.1 OPA Gatekeeper

Already covered — constraint-based policy with Rego.

### 7.2 Kyverno

Already covered — YAML-native policy.

### 7.3 jsPolicy

| Aspect | Details |
|--------|---------|
| **What** | JavaScript-based policy engine |
| **Best for** | Teams comfortable with JavaScript |
| **Pros** | Easier than Rego for JS developers |
| **Cons** | Smaller community |

### 7.4 Comparison

| Feature | Kyverno | Gatekeeper | jsPolicy |
|---------|---------|------------|----------|
| **Language** | YAML | Rego | JavaScript |
| **Mutating** | ✅ | Extension | ✅ |
| **Generating** | ✅ | ❌ | ❌ |
| **Learning curve** | Low | High | Medium |
| **Community** | Large | Large | Small |

---

## 8. Load Balancer Alternatives

### 8.1 HAProxy (Software)

| Aspect | Details |
|--------|---------|
| **What** | Reliable TCP/HTTP load balancer |
| **Best for** | L4 load balancing, high throughput |
| **Pros** | Battle-tested, very fast |
| **Cons** | No K8s-native integration (needs MetalLB for that) |

### 8.2 Traefik

| Aspect | Details |
|--------|---------|
| **What** | Cloud-native reverse proxy |
| **Best for** | K8s ingress, microservices |
| **Pros** | Auto-discovery, great for containers |
| **Cons** | Less performant than NGINX at scale |

### 8.3 Envoy

| Aspect | Details |
|--------|---------|
| **What** | Service proxy (used by Istio) |
| **Best for** | Service mesh data plane |
| **Pros** | Extremely flexible, L7 proxy |
| **Cons** | Complex configuration |

### 8.4 Comparison

| Feature | MetalLB | HAProxy | Traefik | NGINX Ingress |
|---------|---------|---------|---------|---------------|
| **Type** | L2/BGP | L4/L7 | L7 | L7 |
| **K8s integration** | ✅ (provides IP) | ❌ | ✅ | ✅ |
| **VIP failover** | ✅ | Keepalived | ❌ | ❌ |
| **Performance** | High | Highest | High | High |
| **Complexity** | Low | Medium | Low | Low |

**Recommendation**: **MetalLB** for LoadBalancer IPs + **NGINX Ingress** for HTTP routing.

---

## 9. Backup Alternatives

### 9.1 Kasten K10

| Aspect | Details |
|--------|---------|
| **What** | Enterprise Kubernetes backup |
| **Best for** | Enterprise with budget |
| **Pros** | GUI, application-aware, cross-cloud |
| **Cons** | Commercial license |

### 9.2 Stash by AppsCode

| Aspect | Details |
|--------|---------|
| **What** | Backup for K8s workloads |
| **Best for** | Application-level backup |
| **Pros** | K8s-native, supports many databases |
| **Cons** | Smaller community |

### 9.3 Comparison

| Feature | Velero | Kasten K10 | Stash |
|---------|--------|------------|-------|
| **Cost** | Free | $$$ | Free |
| **GUI** | ❌ (CLI + k9s) | ✅ | ❌ |
| **PV backup** | Restic/CSI | ✅ Native | ✅ |
| **Schedule** | ✅ | ✅ | ✅ |
| **Air-gap** | ✅ | ✅ | ✅ |

**Recommendation**: **Velero** for free. **Kasten** if you need GUI and have budget.

---

## 10. Automation Platform Alternatives

### 10.1 AWX (Ansible Tower Open Source)

| Aspect | Details |
|--------|---------|
| **What** | Web UI and scheduler for Ansible |
| **Best for** | Teams wanting GUI for Ansible |
| **Pros** | Job scheduling, RBAC, audit trail, REST API |
| **Cons** | Heavy resource usage, complex setup |

```bash
# Install AWX via Operator
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/devel/deploy/awx-operator.yaml

# Or via Docker Compose
git clone https://github.com/ansible/awx.git
cd awx/installer
ansible-playbook -i inventory install.yml
```

### 10.2 Oracle Linux Automation Manager

| Aspect | Details |
|--------|---------|
| **What** | Oracle's fork of AWX |
| **Best for** | Oracle Linux environments |
| **Pros** | Oracle support, based on AWX |
| **Cons** | Tied to Oracle ecosystem |

### 10.3 Jenkins

| Aspect | Details |
|--------|---------|
| **What** | CI/CD automation server |
| **Best for** | CI pipelines, not just Ansible |
| **Pros** | Huge plugin ecosystem |
| **Cons** | Complex, Groovy-based, heavy |

### 10.4 Rundeck

| Aspect | Details |
|--------|---------|
| **What** | Job scheduler and runbook automation |
| **Best for** | Ad-hoc job execution |
| **Pros** | Simple, good RBAC |
| **Cons** | Not Ansible-specific |

### 10.5 Comparison

| Feature | AWX | Oracle LAM | Jenkins | Rundeck |
|---------|-----|------------|---------|---------|
| **Ansible native** | ✅ | ✅ | Plugin | Plugin |
| **Web UI** | ✅ | ✅ | ✅ | ✅ |
| **Job scheduling** | ✅ | ✅ | ✅ | ✅ |
| **RBAC** | ✅ | ✅ | ✅ | ✅ |
| **REST API** | ✅ | ✅ | ✅ | ✅ |
| **Air-gap** | ✅ | ✅ | ✅ | ✅ |
| **Resource usage** | High | High | High | Medium |
| **Complexity** | High | High | High | Medium |

**Recommendation**: **AWX** if you want Ansible-specific GUI. **Jenkins** if you need general CI/CD.

---

## 11. Source Control Alternatives

### 11.1 GitHub Enterprise

| Aspect | Details |
|--------|---------|
| **What** | Git hosting by Microsoft |
| **Best for** | Teams familiar with GitHub |
| **Cons** | Licensing cost, not self-hosted (Enterprise Server is) |

### 11.2 Bitbucket Server

| Aspect | Details |
|--------|---------|
| **What** | Git hosting by Atlassian |
| **Best for** | Teams using Jira/Confluence |
| **Cons** | Commercial license |

### 11.3 Gitea

| Aspect | Details |
|--------|---------|
| **What** | Lightweight Git hosting |
| **Best for** | Small teams, self-hosted |
| **Pros** | Lightweight, easy setup |
| **Cons** | Fewer features than GitLab |

### 11.4 Comparison

| Feature | GitLab | GitHub Enterprise | Gitea | Bitbucket |
|---------|--------|-------------------|-------|-----------|
| **CI/CD** | ✅ Built-in | Actions | ❌ | Pipelines |
| **Container Registry** | ✅ | ✅ | ❌ | ❌ |
| **Self-hosted** | ✅ | ✅ (Server) | ✅ | ✅ |
| **Air-gap** | ✅ | ✅ | ✅ | ✅ |
| **Cost** | Free (CE) | $$$ | Free | $$$ |
| **Features** | Most | Most | Basic | Medium |

**Recommendation**: **GitLab** for full DevOps platform. **Gitea** for lightweight.

---

## 12. GUI Tools Overview

### 12.1 Kubernetes GUIs

| Tool | Type | Description |
|------|------|-------------|
| **Kubernetes Dashboard** | Web UI | Official K8s dashboard |
| **k9s** | Terminal | Terminal-based K8s UI |
| **Lens** | Desktop | Full-featured K8s IDE |
| **Rancher** | Web UI | Multi-cluster management |
| **ArgoCD UI** | Web UI | GitOps dashboard |
| **Octant** | Web UI | K8s resource viewer (deprecated) |

### 12.2 Container GUIs

| Tool | Type | Description |
|------|------|-------------|
| **Portainer** | Web UI | Docker/K8s container management |
| **Podman Desktop** | Desktop | Podman GUI |
| **LXD Web UI** | Web UI | LXC/LXD management (lxd-ui) |

### 12.3 Storage GUIs

| Tool | Type | Description |
|------|------|-------------|
| **Ceph Dashboard** | Web UI | Built-in Ceph management |
| **MinIO Console** | Web UI | Built-in MinIO management |
| **Longhorn UI** | Web UI | Built-in Longhorn management |

### 12.4 Monitoring GUIs

| Tool | Type | Description |
|------|------|-------------|
| **Grafana** | Web UI | Metrics dashboards |
| **Kiali** | Web UI | Istio service mesh dashboard |
| **Jaeger UI** | Web UI | Distributed tracing |
| **Hubble UI** | Web UI | Cilium observability |

### 12.5 Server Management GUIs

| Tool | Type | Description |
|------|------|-------------|
| **Cockpit** | Web UI | Linux server monitoring (built into RHEL/Ubuntu) |
| **Webmin** | Web UI | General server management |
| **AWX/Tower** | Web UI | Ansible job management |
| **Rancher** | Web UI | K8s cluster management |

### 12.6 Velero GUI

Velero does **not** have a built-in GUI. Options:

| Tool | Description |
|------|-------------|
| **Velero CLI** | `velero backup get`, `velero restore create` |
| **k9s** | Terminal UI shows Velero resources |
| **Kubernetes Dashboard** | Shows Velero CRDs |
| **ArgoCD** | Can manage Velero Application resources |
| **Custom Grafana** | Dashboard for backup status via Prometheus metrics |

```bash
# Velero CLI (primary interface)
velero backup get
velero backup describe <name>
velero restore create --from-backup <name>
velero schedule create daily --schedule="0 2 * * *"

# Prometheus metrics for Grafana
curl http://localhost:8080/metrics | grep velero
```

---

## 13. Summary Matrix

| Component | Primary | Best Alternative | When to Switch |
|-----------|---------|-----------------|----------------|
| **Orchestration** | Kubernetes | K3s | < 10 nodes, edge |
| **Runtime** | containerd | Podman | Rootless, security |
| **CNI** | Calico | Cilium | Need eBPF observability |
| **Storage** | Ceph | MinIO | Object-only, simplicity |
| **Monitoring** | Prometheus | Zabbix | Non-K8s infrastructure |
| **GitOps** | ArgoCD | Flux | Want minimal UI |
| **Policy** | Kyverno | Gatekeeper | Need Rego expressiveness |
| **Load Balancer** | MetalLB | HAProxy | Advanced L4 features |
| **Ingress** | NGINX | Traefik | Auto-discovery needed |
| **Backup** | Velero | Kasten K10 | Need GUI, have budget |
| **Source Control** | GitLab | Gitea | Lightweight, small team |
| **Automation** | Ansible CLI | AWX | Need web UI, scheduling |
| **Registry** | Harbor | Nexus Docker | Already using Nexus |
| **Package Repo** | Nexus | Artifactory | Enterprise features needed |
