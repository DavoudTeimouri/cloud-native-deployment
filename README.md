# Cloud-Native Deployment Documentation

> Enterprise cloud-native deployment guides for Kubernetes, Ceph, and platform components

---

## 📖 About This Repository

This repository contains comprehensive deployment guides, troubleshooting
references, upgrade procedures, and operational runbooks for an enterprise
cloud-native infrastructure stack. It covers the full lifecycle from bare
metal/VM provisioning through production operations.

### Infrastructure Stack

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
(Nexus, Harbor, GitLab) behind a single static address, so servers never
need to know actual backend IPs.

```
Management Server (Ansible)
        │
        ├── Reverse Proxy (NGINX) ─── Single entry point
        │       ├── nexus.internal  → Nexus Repository
        │       ├── harbor.internal → Harbor Registry
        │       └── gitlab.internal → GitLab
        │
        ├── Kubernetes Cluster
        │       ├── Control Plane (3 masters)
        │       └── Worker Nodes (N)
        │
        ├── Ceph Cluster
        │       ├── MON (3)
        │       ├── OSD (N)
        │       └── MDS (2, for CephFS)
        │
        └── Monitoring Stack
                ├── Prometheus
                ├── Grafana
                └── Loki
```

---

## 🖥️ Deployment Targets

### Virtual Machines (Primary)

The primary deployment targets are virtual machines running on hypervisors
such as VMware vSphere, Proxmox VE, KVM/libvirt, or Hyper-V. VMs provide:

- **Flexibility**: Easy snapshot, clone, and resource adjustment
- **Density**: Multiple nodes per physical host
- **Automation**: Full API-driven provisioning via Terraform/Ansible
- **Isolation**: Hypervisor-level separation between workloads

All guides assume VM-based deployment unless otherwise noted.

### Physical Servers (Bare Metal)

For workloads requiring direct hardware access (GPU, NVMe, high memory) or
when virtualization overhead is unacceptable, the same stack deploys on
physical servers with these additional considerations:

| Topic | VM | Physical Server |
|-------|----|-----------------|
| **Provisioning** | Cloud-init / Terraform | PXE boot (iPXE + Kickstart/Preseed) |
| **Storage** | Virtual disks on shared storage | Direct-attached NVMe/SSD (use Ceph for shared) |
| **Network** | Virtual switches | Physical NICs, bonding, VLANs |
| **GPU** | PCI passthrough | Native GPU (device-plugin for K8s) |
| **Boot** | Virtual BIOS/UEFI | UEFI Secure Boot (requires additional config) |
| **Firmware** | N/A | Update BIOS/BMC before deployment |
| **IPMI/BMC** | N/A | Configure for remote management |
| **RAID** | Handled by hypervisor | Hardware or software RAID (mdadm) |

#### Physical Server Additional Steps

```bash
# 1. PXE boot configuration (on management server)
sudo apt-get install -y dnsmasq tftpd-hpa
# Configure /etc/dnsmasq.d/pxe.conf for network boot

# 2. Kickstart/Preseed for automated OS install
# Place preseed file on HTTP server for unattended install

# 3. IPMI configuration for remote management
ipmitool -H <bmc-ip> -U admin -P pass power on
ipmitool -H <bmc-ip> -U admin -P bootdev pxe

# 4. RAID configuration (if not using Ceph)
sudo mdadm --create /dev/md0 --level=10 --raid-devices=4 /dev/sd[abcd]

# 5. Firmware updates
# Use vendor tools ( Dell iDRAC, HPE iLO, Lenovo XClarity)

# 6. Physical network bonding
cat > /etc/netplan/01-bond.yaml <<EOF
network:
  version: 2
  ethernets:
    enp1s0: {}
    enp2s0: {}
  bonds:
    bond0:
      addresses: [10.0.0.20/24]
      interfaces: [enp1s0, enp2s0]
      parameters:
        mode: 802.3ad
        transmit-hash-policy: layer3+4
EOF
sudo netplan apply
```

#### Physical Server K8s Considerations

- **etcd on dedicated disk**: Physical servers often have multiple disks — use a separate SSD for etcd
- **GPU node labels**: `kubectl label node <gpu-node> gpu=true`
- **Node taints**: Taint physical GPU nodes so only GPU workloads schedule there
- **Power management**: Configure STONITH/fencing if using Pacemaker
- **BMC monitoring**: Use IPMI exporter for hardware metrics in Prometheus

---

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

---

## 🚀 Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/DavoudTeimouri/cloud-native-deployment.git
cd cloud-native-deployment

# 2. Prepare the management server
ansible-playbook ansible/playbooks/mgmt-server-prep.yml

# 3. Prepare K8s nodes
ansible-playbook -i ansible/inventory/mgmt-cluster/hosts.yml ansible/playbooks/os-preparation.yml

# 4. Deploy Kubernetes via KubeSpray
ansible-playbook -i ansible/inventory/mgmt-cluster/hosts.yml ansible/playbooks/kubespray-deploy.yml

# 5. Deploy platform components
ansible-playbook -i ansible/inventory/mgmt-cluster/hosts.yml ansible/playbooks/platform-deploy.yml

# 6. Deploy monitoring
ansible-playbook -i ansible/inventory/mgmt-cluster/hosts.yml ansible/playbooks/monitoring-deploy.yml
```

---

## 📝 Notes

- **Air-gap**: All guides assume an air-gapped environment. Internal Nexus
  and Harbor proxies replace public registries and package repositories.
- **Versions**: Target Kubernetes 1.29, Ceph Reef (18.x), Calico 3.27.
  Adjust versions in your inventory as needed.
- **Customization**: All Ansible variables, Helm values, and configurations
  are designed to be overridden for your specific environment.
