# External Load Balancer Guide: HAProxy + keepalived

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [VIP Planning](#vip-planning)
- [HAProxy Configuration](#haproxy-configuration)
- [keepalived Configuration](#keepalived-configuration)
- [Health Check Scripts](#health-check-scripts)
- [Failover Behavior](#failover-behavior)
- [Full Configuration Examples](#full-configuration-examples)
- [Air-Gap: Packages from Nexus](#air-gap-packages-from-nexus)
- [Monitoring and Operations](#monitoring-and-operations)
- [Troubleshooting](#troubleshooting)

---

## Overview

The external load balancer layer provides high-availability access to Kubernetes API servers and platform services. Each cluster (Management and Application) has a dedicated pair of LB nodes running HAProxy and keepalived.

**Key Responsibilities:**
- K8s API server load balancing (TCP 6443)
- Platform service load balancing (Rancher, ArgoCD, Grafana, Prometheus, etc.)
- Virtual IP failover via VRRP
- Health checking and automatic failover
- Optional SSL/TLS offloading

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        EXTERNAL LOAD BALANCER PAIR                           │
│                                                                             │
│  ┌─────────────────────────────┐    ┌─────────────────────────────┐        │
│  │       LB-MGMT-01            │    │       LB-MGMT-02            │        │
│  │       (Active)              │    │       (Standby)             │        │
│  │                             │    │                             │        │
│  │  HAProxy (active)           │    │  HAProxy (standby)          │        │
│  │  keepalived (MASTER)        │    │  keepalived (BACKUP)        │        │
│  │  RIP: 10.0.1.11             │    │  RIP: 10.0.1.12             │        │
│  │  VIP: 10.0.1.10             │    │  VIP: 10.0.1.10             │        │
│  │                             │    │                             │        │
│  │  ┌───────────────────────┐  │    │  ┌───────────────────────┐  │        │
│  │  │  Frontend: *:6443     │  │    │  │  Frontend: *:6443     │  │        │
│  │  │  Backend: k8s-masters │  │    │  │  Backend: k8s-masters │  │        │
│  │  ├───────────────────────┤  │    │  ├───────────────────────┤  │        │
│  │  │  Frontend: *:443      │  │    │  │  Frontend: *:443      │  │        │
│  │  │  Backend: SNI-based   │  │    │  │  Backend: SNI-based   │  │        │
│  │  ├───────────────────────┤  │    │  ├───────────────────────┤  │        │
│  │  │  Frontend: *:80       │  │    │  │  Frontend: *:80       │  │        │
│  │  │  Backend: redirect    │  │    │  │  Backend: redirect    │  │        │
│  │  └───────────────────────┘  │    │  └───────────────────────┘  │        │
│  └─────────────────────────────┘    └─────────────────────────────┘        │
│                                    │                                        │
│                              VRRP (keepalived)                              │
│                                    │                                        │
└────────────────────────────────────┼────────────────────────────────────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
                    ▼                ▼                ▼
              VIP: 10.0.1.10   VIP: 10.0.1.10   VIP: 10.0.1.20
              (Mgmt API)       (Mgmt Ingress)   (App API)
```

---

## VIP Planning

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
| *.apps.corp.internal | 10.0.1.20 | NGINX Ingress | 80, 443 | TCP |
| grafana.app.corp.internal | 10.0.1.20 | Grafana | 443 | TCP |
| prometheus.app.corp.internal | 10.0.1.20 | Prometheus | 443 | TCP |

### VIP Summary Per Cluster

| Cluster | VIP1 (API) | VIP2 (Ingress/Monitoring) |
|---------|-----------|--------------------------|
| Management | 10.0.1.10 (port 6443) | 10.0.1.10 (port 80, 443) |
| Application | 10.0.1.20 (port 6443) | 10.0.1.20 (port 80, 443, 30000+) |

---

## HAProxy Configuration

### Global Section

```haproxy
# /etc/haproxy/haproxy.cfg

global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # SSL/TLS settings
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

    # Performance tuning
    maxconn 10000
    ulimit-n 20000

    # Tuning
    tune.ssl.default-dh-param 2048
    tune.bufsize 32768
    tune.maxrewrite 1024
```

### Defaults Section

```haproxy
defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    option redispatch
    retries 3
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    timeout check 5s
    timeout queue 30s
    timeout http-request 10s
    timeout http-keep-alive 10s
    default-server inter 2s fall 3 rise 2
```

### K8s API Backend

```haproxy
# ============================================================
# KUBERNETES API SERVER (Management Cluster)
# ============================================================
frontend k8s-api-mgmt
    bind 10.0.1.10:6443
    mode tcp
    option tcplog
    option tcp-check
    
    # TCP health check on port 6443
    tcp-check connect port 6443
    
    default_backend k8s-masters-mgmt

backend k8s-masters-mgmt
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 6443
    
    # All management cluster master nodes
    server mgmt-master1 10.0.2.11:6443 check inter 2s fall 3 rise 2
    server mgmt-master2 10.0.2.12:6443 check inter 2s fall 3 rise 2
    server mgmt-master3 10.0.2.13:6443 check inter 2s fall 3 rise 2
    server mgmt-master4 10.0.2.14:6443 check inter 2s fall 3 rise 2
    server mgmt-master5 10.0.2.15:6443 check inter 2s fall 3 rise 2
```

### K8s API Backend (Application Cluster)

```haproxy
# ============================================================
# KUBERNETES API SERVER (Application Cluster)
# ============================================================
frontend k8s-api-app
    bind 10.0.1.20:6443
    mode tcp
    option tcplog
    option tcp-check
    tcp-check connect port 6443
    
    default_backend k8s-masters-app

backend k8s-masters-app
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 6443
    
    # All application cluster master nodes
    server app-master1 10.0.4.11:6443 check inter 2s fall 3 rise 2
    server app-master2 10.0.4.12:6443 check inter 2s fall 3 rise 2
    server app-master3 10.0.4.13:6443 check inter 2s fall 3 rise 2
    server app-master4 10.0.4.14:6443 check inter 2s fall 3 rise 2
    server app-master5 10.0.4.15:6443 check inter 2s fall 3 rise 2
```

### HTTP Frontend (Redirect to HTTPS)

```haproxy
# ============================================================
# HTTP → HTTPS REDIRECT
# ============================================================
frontend http-redirect
    bind 10.0.1.10:80
    mode http
    option httplog
    
    # Redirect all HTTP to HTTPS
    redirect scheme https code 301 if !{ ssl_fc }
    
    # Or for Application cluster:
    # bind 10.0.1.20:80
```

### HTTPS Frontend with SNI Routing

```haproxy
# ============================================================
# HTTPS SERVICES (SNI-BASED ROUTING)
# ============================================================
frontend https-services
    bind 10.0.1.10:443
    mode tcp
    option tcplog
    
    # Wait for SSL Client Hello
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    # Route based on SNI
    use_backend rancher if { req_ssl_sni -i rancher.corp.internal }
    use_backend argocd if { req_ssl_sni -i argocd.corp.internal }
    use_backend grafana if { req_ssl_sni -i grafana.corp.internal }
    use_backend prometheus if { req_ssl_sni -i prometheus.corp.internal }
    use_backend alertmanager if { req_ssl_sni -i alertmanager.corp.internal }
    use_backend harbor if { req_ssl_sni -i harbor.corp.internal }
    use_backend nexus if { req_ssl_sni -i nexus.corp.internal }
    
    # Default: forward to NGINX Ingress
    default_backend nginx-ingress-https
```

### Platform Service Backends

```haproxy
# ============================================================
# PLATFORM SERVICE BACKENDS
# ============================================================

# Rancher
backend rancher
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 443
    
    # Rancher runs on management cluster workers via NodePort or Ingress
    server mgmt-w1 10.0.3.11:30443 check inter 5s fall 3 rise 2
    server mgmt-w2 10.0.3.12:30443 check inter 5s fall 3 rise 2
    server mgmt-w3 10.0.3.13:30443 check inter 5s fall 3 rise 2
    server mgmt-w4 10.0.3.14:30443 check inter 5s fall 3 rise 2
    server mgmt-w5 10.0.3.15:30443 check inter 5s fall 3 rise 2

# ArgoCD
backend argocd
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 443
    
    server mgmt-w1 10.0.3.11:30444 check inter 5s fall 3 rise 2
    server mgmt-w2 10.0.3.12:30444 check inter 5s fall 3 rise 2
    server mgmt-w3 10.0.3.13:30444 check inter 5s fall 3 rise 2
    server mgmt-w4 10.0.3.14:30444 check inter 5s fall 3 rise 2
    server mgmt-w5 10.0.3.15:30444 check inter 5s fall 3 rise 2

# Grafana
backend grafana
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 443
    
    server mgmt-w1 10.0.3.11:30445 check inter 5s fall 3 rise 2
    server mgmt-w2 10.0.3.12:30445 check inter 5s fall 3 rise 2
    server mgmt-w3 10.0.3.13:30445 check inter 5s fall 3 rise 2
    server mgmt-w4 10.0.3.14:30445 check inter 5s fall 3 rise 2
    server mgmt-w5 10.0.3.15:30445 check inter 5s fall 3 rise 2

# Prometheus
backend prometheus
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 443
    
    server mgmt-w1 10.0.3.11:30446 check inter 5s fall 3 rise 2
    server mgmt-w2 10.0.3.12:30446 check inter 5s fall 3 rise 2
    server mgmt-w3 10.0.3.13:30446 check inter 5s fall 3 rise 2
    server mgmt-w4 10.0.3.14:30446 check inter 5s fall 3 rise 2
    server mgmt-w5 10.0.3.15:30446 check inter 5s fall 3 rise 2

# Alertmanager
backend alertmanager
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 443
    
    server mgmt-w1 10.0.3.11:30447 check inter 5s fall 3 rise 2
    server mgmt-w2 10.0.3.12:30447 check inter 5s fall 3 rise 2
    server mgmt-w3 10.0.3.13:30447 check inter 5s fall 3 rise 2
    server mgmt-w4 10.0.3.14:30447 check inter 5s fall 3 rise 2
    server mgmt-w5 10.0.3.15:30447 check inter 5s fall 3 rise 2

# Harbor
backend harbor
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 443
    
    # Harbor runs on infrastructure node
    server harbor-node 10.0.6.21:443 check inter 5s fall 3 rise 2

# Nexus
backend nexus
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 443
    
    # Nexus runs on infrastructure node
    server nexus-node 10.0.6.20:8443 check inter 5s fall 3 rise 2
```

### NGINX Ingress Backend

```haproxy
# ============================================================
# NGINX INGRESS CONTROLLER (Default Backend)
# ============================================================
backend nginx-ingress-https
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 443
    
    # All worker nodes running NGINX Ingress
    server mgmt-w1 10.0.3.11:443 check inter 2s fall 3 rise 2
    server mgmt-w2 10.0.3.12:443 check inter 2s fall 3 rise 2
    server mgmt-w3 10.0.3.13:443 check inter 2s fall 3 rise 2
    server mgmt-w4 10.0.3.14:443 check inter 2s fall 3 rise 2
    server mgmt-w5 10.0.3.15:443 check inter 2s fall 3 rise 2

backend nginx-ingress-http
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 80
    
    server mgmt-w1 10.0.3.11:80 check inter 2s fall 3 rise 2
    server mgmt-w2 10.0.3.12:80 check inter 2s fall 3 rise 2
    server mgmt-w3 10.0.3.13:80 check inter 2s fall 3 rise 2
    server mgmt-w4 10.0.3.14:80 check inter 2s fall 3 rise 2
    server mgmt-w5 10.0.3.15:80 check inter 2s fall 3 rise 2
```

### Stats Page

```haproxy
# ============================================================
# STATS PAGE (Monitoring)
# ============================================================
listen stats
    bind 10.0.1.10:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE
    stats auth admin:changeme
    stats show-legends
    stats show-desc "HAProxy Stats - Management Cluster"
```

### TCP Mode Backends (for non-HTTP services)

```haproxy
# ============================================================
# TCP MODE BACKENDS
# ============================================================

# PostgreSQL (if exposed via HAProxy)
frontend postgres-tcp
    bind 10.0.1.10:5432
    mode tcp
    option tcplog
    default_backend postgres-backend

backend postgres-backend
    mode tcp
    balance leastconn
    option tcp-check
    tcp-check connect port 5432
    timeout server 30m
    
    server pg-node1 10.0.3.11:5432 check inter 10s fall 3 rise 2
    server pg-node2 10.0.3.12:5432 check inter 10s fall 3 rise 2

# Redis (if exposed via HAProxy)
frontend redis-tcp
    bind 10.0.1.10:6379
    mode tcp
    option tcplog
    default_backend redis-backend

backend redis-backend
    mode tcp
    balance leastconn
    option tcp-check
    tcp-check connect port 6379
    timeout server 2h
    
    server redis-node1 10.0.3.11:6379 check inter 5s fall 3 rise 2
    server redis-node2 10.0.3.12:6379 check inter 5s fall 3 rise 2
```

---

## keepalived Configuration

### Management Cluster — LB-MGMT-01 (MASTER)

```conf
# /etc/keepalived/keepalived.conf (LB-MGMT-01)

# Global definitions
global_defs {
    router_id LB_MGMT_01
    vrrp_version 3
    enable_script_security
    script_user root
}

# VRRP script to check HAProxy
vrrp_script check_haproxy {
    script "/usr/local/bin/check-haproxy.sh"
    interval 2
    weight -20
    fall 3
    rise 2
}

# VRRP script to check network connectivity
vrrp_script check_network {
    script "/usr/local/bin/check-network.sh"
    interval 5
    weight -30
    fall 3
    rise 2
}

# VRRP instance for Management Cluster
vrrp_instance VI_MGMT {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass mgmtsecret123
    }
    
    virtual_ipaddress {
        10.0.1.10/24 dev eth0 label eth0:vip
    }
    
    track_script {
        check_haproxy
        check_network
    }
    
    notify_master "/usr/local/bin/haproxy-notify.sh MASTER"
    notify_backup "/usr/local/bin/haproxy-notify.sh BACKUP"
    notify_fault "/usr/local/bin/haproxy-notify.sh FAULT"
    
    # Preempt: take back VIP when recovering
    preempt_delay 30
}
```

### Management Cluster — LB-MGMT-02 (BACKUP)

```conf
# /etc/keepalived/keepalived.conf (LB-MGMT-02)

global_defs {
    router_id LB_MGMT_02
    vrrp_version 3
    enable_script_security
    script_user root
}

vrrp_script check_haproxy {
    script "/usr/local/bin/check-haproxy.sh"
    interval 2
    weight -20
    fall 3
    rise 2
}

vrrp_script check_network {
    script "/usr/local/bin/check-network.sh"
    interval 5
    weight -30
    fall 3
    rise 2
}

vrrp_instance VI_MGMT {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 90
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass mgmtsecret123
    }
    
    virtual_ipaddress {
        10.0.1.10/24 dev eth0 label eth0:vip
    }
    
    track_script {
        check_haproxy
        check_network
    }
    
    notify_master "/usr/local/bin/haproxy-notify.sh MASTER"
    notify_backup "/usr/local/bin/haproxy-notify.sh BACKUP"
    notify_fault "/usr/local/bin/haproxy-notify.sh FAULT"
    
    preempt_delay 30
}
```

### Application Cluster — LB-APP-01 (MASTER)

```conf
# /etc/keepalived/keepalived.conf (LB-APP-01)

global_defs {
    router_id LB_APP_01
    vrrp_version 3
    enable_script_security
    script_user root
}

vrrp_script check_haproxy {
    script "/usr/local/bin/check-haproxy.sh"
    interval 2
    weight -20
    fall 3
    rise 2
}

vrrp_script check_network {
    script "/usr/local/bin/check-network.sh"
    interval 5
    weight -30
    fall 3
    rise 2
}

vrrp_instance VI_APP {
    state MASTER
    interface eth0
    virtual_router_id 52
    priority 100
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass appsecret123
    }
    
    virtual_ipaddress {
        10.0.1.20/24 dev eth0 label eth0:vip
    }
    
    track_script {
        check_haproxy
        check_network
    }
    
    notify_master "/usr/local/bin/haproxy-notify.sh MASTER"
    notify_backup "/usr/local/bin/haproxy-notify.sh BACKUP"
    notify_fault "/usr/local/bin/haproxy-notify.sh FAULT"
    
    preempt_delay 30
}
```

### Application Cluster — LB-APP-02 (BACKUP)

```conf
# /etc/keepalived/keepalived.conf (LB-APP-02)

global_defs {
    router_id LB_APP_02
    vrrp_version 3
    enable_script_security
    script_user root
}

vrrp_script check_haproxy {
    script "/usr/local/bin/check-haproxy.sh"
    interval 2
    weight -20
    fall 3
    rise 2
}

vrrp_script check_network {
    script "/usr/local/bin/check-network.sh"
    interval 5
    weight -30
    fall 3
    rise 2
}

vrrp_instance VI_APP {
    state BACKUP
    interface eth0
    virtual_router_id 52
    priority 90
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass appsecret123
    }
    
    virtual_ipaddress {
        10.0.1.20/24 dev eth0 label eth0:vip
    }
    
    track_script {
        check_haproxy
        check_network
    }
    
    notify_master "/usr/local/bin/haproxy-notify.sh MASTER"
    notify_backup "/usr/local/bin/haproxy-notify.sh BACKUP"
    notify_fault "/usr/local/bin/haproxy-notify.sh FAULT"
    
    preempt_delay 30
}
```

---

## Health Check Scripts

### HAProxy Process Check

```bash
#!/bin/bash
# /usr/local/bin/check-haproxy.sh

# Check if HAProxy process is running
if ! pgrep -x "haproxy" > /dev/null 2>&1; then
    echo "HAProxy is not running"
    exit 1
fi

# Check if HAProxy stats socket is responding
if ! echo "show info" | socat stdio /run/haproxy/admin.sock > /dev/null 2>&1; then
    echo "HAProxy stats socket not responding"
    exit 1
fi

# Check if HAProxy has at least one healthy backend
HEALTHY_BACKENDS=$(echo "show stat" | socat stdio /run/haproxy/admin.sock | \
  awk -F, '/k8s-masters/ && $2=="BACKUP" {print $18}' | grep -c "UP")

if [ "$HEALTHY_BACKENDS" -lt 1 ]; then
    echo "No healthy K8s API backends"
    exit 1
fi

exit 0
```

### Network Connectivity Check

```bash
#!/bin/bash
# /usr/local/bin/check-network.sh

# Check default gateway is reachable
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
if [ -z "$GATEWAY" ]; then
    echo "No default gateway found"
    exit 1
fi

if ! ping -c 1 -W 2 "$GATEWAY" > /dev/null 2>&1; then
    echo "Gateway $GATEWAY unreachable"
    exit 1
fi

# Check interface is up
if ! ip link show eth0 | grep -q "state UP"; then
    echo "Interface eth0 is down"
    exit 1
fi

exit 0
```

### Notification Script

```bash
#!/bin/bash
# /usr/local/bin/haproxy-notify.sh

TYPE=$1
LOG_FILE="/var/log/keepalived-notify.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] State change: $TYPE" >> "$LOG_FILE"

case $TYPE in
    MASTER)
        echo "[$DATE] This node is now MASTER" >> "$LOG_FILE"
        # Ensure HAProxy is running
        systemctl start haproxy
        # Optional: send alert
        # echo "LB node $(hostname) is now MASTER" | mail -s "LB Failover" admin@corp.internal
        ;;
    BACKUP)
        echo "[$DATE] This node is now BACKUP" >> "$LOG_FILE"
        ;;
    FAULT)
        echo "[$DATE] This node is in FAULT state" >> "$LOG_FILE"
        # Optional: send alert
        # echo "LB node $(hostname) is in FAULT state" | mail -s "LB Fault" admin@corp.internal
        ;;
esac
```

### Script Permissions

```bash
chmod +x /usr/local/bin/check-haproxy.sh
chmod +x /usr/local/bin/check-network.sh
chmod +x /usr/local/bin/haproxy-notify.sh
```

---

## Failover Behavior

### Failover Timeline

```
T+0s    Active LB node fails (HAProxy crash, network loss, power off)
T+2s    keepalived health check fails (3 consecutive failures × 2s interval)
T+5s    VRRP priority reduced, BACKUP node detects missing advertisements
T+6s    BACKUP node transitions to MASTER state
T+7s    VIP moves to BACKUP node, gratuitous ARP sent
T+8-10s Clients reconnect to new active node
```

### Priority Configuration

| Node | State | Priority | Preempt | Notes |
|------|-------|----------|---------|-------|
| LB-MGMT-01 | MASTER | 100 | Yes | Primary for Management |
| LB-MGMT-02 | BACKUP | 90 | Yes | Standby for Management |
| LB-APP-01 | MASTER | 100 | Yes | Primary for Application |
| LB-APP-02 | BACKUP | 90 | Yes | Standby for Application |

### Weight-Based Priority Reduction

```
Initial priority: 100
HAProxy check fails: 100 - 20 = 80
Network check fails: 100 - 30 = 70
Both fail: 100 - 20 - 30 = 50

When priority drops below BACKUP node's priority (90), failover occurs.
```

---

## Full Configuration Examples

### Complete HAProxy Config — Management Cluster

```haproxy
# /etc/haproxy/haproxy.cfg — Management Cluster LB Nodes
# LB-MGMT-01 (MASTER) and LB-MGMT-02 (BACKUP)

global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Performance
    maxconn 10000
    ulimit-n 20000

    # SSL defaults
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
    tune.ssl.default-dh-param 2048

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    option redispatch
    retries 3
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    timeout check 5s
    default-server inter 2s fall 3 rise 2

# ─── KUBERNETES API SERVER ───
frontend k8s-api-mgmt
    bind 10.0.1.10:6443
    mode tcp
    option tcplog
    default_backend k8s-masters-mgmt

backend k8s-masters-mgmt
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 6443
    server mgmt-master1 10.0.2.11:6443 check inter 2s fall 3 rise 2
    server mgmt-master2 10.0.2.12:6443 check inter 2s fall 3 rise 2
    server mgmt-master3 10.0.2.13:6443 check inter 2s fall 3 rise 2
    server mgmt-master4 10.0.2.14:6443 check inter 2s fall 3 rise 2
    server mgmt-master5 10.0.2.15:6443 check inter 2s fall 3 rise 2

# ─── HTTP → HTTPS REDIRECT ───
frontend http-redirect
    bind 10.0.1.10:80
    mode http
    redirect scheme https code 301 if !{ ssl_fc }

# ─── HTTPS SERVICES (SNI ROUTING) ───
frontend https-services
    bind 10.0.1.10:443
    mode tcp
    option tcplog
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    use_backend rancher if { req_ssl_sni -i rancher.corp.internal }
    use_backend argocd if { req_ssl_sni -i argocd.corp.internal }
    use_backend grafana if { req_ssl_sni -i grafana.corp.internal }
    use_backend prometheus if { req_ssl_sni -i prometheus.corp.internal }
    use_backend alertmanager if { req_ssl_sni -i alertmanager.corp.internal }
    use_backend harbor if { req_ssl_sni -i harbor.corp.internal }
    use_backend nexus if { req_ssl_sni -i nexus.corp.internal }
    default_backend nginx-ingress-https

# ─── PLATFORM SERVICE BACKENDS ───
backend rancher
    mode tcp
    balance roundrobin
    option tcp-check
    server mgmt-w1 10.0.3.11:30443 check inter 5s fall 3 rise 2
    server mgmt-w2 10.0.3.12:30443 check inter 5s fall 3 rise 2
    server mgmt-w3 10.0.3.13:30443 check inter 5s fall 3 rise 2
    server mgmt-w4 10.0.3.14:30443 check inter 5s fall 3 rise 2
    server mgmt-w5 10.0.3.15:30443 check inter 5s fall 3 rise 2

backend argocd
    mode tcp
    balance roundrobin
    option tcp-check
    server mgmt-w1 10.0.3.11:30444 check inter 5s fall 3 rise 2
    server mgmt-w2 10.0.3.12:30444 check inter 5s fall 3 rise 2
    server mgmt-w3 10.0.3.13:30444 check inter 5s fall 3 rise 2
    server mgmt-w4 10.0.3.14:30444 check inter 5s fall 3 rise 2
    server mgmt-w5 10.0.3.15:30444 check inter 5s fall 3 rise 2

backend grafana
    mode tcp
    balance roundrobin
    option tcp-check
    server mgmt-w1 10.0.3.11:30445 check inter 5s fall 3 rise 2
    server mgmt-w2 10.0.3.12:30445 check inter 5s fall 3 rise 2
    server mgmt-w3 10.0.3.13:30445 check inter 5s fall 3 rise 2
    server mgmt-w4 10.0.3.14:30445 check inter 5s fall 3 rise 2
    server mgmt-w5 10.0.3.15:30445 check inter 5s fall 3 rise 2

backend prometheus
    mode tcp
    balance roundrobin
    option tcp-check
    server mgmt-w1 10.0.3.11:30446 check inter 5s fall 3 rise 2
    server mgmt-w2 10.0.3.12:30446 check inter 5s fall 3 rise 2
    server mgmt-w3 10.0.3.13:30446 check inter 5s fall 3 rise 2
    server mgmt-w4 10.0.3.14:30446 check inter 5s fall 3 rise 2
    server mgmt-w5 10.0.3.15:30446 check inter 5s fall 3 rise 2

backend alertmanager
    mode tcp
    balance roundrobin
    option tcp-check
    server mgmt-w1 10.0.3.11:30447 check inter 5s fall 3 rise 2
    server mgmt-w2 10.0.3.12:30447 check inter 5s fall 3 rise 2
    server mgmt-w3 10.0.3.13:30447 check inter 5s fall 3 rise 2
    server mgmt-w4 10.0.3.14:30447 check inter 5s fall 3 rise 2
    server mgmt-w5 10.0.3.15:30447 check inter 5s fall 3 rise 2

backend harbor
    mode tcp
    balance roundrobin
    option tcp-check
    server harbor-node 10.0.6.21:443 check inter 5s fall 3 rise 2

backend nexus
    mode tcp
    balance roundrobin
    option tcp-check
    server nexus-node 10.0.6.20:8443 check inter 5s fall 3 rise 2

# ─── NGINX INGRESS (Default) ───
backend nginx-ingress-https
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 443
    server mgmt-w1 10.0.3.11:443 check inter 2s fall 3 rise 2
    server mgmt-w2 10.0.3.12:443 check inter 2s fall 3 rise 2
    server mgmt-w3 10.0.3.13:443 check inter 2s fall 3 rise 2
    server mgmt-w4 10.0.3.14:443 check inter 2s fall 3 rise 2
    server mgmt-w5 10.0.3.15:443 check inter 2s fall 3 rise 2

backend nginx-ingress-http
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 80
    server mgmt-w1 10.0.3.11:80 check inter 2s fall 3 rise 2
    server mgmt-w2 10.0.3.12:80 check inter 2s fall 3 rise 2
    server mgmt-w3 10.0.3.13:80 check inter 2s fall 3 rise 2
    server mgmt-w4 10.0.3.14:80 check inter 2s fall 3 rise 2
    server mgmt-w5 10.0.3.15:80 check inter 2s fall 3 rise 2

# ─── STATS PAGE ───
listen stats
    bind 10.0.1.10:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE
    stats auth admin:changeme
    stats show-legends
    stats show-desc "HAProxy Stats - Management Cluster"
```

### Complete HAProxy Config — Application Cluster

```haproxy
# /etc/haproxy/haproxy.cfg — Application Cluster LB Nodes
# LB-APP-01 (MASTER) and LB-APP-02 (BACKUP)

global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 10000
    ulimit-n 20000
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
    tune.ssl.default-dh-param 2048

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    option redispatch
    retries 3
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    timeout check 5s
    default-server inter 2s fall 3 rise 2

# ─── KUBERNETES API SERVER ───
frontend k8s-api-app
    bind 10.0.1.20:6443
    mode tcp
    option tcplog
    default_backend k8s-masters-app

backend k8s-masters-app
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 6443
    server app-master1 10.0.4.11:6443 check inter 2s fall 3 rise 2
    server app-master2 10.0.4.12:6443 check inter 2s fall 3 rise 2
    server app-master3 10.0.4.13:6443 check inter 2s fall 3 rise 2
    server app-master4 10.0.4.14:6443 check inter 2s fall 3 rise 2
    server app-master5 10.0.4.15:6443 check inter 2s fall 3 rise 2

# ─── HTTP → HTTPS REDIRECT ───
frontend http-redirect
    bind 10.0.1.20:80
    mode http
    redirect scheme https code 301 if !{ ssl_fc }

# ─── HTTPS SERVICES (SNI ROUTING) ───
frontend https-services
    bind 10.0.1.20:443
    mode tcp
    option tcplog
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    use_backend grafana if { req_ssl_sni -i grafana.app.corp.internal }
    use_backend prometheus if { req_ssl_sni -i prometheus.app.corp.internal }
    use_backend alertmanager if { req_ssl_sni -i alertmanager.app.corp.internal }
    default_backend nginx-ingress-https

# ─── MONITORING BACKENDS ───
backend grafana
    mode tcp
    balance roundrobin
    option tcp-check
    server app-w1 10.0.5.11:30445 check inter 5s fall 3 rise 2
    server app-w2 10.0.5.12:30445 check inter 5s fall 3 rise 2
    server app-w3 10.0.5.13:30445 check inter 5s fall 3 rise 2
    server app-w4 10.0.5.14:30445 check inter 5s fall 3 rise 2
    server app-w5 10.0.5.15:30445 check inter 5s fall 3 rise 2

backend prometheus
    mode tcp
    balance roundrobin
    option tcp-check
    server app-w1 10.0.5.11:30446 check inter 5s fall 3 rise 2
    server app-w2 10.0.5.12:30446 check inter 5s fall 3 rise 2
    server app-w3 10.0.5.13:30446 check inter 5s fall 3 rise 2
    server app-w4 10.0.5.14:30446 check inter 5s fall 3 rise 2
    server app-w5 10.0.5.15:30446 check inter 5s fall 3 rise 2

backend alertmanager
    mode tcp
    balance roundrobin
    option tcp-check
    server app-w1 10.0.5.11:30447 check inter 5s fall 3 rise 2
    server app-w2 10.0.5.12:30447 check inter 5s fall 3 rise 2
    server app-w3 10.0.5.13:30447 check inter 5s fall 3 rise 2
    server app-w4 10.0.5.14:30447 check inter 5s fall 3 rise 2
    server app-w5 10.0.5.15:30447 check inter 5s fall 3 rise 2

# ─── NGINX INGRESS (Default) ───
backend nginx-ingress-https
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 443
    server app-w1 10.0.5.11:443 check inter 2s fall 3 rise 2
    server app-w2 10.0.5.12:443 check inter 2s fall 3 rise 2
    server app-w3 10.0.5.13:443 check inter 2s fall 3 rise 2
    server app-w4 10.0.5.14:443 check inter 2s fall 3 rise 2
    server app-w5 10.0.5.15:443 check inter 2s fall 3 rise 2

backend nginx-ingress-http
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 80
    server app-w1 10.0.5.11:80 check inter 2s fall 3 rise 2
    server app-w2 10.0.5.12:80 check inter 2s fall 3 rise 2
    server app-w3 10.0.5.13:80 check inter 2s fall 3 rise 2
    server app-w4 10.0.5.14:80 check inter 2s fall 3 rise 2
    server app-w5 10.0.5.15:80 check inter 2s fall 3 rise 2

# ─── STATS PAGE ───
listen stats
    bind 10.0.1.20:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE
    stats auth admin:changeme
    stats show-legends
    stats show-desc "HAProxy Stats - Application Cluster"
```

---

## Air-Gap: Packages from Nexus

### Required Packages

| Package | Version | Repository |
|---------|---------|------------|
| haproxy | 2.8.x | ubuntu-22.04 (hosted) |
| keepalived | 2.2.x | ubuntu-22.04 (hosted) |
| socat | 1.7.x | ubuntu-22.04 (hosted) |

### Installation Script

```bash
#!/bin/bash
# install-lb-packages.sh — Run on each LB node

# Configure apt to use Nexus
cat > /etc/apt/sources.list.d/nexus.list << 'EOF'
deb https://nexus.corp.internal/repository/ubuntu-22-04/ jammy main restricted universe multiverse
deb https://nexus.corp.internal/repository/ubuntu-22-04/ jammy-updates main restricted universe multiverse
deb https://nexus.corp.internal/repository/ubuntu-22-04-security/ jammy-security main restricted universe multiverse
EOF

# Add Nexus CA certificate
cp /tmp/nexus-ca.crt /usr/local/share/ca-certificates/
update-ca-certificates

# Install packages
apt-get update
apt-get install -y haproxy keepalived socat

# Verify versions
haproxy -v
keepalived --version
```

### Offline Package Download (for manual transfer)

```bash
# On a machine with internet access
apt-get download haproxy keepalived socat

# Transfer to air-gap via approved media
# Then install:
dpkg -i haproxy_2.8.*_amd64.deb keepalived_2.*_amd64.deb socat_1.7.*_amd64.deb
```

### HAProxy Service Configuration

```bash
# Enable HAProxy
systemctl enable haproxy
systemctl start haproxy

# Validate configuration before restart
haproxy -c -f /etc/haproxy/haproxy.cfg
```

### keepalived Service Configuration

```bash
# Enable keepalived
systemctl enable keepalived
systemctl start keepalived

# Check status
systemctl status keepalived
journalctl -u keepalived -f
```

---

## Monitoring and Operations

### Prometheus Metrics for HAProxy

```yaml
# haproxy-exporter deployment (optional)
# Or use HAProxy's built-in Prometheus endpoint (HAProxy 2.4+)
```

```haproxy
# HAProxy Prometheus endpoint (HAProxy 2.4+)
frontend prometheus
    bind 10.0.1.10:8405
    mode http
    http-request use-service prometheus-exporter if { path /metrics }
```

### Key Metrics to Monitor

| Metric | Warning Threshold | Critical Threshold |
|--------|------------------|-------------------|
| Backend server UP | < 3 of 5 | < 2 of 5 |
| HAProxy process | Not running | — |
| VIP not on expected node | — | VIP missing |
| Connection rate | > 80% maxconn | > 95% maxconn |
| Response time (p99) | > 500ms | > 2s |
| Queue depth | > 100 | > 500 |

### Grafana Dashboard Panels

- K8s API server response time (p50, p95, p99)
- Backend server health (UP/DOWN per master)
- Active connections per backend
- VIP ownership (which node is MASTER)
- HAProxy memory usage
- Request rate per service

### Log Rotation

```bash
# /etc/logrotate.d/haproxy
/var/log/haproxy/*.log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
```

---

## Troubleshooting

### VIP Not Accessible

```bash
# Check which node holds the VIP
ip addr show eth0 | grep 10.0.1.10

# Check keepalived status
systemctl status keepalived
journalctl -u keepalived --since "5 minutes ago"

# Check VRRP advertisements
tcpdump -i eth0 vrrp -n

# Check if HAProxy is running
systemctl status haproxy
ss -tlnp | grep -E '6443|443|80'
```

### HAProxy Backend Down

```bash
# Check backend status
echo "show stat" | socat stdio /run/haproxy/admin.sock | grep -E "k8s-masters|nginx-ingress"

# Check HAProxy logs
journalctl -u haproxy --since "5 minutes ago"

# Test backend connectivity
nc -zv 10.0.2.11 6443
nc -zv 10.0.2.12 6443

# Check HAProxy configuration
haproxy -c -f /etc/haproxy/haproxy.cfg
```

### keepalived Not Failing Over

```bash
# Check VRRP state
cat /var/run/keepalived.state

# Check health script output
/usr/local/bin/check-haproxy.sh
echo $?  # Should be 0

# Check priority
ip -4 addr show eth0 | grep "inet "

# Check firewall (VRRP protocol 112 must be allowed)
iptables -L -n | grep 112
```

### SNI Routing Not Working

```bash
# Test SNI routing
openssl s_client -connect 10.0.1.10:443 -servername rancher.corp.internal </dev/null
openssl s_client -connect 10.0.1.10:443 -servername grafana.corp.internal </dev/null

# Check HAProxy logs for SNI
journalctl -u haproxy | grep "SNI"

# Verify tcp-request inspect-delay is sufficient
grep inspect /etc/haproxy/haproxy.cfg
```

### Common Issues and Resolution

| Symptom | Cause | Resolution |
|---------|-------|------------|
| VIP not on any node | keepalived not running | Start keepalived, check config |
| VIP on wrong node | Priority misconfiguration | Check priority values |
| Backend shows DOWN | Health check failing | Check backend connectivity, health check config |
| Slow failover | advert_int too high | Reduce to 1s |
| SNI routing fails | inspect-delay too short | Increase to 5s |
| Connection refused | HAProxy not listening | Check bind address, port conflicts |
| SSL handshake error | Certificate issue | Check cert validity, SNI matching |
