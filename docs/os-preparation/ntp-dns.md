# NTP and DNS Deep-Dive for Air-Gapped Environments

## Overview

This document covers time synchronization and DNS configuration for an
air-gapped cloud-native deployment. Proper NTP and DNS are critical for
cluster operations (certificate validation, log correlation, distributed
consensus).

---

## 1. NTP Configuration with Chrony

### 1.1 Architecture

 air-gapped environments, there is no access to public NTP servers
(pool.ntp.org). The architecture uses a tiered approach:

```
┌─────────────────────────────────────────────────────┐
│                  NTP Hierarchy                       │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Stratum 0: GPS / Atomic Clock (hardware)           │
│       │                                              │
│  Stratum 1: ntp1.internal.lan (directly attached)   │
│       │                                              │
│  Stratum 2: ntp2.internal.lan (synced from Stratum1)│
│       │                                              │
│  Stratum 3: k8s-master-01, k8s-worker-*             │
│       │                                              │
│  Stratum 4: Application servers                      │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### 1.2 Chrony Configuration - Stratum 1 Server (GPS/Atomic)

`/etc/chrony/chrony.conf` on the primary NTP server:

```conf
# Stratum 1 - directly connected to hardware clock (GPS/Atomic)
# This server has NO upstream internet NTP sources

# Hardware reference clock (GPS receiver via PPS)
refclock PSH /dev/pps0 poll 3 trust
refclock SHM 0 offset 0.0 delay 0.1 refid GPS trust

# Local clock as fallback (stratum 10 if no refclock)
local stratum 10

# Allow internal network to sync from this server
allow 10.0.0.0/8
allow 172.16.0.0/12
allow 192.168.0.0/16

# Serve time even if not synchronized
local stratum 10

# Drift file
driftfile /var/lib/chrony/chrony.drift

# Logging
logdir /var/log/chrony
log measurements statistics tracking

# Kernel RTC sync
rtcsync

# Step threshold: 1 second in first 3 updates
makestep 1.0 3

# Minimum number of sources required
minsources 2

# Disable IPv6 if not used
bindaddress 0.0.0.0
```

### 1.3 Chrony Configuration - Stratum 2 Server

`/etc/chrony/chrony.conf` on the secondary NTP server:

```conf
# Stratum 2 - syncs from Stratum 1 servers
server ntp1.internal.lan iburst prefer
server ntp2.internal.lan iburst

# If no Stratum 1 available, use local clock
local stratum 10

# Allow internal network
allow 10.0.0.0/8

# Drift file
driftfile /var/lib/chrony/chrony.drift

# Logging
logdir /var/log/chrony

# RTC sync
rtcsync

# Step threshold
makestep 1.0 3
```

### 1.4 Chrony Configuration - Kubernetes Nodes

`/etc/chrony/chrony.conf` on all K8s nodes:

```conf
# Kubernetes node - syncs from internal NTP servers
server ntp1.internal.lan iburst prefer
server ntp2.internal.lan iburst

# Fallback to local clock if NTP servers unreachable
local stratum 10

# Drift file
driftfile /var/lib/chrony/chrony.drift

# Logging
logdir /var/log/chrony

# RTC sync
rtcsync

# Step threshold
makestep 1.0 3

# Minimum sources
minsources 1
```

### 1.5 Verification Commands

```bash
# Check tracking status
chronyc tracking

# Check sources
chronyc sources -v

# Check source statistics
chronyc sourcestats

# Check NTP activity
chronyc ntpdata

# Force sync check
chronyc waitsync 30
```

### 1.6 Expected Output

```
$ chronyc tracking
Reference ID    : 0A0A0A0A (ntp1.internal.lan)
Stratum         : 3
Ref time (UTC)  : Thu Jan 01 00:00:00 2024
System time     : 0.000123456 seconds fast of NTP time
Last offset     : +0.000045678 seconds
RMS offset      : 0.000045678 seconds
Frequency       : 1.234 ppm slow
Residual freq   : +0.001 ppm
Skew            : 0.012 ppm
Root delay      : 0.012345678 seconds
Root dispersion : 0.001234567 seconds
Update interval  : 64.2 seconds
Leap status     : Normal
```

---

## 2. DNS Zone Design

### 2.1 Zone Architecture

```
┌─────────────────────────────────────────────────────────────�
│                    DNS Zone Architecture                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  .internal.lan (Internal corporate domain)                  │
│  │                                                           │
│  ├── cluster.local (Kubernetes service namespace)           │
│  │   ├── svc.cluster.local (Services)                       │
│  │   ├── headless.namespace.svc.cluster.local                │
│  │   └── pod.cluster.local (Pod DNS, optional)              │
│  │                                                           │
│  ├── nodes.internal.lan (Node hostnames)                    │
│  │   ├── k8s-master-01.nodes.internal.lan                   │
│  │   └── k8s-worker-01.nodes.internal.lan                   │
│  │                                                           │
│  ├── apps.internal.lan (Application endpoints)              │
│  │   ├── rancher.apps.internal.lan                          │
│  │   └── harbor.apps.internal.lan                            │
│  │                                                           │
│  └── infra.internal.lan (Infrastructure services)           │
│      ├── ntp1.infra.internal.lan                            │
│      └── dns1.infra.internal.lan                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Zone Files

