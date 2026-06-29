# Cloud-Native Deployment Documentation

> Enterprise cloud-native deployment guides for Kubernetes, Ceph, and platform components

## 📋 Documentation Index

### 🏗️ Architecture & Design
| Document | Description |
|----------|-------------|
| [Architecture Overview](docs/architecture/overview.md) | High-level architecture and design decisions |
| [Network Diagram](docs/architecture/network-diagram.md) | Network topology and connectivity |
| [Server Specifications](docs/architecture/server-specs.md) | Hardware and VM specifications |
| [Reverse Proxy Architecture](docs/architecture/reverse-proxy-architecture.md) | NGINX reverse proxy for all internal services |
| [Registry & Repository Reference](docs/architecture/registry-repository-reference.md) | Centralized list of all remote URLs |
| [Multi-Cluster Architecture](docs/advanced/multi-cluster-architecture.md) | Multi-cluster concepts, patterns, and management |
| [Multi-DC Architecture](docs/advanced/multi-site/multi-dc-architecture.md) | Multi-datacenter deployment |

### 📦 Deployment Guides
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
| [NGINX Ingress](docs/networking/ingress/nginx-http.md) | HTTP ingress configuration |
| [NGINX Ingress TCP](docs/networking/ingress/nginx-tcp.md) | TCP ingress configuration |
| [Ceph](docs/ceph/bare-metal-ceph.md) | Ceph storage deployment |
| [Ceph Rook](docs/ceph/rook-ceph.md) | Rook-Ceph deployment |
| [CephFS CSI](docs/ceph/cephfs-csi.md) | CephFS CSI driver |
| [RGW](docs/ceph/rados-gateway.md) | Ceph RADOS Gateway |
| [MinIO](docs/ceph/minio.md) | MinIO object storage |
| [Rancher](docs/platform/rancher.md) | Rancher management platform |
| [ArgoCD](docs/platform/argocd.md) | ArgoCD GitOps |
| [Gatekeeper](docs/platform/gatekeeper.md) | OPA Gatekeeper policies |
| [Gatekeeper Appendix](docs/platform/gatekeeper-appendix.md) | Additional Gatekeeper examples |
| [cert-manager](docs/platform/cert-manager.md) | Certificate management |
| [cert-manager Part 2](docs/platform/cert-manager-part2.md) | Advanced cert-manager |
| [Prometheus/Grafana](docs/monitoring/prometheus-grafana.md) | Monitoring stack |
| [Logging](docs/monitoring/logging.md) | Centralized logging |
| [Log Collector](docs/monitoring/log-collector.md) | Log collection with Promtail |
| [Prerequisites](docs/prerequisites/repository-list.md) | Required repositories |
| [Hardware Requirements](docs/prerequisites/hardware-requirements.md) | Hardware specifications |
| [Network Requirements](docs/prerequisites/network-requirements.md) | Network requirements |
| [Cluster Sizing](docs/scaling/cluster-sizing.md) | Cluster sizing guide |

### 🔧 Ansible Playbooks
| Playbook | Description |
|----------|-------------|
| [OS Preparation](ansible/playbooks/os-preparation.yml) | K8s node OS preparation |
| [Management Server Prep](ansible/playbooks/mgmt-server-prep.yml) | Management server setup |
| [KubeSpray Deploy](ansible/playbooks/kubespray-deploy.yml) | KubeSpray deployment |
| [Monitoring Deploy](ansible/playbooks/monitoring-deploy.yml) | Monitoring stack deployment |
| [Platform Deploy](ansible/playbooks/platform-deploy.yml) | Platform components deployment |

