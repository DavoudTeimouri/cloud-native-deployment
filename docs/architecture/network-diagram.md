# Network Diagrams

## Table of Contents

- [Physical Network Layout](#physical-network-layout)
- [Logical Network (Calico CNI)](#logical-network-calico-cni)
- [Service Network](#service-network)
- [HAProxy → NGINX Ingress Flow (HTTP)](#proxy--nginx-ingress-flow-http)
- [HAProxy TCP Passthrough Flow](#haproxy-tcp-passthrough-flow)
- [MetalLB IP Pool Allocation](#metallb-ip-pool-allocation)
- [Ceph Network](#ceph-network)
- [DNS Resolution Flow](#dns-resolution-flow)
- [IP Address Reference](#ip-address-reference)

---

## Physical Network Layout

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              RACK 1 (Management Cluster)                            │
│                                                                                     │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐                      │
│  │MGMT-M1  │ │MGMT-M2  │ │MGMT-M3  │ │MGMT-M4  │ │MGMT-M5  │  (Masters)          │
│  │10.0.2.11│ │10.0.2.12│ │10.0.2.13│ │10.0.2.14│ │10.0.2.15│                      │
│  │10.0.10.1│ │10.0.10.2│ │10.0.10.3│ │10.0.10.4│ │10.0.10.5│  (Ceph Public)      │
│  │10.0.11.1│ │10.0.11.2│ │10.0.11.3│ │10.0.11.4│ │10.0.11.5│  (Ceph Cluster)     │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘                      │
│       │           │           │           │           │                             │
│  ┌────┴───────────┴───────────┴───────────┴───────────┴────┐                       │
│  │                    10GbE Switch (Access)                 │                       │
│  │                    VLAN 102, 110, 111                    │                       │
│  └────┬───────────┬───────────┬───────────┬───────────┬────┘                       │
│       │           │           │           │           │                             │
│  ┌────┴────┐ ┌────┴────┐ ┌────┴────┐ ┌────┴────┐ ┌────┴────┐                      │
│  │MGMT-W1  │ │MGMT-W2  │ │MGMT-W3  │ │MGMT-W4  │ │MGMT-W5  │  (Workers)          │
│  │10.0.3.11│ │10.0.3.12│ │10.0.3.13│ │10.0.3.14│ │10.0.3.15│                      │
│  │10.0.10.1│ │10.0.10.2│ │10.0.10.3│ │10.0.10.4│ │10.0.10.5│  (Ceph Public)      │
│  │10.0.11.1│ │10.0.11.2│ │10.0.11.3│ │10.0.11.4│ │10.0.11.5│  (Ceph Cluster)     │
│  │+OSD 2TB │ │+OSD 2TB │ │+OSD 2TB │ │+OSD 2TB │ │+OSD 2TB │                      │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘                      │
│                                                                                     │
│  ┌─────────────┐  ┌─────────────┐                                                  │
│  │ LB-MGMT-01  │  │ LB-MGMT-02  │  (External Load Balancers)                      │
│  │ 10.0.1.11   │  │ 10.0.1.12   │                                                  │
│  │ VIP:10.0.1.10│  │ VIP:10.0.1.10│                                                  │
│  └─────────────┘  └─────────────┘                                                  │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                              │
                                              │ 10GbE Uplink
                                              │
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              RACK 2 (Application Cluster)                           │
│                                                                                     │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐                      │
│  │APP-M1   │ │APP-M2   │ │APP-M3   │ │APP-M4   │ │APP-M5   │  (Masters)           │
│  │10.0.4.11│ │10.0.4.12│ │10.0.4.13│ │10.0.4.14│ │10.0.4.15│                      │
│  │10.0.10.6│ │10.0.10.7│ │10.0.10.8│ │10.0.10.9│ │10.0.10.10│ (Ceph Public)      │
│  │10.0.11.6│ │10.0.11.7│ │10.0.11.8│ │10.0.11.9│ │10.0.11.10│ (Ceph Cluster)     │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘                      │
│       │           │           │           │           │                             │
│  ┌────┴───────────┴───────────┴───────────┴───────────┴────┐                       │
│  │                    10GbE Switch (Access)                 │                       │
│  │                    VLAN 104, 110, 111                    │                       │
│  └────┬───────────┬───────────┬───────────┬───────────┬────┘                       │
│       │           │           │           │           │                             │
│  ┌────┴────┐ ┌────┴────┐ ┌────┴────┐ ┌────┴────┐ ┌────┴────┐                      │
│  │APP-W1   │ │APP-W2   │ │APP-W3   │ │APP-W4   │ │APP-W5   │  (Workers)           │
│  │10.0.5.11│ │10.0.5.12│ │10.0.5.13│ │10.0.5.14│ │10.0.5.15│                      │
│  │10.0.10.6│ │10.0.10.7│ │10.0.10.8│ │10.0.10.9│ │10.0.10.10│ (Ceph Public)      │
│  │10.0.11.6│ │10.0.11.7│ │10.0.11.8│ │10.0.11.9│ │10.0.11.10│ (Ceph Cluster)     │
│  │+OSD 2TB │ │+OSD 2TB │ │+OSD 2TB │ │+OSD 2TB │ │+OSD 2TB │                      │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘                      │
│                                                                                     │
│  ┌─────────────┐  ┌─────────────┐                                                  │
│  │ LB-APP-01   │  │ LB-APP-02   │  (External Load Balancers)                      │
│  │ 10.0.1.21   │  │ 10.0.1.22   │                                                  │
│  │ VIP:10.0.1.20│  │ VIP:10.0.1.20│                                                  │
│  └─────────────┘  └─────────────┘                                                  │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                              │
                                              │ 10GbE Uplink
                                              │
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              RACK 3 (Infrastructure & Operations)                   │
│                                                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │
│  │ OPS-LINUX   │  │ OPS-WINDOWS │  │   NEXUS     │  │   HARBOR    │               │
│  │ 10.0.0.10   │  │ 10.0.0.11   │  │ 10.0.30.10  │  │ 10.0.30.11  │               │
│  │ (Ansible)   │  │ (AD/DNS)    │  │ (Artifacts) │  │ (Registry)  │               │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘               │
│                                                                                     │
│  ┌─────────────┐  ┌─────────────┐                                                  │
│  │  IPMI/iDRAC │  │  MGMT SW    │  (Out-of-band management)                       │
│  │ 10.0.0.0/24 │  │ 10.0.0.0/24 │                                                  │
│  └─────────────┘  └─────────────┘                                                  │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Logical Network (Calico CNI)

### VXLAN Overlay Network (Management Cluster)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    MANAGEMENT CLUSTER - POD NETWORK                  │
│                         10.1.0.0/16 (VXLAN)                         │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Master Nodes (Control Plane)              │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐       │   │
│  │  │ MGMT-M1 │  │ MGMT-M2 │  │ MGMT-M3 │  │ MGMT-M4 │  ...  │   │
│  │  │ VTEP:   │  │ VTEP:   │  │ VTEP:   │  │ VTEP:   │       │   │
│  │  │10.0.2.11│  │10.0.2.12│  │10.0.2.13│  │10.0.2.14│       │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘       │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                    VXLAN Tunnel (IPIP/VXLAN encap)                  │
│                              │                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Worker Nodes (Data Plane)                 │   │
│  │                                                              │   │
│  │  ┌─────────────────────┐    ┌─────────────────────┐        │   │
│  │  │     MGMT-W1          │    │     MGMT-W2          │        │   │
│  │  │   Pod CIDR:          │    │   Pod CIDR:          │        │   │
│  │  │   10.1.0.0/24       │    │   10.1.1.0/24       │        │   │
│  │  │                      │    │                      │        │   │
│  │  │  ┌────┐  ┌────┐     │    │  ┌────┐  ┌────┐     │        │   │
│  │  │  │Pod1│  │Pod2│     │    │  │Pod3│  │Pod4│     │        │   │
│  │  │  │.10 │  │.11 │     │    │  │.10 │  │.11 │     │        │   │
│  │  │  └────┘  └────┘     │    │  └────┘  └────┘     │        │   │
│  │  └─────────────────────┘    └─────────────────────┘        │   │
│  │                                                              │   │
│  │  ┌─────────────────────┐    ┌─────────────────────┐        │   │
│  │  │     MGMT-W3          │    │     MGMT-W4          │        │   │
│  │  │   Pod CIDR:          │    │   Pod CIDR:          │        │   │
│  │  │   10.1.2.0/24       │    │   10.1.3.0/24       │        │   │
│  │  └─────────────────────┘    └─────────────────────┘        │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  Service Network: 10.0.20.0/24                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  ClusterIP Range: 10.0.20.1 - 10.0.20.254                   │   │
│  │  kube-proxy / IPVS handles VIP → Pod translation            │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### BGP Peering Mode (Alternative)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CALICO BGP MODE (Optional)                        │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Top-of-Rack Switch                         │   │
│  │                    (BGP AS 64512)                             │   │
│  │                                                              │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │   │
│  │  │ Route    │  │ Route    │  │ Route    │                  │   │
│  │  │ Reflector│  │ Reflector│  │ Reflector│                  │   │
│  │  │ (RR1)    │  │ (RR2)    │  │ (RR3)    │                  │   │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘                  │   │
│  │       │              │              │                        │   │
│  └───────┼──────────────┼──────────────┼───────────────────────┘   │
│          │              │              │                            │
│     BGP Peering    BGP Peering    BGP Peering                      │
│     AS 64513       AS 64513       AS 64513                         │
│          │              │              │                            │
│  ┌───────┴──────────────┴──────────────┴───────────────────────┐   │
│  │                    Worker Nodes                              │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐       │   │
│  │  │ MGMT-W1 │  │ MGMT-W2 │  │ MGMT-W3 │  │ MGMT-W4 │  ...  │   │
│  │  │ BGP     │  │ BGP     │  │ BGP     │  │ BGP     │       │   │
│  │  │ Peer    │  │ Peer    │  │ Peer    │  │ Peer    │       │   │
│  │  │10.0.3.11│  │10.0.3.12│  │10.0.3.13│  │10.0.3.14│       │   │
│  │  │ Pod CIDR│  │ Pod CIDR│  │ Pod CIDR│  │ Pod CIDR│       │   │
│  │  │10.1.0.0 │  │10.1.1.0 │  │10.1.2.0 │  │10.1.3.0 │       │   │
│  │  │  /24    │  │  /24    │  │  /24    │  │  /24    │       │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘       │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  In BGP mode, each worker advertises its Pod CIDR via BGP.         │
│  No overlay encapsulation — direct routing.                         │
│  MetalLB uses BGP for LoadBalancer IP allocation.                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Service Network

### ClusterIP Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                       SERVICE NETWORK FLOW                           │
│                                                                     │
│  Client (Pod or External)                                          │
│       │                                                             │
│       ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  ClusterIP: 10.0.20.100                                      │   │
│  │  Service: my-service.namespace.svc.cluster.local              │   │
│  │  Port: 80                                                    │   │
│  │                                                              │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │  kube-proxy (IPVS mode)                               │   │   │
│  │  │                                                       │   │   │
│  │  │  Virtual Server: 10.0.20.100:80                       │   │   │
│  │  │  ├── Real Server: 10.1.0.10:8080 (Pod on W1)        │   │   │
│  │  │  ├── Real Server: 10.1.1.15:8080 (Pod on W2)        │   │   │
│  │  │  └── Real Server: 10.1.2.20:8080 (Pod on W3)        │   │   │
│  │  │                                                       │   │   │
│  │  │  Load Balancing: least-connection (lc)                │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│       │                                                             │
│       ▼                                                             │
│  Backend Pod (selected by IPVS)                                    │
└─────────────────────────────────────────────────────────────────────┘
```

### NodePort Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                       NODEPORT FLOW                                  │
│                                                                     │
│  External Client: 203.0.113.50                                      │
│       │                                                             │
│       ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Any Worker Node: 10.0.3.11                                 │   │
│  │  NodePort: 30000-32767                                      │   │
│  │                                                              │   │
│  │  Destination: 10.0.3.11:30080                               │   │
│  │  → kube-proxy redirects to Service ClusterIP                 │   │
│  │  → IPVS selects backend Pod                                 │   │
│  └─────────────────────────────────────────────────────────────┘   │
│       │                                                             │
│       ▼                                                             │
│  Backend Pod (may be on different node — auto-routing)             │
└─────────────────────────────────────────────────────────────────────┘
```

### LoadBalancer Flow (MetalLB)

```
┌─────────────────────────────────────────────────────────────────────┐
│                   METALLB LOADBALANCER FLOW                          │
│                                                                     │
│  External Client: 10.0.30.50                                       │
│       │                                                             │
│       ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  MetalLB IP: 10.0.30.100                                    │   │
│  │  (Allocated from pool: 10.0.30.100-10.0.30.200)            │   │
│  │                                                              │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │  MetalLB Speaker (BGP or ARP mode)                    │   │   │
│  │  │                                                       │   │   │
│  │  │  BGP: Announces IP to ToR switch via eBGP             │   │   │
│  │  │  ARP: Responds to ARP requests for the IP             │   │   │
│  │  │                                                       │   │   │
│  │  │  Active node: APP-W1 (10.0.5.11)                      │   │   │
│  │  │  Backup: APP-W2, APP-W3 (standby)                     │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│       │                                                             │
│       ▼                                                             │
│  NGINX Ingress Controller (DaemonSet on all workers)               │
│       │                                                             │
│       ▼                                                             │
│  Backend Pod (routed by Ingress rules)                             │
└─────────────────────────────────────────────────────────────────────┘
```

---

## HAProxy → NGINX Ingress Flow (HTTP)

```
┌─────────────────────────────────────────────────────────────────────┐
│              HTTP INGRESS FLOW (Application Cluster)                 │
│                                                                     │
│  External User                                                      │
│  https://app.example.com                                            │
│       │                                                             │
│       ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  DNS: app.example.com → 10.0.1.20 (HAProxy VIP)             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│       │                                                             │
│       ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  HAProxy (LB-APP-01 / LB-APP-02)                             │   │
│  │  VIP: 10.0.1.20                                              │   │
│  │                                                              │   │
│  │  Frontend: bind *:443                                       │   │
│  │  → SSL termination (or passthrough)                          │   │
│  │  → SNI inspection: app.example.com                           │   │
│  │  → Backend: ingress-nginx                                    │   │
│  └─────────────────────────────────────────────────────────────┘   │
│       │                                                             │
│       ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  NGINX Ingress Controller (DaemonSet)                        │   │
│  │  Running on: APP-W1, APP-W2, APP-W3, APP-W4, APP-W5         │   │
│  │                                                              │   │
│  │  1. TLS termination (using cert-manager issued cert)         │   │
│  │  2. Ingress rule matching:                                  │   │
│  │     host: app.example.com                                    │   │
│  │     path: / → Service: app-frontend                         │   │
│  │  3. Rate limiting, annotations processing                    │   │
│  └─────────────────────────────────────────────────────────────┘   │
│       │                                                             │
│       ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Service: app-frontend (ClusterIP: 10.0.21.100)             │   │
│  │  → kube-proxy IPVS load balances to Pod endpoints            │   │
│  └─────────────────────────────────────────────────────────────┘   │
│       │                                                             │
│       ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Backend Pod: app-frontend-7d8f9-x2k4m                      │   │
│  │  IP: 10.2.1.15 (on APP-W2)                                  │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## HAProxy TCP Passthrough Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│              TCP PASSTHROUGH FLOW (K8s API Server)                   │
│                                                                     │
│  kubectl, kubelet, controller-manager                                │
│       │                                                             │
│       ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  DNS: api.mgmt.corp.internal → 10.0.1.10 (HAProxy VIP)      │   │
│  └─────────────────────────────────────────────────────────────┘   │
│       │                                                             │
│       ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  HAProxy (LB-MGMT-01 / LB-MGMT-02)                           │   │
│  │  VIP: 10.0.1.10                                              │   │
│  │                                                              │   │
│  │  Frontend: bind *:6443 (mode tcp)                           │   │
│  │  → TCP health checks (connect port 6443)                     │   │
│  │  → Balance: roundrobin                                       │   │
│  │  → Backend: k8s-masters                                      │   │
│  │                                                              │   │
│  │  Server: mgmt-master1 10.0.2.11:6443 check inter 2s         │   │
│  │  Server: mgmt-master2 10.0.2.12:6443 check inter 2s         │   │
│  │  Server: mgmt-master3 10.0.2.13:6443 check inter 2s         │   │
│  │  Server: mgmt-master4 10.0.2.14:6443 check inter 2s         │   │
│  │  Server: mgmt-master5 10.0.2.15:6443 check inter 2s         │   │
│  └─────────────────────────────────────────────────────────────┘   │
│       │                                                             │
│       ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  kube-apiserver (on selected master)                         │   │
│  │  → Authenticates request                                     │   │
│  │  → etcd query/update                                         │   │
│  │  → Returns response                                          │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  Note: No SSL termination at HAProxy — end-to-end TLS              │
│  Note: No HTTP inspection — pure TCP forwarding                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## MetalLB IP Pool Allocation

```
┌─────────────────────────────────────────────────────────────────────┐
│                    METALLB IP POOL ALLOCATION                        │
│                                                                     │
│  Pool: 10.0.30.100 - 10.0.30.200 (100 IPs)                         │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Allocated IPs:                                              │   │
│  │                                                              │   │
│  │  10.0.30.100  →  ingress-nginx (NGINX Ingress Controller)   │   │
│  │  10.0.30.101  →  app-loadbalancer (Service: app-lb)        │   │
│  │  10.0.30.102  →  grafana (Service: grafana-ext)            │   │
│  │  10.0.30.103  →  prometheus (Service: prometheus-ext)      │   │
│  │  10.0.30.104  →  alertmanager (Service: alertmanager-ext)  │   │
│  │  10.0.30.105  →  jenkins (Service: jenkins)                │   │
│  │  10.0.30.106  →  nexus (Service: nexus-ext)                │   │
│  │  10.0.30.107  →  harbor (Service: harbor-ext)             │   │
│  │  ...                                                         │   │
│  │  10.0.30.200  →  (reserved for future use)                 │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  MetalLB Configuration:                                      │   │
│  │                                                              │   │
│  │  apiVersion: metallb.io/v1beta1                              │   │
│  │  kind: IPAddressPool                                         │   │
│  │  metadata:                                                   │   │
│  │    name: production-pool                                     │   │
│  │    namespace: metallb-system                                 │   │
│  │  spec:                                                       │   │
│  │    addresses:                                                │   │
│  │    - 10.0.30.100-10.0.30.200                                 │   │
│  │    autoAssign: true                                          │   │
│  │                                                              │   │
│  │  ---                                                         │   │
│  │                                                              │   │
│  │  apiVersion: metallb.io/v1beta1                              │   │
│  │  kind: L2Advertisement                                       │   │
│  │  metadata:                                                   │   │
│  │    name: l2-advertisement                                    │   │
│  │    namespace: metallb-system                                 │   │
│  │  spec:                                                       │   │
│  │    ipAddressPools:                                           │   │
│  │    - production-pool                                         │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Ceph Network

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CEPH NETWORK ARCHITECTURE                         │
│                    (Per Cluster)                                     │
│                                                                     │
│  ═══════════════════════════════════════════════════════════════   │
│  PUBLIC NETWORK (10.0.10.0/24) — Client ↔ Cluster Communication    │
│  ═══════════════════════════════════════════════════════════════   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                                                              │   │
│  │  Kubernetes Pods / CSI Provisioner                          │   │
│  │       │                                                      │   │
│  │       ▼                                                      │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │  Ceph MONs (Public IPs)                               │   │   │
│  │  │                                                       │   │   │
│  │  │  MON1: 10.0.10.11   MON2: 10.0.10.12                 │   │   │
│  │  │  MON3: 10.0.10.13   MON4: 10.0.10.14                 │   │   │
│  │  │  MON5: 10.0.10.15                                    │   │   │
│  │  │                                                       │   │   │
│  │  │  ← Client connections (libceph, rbd, cephfs)        │   │   │
│  │  │  ← OSD registration and heartbeat                    │   │   │
│  │  │  ← MGR dashboard (port 8443)                         │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  │                                                              │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ═══════════════════════════════════════════════════════════════   │
│  CLUSTER NETWORK (10.0.11.0/24) — OSD Replication & Recovery       │
│  ═══════════════════════════════════════════════════════════════   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                                                              │   │
│  │  ┌──────────────────────────────────────────────────────┐   │   │
│  │  │  Ceph OSDs (Cluster IPs)                              │   │   │
│  │  │                                                       │   │   │
│  │  │  OSD1: 10.0.11.11   OSD2: 10.0.11.12                 │   │   │
│  │  │  OSD3: 10.0.11.13   OSD4: 10.0.11.14                 │   │   │
│  │  │  OSD5: 10.0.11.15                                    │   │   │
│  │  │                                                       │   │   │
│  │  │  ← Primary OSD writes to Replica OSDs                │   │   │
│  │  │  ← Recovery/rebalancing traffic                      │   │   │
│  │  │  ← Heartbeat (ping → MON)                            │   │   │
│  │  │  ← Backfill (replicated data transfer)               │   │   │
│  │  └──────────────────────────────────────────────────────┘   │   │
│  │                                                              │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  CEPH CONNECTION FLOW:                                       │   │
│  │                                                              │   │
│  │  1. Client → Public Network → MON (get CRUSH map)          │   │
│  │  2. Client → Public Network → OSD (read/write data)        │   │
│  │  3. OSD → Cluster Network → OSD (replicate data)           │   │
│  │  4. OSD → Public Network → MON (report status)             │   │
│  │  5. MON → Public Network → MON (quorum/election)           │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  NETWORK BANDWIDTH PLANNING:                                 │   │
│  │                                                              │   │
│  │  Public Network:  10 GbE (client access)                    │   │
│  │  Cluster Network: 25 GbE (replication, recovery)            │   │
│  │                                                              │   │
│  │  Recommendation: Dedicated NICs for each network            │   │
│  │  Public:   eno1 (10GbE)                                     │   │
│  │  Cluster:  eno2 (25GbE)                                     │   │
│  │  Or: Bonded LACP (802.3ad) for redundancy                   │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## DNS Resolution Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DNS RESOLUTION FLOW                                │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  INTERNAL DNS ZONES:                                         │   │
│  │                                                              │   │
│  │  Zone: corp.internal                                        │   │
│  │  ├── nexus.corp.internal        → 10.0.30.10                │   │
│  │  ├── harbor.corp.internal       → 10.0.30.11                │   │
│  │  ├── api.mgmt.corp.internal     → 10.0.1.10 (VIP)           │   │
│  │  ├── api.app.corp.internal      → 10.0.1.20 (VIP)           │   │
│  │  ├── rancher.corp.internal      → 10.0.1.10 (VIP)           │   │
│  │  ├── argocd.corp.internal       → 10.0.1.10 (VIP)           │   │
│  │  ├── grafana.corp.internal      → 10.0.1.10 (VIP)           │   │
│  │  ├── prometheus.corp.internal   → 10.0.1.10 (VIP)           │   │
│  │  ├── *.apps.corp.internal       → 10.0.30.100 (MetalLB)     │   │
│  │  └── _tcp.corp.internal (SRV)   → service discovery          │   │
│  │                                                              │   │
│  │  Zone: cluster.local (Kubernetes internal)                   │   │
│  │  ├── kubernetes.default.svc.cluster.local → 10.0.20.1        │   │
│  │  ├── my-service.namespace.svc.cluster.local → 10.0.20.100     │   │
│  │  └── <pod-ip-dashed>.namespace.pod.cluster.local            │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  RESOLUTION FLOW:                                            │   │
│  │                                                              │   │
│  │  Pod → CoreDNS (10.0.20.2)                                   │   │
│  │    │                                                         │   │
│  │    ├─ .cluster.local? → CoreDNS local cache/zone            │   │
│  │    │                                                         │   │
│  │    ├─ .corp.internal? → Forward to BIND9/Windows DNS        │   │
│  │    │   (10.0.0.10 / 10.0.0.11)                              │   │
│  │    │                                                         │   │
│  │    └─ External? → BLOCKED (air-gap)                         │   │
│  │        (or forward to internal proxy if needed)             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  CoreDNS ConfigMap:                                          │   │
│  │                                                              │   │
│  │  apiVersion: v1                                              │   │
│  │  kind: ConfigMap                                             │   │
│  │  metadata:                                                   │   │
│  │    name: coredns                                             │   │
│  │    namespace: kube-system                                    │   │
│  │  data:                                                       │   │
│  │    Corefile: |                                               │   │
│  │      .:53 {                                                  │   │
│  │          errors                                              │   │
│  │          health {                                            │   │
│  │             lameduck 5s                                      │   │
│  │          }                                                   │   │
│  │          ready                                                │   │
│  │          kubernetes cluster.local in-addr.arpa ip6.arpa {    │   │
│  │             pods insecure                                    │   │
│  │             fallthrough in-addr.arpa ip6.arpa                │   │
│  │             ttl 30                                           │   │
│  │          }                                                   │   │
│  │          corp.internal {                                     │   │
│  │              forward . 10.0.0.10 10.0.0.11                   │   │
│  │          }                                                   │   │
│  │          prometheus :9153                                    │   │
│  │          forward . /etc/resolv.conf {                        │   │
│  │             max_concurrent 1000                              │   │
│  │          }                                                   │   │
│  │          cache 30                                            │   │
│  │          loop                                                 │   │
│  │          reload                                               │   │
│  │          loadbalance                                          │   │
│  │      }                                                       │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## IP Address Reference

### Management Cluster IPs

| Hostname | Role | Management | Pod Network | Ceph Public | Ceph Cluster |
|----------|------|-----------|-------------|-------------|--------------|
| mgmt-m1 | Master | 10.0.2.11 | — | 10.0.10.11 | 10.0.11.11 |
| mgmt-m2 | Master | 10.0.2.12 | — | 10.0.10.12 | 10.0.11.12 |
| mgmt-m3 | Master | 10.0.2.13 | — | 10.0.10.13 | 10.0.11.13 |
| mgmt-m4 | Master | 10.0.2.14 | — | 10.0.10.14 | 10.0.11.14 |
| mgmt-m5 | Master | 10.0.2.15 | — | 10.0.10.15 | 10.0.11.15 |
| mgmt-w1 | Worker | 10.0.3.11 | 10.1.0.0/24 | 10.0.10.21 | 10.0.11.21 |
| mgmt-w2 | Worker | 10.0.3.12 | 10.1.1.0/24 | 10.0.10.22 | 10.0.11.22 |
| mgmt-w3 | Worker | 10.0.3.13 | 10.1.2.0/24 | 10.0.10.23 | 10.0.11.23 |
| mgmt-w4 | Worker | 10.0.3.14 | 10.1.3.0/24 | 10.0.10.24 | 10.0.11.24 |
| mgmt-w5 | Worker | 10.0.3.15 | 10.1.4.0/24 | 10.0.10.25 | 10.0.11.25 |
| lb-mgmt-01 | LB | 10.0.1.11 | — | — | — |
| lb-mgmt-02 | LB | 10.0.1.12 | — | — | — |
| VIP-MGMT | VIP | 10.0.1.10 | — | — | — |

### Application Cluster IPs

| Hostname | Role | Management | Pod Network | Ceph Public | Ceph Cluster |
|----------|------|-----------|-------------|-------------|--------------|
| app-m1 | Master | 10.0.4.11 | — | 10.0.10.31 | 10.0.11.31 |
| app-m2 | Master | 10.0.4.12 | — | 10.0.10.32 | 10.0.11.32 |
| app-m3 | Master | 10.0.4.13 | — | 10.0.10.33 | 10.0.11.33 |
| app-m4 | Master | 10.0.4.14 | — | 10.0.10.34 | 10.0.11.34 |
| app-m5 | Master | 10.0.4.15 | — | 10.0.10.35 | 10.0.11.35 |
| app-w1 | Worker | 10.0.5.11 | 10.2.0.0/24 | 10.0.10.41 | 10.0.11.41 |
| app-w2 | Worker | 10.0.5.12 | 10.2.1.0/24 | 10.0.10.42 | 10.0.11.42 |
| app-w3 | Worker | 10.0.5.13 | 10.2.2.0/24 | 10.0.10.43 | 10.0.11.43 |
| app-w4 | Worker | 10.0.5.14 | 10.2.3.0/24 | 10.0.10.44 | 10.0.11.44 |
| app-w5 | Worker | 10.0.5.15 | 10.2.4.0/24 | 10.0.10.45 | 10.0.11.45 |
| lb-app-01 | LB | 10.0.1.21 | — | — | — |
| lb-app-02 | LB | 10.0.1.22 | — | — | — |
| VIP-APP | VIP | 10.0.1.20 | — | — | — |

### Infrastructure IPs

| Hostname | Role | IP | Purpose |
|----------|------|-----|---------|
| ops-linux | Operations (Linux) | 10.0.0.10 | Ansible/KubeSpray |
| ops-win | Operations (Windows) | 10.0.0.11 | AD/DNS Admin |
| nexus | Nexus Repository | 10.0.30.10 | Artifact management |
| harbor | Harbor Registry | 10.0.30.11 | Container registry |
| dns-01 | BIND9 DNS | 10.0.0.20 | Internal DNS primary |
| dns-02 | Windows DNS | 10.0.0.21 | Internal DNS secondary |

### Service Networks

| Cluster | Service CIDR | DNS Service IP |
|---------|-------------|----------------|
| Management | 10.0.20.0/24 | 10.0.20.2 |
| Application | 10.0.21.0/24 | 10.0.21.2 |

### Pod Networks

| Cluster | Pod CIDR | VXLAN |
|---------|----------|-------|
| Management | 10.1.0.0/16 | Enabled |
| Application | 10.2.0.0/16 | Enabled |

### MetalLB Pool

| Cluster | Pool Range | Purpose |
|---------|-----------|---------|
| Application | 10.0.30.100-10.0.30.200 | LoadBalancer IPs |
| Management | 10.0.30.50-10.0.30.99 | Infrastructure LB IPs |
