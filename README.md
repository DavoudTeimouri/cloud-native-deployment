# Cloud-Native Deployment Guide

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub Pages](https://img.shields.io/badge/GitHub-Pages-blue.svg)](https://pages.github.com/)

## ⚠️ AIR-GAP NOTICE

> **This project is designed for fully air-gapped environments.** There is **no internet access** and **no proxy configuration** at any point during deployment. All artifacts (container images, Helm charts, OS packages, binaries) are mirrored through an internal **Nexus Repository Manager** and **Harbor Container Registry**. Every deployment step assumes zero external connectivity.

---

## Table of Contents

- [Overview](#overview)
- [Architecture Summary](#architecture-summary)
- [Component List](#component-list)
- [Deployment Phases](#deployment-phases)
- [Directory Structure](#directory-structure)
- [Quick Start](#quick-start)
- [Documentation Links](#documentation-links)
- [License](#license)

---

## Overview

The **Cloud-Native Deployment Guide** provides a comprehensive, production-grade reference for deploying Kubernetes clusters using [KubeSpray](https://github.com/kubernetes-sigs/kubespray) in an enterprise air-gapped environment. This project covers:

1. **Two-Cluster Architecture**: A Management Cluster for platform tooling and an Application Cluster for workloads.
2. **Ceph Storage**: Distributed block/file/object storage for both clusters.
3. **Air-Gap Artifact Management**: Nexus Repository Manager + Harbor Container Registry.
4. **External Load Balancing**: HAProxy + keepalived for high-availability control plane access.
5. **GitOps & Platform Tooling**: ArgoCD, Rancher, cert-manager, Gatekeeper, Prometheus/Grafana, Loki, Velero.

All procedures assume Ubuntu 22.04 LTS as the base operating system and are designed for enterprise production environments.

---

## Architecture Summary

| Aspect | Management Cluster | Application Cluster |
|--------|-------------------|---------------------|
| **Purpose** | Platform tooling, monitoring, GitOps, cluster management | Business workloads, application hosting |
| **Masters** | 5 (HA control plane) | 5 (HA control plane) |
| **Workers** | 5 (platform services) | 5 (application workloads) |
| **External LBs** | 2 (HAProxy + keepalived) | 2 (HAProxy + keepalived) |
| **Storage** | Rook-Ceph or bare Ceph (5 MON + 5 OSD) | bare Ceph or Rook-Ceph (5 MON + 5 OSD) |
| **Key Components** | Rancher, ArgoCD, cert-manager, Gatekeeper, Prometheus, Grafana, Loki, Velero | MetalLB, CephFS CSI, cert-manager, Gatekeeper, NGINX Ingress |
| **Kubernetes Version** | `$K8S_VERSION` | `$K8S_VERSION` |
| **Ceph Version** | `$CEPH_VERSION` | `$CEPH_VERSION` |

### Additional Infrastructure

| Role | Count | OS | Purpose |
|------|-------|----|---------|
| Operations Server (Linux) | 1 | Ubuntu 22.04 | KubeSpray deployment host, Ansible control node |
| Operations Server (Windows) | 1 | Windows Server 2022 | Windows admin, AD/DNS management |
| External Load Balancer | 4 (2 per cluster) | Ubuntu 22.04 | HAProxy + keepalived VIP |

---

## Component List

### Core Platform Components

| Component | Version Variable | Purpose |
|-----------|-----------------|---------|
| Kubernetes | `$K8S_VERSION` | Container orchestration platform |
| KubeSpray | `$KUBESPRAY_VERSION` | Kubernetes deployment automation |
| Ceph | `$CEPH_VERSION` | Distributed storage (block/file/object) |
| Calico | `$CALICO_VERSION` | CNI networking (VXLAN/BGP) |
| containerd | `$CONTAINERD_VERSION` | Container runtime |
| etcd | `$ETCD_VERSION` | Distributed key-value store |
| Helm | `$HELM_VERSION` | Kubernetes package manager |

### Platform Services (Management Cluster)

| Component | Purpose |
|-----------|---------|
| Rancher | Multi-cluster management UI |
| ArgoCD | GitOps continuous delivery |
| cert-manager | Automated TLS certificate management |
| Gatekeeper | OPA-based policy enforcement |
| Prometheus | Metrics collection |
| Grafana | Monitoring dashboards |
| Loki | Log aggregation |
| Velero | Backup and disaster recovery |

### Platform Services (Application Cluster)

| Component | Purpose |
|-----------|---------|
| MetalLB | Bare-metal LoadBalancer controller |
| CephFS CSI | Ceph filesystem persistent volumes |
| cert-manager | Automated TLS certificate management |
| Gatekeeper | OPA-based policy enforcement |
| NGINX Ingress | HTTP/HTTPS ingress controller |

### Infrastructure Services

| Component | Purpose |
|-----------|---------|
| Nexus Repository Manager | Artifact repository (apt, docker, helm, generic) |
| Harbor | Container registry with vulnerability scanning |
| HAProxy | Layer 4/7 load balancer |
| keepalived | VRRP-based VIP failover |
| CoreDNS | Internal DNS resolution |

---

## Deployment Phases

| Phase | Name | Description |
|-------|------|-------------|
| 0 | Prerequisites | Hardware provisioning, network configuration, firmware updates |
| 1 | Air-Gap Setup | Deploy Nexus, Harbor, mirror all artifacts |
| 2 | OS Provisioning | Install Ubuntu 22.04 on all nodes, baseline configuration |
| 3 | Network Configuration | VLANs, bonds, firewall rules, DNS zones |
| 4 | Ceph Deployment | Deploy Ceph cluster (MONs + OSDs) for Management Cluster |
| 5 | KubeSpray Prep | Prepare KubeSpray inventory, configure air-gap settings |
| 6 | Management Cluster | Deploy Management Cluster via KubeSpray |
| 7 | Management Services | Deploy platform services (Rancher, ArgoCD, monitoring) |
| 8 | Ceph Deployment | Deploy Ceph cluster (MONs + OSDs) for Application Cluster |
| 9 | Application Cluster | Deploy Application Cluster via KubeSpray |
| 10 | Application Services | Deploy platform services (MetalLB, Ingress, CSI) |
| 11 | Load Balancer Config | Configure HAProxy + keepalived on all LB nodes |
| 12 | Security Hardening | Apply CIS benchmarks, Gatekeeper policies, network policies |
| 13 | Backup Setup | Configure Velero, test backup/restore procedures |
| 14 | Validation | End-to-end testing, smoke tests, HA failover tests |
| 15 | Handover | Documentation handover, runbook creation, team training |

---

## Directory Structure

```
cloud-native-deployment/
├── README.md                          # This file
├── LICENSE                            # MIT License
├── docs/
│   ├── architecture/
│   │   ├── overview.md                # Two-cluster architecture overview
│   │   ├── network-diagram.md         # ASCII network diagrams
│   │   └── server-specs.md            # Hardware specifications per role
│   ├── prerequisites/
│   │   ├── hardware-requirements.md   # Hardware checklist and specs
│   │   ├── network-requirements.md    # Subnet/VLAN design, port matrix
│   │   └── repository-list.md         # Air-gap artifact manifest
│   ├── deployment/
│   │   ├── phase-01-*.md              # Phase-specific deployment guides
│   │   ├── phase-02-*.md
│   │   └── ...
│   ├── operations/
│   │   ├── runbooks/
│   │   └── troubleshooting/
│   └── reference/
│       ├── ansible-inventories/
│       ├── kubespray-configs/
│       └── helm-values/
├── scripts/
│   ├── airgap/
│   │   ├── mirror-artifacts.sh
│   │   └── validate-checksums.sh
│   └── deployment/
│       └── deploy-cluster.sh
└── config/
    ├── kubespray/
    │   ├── inventory.ini
    │   ├── k8s-cluster.yml
    │   └── addons.yml
    └── ceph/
        ├── ceph.conf
        └── osd-config.yml
```

---

## Quick Start

### 1. Verify Prerequisites

```bash
# Verify all hardware is provisioned and network is configured
./scripts/prerequisites/validate-hardware.sh
./scripts/prerequisites/validate-network.sh
```

### 2. Set Up Air-Gap Environment

```bash
# Deploy Nexus and Harbor, mirror all artifacts
./scripts/airgap/deploy-nexus.sh
./scripts/airgap/deploy-harbor.sh
./scripts/airgap/mirror-all-artifacts.sh
```

### 3. Deploy Management Cluster

```bash
# Configure KubeSpray inventory
cd config/kubespray
cp inventory.ini.example inventory.ini
# Edit inventory.ini with your node IPs

# Deploy via KubeSpray
ansible-playbook -i inventory.ini \
  ../../kubespray/cluster.yml \
  -e @k8s-cluster.yml \
  -e @addons.yml
```

### 4. Deploy Application Cluster

```bash
# Repeat KubeSpray deployment for Application Cluster
ansible-playbook -i inventory-app.ini \
  ../../kubespray/cluster.yml \
  -e @k8s-cluster.yml \
  -e @addons.yml
```

### 5. Validate Deployment

```bash
# Run validation scripts
./scripts/deployment/validate-cluster.sh
./scripts/deployment/validate-ceph.sh
```

---

## Documentation Links

### Architecture
- [Architecture Overview](docs/architecture/overview.md) — Two-cluster design, component placement, HA patterns
- [Network Diagrams](docs/architecture/network-diagram.md) — Physical and logical network layouts
- [Server Specifications](docs/architecture/server-specs.md) — Hardware specs per server role

### Prerequisites
- [Hardware Requirements](docs/prerequisites/hardware-requirements.md) — Complete hardware checklist
- [Network Requirements](docs/prerequisites/network-requirements.md) — Subnet design, port matrix, firewall rules
- [Repository List](docs/prerequisites/repository-list.md) — Complete air-gap artifact manifest

### Deployment Guides
- Phase 0: Prerequisites Validation
- Phase 1: Air-Gap Infrastructure Setup
- Phase 2: OS Provisioning
- Phase 3: Network Configuration
- Phase 4-5: Ceph & KubeSpray Preparation
- Phase 6: Management Cluster Deployment
- Phase 7: Management Services Installation
- Phase 8-9: Application Cluster Deployment
- Phase 10: Application Services Installation
- Phase 11: Load Balancer Configuration
- Phase 12: Security Hardening
- Phase 13: Backup Configuration
- Phase 14: Validation & Testing
- Phase 15: Handover

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2026 Cloud-Native Deployment Guide Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Contributing

Contributions are welcome! Please ensure all content aligns with enterprise deployment standards and maintains the air-gap-first approach.

## Support

For issues and questions, please open a GitHub Issue or refer to the troubleshooting guides in `docs/operations/troubleshooting/`.
