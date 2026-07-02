# Cloud-Native Deployment

> Complete deployment guides, technology wiki, and interactive wizard for enterprise cloud-native infrastructure

---

## 🚀 New Here? Start With the Wizard

The **Deployment Wizard** is an interactive step-by-step guide that asks you
a few questions and generates personalized deployment commands. No prior
Kubernetes experience required.

**[→ Open the Deployment Wizard](https://davoudteimouri.github.io/cloud-native-deployment/wizard/)**

The wizard will help you choose:
- Deployment target (VM or bare metal)
- Hypervisor (Proxmox, VMware, KVM, Hyper-V) or server vendor (Dell, HPE, Lenovo)
- Cluster size (K3s or full Kubernetes)
- Internet or air-gap
- GUI tools or CLI only
- Storage backend (Ceph or MinIO)
- Components (monitoring, GitOps, backup, registry, policy, logging, mesh)
- Post-deployment hardening

At the end, it generates:
- **Ansible playbooks** for automated deployment
- **Shell scripts** for OS preparation and health checks
- **Custom commands** with your IPs, hostnames, and variables pre-filled

---

## 📚 Technology Wiki

The **Wiki** explains every technology used in this deployment — what it does,
how it works, and why we chose it. Perfect for learning and training.

**[→ Open the Technology Wiki](https://davoudteimouri.github.io/cloud-native-deployment/technology-wiki.html)**

Topics covered:
- Kubernetes, Ceph, Calico, Prometheus/Grafana, Loki, Velero
- Rancher, ArgoCD, cert-manager, Kyverno/Gatekeeper
- GitLab, Nexus, Harbor, MetalLB, NGINX Ingress
- Ansible, Vault, containerd, Reverse Proxy architecture
- Alternatives (K3s, Podman, LXC/LXD, Cilium, MinIO, Flux, etc.)

---

## 📋 Documentation

### Architecture & Design
| Document | Description |
|----------|-------------|
| [Architecture Overview](docs/architecture/overview.md) | High-level architecture and design decisions |
| [Network Diagram](docs/architecture/network-diagram.md) | Network topology and connectivity |
| [Server Specifications](docs/architecture/server-specs.md) | Hardware and VM specifications |
| [Reverse Proxy Architecture](docs/architecture/reverse-proxy-architecture.md) | NGINX reverse proxy for all internal services |
| [Registry & Repository Reference](docs/architecture/registry-repository-reference.md) | Centralized list of all remote URLs |
| [Multi-Cluster Architecture](docs/advanced/multi-cluster-architecture.md) | Multi-cluster concepts, patterns, and management |
| [Multi-DC Architecture](docs/advanced/multi-site/multi-dc-architecture.md) | Multi-datacenter deployment |

### Deployment Guides
| Document | Description |
|----------|-------------|
| [OS Preparation](docs/os-preparation/os-prep-guide.md) | Time, firewall, services, updates |
| [Linux Hardening](docs/os-preparation/linux-hardening.md) | CIS benchmark hardening for K8s nodes |
| [NTP & DNS](docs/os-preparation/ntp-dns.md) | Time sync and DNS configuration |
| [Management Server](docs/os-preparation/management-server.md) | Ansible control node setup |
| [Container Services](docs/operations/container-services.md) | Nexus, Harbor, GitLab as containers with custom ports |
| [Repository & Registry Manager](docs/operations/repository-registry-manager.md) | Nexus and Harbor with advanced path handling |
| [GitLab Deployment](docs/gitlab/deployment.md) | GitLab native, container, and K8S deployment |
| [Load Balancer & Ingress](docs/networking/load-balancer-ingress.md) | MetalLB, NGINX Ingress, HAProxy/Keepalived |
| [Velero Storage](docs/velero/storage.md) | Backup storage targets (MinIO, Ceph RGW, NFS) |
| [Velero Deployment](docs/velero/deployment.md) | Velero installation and configuration |
| [Calico](docs/networking/calico.md) | Calico CNI deployment |
| [MetalLB](docs/networking/metallb.md) | Bare-metal load balancer |
| [NGINX Ingress HTTP](docs/networking/ingress/nginx-http.md) | HTTP ingress configuration |
| [NGINX Ingress TCP](docs/networking/ingress/nginx-tcp.md) | TCP ingress configuration |
| [Ceph Bare Metal](docs/ceph/bare-metal-ceph.md) | Ceph storage deployment |
| [Ceph Rook](docs/ceph/rook-ceph.md) | Rook-Ceph deployment |
| [CephFS CSI](docs/ceph/cephfs-csi.md) | CephFS CSI driver |
| [RGW](docs/ceph/rados-gateway.md) | Ceph RADOS Gateway |
| [MinIO](docs/ceph/minio.md) | MinIO object storage |
| [Rancher](docs/platform/rancher.md) | Rancher management platform |
| [ArgoCD](docs/platform/argocd.md) | ArgoCD GitOps |
| [Gatekeeper](docs/platform/gatekeeper.md) | OPA Gatekeeper policies |
| [cert-manager](docs/platform/cert-manager.md) | Certificate management |
| [Prometheus/Grafana](docs/monitoring/prometheus-grafana.md) | Monitoring stack |
| [Logging](docs/monitoring/logging.md) | Centralized logging |
| [Log Collector](docs/monitoring/log-collector.md) | Log collection with Promtail |
| [Prerequisites](docs/prerequisites/repository-list.md) | Required repositories |
| [Hardware Requirements](docs/prerequisites/hardware-requirements.md) | Hardware specifications |
| [Network Requirements](docs/prerequisites/network-requirements.md) | Network requirements |
| [Cluster Sizing](docs/scaling/cluster-sizing.md) | Cluster sizing guide |

### Troubleshooting
| Document | Description |
|----------|-------------|
| [Kubernetes Troubleshooting](docs/troubleshooting/kubernetes.md) | Node, Pod, etcd, API server issues |
| [Ceph Troubleshooting](docs/troubleshooting/ceph.md) | Ceph health, PG, OSD, MON issues |
| [Networking Troubleshooting](docs/troubleshooting/networking.md) | Calico, MetalLB, Ingress, DNS issues |
| [Platform Troubleshooting](docs/troubleshooting/platform.md) | Rancher, ArgoCD, Gatekeeper, cert-manager |
| [Monitoring Troubleshooting](docs/troubleshooting/monitoring.md) | Prometheus, Grafana, Loki, Velero |

### Upgrade Guides
| Document | Description |
|----------|-------------|
| [Comprehensive Upgrade](docs/upgrade/comprehensive.md) | All components + OS upgrade procedures |
| [Kubernetes Upgrade](docs/upgrade/kubernetes.md) | K8s upgrade + OS upgrade details |
| [Ceph Upgrade](docs/upgrade/ceph.md) | Ceph rolling upgrade details |
| [Component Upgrade](docs/upgrade/components.md) | Helm upgrades for all components |

### Cheat Sheets
| Document | Description |
|----------|-------------|
| [Kubernetes Cheat Sheet](docs/cheat-sheets/kubernetes.md) | K8s quick reference |
| [Ceph Cheat Sheet](docs/cheat-sheets/ceph.md) | Ceph quick reference |
| [KubeSpray Cheat Sheet](docs/cheat-sheets/kubespray.md) | KubeSpray quick reference |
| [Monitoring Cheat Sheet](docs/cheat-sheets/monitoring.md) | Monitoring quick reference |

### Operations
| Document | Description |
|----------|-------------|
| [Health Check](docs/operations/health-check.md) | All-component health checks |
| [Hardening](docs/operations/hardening.md) | Post-deployment security hardening |
| [Kubernetes Addons](docs/operations/kubernetes-addons.md) | Kyverno, Falco, Trivy, Vault, service mesh |
| [Service Mesh](docs/operations/service-mesh.md) | Istio, Linkerd, Cilium — when to use, which one |
| [Container Services](docs/operations/container-services.md) | Services as containers with custom ports |
| [Repository/Registry Manager](docs/operations/repository-registry-manager.md) | Nexus/Harbor with reverse proxy |

### Monitoring
| Document | Description |
|----------|-------------|
| [Metrics Implementation](docs/monitoring/metrics.md) | Simple + advanced monitoring with Prometheus/Grafana/Loki |
| [Prometheus/Grafana](docs/monitoring/prometheus-grafana.md) | Monitoring stack deployment |
| [Logging](docs/monitoring/logging.md) | Centralized logging |
| [Log Collector](docs/monitoring/log-collector.md) | Log collection with Promtail |

### OS Preparation
| Document | Description |
|----------|-------------|
| [OS Prep Guide](docs/os-preparation/os-prep-guide.md) | Time, firewall, services, updates |
| [Linux Hardening](docs/os-preparation/linux-hardening.md) | CIS benchmark hardening |
| [NTP & DNS](docs/os-preparation/ntp-dns.md) | Time sync and DNS |
| [Management Server](docs/os-preparation/management-server.md) | Ansible control node |
| [VM Customization](docs/os-preparation/vm-customization.md) | Hypervisor-specific VM configs |
| [Physical Server](docs/os-preparation/physical-customization.md) | Vendor-specific bare-metal configs |
| [Windows Setup](docs/os-preparation/windows-setup.md) | Windows node preparation |

---

## 🔧 Ansible Playbooks

| Playbook | Description |
|----------|-------------|
| [OS Preparation](ansible/playbooks/os-preparation.yml) | K8s node OS preparation |
| [Management Server Prep](ansible/playbooks/mgmt-server-prep.yml) | Management server setup |
| [KubeSpray Deploy](ansible/playbooks/kubespray-deploy.yml) | KubeSpray deployment |
| [Monitoring Deploy](ansible/playbooks/monitoring-deploy.yml) | Monitoring stack deployment |
| [Platform Deploy](ansible/playbooks/platform-deploy.yml) | Platform components deployment |

## 📜 Scripts

| Script | Description |
|--------|-------------|
| [Linux Hardening](scripts/os-prep/linux-hardening.sh) | Node hardening shell script |
| [DNS Setup](scripts/os-prep/dns-setup.sh) | DNS configuration |
| [NTP Setup](scripts/os-prep/ntp-setup.sh) | NTP configuration |
| [Ceph Deploy](scripts/ceph/deploy-ceph.sh) | Ceph deployment |
| [Ceph Dashboard](scripts/ceph/ceph-dashboard.sh) | Ceph dashboard setup |
| [Monitoring Deploy](scripts/monitoring/deploy-monitoring.sh) | Monitoring deployment |
| [Logging Deploy](scripts/monitoring/deploy-logging.sh) | Logging deployment |
| [Velero Deploy](scripts/velero/deploy-velero.sh) | Velero deployment |

## 📊 Helm Values

| File | Description |
|------|-------------|
| [ArgoCD Values](helm-values/argocd-values.yaml) | ArgoCD Helm values |
| [Rancher Values](helm-values/rancher-values.yaml) | Rancher Helm values |
| [NGINX Ingress Values](helm-values/nginx-ingress-values.yaml) | NGINX Ingress values |
| [MetalLB Values](helm-values/metallb-values.yaml) | MetalLB Helm values |

---

## 🏗️ Infrastructure Stack

| Component | Purpose |
|-----------|---------|
| **Kubernetes** | Container orchestration (deployed via KubeSpray) |
| **Ceph** | Distributed storage (block, object, filesystem) |
| **Calico** | CNI networking with BGP and network policies |
| **Rancher** | Multi-cluster management platform |
| **ArgoCD** | GitOps continuous delivery |
| **Gatekeeper / Kyverno** | Policy enforcement |
| **Prometheus / Grafana** | Monitoring and alerting |
| **Loki** | Log aggregation |
| **Velero** | Backup and disaster recovery |
| **GitLab** | Source control and CI/CD |
| **Nexus / Harbor** | Package and container registry |
| **MetalLB / NGINX Ingress** | Load balancing and ingress |
| **cert-manager** | Automated TLS certificate management |

### Deployment Architecture

All deployments are designed for **air-gapped environments** with no direct
internet access. A reverse proxy (NGINX) abstracts all internal services
behind a single static address. Clients use canonical public URLs
(`archive.ubuntu.com`, `docker.io`, etc.) — the proxy handles routing
transparently via DNS.

```
Management Server (Ansible)
        │
        ├── Reverse Proxy (NGINX) ─── Single entry point
        │       ├── archive.ubuntu.com  → Nexus (packages)
        │       ├── registry-1.docker.io → Harbor (images)
        │       └── quay.io, registry.k8s.io → Harbor/Nexus
        │
        ├── Kubernetes Cluster
        │       ├── Control Plane (3 masters)
        │       └── Worker Nodes (N)
        │
        ├── Ceph Cluster
        │       ├── MON (3)  OSD (N)  MDS (2)  RGW (2)
        │
        └── Monitoring Stack
                ├── Prometheus  ├── Grafana  └── Loki
```

---

## 🖥️ Deployment Targets

### Virtual Machines (Primary)

The primary deployment targets are virtual machines running on hypervisors
such as VMware vSphere, Proxmox VE, KVM/libvirt, or Hyper-V.

### Physical Servers (Bare Metal)

For workloads requiring direct hardware access (GPU, NVMe, high memory) or
when virtualization overhead is unacceptable, the same stack deploys on
physical servers. Additional steps include PXE boot, IPMI configuration,
network bonding, and RAID setup.

---

## 📝 Notes

- **Air-gap**: All guides assume an air-gapped environment. Internal Nexus
  and Harbor proxies replace public registries and package repositories.
- **Versions**: Target Kubernetes 1.29, Ceph Reef (18.x), Calico 3.27.
  Adjust versions in your inventory as needed.
- **Customization**: All Ansible variables, Helm values, and configurations
  are designed to be overridden for your specific environment.
- **DNS**: All public repository domains resolve to the reverse proxy IP.
  No client-side configuration changes are needed.