#### Forward Zone: `db.internal.lan`

```dns
$TTL 86400
@   IN  SOA ns1.internal.lan. admin.internal.lan. (
            2024010101  ; Serial
            3600        ; Refresh
            900         ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL

; Nameservers
    IN  NS  ns1.internal.lan.
    IN  NS  ns2.internal.lan.

; Infrastructure
ntp1    IN  A   10.0.0.10
ntp2    IN  A   10.0.0.11
ns1     IN  A   10.0.0.2
ns2     IN  A   10.0.0.3

; Kubernetes Masters
k8s-master-01    IN  A   10.0.1.11
k8s-master-02    IN  A   10.0.1.12
k8s-master-03    IN  A   10.0.1.13

; Kubernetes Workers
k8s-worker-01    IN  A   10.0.1.21
k8s-worker-02    IN  A   10.0.1.22
k8s-worker-03    IN  A   10.0.1.23

; Load Balancers
k8s-api          IN  A   10.0.1.10

; Registry
harbor           IN  A   10.0.0.50
nexus            IN  A   10.0.0.51

; Rancher
rancher          IN  A   10.0.0```

#### Forward Zone: `db.cluster.local`

```dns
$TTL 86400
@   IN  SOA ns1.internal.lan. admin.internal.lan. (
            2024010101  ; Serial
            3600        ; Refresh
            900         ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL

; Nameservers (forwarded to CoreDNS)
    IN  NS  ns1.internal.lan.

; Kubernetes API (internal LB)
kubernetes   IN  A   10.0.1.10
```

### 2.3 Reverse Zone: `db.10.0`

```dns
$TTL 86400
@   IN  SOA ns1.internal.lan. admin.internal.lan. (
            2024010101  ; Serial
            3600        ; Refresh
            900         ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL

    IN  NS  ns1.internal.lan.

; Masters
11  IN  PTR k8s-master-01.nodes.internal.lan.
12  IN  PTR k8s-master-02.nodes.internal.lan.
13  IN  PTR k8s-master-03.nodes.internal.lan.

; Workers
21  IN  PTR k8s-worker-01.nodes.internal.lan.
22  IN  PTR k8s-worker-02.nodes.internal.lan.
23  IN  PTR k8s-worker-03.nodes.internal.lan.

; Infrastructure
10  IN  PTR ntp1.infra.internal.lan.
11  IN  PTR ntp2.infra.internal.lan.
2   IN  PTR ns1.infra.internal.lan.
3   IN  PTR ns2.infra.internal.lan.
```

---

## 3. CoreDNS Configuration

### 3.1 CoreDNS ConfigMap

