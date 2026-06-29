# Calico CNI Guide

## Table of Contents
- [Overview](#overview)
- [Deployment via KubeSpray](#deployment-via-kubespray)
- [BGP Mode vs VXLAN Mode](#bgp-mode-vs-vxlan-mode)
- [BGP Peering with Physical Routers](#bgp-peering-with-physical-routers)
- [IP Pool Configuration](#ip-pool-configuration)
- [Network Policy Examples](#network-policy-examples)
- [MTU Considerations](#mtu-considerations)
- [eBPF Data Plane](#ebpf-data-plane)
- [Calicoctl Installation and Usage](#calicoctl-installation-and-usage)
- [Air-Gap: Calico Images from Harbor](#air-gap-calico-images-from-harbor)
- [Performance Tuning](#performance-tuning)
- [Troubleshooting Connectivity](#troubleshooting-connectivity)

---

## Overview

Calico is the default CNI for both the Management and Application clusters deployed via KubeSpray. It provides pod-to-pod networking, network policy enforcement, and optional BGP peering with physical infrastructure.

**Key Components:**

| Component | Purpose | Port |
|-----------|---------|------|
| Felix | Agent on each node, enforces policy and routes | — |
| BIRD | BGP daemon, advertises pod CIDRs | 179/TCP |
| Typha | Reduces API server load (large clusters) | 5473/TCP |
| kube-controllers | Watches K8s API, syncs Calico state | — |

**Cluster IP Ranges:**

| Cluster | Pod CIDR | Service CIDR |
|---------|----------|--------------|
| Management | 10.1.0.0/16 | 10.0.20.0/24 |
| Application | 10.2.0.0/16 | 10.0.21.0/24 |

---

## Deployment via KubeSpray

Calico is the default CNI in KubeSpray. No special configuration is required beyond the standard inventory.

### KubeSpray Configuration

```yaml
# inventory/group_vars/k8s_cluster/k8s-cluster.yml
kube_network_plugin: calico
kube_pods_subnet: 10.1.0.0/16    # Management cluster
kube_service_addresses: 10.0.20.0/24

# For Application cluster:
# kube_pods_subnet: 10.2.0.0/16
# kube_service_addresses: 10.0.21.0/24
```

### Calico-Specific KubeSpray Variables

```yaml
# inventory/group_vars/k8s_cluster/k8s-net-calico.yml

# VXLAN mode (default in KubeSpray)
calico_pool_block_size: 26       # /26 per node = 64 IPs per node
calico_network_backend: bird     # BGP for route distribution

# VXLAN encapsulation
calico_vxlan: CrossSubnet        # VXLAN only for cross-subnet traffic
# Options: Always, CrossSubnet, Never (Never = pure BGP)

# IPIP (deprecated — do not use)
# calico_ipip: Always             # DEPRECATED

# Typha (recommended for >50 nodes)
typha_enabled: false             # Enable for large clusters
typha_replicas: 3

# etcd for Calico (uses K8s API by default, no separate etcd needed)
calico_datastore_type: "kvstore"  # Default: uses Kubernetes API
```

### Deployment Command

```bash
# From the KubeSpray control node
ansible-playbook -i inventory/hosts.ini cluster.yml \
  --tags network,calico
```

### Post-Deployment Verification

```bash
# Check Calico pods are running
kubectl -n calico-system get pods -o wide

# Check node status
kubectl get nodes -o wide

# Verify Calico is using the correct backend
kubectl get ippool default-pod-cidr -o yaml

# Check BGP peer status (if BGP mode)
calicoctl node status
```

---

## BGP Mode vs VXLAN Mode

### Decision Table

| Criteria | VXLAN Mode | BGP Mode |
|----------|-----------|----------|
| **Network topology** | L2 adjacent or routed | Routed (L3) infrastructure |
| **Router requirements** | None (overlay) | BGP-capable routers |
| **Encapsulation overhead** | 50 bytes (VXLAN header) | None |
| **MTU impact** | Reduced (1450 for 1500 link) | Full MTU (1500+) |
| **Performance** | Slightly lower (encap/decap) | Highest (no overlay) |
| **Troubleshooting** | Harder (encapsulated packets) | Easier (native routing) |
| **Physical network visibility** | Pods invisible to physical net | Pod CIDRs visible via BGP |
| **Multi-cluster** | Simpler (isolated overlays) | Requires BGP coordination |
| **MetalLB integration** | Works with L2 mode | Works with BGP mode |
| **Recommended for** | Most deployments | High-performance, routed DC |

### Recommendation for This Deployment

**VXLAN mode** is recommended as the default for both clusters because:
- No dependency on physical router BGP configuration
- Simpler operations in air-gapped environments
- Sufficient performance for 10GbE infrastructure
- MetalLB L2 mode works without BGP on routers

**BGP mode** is recommended if:
- You need maximum throughput (HPC, AI/ML workloads)
- Your network team can configure BGP peering on ToR switches
- You want pod CIDRs routable from physical network

### Configuration: VXLAN Mode

```yaml
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: management-pod-cidr
spec:
  cidr: 10.1.0.0/16
  vxlanMode: Always
  natOutgoing: true
  disabled: false
  nodeSelector: all()
---
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: application-pod-cidr
spec:
  cidr: 10.2.0.0/16
  vxlanMode: Always
  natOutgoing: true
  disabled: false
  nodeSelector: all()
```

### Configuration: BGP Mode

```yaml
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: management-pod-cidr
spec:
  cidr: 10.1.0.0/16
  ipipMode: Never
  vxlanMode: Never
  natOutgoing: true
  disabled: false
  nodeSelector: all()
---
# BGP configuration (global)
apiVersion: crd.projectcalico.org/v1
kind: BGPConfiguration
metadata:
  name: default
spec:
  logSeverityScreen: Info
  nodeToNodeMeshEnabled: true
  asNumber: 64513
```

---

## BGP Peering with Physical Routers

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    TOP-OF-RACK SWITCH                        │
│                    BGP AS 64512                              │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                 │
│  │ Route    │  │ Route    │  │ Route    │                 │
│  │ Reflector│  │ Reflector│  │ Reflector│                 │
│  │ (RR1)    │  │ (RR2)    │  │ (RR3)    │                 │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                 │
│       │              │              │                        │
└───────┼──────────────┼──────────────┼────────────────────────┘
        │              │              │
   eBGP Peering   eBGP Peering   eBGP Peering
   AS 64513       AS 64513       AS 64513
        │              │              │
┌───────┴──────────────┴──────────────┴────────────────────────┐
│                    KUBERNETES WORKERS                         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐       │
│  │ MGMT-W1 │  │ MGMT-W2 │  │ MGMT-W3 │  │ MGMT-W4 │  ...  │
│  │ BGP     │  │ BGP     │  │ BGP     │  │ BGP     │       │
│  │ Peer    │  │ Peer    │  │ Peer    │  │ Peer    │       │
│  │10.0.3.11│  │10.0.3.12│  │10.0.3.13│  │10.0.3.14│       │
│  │ Pod     │  │ Pod     │  │ Pod     │  │ Pod     │       │
│  │10.1.0.0 │  │10.1.1.0 │  │10.1.2.0 │  │10.1.3.0 │       │
│  │  /24    │  │  /24    │  │  /24    │  │  /24    │       │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### Route Reflector Configuration

Instead of full-mesh BGP between all nodes, use Route Reflectors on the ToR switches:

```yaml
# Disable node-to-node mesh (use RR instead)
apiVersion: crd.projectcalico.org/v1
kind: BGPConfiguration
metadata:
  name: default
spec:
  nodeToNodeMeshEnabled: false
  asNumber: 64513

---
# Configure Route Reflector peers
apiVersion: crd.projectcalico.org/v1
kind: BGPPeer
metadata:
  name: rr-peer-1
spec:
  peerIP: 10.0.3.1          # ToR switch / RR IP
  asNumber: 64512
  nodeSelector: "rack == 'rack1'"

---
apiVersion: crd.projectcalico.org/v1
kind: BGPPeer
metadata:
  name: rr-peer-2
spec:
  peerIP: 10.0.3.2          # Secondary ToR / RR IP
  asNumber: 64512
  nodeSelector: "rack == 'rack1'"
```

### Per-Node BGP Peer (Alternative to RR)

For smaller deployments without Route Reflectors:

```yaml
apiVersion: crd.projectcalico.org/v1
kind: BGPPeer
metadata:
  name: tor-switch-peer
spec:
  peerIP: 10.0.3.1
  asNumber: 64512
  node: mgmt-w1              # Specific node
```

### AS Number Plan

| Entity | ASN | Notes |
|--------|-----|-------|
| Physical network (ToR) | 64512 | Private ASN |
| Management cluster | 64513 | Private ASN |
| Application cluster | 64514 | Private ASN |
| MetalLB (App cluster) | 64514 | Same as cluster |

---

## IP Pool Configuration

### No Overlap Between Clusters

Critical: Pod CIDRs and Service CIDRs must not overlap between clusters.

```yaml
# Management Cluster IPPool
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: mgmt-pod-pool
spec:
  cidr: 10.1.0.0/16
  vxlanMode: Always
  natOutgoing: true
  block_size: 26              # 64 IPs per node
  disabled: false
  nodeSelector: all()

---
# Application Cluster IPPool
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: app-pod-pool
spec:
  cidr: 10.2.0.0/16
  vxlanMode: Always
  natOutgoing: true
  block_size: 26
  disabled: false
  nodeSelector: all()
```

### Block Size Planning

| Block Size | IPs per Node | Max Nodes (/16) | Use Case |
|------------|-------------|-----------------|----------|
| /24 | 256 | 254 | Large nodes (100+ pods) |
| /25 | 128 | 508 | Medium nodes |
| /26 | 64 | 1020 | Standard (recommended) |
| /27 | 32 | 2044 | Small nodes |

### NAT Outbound Configuration

```yaml
# Allow pods to reach external networks (internet via proxy, or other subnets)
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: mgmt-pod-pool
spec:
  cidr: 10.1.0.0/16
  natOutgoing: true           # SNAT for outbound pod traffic
  vxlanMode: Always
```

### Disabling Default Pool (Custom Pool Only)

```yaml
# If you want to use only custom pools, disable the default
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  cidr: 192.168.0.0/16       # Original default
  disabled: true              # Disable it
```

---

## Network Policy Examples

### Default Deny All

Apply a cluster-wide default deny policy. All traffic is blocked unless explicitly allowed.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}             # Selects all pods
  policyTypes:
  - Ingress
  - Egress
```

### Allow Specific Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api-server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

### Namespace Isolation

Allow traffic within a namespace but block cross-namespace (except system namespaces):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-isolation
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}          # Allow same-namespace traffic
    - namespaceSelector:
        matchLabels:
          name: monitoring      # Allow from monitoring namespace
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
```

### Allow DNS (Required for All Namespaces)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

### Allow Outbound to Specific CIDR

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: payment-service
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 203.0.113.0/24
    ports:
    - protocol: TCP
      port: 443
  - to:
    - ipBlock:
        cidr: 10.0.0.0/8          # Internal networks
    ports:
    - protocol: TCP
      port: 443
```

### Calico Global Network Policy (Cluster-Wide)

```yaml
apiVersion: crd.projectcalico.org/v1
kind: GlobalNetworkPolicy
metadata:
  name: global-deny-egress
spec:
  selector: all()
  types:
  - Egress
  egress:
  - action: Allow
    destination:
      nets:
      - 10.0.0.0/8
      - 172.16.0.0/12
      - 192.168.0.0/16
  - action: Deny
    destination:
      nets:
      - 0.0.0.0/0
```

### Allow Inter-Cluster Communication

```yaml
# Allow Application cluster pods to reach Management cluster API
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-mgmt-api-access
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: argocd
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 10.0.2.0/24         # Management masters
    ports:
    - protocol: TCP
      port: 6443
```

---

## MTU Considerations

### Overhead by Encapsulation Type

| Mode | Overhead | Effective MTU (1500 link) | Notes |
|------|----------|---------------------------|-------|
| VXLAN | 50 bytes | 1450 | UDP(8) + VXLAN(8) + outer IP(20) + outer ETH(14) |
| IPIP | 20 bytes | 1480 | Deprecated |
| BGP (none) | 0 bytes | 1500 | Native routing |
| WireGuard | 60 bytes | 1440 | If encryption enabled |

### VXLAN MTU Configuration

```yaml
# Calico FelixConfiguration for MTU tuning
apiVersion: crd.projectcalico.org/v1
kind: FelixConfiguration
metadata:
  name: default
spec:
  vxlanMTU: 1450              # For 1500 byte physical MTU
  vxlanMTUByInterface:
    "eth0": 1450
    "ens1": 9000              # Jumbo frame interface
  # For jumbo frames (9000 MTU physical):
  # vxlanMTU: 8950
```

### Path MTU Discovery

Calico enables PMTU discovery by default. Ensure ICMP "Fragmentation Needed" messages are not blocked:

```bash
# Firewall rule: Allow ICMP Type 3 Code 4 (Fragmentation Needed)
iptables -A INPUT -p icmp --icmp-type 3/4 -j ACCEPT
```

### Jumbo Frames

If your physical network supports jumbo frames (9000 MTU):

```yaml
# Set physical interface MTU to 9000 on all nodes
# /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    eth0:
      mtu: 9000
      addresses:
      - 10.0.3.11/24

# Calico FelixConfiguration
apiVersion: crd.projectcalico.org/v1
kind: FelixConfiguration
metadata:
  name: default
spec:
  vxlanMTU: 8950
```

---

## eBPF Data Plane

### Overview

Calico's eBPF data plane is an enterprise feature that replaces iptables/kube-proxy with eBPF programs for:
- Service load balancing (replaces kube-proxy/IPVS)
- Network policy enforcement
- Connection tracking

### Requirements

| Requirement | Value |
|-------------|-------|
| Kernel version | >= 5.3 (recommended >= 5.10) |
| Calico version | >= 3.18 (Enterprise) |
| Helm chart | tigera-operator |
| License | Calico Enterprise license |

### Enable eBPF Mode

```yaml
apiVersion: crd.projectcalico.org/v1
kind: FelixConfiguration
metadata:
  name: default
spec:
  bpfEnabled: true
  bpfExternalServiceMode: Tunnel     # Preserve source IP
  bpfKubeProxyIptablesCleanupEnabled: true
  bpfLogLevel: "Off"
  bpfConnectTimeLoadBalancing: "TCP"  # TCP-aware LB
  bpfHostNetworkedNATWithoutCTLB: "Disabled"
```

### Disable kube-proxy (When Using eBPF)

```yaml
# In KubeSpray, set:
kube_proxy_remove: true
```

### Verify eBPF Mode

```bash
# Check if eBPF is active
calicoctl felix configured

# Check BPF maps
calicoctl bpftool map show

# Check service acceleration
calicoctl bpftool ipcache show
```

---

## Calicoctl Installation and Usage

### Installation (Air-Gapped)

```bash
# Download from Nexus (air-gap)
curl -LO https://nexus.corp.internal/repository/raw-hosted/calicoctl/v3.27.0/calicoctl-linux-amd64

# Or pull from Harbor and extract
docker pull harbor.corp.internal/k8s/calicoctl:v3.27.0
docker create --name extract harbor.corp.internal/k8s/calicoctl:v3.27.0
docker cp extract:/calicoctl-linux-amd64 ./calicoctl
docker rm extract

# Install
chmod +x calicoctl
mv calicoctl /usr/local/bin/
```

### Configuration

```yaml
# ~/.calicoctl/calicoctl.cfg
apiVersion: projectcalico.org/v3
kind: CalicoAPIConfig
metadata:
spec:
  datastoreType: "kubernetes"
  kubeconfig: "/root/.kube/config"
  # Or for direct etcd access:
  # etcdEndpoints: "https://10.0.2.11:2379,https://10.0.2.12:2379"
  # etcdKeyFile: "/etc/kubernetes/pki/etcd/server.key"
  # etcdCertFile: "/etc/kubernetes/pki/etcd/server.crt"
  # etcdCACertFile: "/etc/kubernetes/pki/etcd/ca.crt"
```

### Common Commands

```bash
# Node status
calicoctl node status

# List IP pools
calicoctl get ippool -o wide

# List network policies
calicoctl get networkpolicy --all-namespaces

# List global network policies
calicoctl get globalnetworkpolicy

# List BGP peers
calicoctl get bgppeer

# List BGP configuration
calicoctl get bgpconfig

# Get workload endpoints
calicoctl get workloadendpoint

# Check IP pool utilization
calicoctl get ippool -o yaml

# Create a network policy from file
calicoctl apply -f policy.yaml

# Delete a resource
calicoctl delete ippool mgmt-pod-pool

# Export all Calico resources
calicoctl export -f calico-backup.yaml
```

---

## Air-Gap: Calico Images from Harbor

### Required Images

| Image | Purpose | Size (approx) |
|-------|---------|---------------|
| calico/node | Felix agent, BIRD | 150 MB |
| calico/cni | CNI plugin binaries | 100 MB |
| calico/kube-controllers | Kubernetes controllers | 80 MB |
| calico/typha | API reduction proxy | 60 MB |
| calico/pod2daemon-flexvol | FlexVolume driver | 10 MB |
| calicoctl | CLI tool | 50 MB |

### Image Mirroring Script

```bash
#!/bin/bash
# mirror-calico-images.sh

HARBOR="harbor.corp.internal"
PROJECT="k8s"
VERSION="v3.27.0"

IMAGES=(
  "calico/node:${VERSION}"
  "calico/cni:${VERSION}"
  "calico/kube-controllers:${VERSION}"
  "calico/typha:${VERSION}"
  "calico/pod2daemon-flexvol:${VERSION}"
)

for img in "${IMAGES[@]}"; do
  echo "Mirroring ${img}..."
  docker pull "docker.io/${img}"
  docker tag "docker.io/${img}" "${HARBOR}/${PROJECT}/${img}"
  docker push "${HARBOR}/${PROJECT}/${img}"
done

echo "All Calico images mirrored to ${HARBOR}/${PROJECT}/"
```

### KubeSpray Air-Gap Configuration

```yaml
# inventory/group_vars/all/offline.yml
registry_host: "harbor.corp.internal"
kube_image_repo: "harbor.corp.internal/k8s"
calico_image_repo: "harbor.corp.internal/k8s"

# Image references
calico_node_image_repo: "{{ calico_image_repo }}/node"
calico_cni_image_repo: "{{ calico_image_repo }}/cni"
calico_controllers_image_repo: "{{ calico_image_repo }}/kube-controllers"
calico_typha_image_repo: "{{ calico_image_repo }}/typha"
calico_flexvol_image_repo: "{{ calico_image_repo }}/pod2daemon-flexvol"
```

### containerd Registry Configuration

```toml
# /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".registry]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
    endpoint = ["https://harbor.corp.internal/v2/proxy-docker-hub"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.corp.internal"]
    endpoint = ["https://harbor.corp.internal"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs."harbor.corp.internal".tls]
    insecure_skip_verify = false
    ca_file = "/etc/container.d/certs/harbor-ca.crt"
```

---

## Performance Tuning

### Connection Tracking (conntrack)

```yaml
# FelixConfiguration for conntrack tuning
apiVersion: crd.projectcalico.org/v1
kind: FelixConfiguration
metadata:
  name: default
spec:
  bpfLogLevel: ""
  reportingInterval: "0s"
  healthEnabled: true
  
  # Conntrack settings
  # Default conntrack table size: 65536
  # For high-traffic clusters, increase via sysctl on nodes
```

### Node-Level sysctl Tuning

```bash
# /etc/sysctl.d/99-calico.conf
# Increase conntrack table size
net.netfilter.nf_conntrack_max = 524288
net.netfilter.nf_conntrack_buckets = 131072

# Increase connection hash size
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120

# Apply
sysctl -p /etc/sysctl.d/99-calico.conf
```

### Flow Logs (for Monitoring)

```yaml
# Enable flow logs for observability
apiVersion: crd.projectcalico.org/v1
kind: FlowLogs
metadata:
  name: all-flows
spec:
  type: FlowLog
  source: ""
  destination: ""
  action: ""
  reporter: "all"
  flowLogsFileEnabled: true
  flowLogsFileMaxFiles: 5
  flowLogsFileMaxFileSize: 100
```

### BGP Tuning

```yaml
apiVersion: crd.projectcalico.org/v1
kind: BGPConfiguration
metadata:
  name: default
spec:
  nodeToNodeMeshEnabled: false    # Use RR for >50 nodes
  asNumber: 64513
  logSeverityScreen: Info
```

### Resource Allocation

```yaml
# Resource requests/limits for Calico components
# In tigera-operator or DaemonSet spec:
resources:
  requests:
    cpu: "250m"
    memory: "256Mi"
  limits:
    cpu: "1000m"
    memory: "512Mi"

# For Typha:
resources:
  requests:
    cpu: "200m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

---

## Troubleshooting Connectivity

### Common Issues and Resolution

#### 1. Pod Cannot Reach Another Pod on Different Node

```bash
# Check if VXLAN tunnel is established
ip -d link show vxlan.calico

# Check routes
ip route show | grep calico

# Check BGP peers (BGP mode)
calicoctl node status

# Check iptables rules
iptables -L -n -v | grep calico

# Check Felix logs
kubectl -n calico-system logs -l k8s-app=calico-node --tail=100
```

#### 2. Pod Cannot Reach External Network

```bash
# Check NAT rules
iptables -t nat -L -n -v | grep MASQUERADE

# Check natOutgoing setting
kubectl get ippool -o yaml | grep natOutgoing

# Check default route on node
ip route show default
```

#### 3. Network Policy Blocking Traffic

```bash
# List all policies in namespace
kubectl get networkpolicy -n <namespace>

# Check Calico's iptables rules for the pod
iptables -L -n -v --line-numbers | grep <pod-ip>

# Use calicoctl to check workload endpoints
calicoctl get workloadendpoint -o wide

# Check policy order (Calico evaluates in order)
calicoctl get networkpolicy --all-namespaces -o wide
```

#### 4. IP Pool Exhaustion

```bash
# Check IP pool utilization
calicoctl get ippool -o yaml

# Check how many blocks are allocated
kubectl get ippool -o jsonpath='{.items[*].spec}'
```

### Diagnostic Commands Reference

```bash
# Full node status
calicoctl node status

# Check all Calico resources
calicoctl get all

# Check Felix configuration
calicoctl get felixconfig -o yaml

# Check BGP peers
calicoctl get bgppeer

# Check cluster info
calicoctl get clusterinfo

# Run connectivity test
kubectl run test-pod --image=harbor.corp.internal/system/netshoot:latest -- sleep 3600
kubectl exec -it test-pod -- ping <target-pod-ip>

# Capture traffic on VXLAN interface
tcpdump -i vxlan.calico -n

# Check conntrack table
conntrack -L | wc -l
conntrack -S
```

### Health Checks

```bash
# Calico node health
kubectl -n calico-system get pods -l k8s-app=calico-node

# Check Felix is reporting healthy
kubectl -n calico-system exec <calico-node-pod> -- calico-node -felix-ready

# Check BIRD is healthy
kubectl -n calico-system exec <calico-node-pod> -- birdcl show status

# Check all BGP sessions
kubectl -n calico-system exec <calico-node-pod> -- birdcl show proto all
```
