# MetalLB Guide

## Table of Contents
- [Overview](#overview)
- [L2 Mode vs BGP Mode](#l2-mode-vs-bgp-mode)
- [IPAddressPool Configuration](#ipaddresspool-configuration)
- [Advertisement Configuration](#advertisement-configuration)
- [BGP Peering with Physical Routers](#bgp-peering-with-physical-routers)
- [Pod Sizing and Resource Allocation](#pod-sizing-and-resource-allocation)
- [Failover Behavior](#failover-behavior)
- [Integration with NGINX Ingress Controller](#integration-with-nginx-ingress-controller)
- [Integration with HAProxy](#integration-with-haproxy)
- [Air-Gap: MetalLB Images from Harbor](#air-gap-metallb-images-from-harbor)
- [Troubleshooting](#troubleshooting)

---

## Overview

MetalLB provides `LoadBalancer` type services for bare-metal Kubernetes clusters. It is deployed **only on the Application cluster** — the Management cluster uses external HAProxy+keepalived for service exposure.

**Architecture:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    APPLICATION CLUSTER                           │
│                                                                 │
│  External Client                                                │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  MetalLB LoadBalancer IP: 10.0.21.100                    │   │
│  │  (Allocated from pool: 10.0.21.100-10.0.21.200)         │   │
│  │                                                          │   │
│  │  L2 Mode: Speaker responds to ARP for the IP            │   │
│  │  BGP Mode: Speaker advertises IP via eBGP to ToR        │   │
│  └─────────────────────────────────────────────────────────┘   │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  NGINX Ingress Controller (DaemonSet)                    │   │
│  │  Running on: APP-W1, APP-W2, APP-W3, APP-W4, APP-W5     │   │
│  └─────────────────────────────────────────────────────────┘   │
│       │                                                         │
│       ▼                                                         │
│  Backend Service / Pod                                          │
└─────────────────────────────────────────────────────────────────┘
```

**Components:**

| Component | Purpose |
|-----------|---------|
| Controller | Watches Services of type LoadBalancer, assigns IPs from pools |
| Speaker (DaemonSet) | Announces assigned IPs via ARP (L2) or BGP |

**MetalLB IP Pool Allocation:**

| Pool Name | Range | Usage |
|-----------|-------|-------|
| app-ingress | 10.0.21.100 - 10.0.21.200 | NGINX Ingress, key platform services |
| app-services | 10.0.21.50 - 10.0.21.99 | Application LoadBalancer services |

---

## L2 Mode vs BGP Mode

### L2 Mode (ARP/NDP)

In Layer 2 mode, MetalKB uses ARP (IPv4) or NDP (IPv6) to announce service IPs.

**How it works:**
1. When a `LoadBalancer` service is created, the Controller assigns an IP from the pool.
2. The Speaker on one node (elected leader) responds to ARP requests for that IP.
3. All traffic for the IP goes to that single node.
4. kube-proxy then load-balances to backend pods.

**Characteristics:**
- Single node handles all traffic for a given IP (traffic hair-pinning)
- Failover time: ~3-10 seconds (ARP cache timeout on switches)
- No router configuration required
- Simpler to deploy and troubleshoot

### BGP Mode

In BGP mode, MetalLB peers with physical routers and announces service IPs.

**How it works:**
1. Controller assigns IP from pool.
2. Speaker announces the IP prefix to BGP peers (ToR switches).
3. Router load-balances traffic across all nodes via ECMP.
4. True distributed load balancing.

**Characteristics:**
- Traffic distributed across all nodes (ECMP)
- Failover time: ~1-3 seconds (BGP convergence)
- Requires BGP-capable routers
- More complex but higher performance

### Decision Table

| Criteria | L2 Mode | BGP Mode |
|----------|---------|----------|
| **Router requirements** | None | BGP-capable ToR |
| **Load distribution** | Single node per IP | ECMP across all nodes |
| **Failover time** | 3-10s | 1-3s |
| **Configuration complexity** | Low | Medium-High |
| **Maximum throughput** | Limited by single node | Aggregate of all nodes |
| **Source IP preservation** | Yes | No (unless using `externalTrafficPolicy: Local`) |
| **Recommended for** | Small-medium clusters | Production, large clusters |

### Recommendation

**L2 mode** is recommended for this deployment due to:
- Simpler operations in air-gapped environment
- No dependency on network team for BGP configuration
- Sufficient for 5-node cluster with 10GbE
- Faster deployment and troubleshooting

---

## IPAddressPool Configuration

### Basic Pool Definition

```yaml
# metallb-ipaddresspools.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: app-ingress-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.21.100-10.0.21.200
  autoAssign: true
  avoidBuggyIPs: true           # Skip .0 and .255
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: app-services-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.21.50-10.0.21.99
  autoAssign: true
  avoidBuggyIPs: true
```

### Pool with Specific IP Ranges and Exclusions

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: reserved-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.21.100-10.0.21.150
  - 10.0.21.175-10.0.21.180      # Non-contiguous range
  autoAssign: false               # Manual assignment only
  avoidBuggyIPs: true
```

### Service-Level Pool Selection

```yaml
# Use a specific pool via annotation on the Service
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: production
  annotations:
    metallb.universe.tf/address-pool: app-ingress-pool
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: my-app
```

### Static IP Assignment

```yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    metallb.universe.tf/address-pool: app-ingress-pool
    metallb.universe.tf/loadBalancerIPs: 10.0.21.102
spec:
  type: LoadBalancer
  ports:
  - port: 3000
    targetPort: 3000
  selector:
    app.kubernetes.io/name: grafana
```

---

## Advertisement Configuration

### L2Advertisement

```yaml
# metallb-l2-advertisement.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - app-ingress-pool
  - app-services-pool
  nodeSelectors:
  - matchLabels:
      kubernetes.io/os: linux          # Only announce from Linux nodes
  interfaces:
  - eth0                                # Only use specific interfaces
```

### L2Advertisement with Node Affinity

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ingress-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - app-ingress-pool
  nodeSelectors:
  - matchLabels:
      node-role.kubernetes.io/worker: ""  # Only from worker nodes
```

### BGPAdvertisement

```yaml
# metallb-bgp-advertisement.yaml
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: bgp-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - app-ingress-pool
  - app-services-pool
  aggregationLen: 32                     # Announce individual /32 routes
  communities:
  - 64512:65281                         # No-export community
  localPref: 100                         # Local preference
  nodeSelectors:
  - matchLabels:
      kubernetes.io/os: linux
```

### BGP Communities

```yaml
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: bgp-advertisement-tier1
  namespace: metallb-system
spec:
  ipAddressPools:
  - app-ingress-pool
  communities:
  - 64512:100                          # Custom community for tier-1 services
  - no-export                           # Standard community
```

---

## BGP Peering with Physical Routers

### BGPPeer Configuration

```yaml
# metallb-bgp-peers.yaml
apiVersion: metallb.io/v1beta1
kind: BGPPeer
metadata:
  name: tor-switch-1
  namespace: metallb-system
spec:
  myASN: 64514                          # MetalLB ASN (App cluster)
  peerASN: 64512                       # ToR switch ASN
  peerAddress: 10.0.5.1                # ToR switch IP
  routerID: 10.0.5.11                  # MetalLB router ID
  bfdProfile: bfd-default              # BFD for fast failover
  holdTime: 90s
  keepAliveTime: 30s

---
apiVersion: metallb.io/v1beta1
kind: BGPPeer
metadata:
  name: tor-switch-2
  namespace: metallb-system
spec:
  myASN: 64514
  peerASN: 64512
  peerAddress: 10.0.5.2                # Secondary ToR
  routerID: 10.0.5.11
  bfdProfile: bfd-default
```

### BFD Profile (Fast Failover)

```yaml
apiVersion: metallb.io/v1beta1
kind: BFDProfile
metadata:
  name: bfd-default
  namespace: metallb-system
spec:
  receiveInterval: 300ms
  transmitInterval: 300ms
  detectMultiplier: 3
  echoInterval: 50ms
  echoMode: true
  passiveMode: true
  minimumTtl: 254
```

### Node-Specific BGP Peer

```yaml
apiVersion: metallb.io/v1beta1
kind: BGPPeer
metadata:
  name: app-w1-peer
  namespace: metallb-system
spec:
  myASN: 64514
  peerASN: 64512
  peerAddress: 10.0.5.1
  nodeSelectors:
  - matchLabels:
      kubernetes.io/hostname: app-w1
```

### AS Number Plan for MetalLB

| Entity | ASN |
|--------|-----|
| Physical network | 64512 |
| Management cluster Calico | 64513 |
| Application cluster Calico | 64514 |
| Application cluster MetalLB | 64514 |

---

## Pod Sizing and Resource Allocation

### Recommended Resources

```yaml
# Controller resources
controller:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi

# Speaker resources
speaker:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
```

### Helm Values

```yaml
# values-metallb.yaml
controller:
  image:
    registry: harbor.corp.internal
    repository: k8s/metallb/controller
    tag: v0.14.3
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "256Mi"

speaker:
  image:
    registry: harbor.corp.internal
    repository: k8s/metallb/speaker
    tag: v0.14.3
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "200m"
      memory: "256Mi"
  # Required for BGP mode
  enabled: true
  # Tolerate all taints (run on all nodes including masters if needed)
  tolerations:
  - effect: NoSchedule
    operator: Exists
```

---

## Failover Behavior

### L2 Mode Failover

```
Timeline for L2 Failover:
  T+0s    Active speaker node fails
  T+2s    ARP cache expires on upstream switch
  T+3-5s  New speaker starts responding to ARP
  T+5-10s Traffic flows to new node (ARP cache refreshed)
```

**Mitigation:**
- Reduce ARP cache timeout on upstream switches (30s → 10s)
- Use `externalTrafficPolicy: Local` to avoid cross-node routing

### BGP Mode Failover

```
Timeline for BGP Failover (with BFD):
  T+0s     Active speaker node fails
  T+0.9s   BFD detects failure (300ms × 3 multiplier)
  T+1s     BGP session drops, routes withdrawn
  T+1-3s   Traffic rerouted to remaining nodes via ECMP
```

### Health Check Configuration

```yaml
# Speaker uses Kubernetes readiness probe
# Additional health check for L2 mode
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-with-health
  namespace: metallb-system
spec:
  ipAddressPools:
  - app-ingress-pool
```

---

## Integration with NGINX Ingress Controller

### Recommended: MetalLB + NGINX Ingress

The NGINX Ingress Controller uses a `LoadBalancer` service backed by MetalLB for external traffic entry.

### Service Configuration

```yaml
# ingress-nginx-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  annotations:
    metallb.universe.tf/address-pool: app-ingress-pool
    metallb.universe.tf/loadBalancerIPs: 10.0.21.100
    metallb.universe.tf/allow-shared-ip: "ingress"  # L2 mode: share IP
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local    # Preserve source IP, avoid hairpin
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: http
  - name: https
    port: 443
    protocol: TCP
    targetPort: https
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/component: controller
```

### Alternative: DaemonSet with hostNetwork (No MetalLB needed)

```yaml
# When NGINX Ingress runs on external LB nodes with hostNetwork
# MetalLB is NOT needed for the ingress service itself
# But still needed for other LoadBalancer services

apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ingress-nginx
    spec:
      hostNetwork: true
      nodeSelector:
        ingress-nginx: "true"     # Only on designated nodes
      containers:
      - name: controller
        image: harbor.corp.internal/k8s/ingress-nginx/controller:v1.9.4
        ports:
        - containerPort: 80
          hostPort: 80
        - containerPort: 443
          hostPort: 443
```

---

## Integration with HAProxy

### Architecture

```
External Client
       │
       ▼
  HAProxy (VIP: 10.0.1.20)
       │
       ├── Port 80/443 → NGINX Ingress (MetalLB IP: 10.0.21.100)
       │
       └── Port 9090 → Prometheus (MetalLB IP: 10.0.21.103)
```

### HAProxy Backend for MetalLB Services

```haproxy
# MetalLB-backed services (App Cluster)
frontend app-services
    bind 10.0.1.20:80
    bind 10.0.1.20:443
    mode tcp
    option tcplog

    # Route to MetalLB IPs
    default_backend nginx-ingress-metallb

backend nginx-ingress-metallb
    mode tcp
    balance roundrobin
    option tcp-check
    # Forward to the MetalLB-assigned Ingress IP
    server ingress-lb 10.0.21.100:443 check
```

### Hybrid: MetalLB for Some Services, NodePort for Others

```yaml
# Some services exposed directly via MetalLB
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    metallb.universe.tf/loadBalancerIPs: 10.0.21.102
spec:
  type: LoadBalancer
  ports:
  - port: 3000
    targetPort: 3000
  selector:
    app.kubernetes.io/name: grafana
---
# Others exposed via NodePort + HAProxy
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  type: NodePort
  ports:
  - port: 9090
    targetPort: 9090
    nodePort: 30900
  selector:
    app.kubernetes.io/name: prometheus
```

```haproxy
# HAProxy backend for NodePort service
backend prometheus-nodeport
    mode tcp
    balance roundrobin
    option tcp-check
    server app-worker1 10.0.5.11:30900 check
    server app-worker2 10.0.5.12:30900 check
    server app-worker3 10.0.5.13:30900 check
    server app-worker4 10.0.5.14:30900 check
    server app-worker5 10.0.5.15:30900 check
```

---

## Air-Gap: MetalLB Images from Harbor

### Required Images

| Image | Purpose | Tag |
|-------|---------|-----|
| metallb/controller | Pool management, IP assignment | v0.14.3 |
| metallb/speaker | ARP/BGP announcement | v0.14.3 |
| metallb/frr | FRR routing stack (BGP mode alternative) | v0.14.3 |

### Mirroring Script

```bash
#!/bin/bash
# mirror-metallb-images.sh

HARBOR="harbor.corp.internal"
PROJECT="k8s"
VERSION="v0.14.3"

IMAGES=(
  "metallb/controller:${VERSION}"
  "metallb/speaker:${VERSION}"
)

for img in "${IMAGES[@]}"; do
  echo "Mirroring ${img}..."
  docker pull "quay.io/${img}"
  docker tag "quay.io/${img}" "${HARBOR}/${PROJECT}/${img}"
  docker push "${HARBOR}/${PROJECT}/${img}"
done
```

### Helm Installation (Air-Gapped)

```bash
# Add Helm repo (from Nexus or local chart)
helm repo add metallb https://nexus.corp.internal/repository/helm-proxy/metallb
helm repo update

# Or install from local chart
helm install metallb ./charts/metallb \
  -n metallb-system \
  --create-namespace \
  -f values-metallb.yaml
```

### Deployment via Manifest (Recommended for Air-Gap)

```bash
# Download manifest from Nexus
curl -LO https://nexus.corp.internal/repository/raw-hosted/metallb-native-v0.14.3.yaml

# Update image references
sed -i 's|quay.io/metallb/|harbor.corp.internal/k8s/metallb/|g' metallb-native-v0.14.3.yaml

# Apply
kubectl apply -f metallb-native-v0.14.3.yaml
```

---

## Troubleshooting

### Checking MetalLB Status

```bash
# Check Controller and Speaker pods
kubectl -n metallb-system get pods -o wide

# Check Controller logs
kubectl -n metallb-system logs -l app.kubernetes.io/component=controller

# Check Speaker logs
kubectl -n metallb-system logs -l app.kubernetes.io/component=speaker

# Check L2 advertisement status
kubectl -n metallb-system get l2advertisement -o yaml

# Check IPAddressPool status
kubectl -n metallb-system get ipaddresspool -o yaml
```

### Service Not Getting an External IP

```bash
# Check the service status
kubectl get svc -n <namespace>
kubectl describe svc <service-name> -n <namespace>

# Check if pool has available IPs
kubectl -n metallb-system get ipaddresspool -o yaml

# Check Controller logs for assignment errors
kubectl -n metallb-system logs -l app.kubernetes.io/component=controller --tail=50

# Common issues:
# 1. No IP pools defined
# 2. All IPs in pool exhausted
# 3. Service annotation specifies non-existent pool
# 4. Pool conflicting with existing service IP
```

### Traffic Not Reaching Backend Pods

```bash
# For L2 mode: Check which node is the "leader" for the IP
kubectl -n metallb-system logs -l app.kubernetes.io/component=speaker | grep leader

# Check ARP table on upstream switch
# (requires access to switch CLI)
# show arp | include 10.0.21.100

# Verify externalTrafficPolicy setting
kubectl get svc <service> -o yaml | grep externalTrafficPolicy

# Check if backend pods are ready
kubectl get endpoints <service-name> -n <namespace>
```

### BGP Session Not Established

```bash
# Check BGP peer status
kubectl -n metallb-system logs -l app.kubernetes.io/component=speaker | grep -i bgp

# Verify BGP peer configuration
kubectl -n metallb-system get bgpppeer -o yaml

# Check if port 179 is accessible
nc -zv 10.0.5.1 179

# Verify ASN configuration
kubectl -n metallb-system get bgppeer -o jsonpath='{.items[*].spec}'
```

### IP Conflict Detection

```bash
# MetalLB logs will show conflicts
kubectl -n metallb-system logs -l app.kubernetes.io/component=controller | grep -i conflict

# Check if IP is already in use
arping -D -I eth0 10.0.21.100
```

### Diagnostic Commands

```bash
# Full MetalLB status dump
kubectl -n metallb-system get all
kubectl -n metallb-system get ipaddresspool
kubectl -n metallb-system get l2advertisement
kubectl -n metallb-system get bgpadvertisement
kubectl -n metallb-system get bgppeer

# Check all LoadBalancer services across cluster
kubectl get svc --all-namespaces | grep LoadBalancer

# Test connectivity to a LoadBalancer IP
curl -v http://10.0.21.100
nc -zv 10.0.21.100 80
```

### Common Error Messages

| Error | Cause | Resolution |
|-------|-------|------------|
| `no available IPs` | Pool exhausted | Expand pool or remove unused services |
| `pool not found` | Wrong annotation | Check `metallb.universe.tf/address-pool` annotation |
| `BGP session refused` | ASN mismatch or ACL | Verify peer ASN and firewall rules |
| `leader election failed` | Speaker pod issue | Check Speaker pod logs and node connectivity |
| `IP conflict detected` | Duplicate IP assignment | Check for static IP conflicts in pool range |