CoreDNS is the default DNS server in Kubernetes. It resolves cluster-internal
names and forwards other queries to the internal DNS.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        log
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        # Forward internal.lan to internal DNS
        internal.lan {
            forward . 10.0.0.2 10.0.0.3
        }
        # Forward other domains to corporate DNS
        . {
            forward . 10.0.0.2 10.0.0.3
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

### 3.2 NodeLocal DNSCache

For improved DNS performance, deploy NodeLocal DNSCache:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-local-dns
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: node-local-dns
  template:
    metadata:
      labels:
        k8s-app: node-local-dns
    spec:
      containers:
      - name: node-local-dns
        image: registry.internal.lan/google_containers/dns-cache:1.22.23
        args: [
          "-localip", "169.254.20.10",
          "-conf", "/etc/coredns/Corefile",
          "-upstream", "10.0.0.2,10.0.0.3"
        ]
```

---

## 4. /etc/hosts Setup for Initial Bootstrapping

Before DNS is fully operational, use `/etc/hosts` for initial cluster bootstrap.

### 4.1 Bootstrap Hosts File

```bash
# /etc/hosts - Initial bootstrapping entries
# Remove these entries after DNS is fully operational

# Nameservers
10.0.0.2    ns1.internal.lan ns1
10.0.0.3    ns2.internal.lan ns2

# NTP servers
10.0.0.10   ntp1.internal.lan ntp1
10.0.0.11   ntp2.internal.lan ntp2

# Kubernetes API
10.0.1.10   k8s-api.internal.lan k8s-api

# Masters
10.0.1.11   k8s-master-01.nodes.internal.lan k8s-master-01
10.0.1.12   k8s-master-02.nodes.internal.lan k8s-master-02
10.0.1.13   k8s-master-03.nodes.internal.lan k8s-master-03

# Workers
10.0.1.21   k8s-worker-01.nodes.internal.lan k8s-worker-01
10.0.1.22   k8s-worker-02.nodes.internal.lan k8s-worker-02
10.0.1.23   k8s-worker-03.nodes.internal.lan k8s-worker-03

# Infrastructure
10.0.0.50   harbor.internal.lan harbor
10.0.0.51   nexus.internal.lan nexus
10.0.0.60   rancher.internal.lan rancher
```

### 4.2 Cleanup

After DNS is verified operational, remove or comment out the bootstrap entries:

```bash
# Comment out bootstrap entries (keep for reference)
sudo sed -i 's/^\(10\.0\.0\.\)/#\1/' /etc/hosts
sudo sed -i 's/^\(10\.0\.1\.\)/#\1/' /etc/hosts
```

---

## 5. Split-Horizon DNS

### 5.1 When to Use Split-Horizon

Split-horizon DNS is needed when the same domain name must resolve differently
inside vs. outside the cluster. Common scenarios:

- `harbor.internal.lan` resolves to internal IP inside cluster, external IP outside
- `api.cluster.local` resolves to internal LB inside, external LB outside

### 5.2 Implementation with CoreDNS Views

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        log
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        # Internal view for internal.lan
        internal.lan {
            # Match internal clients
            view internal {
                matchclients { 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 }
                forward . 10.0.0.2 10.0.0.3
            }
        }
        hosts /etc/coredns/custom.hosts internal.lan {
            fallthrough
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
```

### 5.3 Custom Hosts for Split-Horizon

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  internal.server: |
    # Internal IPs for services
    harbor.internal.lan.   IN  A  10.0.0.50
    rancher.internal.lan.  IN  A  10.0.0.60
```

---

## 6. DNS Verification

### 6.1 Node-Level Verification

```bash
# Check resolv.conf
cat /etc/resolv.conf

# Test DNS resolution
nslookup k8s-master-01.nodes.internal.lan
nslookup kubernetes.default.svc.cluster.local

# Test reverse DNS
nslookup 10.0.1.11

# Test with dig
dig +short k8s-api.internal.lan
dig +short kubernetes.default.svc.cluster.local
```

### 6.2 Kubernetes-Level Verification

```bash
# Deploy a test DNS pod
kubectl run dns-test --image=registry.internal.lan/busybox:1.36 --rm -it --restart=Never -- sh -c "
  echo '=== resolv.conf ==='
  cat /etc/resolv.conf
  echo ''
  echo '=== nslookup kubernetes ==='
  nslookup kubernetes.default.svc.cluster.local
  echo ''
  echo '=== nslookup internal ==='
  nslookup ntp1.internal.lan
"

# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
```

---

## 7. Troubleshooting

### 7.1 NTP Issues

```bash
# Check if chrony is running
systemctl status chrony

# Check sources (reachability)
chronyc sources -v
# Look for '*' (selected), '+' (good), '-' (excess), 'x' (false tick)

# Check tracking
chronyc tracking
# Look for "Leap status: Normal"

# Force immediate sync
sudo chronyc makestep

# Check NTP port (UDP 123)
ss -ulnp | grep 123
```

### 7.2 DNS Issues

```bash
# Check if systemd-resolved is interfering
systemctl status systemd-resolved
# If running and causing issues:
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# Check DNS resolution path
systemd-resolve --status
resolvectl status

# Test specific DNS server
dig @10.0.0.2 k8s-master-01.nodes.internal.lan

# Check CoreDNS pod logs
kubectl logs -n kube-system -l k8s-app=kube-dns -c node-cache
```

---

## References

- Chrony Documentation: https://chrony.tuxfamily.org/documentation.html
- Kubernetes DNS Service: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
- CoreDNS Plugins: https://coredns.io/plugins/
- BIND 9 ARM: https://downloads.isc.org/isc/bind9/doc/arm/Bv9ARM.pdf
