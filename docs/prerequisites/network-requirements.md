# Network Requirements

## Table of Contents

- [Subnet and VLAN Design](#subnet-and-vlan-design)
- [IP Address Planning Worksheet](#ip-address-planning-worksheet)
- [DNS Zone Design](#dns-zone-design)
- [Firewall Rules](#firewall-rules)
- [Port Matrix](#port-matrix)
- [Load Balancer VIP Planning](#load-balancer-vip-planning)

---

## Subnet and VLAN Design

### VLAN Plan

| VLAN ID | Name | Subnet | Gateway | Purpose |
|---------|------|--------|---------|---------|
| 100 | Management | 10.0.0.0/24 | 10.0.0.1 | IPMI/iDRAC/iLO, BMC management |
| 101 | Infrastructure | 10.0.1.0/24 | 10.0.1.1 | External LB VIPs, infrastructure |
| 102 | Masters-Mgmt | 10.0.2.0/24 | 10.0.2.1 | Management Cluster masters |
| 103 | Workers-Mgmt | 10.0.3.0/24 | 10.0.3.1 | Management Cluster workers |
| 104 | Masters-App | 10.0.4.0/24 | 10.0.4.1 | Application Cluster masters |
| 105 | Workers-App | 10.0.5.0/24 | 10.0.5.1 | Application Cluster workers |
| 106 | Storage-Services | 10.0.6.0/24 | 10.0.6.1 | Nexus, Harbor, DNS, Ops |
| 107 | Backup | 10.0.7.0/24 | 10.0.7.1 | Backup/replication network |
| 110 | Ceph-Public | 10.0.10.0/24 | 10.0.10.1 | Ceph client communication |
| 111 | Ceph-Cluster | 10.0.11.0/24 | 10.0.11.1 | Ceph OSD replication |
| 112 | Ceph-Public-App | 10.0.12.0/24 | 10.0.12.1 | Ceph public (App cluster) |
| 113 | Ceph-Cluster-App | 10.0.13.0/24 | 10.0.13.1 | Ceph cluster (App cluster) |
| 200 | MetalLB-Pool | 10.0.20.0/24 | N/A | MetalLB LoadBalancer IPs |

### Subnet Summary for Kubernetes

| Cluster | Pod CIDR | Service CIDR | DNS Service IP |
|---------|----------|-------------|----------------|
| Management | 10.1.0.0/16 | 10.0.20.0/24 | 10.0.20.2 |
| Application | 10.2.0.0/16 | 10.0.21.0/24 | 10.0.21.2 |

### Calico IPIP/VXLAN Configuration

```yaml
# calico-config (VXLAN mode)
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: management-pod-cidr
spec:
  cidr: 10.1.0.0/16
  vxlanMode: Always
  natOutgoing: true
  disabled: false
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
```

---

## IP Address Planning Worksheet

### Management Cluster

| Hostname | Role | VLAN | IP Address | MAC (to be filled) |
|----------|------|------|------------|-------------------|
| mgmt-m1 | Master | 102 | 10.0.2.11 | |
| mgmt-m2 | Master | 102 | 10.0.2.12 | |
| mgmt-m3 | Master | 102 | 10.0.2.13 | |
| mgmt-m4 | Master | 102 | 10.0.2.14 | |
| mgmt-m5 | Master | 102 | 10.0.2.15 | |
| mgmt-w1 | Worker | 103 | 10.0.3.11 | |
| mgmt-w2 | Worker | 103 | 10.0.3.12 | |
| mgmt-w3 | Worker | 103 | 10.0.3.13 | |
| mgmt-w4 | Worker | 103 | 10.0.3.14 | |
| mgmt-w5 | Worker | 103 | 10.0.3.15 | |
| lb-mgmt-01 | LB | 101 | 10.0.1.11 | |
| lb-mgmt-02 | LB | 101 | 10.0.1.12 | |
| vip-mgmt | VIP | 101 | 10.0.1.10 | N/A |

### Application Cluster

| Hostname | Role | VLAN | IP Address | MAC (to be filled) |
|----------|------|------|------------|-------------------|
| app-m1 | Master | 104 | 10.0.4.11 | |
| app-m2 | Master | 104 | 10.0.4.12 | |
| app-m3 | Master | 104 | 10.0.4.13 | |
| app-m4 | Master | 104 | 10.0.4.14 | |
| app-m5 | Master | 104 | 10.0.4.15 | |
| app-w1 | Worker | 105 | 10.0.5.11 | |
| app-w2 | Worker | 105 | 10.0.5.12 | |
| app-w3 | Worker | 105 | 10.0.5.13 | |
| app-w4 | Worker | 105 | 10.0.5.14 | |
| app-w5 | Worker | 105 | 10.0.5.15 | |
| lb-app-01 | LB | 101 | 10.0.1.21 | |
| lb-app-02 | LB | 101 | 10.0.1.22 | |
| vip-app | VIP | 101 | 10.0.1.20 | N/A |

### Infrastructure

| Hostname | Role | VLAN | IP Address | MAC (to be filled) |
|----------|------|------|------------|-------------------|
| ops-linux | Operations | 106 | 10.0.6.10 | |
| ops-win | Operations | 106 | 10.0.6.11 | |
| nexus | Nexus | 106 | 10.0.6.20 | |
| harbor | Harbor | 106 | 10.0.6.21 | |
| dns-01 | DNS Primary | 106 | 10.0.6.30 | |
| dns-02 | DNS Secondary | 106 | 10.0.6.31 | |

### Ceph (Management Cluster)

| Hostname | Role | Public IP (VLAN 110) | Cluster IP (VLAN 111) |
|----------|------|---------------------|----------------------|
| mgmt-w1 | MON+OSD | 10.0.10.11 | 10.0.11.11 |
| mgmt-w2 | MON+OSD | 10.0.10.12 | 10.0.11.12 |
| mgmt-w3 | MON+OSD | 10.0.10.13 | 10.0.11.13 |
| mgmt-w4 | MON+OSD | 10.0.10.14 | 10.0.11.14 |
| mgmt-w5 | MON+OSD | 10.0.10.15 | 10.0.11.15 |

### Ceph (Application Cluster)

| Hostname | Role | Public IP (VLAN 112) | Cluster IP (VLAN 113) |
|----------|------|---------------------|----------------------|
| app-w1 | MON+OSD | 10.0.12.11 | 10.0.13.11 |
| app-w2 | MON+OSD | 10.0.12.12 | 10.0.13.12 |
| app-w3 | MON+OSD | 10.0.12.13 | 10.0.13.13 |
| app-w4 | MON+OSD | 10.0.12.14 | 10.0.13.14 |
| app-w5 | MON+OSD | 10.0.12.15 | 10.0.13.15 |

### MetalLB IP Pools

| Pool Name | Start IP | End IP | Usage |
|-----------|----------|--------|-------|
| mgmt-infra | 10.0.20.50 | 10.0.20.99 | Management cluster services |
| app-infra | 10.0.21.50 | 10.0.21.99 | Application cluster services |
| app-ingress | 10.0.20.100 | 10.0.20.200 | NGINX Ingress, external services |

---

## DNS Zone Design

### Forward Zone: `corp.internal`

```bind
; /etc/bind/zones/db.corp.internal
$TTL 86400
@   IN  SOA ns1.corp.internal. admin.corp.internal. (
            2026010101  ; Serial
            3600        ; Refresh
            900         ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL

; Nameserver records
    IN  NS  ns1.corp.internal.
    IN  NS  ns2.corp.internal.

; Infrastructure services
nexus       IN  A   10.0.6.20
harbor      IN  A   10.0.6.21
dns-01      IN  A   10.0.6.30
dns-02      IN  A   10.0.6.31
ops-linux   IN  A   10.0.6.10
ops-win     IN  A   10.0.6.11

; Load Balancer VIPs
api.mgmt    IN  A   10.0.1.10
api.app     IN  A   10.0.1.20
rancher     IN  A   10.0.1.10
argocd      IN  A   10.0.1.10
grafana     IN  A   10.0.1.10
prometheus  IN  A   10.0.1.10
alertmanager IN A   10.0.1.10

; Wildcard for Ingress
*.apps      IN  A   10.0.20.100

; Ceph (direct access, no LB)
ceph-mgmt   IN  CNAME   mgmt-w1.corp.internal.
ceph-app    IN  CNAME   app-w1.corp.internal.

; Master nodes
mgmt-m1     IN  A   10.0.2.11
mgmt-m2     IN  A   10.0.2.12
mgmt-m3     IN  A   10.0.2.13
mgmt-m4     IN  A   10.0.2.14
mgmt-m5     IN  A   10.0.2.15

app-m1      IN  A   10.0.4.11
app-m2      IN  A   10.0.4.12
app-m3      IN  A   10.0.4.13
app-m4      IN  A   10.0.4.14
app-m5      IN  A   10.0.4.15

; Worker nodes
mgmt-w1     IN  A   10.0.3.11
mgmt-w2     IN  A   10.0.3.12
mgmt-w3     IN  A   10.0.3.13
mgmt-w4     IN  A   10.0.3.14
mgmt-w5     IN  A   10.0.3.15

app-w1      IN  A   10.0.5.11
app-w2      IN  A   10.0.5.12
app-w3      IN  A   10.0.5.13
app-w4      IN  A   10.0.5.14
app-w5      IN  A   10.0.5.15

; Load Balancer nodes
lb-mgmt-01  IN  A   10.0.1.11
lb-mgmt-02  IN  A   10.0.1.12
lb-app-01   IN  A   10.0.1.21
lb-app-02   IN  A   10.0.1.22
```

### Reverse Zone: `0.10.in-addr.arpa`

```bind
; /etc/bind/zones/db.10.0
$TTL 86400
@   IN  SOA ns1.corp.internal. admin.corp.internal. (
            2026010101  ; Serial
            3600        ; Refresh
            900         ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL

    IN  NS  ns1.corp.internal.
    IN  NS  ns2.corp.internal.

; Infrastructure (10.0.0.0/24)
10          IN  PTR ipmi-gw.corp.internal.

; VIPs (10.0.1.0/24)
10          IN  PTR api.mgmt.corp.internal.
20          IN  PTR api.app.corp.internal.

; Masters-Mgmt (10.0.2.0/24)
11          IN  PTR mgmt-m1.corp.internal.
12          IN  PTR mgmt-m2.corp.internal.
13          IN  PTR mgmt-m3.corp.internal.
14          IN  PTR mgmt-m4.corp.internal.
15          IN  PTR mgmt-m5.corp.internal.

; Workers-Mgmt (10.0.3.0/24)
11          IN  PTR mgmt-w1.corp.internal.
12          IN  PTR mgmt-w2.corp.internal.
13          IN  PTR mgmt-w3.corp.internal.
14          IN  PTR mgmt-w4.corp.internal.
15          IN  PTR mgmt-w5.corp.internal.

; Masters-App (10.0.4.0/24)
11          IN  PTR app-m1.corp.internal.
12          IN  PTR app-m2.corp.internal.
13          IN  PTR app-m3.corp.internal.
14          IN  PTR app-m4.corp.internal.
15          IN  PTR app-m5.corp.internal.

; Workers-App (10.0.5.0/24)
11          IN  PTR app-w1.corp.internal.
12          IN  PTR app-w2.corp.internal.
13          IN  PTR app-w3.corp.internal.
14          IN  PTR app-w4.corp.internal.
15          IN  PTR app-w5.corp.internal.

; Storage Services (10.0.6.0/24)
10          IN  PTR ops-linux.corp.internal.
11          IN  PTR ops-win.corp.internal.
20          IN  PTR nexus.corp.internal.
21          IN  PTR harbor.corp.internal.
30          IN  PTR dns-01.corp.internal.
31          IN  PTR dns-02.corp.internal.
```

### Kubernetes Internal DNS (CoreDNS)

```yaml
# CoreDNS ConfigMap - forward internal zones
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        corp.internal {
            forward . 10.0.6.30 10.0.6.31
        }
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
```

---

## Firewall Rules

### Inter-Node Rules (Within Same Cluster)

| Source | Destination | Ports | Protocol | Action | Purpose |
|--------|-------------|-------|----------|--------|---------|
| All nodes | All nodes | 22 | TCP | ALLOW | SSH management |
| Masters | Masters | 2379-2380 | TCP | ALLOW | etcd server client API |
| Masters | Masters | 10250 | TCP | ALLOW | kubelet API |
| Masters | Masters | 10251 | TCP | ALLOW | kube-scheduler |
| Masters | Masters | 10252 | TCP | ALLOW | kube-controller-manager |
| Workers | Masters | 6443 | TCP | ALLOW | kube-apiserver |
| Workers | Workers | 10250 | TCP | ALLOW | kubelet API |
| Workers | Workers | 30000-32767 | TCP | ALLOW | NodePort services |
| All | All | 4789 | UDP | ALLOW | Calico VXLAN |
| All | All | 4789 | UDP | ALLOW | Flannel (if used) |
| All | All | 8472 | UDP | ALLOW | Calico VXLAN (IPIP) |
| All | All | 7946 | TCP/UDP | ALLOW | Calico BGP (if used) |
| All | All | 5473 | TCP | ALLOW | Calico Typha |
| All | All | 179 | TCP | ALLOW | Calico BGP |
| All | All | 8285 | UDP | ALLOW | Calico BGP (Felix) |

### Inter-Cluster Rules

| Source | Destination | Ports | Protocol | Action | Purpose |
|--------|-------------|-------|----------|--------|---------|
| App Cluster | Mgmt Cluster | 6443 | TCP | ALLOW | App cluster → Mgmt API (Rancher) |
| Mgmt Cluster | App Cluster | 6443 | TCP | ALLOW | Mgmt → App API (monitoring) |
| Mgmt LB | App LB | All | TCP/UDP | ALLOW | Cross-cluster services |

### External Rules (To/From Outside)

| Source | Destination | Ports | Protocol | Action | Purpose |
|--------|-------------|-------|----------|--------|---------|
| External | LB VIPs | 443 | TCP | ALLOW | HTTPS services |
| External | LB VIPs | 6443 | TCP | ALLOW | K8s API (if exposed) |
| External | LB VIPs | 80 | TCP | ALLOW | HTTP (redirect to HTTPS) |
| External | Nexus | 443 | TCP | ALLOW | Nexus UI (if needed) |
| External | Harbor | 443 | TCP | ALLOW | Harbor UI (if needed) |

### Ceph Rules

| Source | Destination | Ports | Protocol | Action | Purpose |
|--------|-------------|-------|----------|--------|---------|
| All nodes | Ceph MONs | 6789 | TCP | ALLOW | Ceph MON |
| All nodes | Ceph MONs | 3300 | TCP | ALLOW | Ceph MON (legacy) |
| All nodes | Ceph MONs | 6800-7300 | TCP | Allow | Ceph MON/MGR/OSD |
| Ceph OSD | Ceph OSD | 6800-7300 | TCP | ALLOW | OSD replication |
| Ceph OSD | Ceph MON | 3300,6789 | TCP | ALLOW | OSD → MON heartbeat |
| Workers | Ceph OSD | 6800-7300 | TCP | ALLOW | RBD client |
| Workers | Ceph MGR | 8443 | TCP | ALLOW | Ceph dashboard |

### Blocked Traffic (Default Deny)

| Source | Destination | Ports | Protocol | Action | Purpose |
|--------|-------------|-------|----------|--------|---------|
| All | All | 0-65535 | ALL | DENY | Default deny all |
| All | Internet | All | All | DENY | Air-gap enforcement |

---

## Port Matrix

### Kubernetes Ports

| Component | Port | Protocol | Source | Direction |
|-----------|------|----------|--------|-----------|
| kube-apiserver | 6443 | TCP | All | Inbound |
| etcd | 2379 | TCP | Masters | Inbound |
| etcd | 2380 | TCP | Masters | Internal |
| kubelet | 10250 | TCP | Masters | Inbound |
| kube-scheduler | 10251 | TCP | Masters | Internal |
| kube-controller-manager | 10252 | TCP | Masters | Internal |
| kube-proxy | 10249 | TCP | Workers | Internal |
| NodePort | 30000-32767 | TCP | All | Inbound |
| CoreDNS | 53 | TCP/UDP | All | Inbound |
| metrics-server | 4443 | TCP | Masters | Internal |
| webhook | 10250 | TCP | Masters | Inbound |

### Calico Ports

| Component | Port | Protocol | Source | Direction |
|-----------|------|----------|--------|-----------|
| VXLAN | 4789 | UDP | All | Internal |
| BGP | 179 | TCP | All | Internal |
| Typha | 5473 | TCP | Workers | Inbound |
| Felix | 8285 | UDP | All | Internal |
| BIRD | 7946 | TCP/UDP | All | Internal |

### Ceph Ports

| Component | Port | Protocol | Source | Direction |
|-----------|------|----------|--------|-----------|
| MON | 3300 | TCP | All | Inbound |
| MON | 6789 | TCP | All | Inbound |
| MGR | 8443 | TCP | All | Inbound |
| OSD | 6800-7300 | TCP | All | Inbound |
| MDS | 6800 | TCP | All | Inbound |
| RGW | 7480 | TCP | All | Inbound |
| Dashboard | 8443 | TCP | All | Inbound |

### HAProxy/keepalived Ports

| Component | Port | Protocol | Source | Direction |
|-----------|------|----------|--------|-----------|
| HAProxy | 6443 | TCP | All | Inbound |
| HAProxy | 443 | TCP | All | Inbound |
| HAProxy | 80 | TCP | All | Inbound |
| HAProxy | 8404 | TCP | Monitoring | Inbound |
| keepalived | 112 | VRRP | LB pair | Internal |
| keepalived | 443 | TCP | LB pair | Internal |

### MetalLB Ports

| Component | Port | Protocol | Source | Direction |
|-----------|------|----------|--------|-----------|
| BGP | 179 | TCP | Workers | Internal |
| ARP | N/A | ARP | Workers | Internal |
| Speaker metrics | 7472 | TCP | Prometheus | Inbound |

### Platform Services Ports

| Component | Port | Protocol | Source | Direction |
|-----------|------|----------|--------|-----------|
| Rancher | 443 | TCP | All | Inbound |
| ArgoCD | 443 | TCP | All | Inbound |
| Prometheus | 9090 | TCP | All | Inbound |
| Grafana | 3000 | TCP | All | Inbound |
| Loki | 3100 | TCP | All | Inbound |
| Alertmanager | 9093 | TCP | All | Inbound |
| Harbor | 443 | TCP | All | Inbound |
| Nexus | 8081 | TCP | All | Inbound |
| Velero | 11443 | TCP | All | Inbound |
| Keycloak | 8443 | TCP | All | Inbound |

### Infrastructure Ports

| Component | Port | Protocol | Source | Direction |
|-----------|------|----------|--------|-----------|
| SSH | 22 | TCP | All | Inbound |
| DNS | 53 | TCP/UDP | All | Inbound |
| NTP | 123 | UDP | All | Inbound |
| SNMP | 161 | UDP | Monitoring | Inbound |
| Syslog | 514 | UDP | All | Inbound |
| LDAP | 389 | TCP | All | Inbound |
| LDAPS | 636 | TCP | All | Inbound |
| Kerberos | 88 | TCP/UDP | All | Inbound |
| SMB | 445 | TCP | All | Inbound |
| WinRM | 5985-5986 | TCP | All | Inbound |

---

## Load Balancer VIP Planning

### Management Cluster VIPs

| VIP | IP | Service | Backend Port | Protocol |
|-----|----|---------|-------------|----------|
| api.mgmt.corp.internal | 10.0.1.10 | K8s API Server | 6443 | TCP |
| rancher.corp.internal | 10.0.1.10 | Rancher | 443 | TCP |
| argocd.corp.internal | 10.0.1.10 | ArgoCD | 443 | TCP |
| grafana.corp.internal | 10.0.1.10 | Grafana | 443 | TCP |
| prometheus.corp.internal | 10.0.1.10 | Prometheus | 443 | TCP |
| alertmanager.corp.internal | 10.0.1.10 | Alertmanager | 443 | TCP |

### Application Cluster VIPs

| VIP | IP | Service | Backend Port | Protocol |
|-----|----|---------|-------------|----------|
| api.app.corp.internal | 10.0.1.20 | K8s API Server | 6443 | TCP |
| *.apps.corp.internal | 10.0.20.100 | NGINX Ingress | 443 | TCP |
| grafana.app.corp.internal | 10.0.20.102 | Grafana | 443 | TCP |
| prometheus.app.corp.internal | 10.0.20.103 | Prometheus | 443 | TCP |

### HAProxy Backend Mapping

```haproxy
# Management Cluster HAProxy Backends
backend k8s-api-mgmt
    mode tcp
    balance roundrobin
    option tcp-check
    default-server inter 2s fall 3 rise 2
    server mgmt-m1 10.0.2.11:6443 check
    server mgmt-m2 10.0.2.12:6443 check
    server mgmt-m3 10.0.2.13:6443 check
    server mgmt-m4 10.0.2.14:6443 check
    server mgmt-m5 10.0.2.15:6443 check

backend k8s-api-app
    mode tcp
    balance roundrobin
    option tcp-check
    default-server inter 2s fall 3 rise 2
    server app-m1 10.0.4.11:6443 check
    server app-m2 10.0.4.12:6443 check
    server app-m3 10.0.4.13:6443 check
    server app-m4 10.0.4.14:6443 check
    server app-m5 10.0.4.15:6443 check

backend ingress-nginx-app
    mode tcp
    balance roundrobin
    option tcp-check
    default-server inter 2s fall 3 rise 2
    server app-w1 10.0.5.11:443 check
    server app-w2 10.0.5.12:443 check
    server app-w3 10.0.5.13:443 check
    server app-w4 10.0.5.14:443 check
    server app-w5 10.0.5.15:443 check
```

### keepalived Priority Configuration

| Node | Cluster | Priority | State (Normal) |
|------|---------|----------|-----------------|
| lb-mgmt-01 | Management | 100 | MASTER |
| lb-mgmt-02 | Management | 90 | BACKUP |
| lb-app-01 | Application | 100 | MASTER |
| lb-app-02 | Application | 90 | BACKUP |

### VIP Failover Behavior

| Failure Scenario | Detection Time | Failover Time | Impact |
|-----------------|---------------|---------------|--------|
| LB-MGMT-01 failure | 1-3s (VRRP) | 3-5s | API requests retry |
| Master failure | 2s (health check) | 5-10s | New connections to new master |
| HAProxy crash | 1s (script) | 3-5s | VIP moves to standby |
| Network partition | 3s (VRRP) | 5-10s | Split-brain prevention via STONITH |