### 📜 Scripts
| Script | Description |
|--------|-------------|
| [Linux Hardening](scripts/os-prep/linux-hardening.sh) | Node hardening shell script |
| [DNS Setup](scripts/os-prep/dns-setup.sh) | DNS configuration |
| [NTP Setup](scripts/os-prep/ntp-setup.sh) | NTP configuration |
| [Ceph Deploy](scripts/ceph/deploy-ceph.sh) | Ceph deployment |
| [Ceph Dashboard](scripts/ceph/ceph-dashboard.sh) | Ceph dashboard setup |
| [Monitoring Deploy](scripts/monitoring/deploy-monitoring.sh) | Monitoring deployment |
| [Logging Deploy](scripts/monitoring/deploy-logging.sh) | Logging deployment |
| [OS Prep Linux](scripts/os-prep/linux-hardening.sh) | OS preparation |
| [Velero Deploy](scripts/velero/deploy-velero.sh) | Velero deployment |

### 📊 Helm Values
| File | Description |
|------|-------------|
| [ArgoCD Values](helm-values/argocd-values.yaml) | ArgoCD Helm values |
| [Rancher Values](helm-values/rancher-values.yaml) | Rancher Helm values |
| [NGINX Ingress Values](helm-values/nginx-ingress-values.yaml) | NGINX Ingress values |
| [MetalLB Values](helm-values/metallb-values.yaml) | MetalLB Helm values |

### 🔍 Troubleshooting
| Document | Description |
|----------|-------------|
| [Kubernetes Troubleshooting](docs/troubleshooting/kubernetes.md) | Node, Pod, etcd, API server issues |
| [Ceph Troubleshooting](docs/troubleshooting/ceph.md) | Ceph health, PG, OSD, MON issues |
| [Networking Troubleshooting](docs/troubleshooting/networking.md) | Calico, MetalLB, Ingress, DNS issues |
| [Platform Troubleshooting](docs/troubleshooting/platform.md) | Rancher, ArgoCD, Gatekeeper, cert-manager |
| [Monitoring Troubleshooting](docs/troubleshooting/monitoring.md) | Prometheus, Grafana, Loki, Velero |

### ⬆️ Upgrade Guides
| Document | Description |
|----------|-------------|
| [Kubernetes Upgrade](docs/upgrade/kubernetes.md) | K8s upgrade + OS upgrade |
| [Ceph Upgrade](docs/upgrade/ceph.md) | Ceph rolling upgrade |
| [Component Upgrade](docs/upgrade/components.md) | Helm upgrades for all components |

### 📝 Cheat Sheets
| Document | Description |
|----------|-------------|
| [Kubernetes Cheat Sheet](docs/cheat-sheets/kubernetes.md) | K8s quick reference |
| [Ceph Cheat Sheet](docs/cheat-sheets/ceph.md) | Ceph quick reference |
| [KubeSpray Cheat Sheet](docs/cheat-sheets/kubespray.md) | KubeSpray quick reference |
| [Monitoring Cheat Sheet](docs/cheat-sheets/monitoring.md) | Monitoring quick reference |

### ⚙️ Operations
| Document | Description |
|----------|-------------|
| [Health Check](docs/operations/health-check.md) | All-component health checks |
| [Kubernetes Addons](docs/operations/kubernetes-addons.md) | Kyverno, Falco, Trivy, Vault, service mesh comparison |
| [Service Mesh Discussion](docs/operations/service-mesh.md) | Istio, Linkerd, Cilium — when to use, which one |
| [Container Services](docs/operations/container-services.md) | Services as containers with custom ports |
| [Repository/Registry Manager](docs/operations/repository-registry-manager.md) | Nexus/Harbor with reverse proxy |

### 🖥️ OS Preparation
| Document | Description |
|----------|-------------|
| [OS Prep Guide](docs/os-preparation/os-prep-guide.md) | Time, firewall, services, updates |
| [Linux Hardening](docs/os-preparation/linux-hardening.md) | CIS benchmark hardening |
| [NTP & DNS](docs/os-preparation/ntp-dns.md) | Time sync and DNS |
| [Management Server](docs/os-preparation/management-server.md) | Ansible control node |
| [Windows Setup](docs/os-preparation/windows-setup.md) | Windows node preparation |
