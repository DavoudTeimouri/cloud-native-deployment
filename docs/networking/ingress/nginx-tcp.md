# NGINX Ingress Controller — TCP/UDP Guide

## Table of Contents
- [Overview](#overview)
- [TCP Service Exposure](#tcp-service-exposure)
- [Configuration Examples](#configuration-examples)
- [UDP Service Exposure](#udp-service-exposure)
- [Proxy Protocol Support](#proxy-protocol-support)
- [HAProxy TCP Passthrough Configuration](#haproxy-tcp-passthrough-configuration)
- [Decision Matrix: Ingress TCP vs MetalLB vs NodePort](#decision-matrix-ingress-tcp-vs-metallb-vs-nodeport)
- [TLS Passthrough (SNI-Based Routing)](#tls-passthrough-sni-based-routing)
- [Stream Snippet Configuration](#stream-snippet-configuration)
- [Connection Timeout Tuning](#connection-timeout-tuning)

---

## Overview

The NGINX Ingress Controller supports TCP and UDP services in addition to HTTP/HTTPS. This is useful for exposing databases, SSH, message queues, and other non-HTTP services through the same ingress infrastructure.

**Traffic Flow (TCP Passthrough):**

```
External Client
     │
     ▼
HAProxy (VIP: 10.0.1.20, TCP passthrough on port 5432)
     │
     ▼
NGINX Ingress Controller (stream block → TCP service)
     │
     ▼
Service → Pod (e.g., PostgreSQL)
```

**Traffic Flow (TLS Passthrough):**

```
External Client (TLS connection)
     │
     ▼
HAProxy (VIP: 10.0.1.20, TCP passthrough on port 443)
     │ (HAProxy inspects SNI)
     ▼
NGINX Ingress Controller (routes by SNI, does NOT decrypt)
     │
     ▼
TLS-enabled backend service
```

---

## TCP Service Exposure

### ConfigMap for TCP Services

The NGINX Ingress Controller uses a ConfigMap to define TCP services. The keys are `<namespace>/<service-name>:<service-port>` and values are the external port to expose.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tcp-services
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/component: controller
data:
  # Format: "<namespace>/<service-name>:<service-port>"
  "production/postgres:5432": "production/postgres:5432"
  "production/redis:6379": "production/redis:6379"
  "development/mysql:3306": "development/mysql:3306"
  "monitoring/cassandra:9042": "monitoring/cassandra:9042"
  "cattle-system/rancher-mongodb:27017": "cattle-system/rancher-mongodb:27017"
```

### Helm Values for TCP Services

```yaml
# values-nginx-ingress.yaml
controller:
  # ... other config ...
  
  tcp:
    "5432": "production/postgres:5432"
    "6379": "production/redis:6379"
    "3306": "development/mysql:3306"
    "9042": "monitoring/cassandra:9042"
    "22": "production/jumpserver:22"
```

### Enabling TCP Services

```yaml
# In the controller args
args:
- /nginx-ingress-controller
- --tcp-services-configmap=$(POD_NAMESPACE)/tcp-services
- --udp-services-configmap=$(POD_NAMESPACE)/udp-services
```

---

## Configuration Examples

### PostgreSQL

```yaml
# TCP Service ConfigMap entry
apiVersion: v1
kind: ConfigMap
metadata:
  name: tcp-services
  namespace: ingress-nginx
data:
  "production/postgres:5432": "production/postgres:5432"

---
# Backend Service
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: production
spec:
  ports:
  - port: 5432
    targetPort: 5432
    name: postgres
  selector:
    app: postgresql
---
# PostgreSQL connection string for clients:
# psql -h 10.0.1.20 -p 5432 -U admin -d mydb
```

### Redis

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tcp-services
  namespace: ingress-nginx
data:
  "production/redis:6379": "production/redis:6379"

---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: production
spec:
  ports:
  - port: 6379
    targetPort: 6379
    name: redis
  selector:
    app: redis
```

### MySQL/MariaDB

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tcp-services
  namespace: ingress-nginx
data:
  "staging/mysql:3306": "staging/mysql:3306"

---
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: staging
spec:
  ports:
  - port: 3306
    targetPort: 3306
    name: mysql
  selector:
    app: mysql
```

### SSH Jump Host

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tcp-services
  namespace: ingress-nginx
data:
  "infra/jumpserver:22": "infra/jumpserver:22"

---
apiVersion: v1
kind: Service
metadata:
  name: jumpserver
  namespace: infra
  annotations:
    # SSH requires longer timeouts
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ports:
  - port: 22
    targetPort: 22
    name: ssh
  selector:
    app: jumpserver
```

### Custom Application (AMQP/RabbitMQ)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tcp-services
  namespace: ingress-nginx
data:
  "production/rabbitmq:5672": "production/rabbitmq:5672"
  "production/rabbitmq-management:15672": "production/rabbitmq-management:15672"

---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
  namespace: production
spec:
  ports:
  - port: 5672
    targetPort: 5672
    name: amqp
  - port: 15672
    targetPort: 15672
    name: management
  selector:
    app: rabbitmq
```

### etcd (for external access)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tcp-services
  namespace: ingress-nginx
data:
  "kube-system/etcd:2379": "kube-system/etcd:2379"

---
apiVersion: v1
kind: Service
metadata:
  name: etcd-external
  namespace: kube-system
spec:
  type: ClusterIP
  ports:
  - port: 2379
    targetPort: 2379
    name: etcd-client
  selector:
    component=etcd,tier=control-plane
```

---

## UDP Service Exposure

### UDP ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: udp-services
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/component: controller
data:
  "monitoring/dns:53": "monitoring/dns:53"
  "monitoring/syslog:514": "monitoring/syslog:514"
  "production/ntp:123": "production/ntp:123"
```

### Helm Values for UDP

```yaml
controller:
  udp:
    "53": "monitoring/dns:53"
    "514": "monitoring/syslog:514"
    "123": "production/ntp:123"
```

### DNS Example

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: udp-services
  namespace: ingress-nginx
data:
  "monitoring/ingress-dns:53": "monitoring/ingress-dns:53"

---
apiVersion: v1
kind: Service
metadata:
  name: ingress-dns
  namespace: monitoring
spec:
  ports:
  - port: 53
    protocol: UDP
    targetPort: 53
    name: dns
  selector:
    app: dns-server
```

---

## Proxy Protocol Overview

Proxy Protocol preserves the original client IP address when traffic passes through a load balancer. HAProxy sends proxy protocol headers, and NGINX Ingress decodes them.

```
Client (172.16.1.55)
     │
     ▼
HAProxy (adds PROXY protocol header)
     │
     ▼
NGINX Ingress (decodes PROXY header, sees original client IP)
     │
     ▼
Backend Pod (sees original client IP in logs)
```

---

## HAProxy TCP Passthrough Configuration

### HAProxy with Proxy Protocol

```haproxy
# /etc/haproxy/haproxy.cfg (Application Cluster LB nodes)

# K8s API Server (TCP 6443)
frontend k8s-api
    bind 10.0.1.20:6443
    mode tcp
    option tcplog
    default_backend k8s-api-masters

backend k8s-api-masters
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 6443
    
    # Send proxy protocol v2
    server app-master1 10.0.4.11:6443 check send-proxy-v2
    server app-master2 10.0.4.12:6443 check send-proxy-v2
    server app-master3 10.0.4.13:6443 check send-proxy-v2
    server app-master4 10.0.4.14:6443 check send-proxy-v2
    server app-master5 10.0.4.15:6443 check send-proxy-v2

# PostgreSQL passthrough (TCP 5432)
frontend postgres
    bind 10.0.1.20:5432
    mode tcp
    option tcplog
    default_backend postgres-ingress

backend postgres-ingress
    mode tcp
    balance leastconn
    option tcp-check
    tcp-check connect port 5432
    
    server app-w1 10.0.5.11:5432 check send-proxy-v2 inter 5s fall 3
    server app-w2 10.0.5.12:5432 check send-proxy-v2 inter 5s fall 3
    server app-w3 10.0.5.13:5432 check send-proxy-v2 inter 5s fall 3
    server app-w4 10.0.5.14:5432 check send-proxy-v2 inter 5s fall 3
    server app-w5 10.0.5.15:5432 check send-proxy-v2 inter 5s fall 3

# Redis passthrough (TCP 6379)
frontend redis
    bind 10.0.1.20:6379
    mode tcp
    option tcplog
    default_backend redis-ingress

backend redis-ingress
    mode tcp
    balance leastconn
    option tcp-check
    tcp-check connect port 6379
    
    server app-w1 10.0.5.11:6379 check send-proxy-v2 inter 5s fall 3
    server app-w2 10.0.5.12:6379 check send-proxy-v2 inter 5s fall 3
    server app-w3 10.0.5.13:6379 check send-proxy-v2 inter 5s fall 3
    server app-w4 10.0.5.14:6379 check send-proxy-v2 inter 5s fall 3
    server app-w5 10.0.5.15:6379 check send-proxy-v2 inter 5s fall 3

# MySQL passthrough (TCP 3306)
frontend mysql
    bind 10.0.1.20:3306
    mode tcp
    option tcplog
    default_backend mysql-ingress

backend mysql-ingress
    mode tcp
    balance leastconn
    option tcp-check
    tcp-check connect port 3306
    
    server app-w1 10.0.5.11:3306 check send-proxy-v2 inter 5s fall 3
    server app-w2 10.0.5.12:3306 check send-proxy-v2 inter 5s fall 3
    server app-w3 10.0.5.13:3306 check send-proxy-v2 inter 5s fall 3
    server app-w4 10.0.5.14:3306 check send-proxy-v2 inter 5s fall 3
    server app-w5 10.0.5.15:3306 check send-proxy-v2 inter 5s fall 3
```

### HAProxy Without Proxy Protocol (Simpler)

```haproxy
# If you don't need source IP preservation
backend postgres-ingress-simple
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 5432
    
    server app-w1 10.0.5.11:5432 check inter 5s fall 3
    server app-w2 10.0.5.12:5432 check inter 5s fall 3
    server app-w3 10.0.5.13:5432 check inter 5s fall 3
    server app-w4 10.0.5.14:5432 check inter 5s fall 3
    server app-w5 10.0.5.15:5432 check inter 5s fall 3
```

---

## Decision Matrix: Overview

Use this matrix to decide how to expose TCP services in your cluster.

### All TCP Exposure Methods

| Method | Complexity | Performance | Source IP | Port Range | Best For |
|--------|-----------|-------------|-----------|------------|----------|
| NGINX Ingress TCP | Medium | Good | Proxy Protocol | Defined per-service | Few TCP services, unified ingress |
| MetalLB LoadBalancer | Low | Excellent | Preserved | Any | Most TCP services, simple |
| NodePort | Lowest | Good | Preserved | 30000-32767 | Development, temporary |
| HostPort | Lowest | Direct | Preserved | Any (host ports) | Single-node services |

---

## TLS Passthrough Routes

TLS passthrough terminates TLS at the backend service (not NGINX). NGINX routes based on SNI (Server Name Indication) without decrypting the traffic.

### Configuration

```yaml
# Enable TLS passthrough in Ingress annotations
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-passthrough
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/secure-backends: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: db-tls.corp.internal:
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: postgres-tls
            port:
              number: 5432
```

### HAProxy Configuration for TLS Passthrough

```haproxy
# HAProxy routes by SNI without decrypting TLS
frontend tls-services
    bind 10.0.1.20:5432
    mode tcp
    option tcplog
    
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    use_backend postgres-tls if { req_ssl_sni -i db-tls.corp.internal }
    use_backend mysql-tls if { req_ssl_sni -i mysql-tls.corp.internal }
    
    # Default: send to NGINX Ingress for SNI-based routing
    default_backend nginx-tls-passthrough

backend nginx-tls-passthrough
    mode tcp
    balance roundrobin
    option tcp-check
    server app-w1 10.0.5.11:5432 check
    server app-w2 10.0.5.12:5432 check
    server app-w3 10.0.5.13:5432 check
    server app-w4 10.0.5.14:5432 check
    server app-w5 10.0.5.15:5432 check

backend postgres-tls
    mode tcp
    balance roundrobin
    server postgres1 10.2.1.10:5432 check sni ssl_fc_sni

backend mysql-tls
    mode tcp
    balance roundrobin
    server mysql1 10.2.1.11:3306 check sni ssl_fc_sni
```

### NGINX ConfigMap for TLS Passthrough

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  # Enable proxy protocol for TCP services
  use-proxy-protocol: "true"
  # Real IP from proxy protocol
  proxy-real-ip-cidr: "0.0.0.0/0"
  
  # TCP passthrough ports
  tcp-services-configmap: "ingress-nginx/tcp-services"
```

---

## Stream Snippet Configuration

### Using stream-snippet for Advanced TCP

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  # Stream-level configuration
  stream-snippet: |
    server {
        listen 5432;
        proxy_pass production_postgres_5432;
        proxy_timeout 1s;
        proxy_connect_timeout 1s;
        proxy_protocol on;
    }
    
    server {
        listen 6379;
        proxy_pass production_redis_6379;
        proxy_timeout 300s;
        proxy_connect_timeout 5s;
    }
```

### Upstream Health Checking (NGINX Plus Only)

```yaml
data:
  stream-snippet: |
    upstream postgres_backend {
        server production-postgres-0.postgres.production.svc.cluster.local:5432;
        server production-postgres-1.postgres.production.svc.cluster.local:5432;
        
        zone postgres_backend 64k;
        
        # NGINX Plus health check
        health_check interval=5s passes=2 fails=3 port=5432;
    }
    
    server {
        listen 5432;
        proxy_pass postgres_backend;
        health_check;
    }
```

---

## Connection Timeout Tuning

### Default Timeout Values

| Parameter | Default | Description |
|-----------|---------|-------------|
| proxy_connect_timeout | 60s | Connection timeout to upstream |
| proxy_timeout | 10m (TCP) / 60s (TLS) | Idle timeout |
| proxy_next_upstream_timeout | 0 | Try next server after timeout |
| proxy_protocol_timeout | 30s | Read proxy protocol header |

### Tuning for Long-Lived Connections (SSH, WebSocket, DB)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  # Global defaults
  proxy-connect-timeout: "10"
  proxy-read-timeout: "3600"
  proxy-send-timeout: "3600"
  
  # Stream-level overrides
  stream-snippet: |
    # SSH: very long timeouts
    server {
        listen 22;
        proxy_pass infra_jumpserver_22;
        proxy_timeout 24h;
        proxy_connect_timeout 10s;
    }
    
    # Database: moderate timeouts
    server {
        listen 5432;
        proxy_pass production_postgres_5432;
        proxy_timeout 30m;
        proxy_connect_timeout 5s;
    }
    
    # Redis: long-lived connections
    server {
        listen 6379;
        proxy_pass production_redis_6379;
        proxy_timeout 2h;
        proxy_connect_timeout 5s;
    }
```

### ExternalTrafficPolicy for Source IP Preservation

```yaml
# For TCP services where source IP matters
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: production
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"  # Not applicable for MetalLB
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local    # Preserve source IP, no hairpin
  ports:
  - port: 5432
    targetPort: 5432
  selector:
    app: postgresql
```

---

## Complete TCP/UDP Configuration Example

### All-in-One ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tcp-services
  namespace: ingress-nginx
data:
  "22": "infra/jumpserver:22"
  "5432": "production/postgres:5432"
  "3306": "staging/mysql:3306"
  "6379": "production/redis:6379"
  "5672": "production/rabbitmq:5672"
  "9042": "monitoring/cassandra:9042"
  "27017": "cattle-system/rancher-mongodb:27017"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: udp-services
  namespace: ingress-nginx
data:
  "53": "monitoring/dns:53"
  "514": "monitoring/syslog:514"
  "123": "production/ntp:123"
  "161": "monitoring/snmp:161"
```

### Corresponding HAProxy Frontend/Backend Pairs

```haproxy
# /etc/haproxy/haproxy.cfg additions for TCP services

# Define ACLs for port-based routing
frontend all-tcp-services
    bind 10.0.1.20:22
    bind 10.0.1.20:5432
    bind 10.0.1.20:3306
    bind 10.0.1.20:6379
    bind 10.0.1.20:5672
    bind 10.0.1.20:9042
    bind 10.0.1.20:27017
    mode tcp
    option tcplog
    
    # Route based on destination port
    use_backend ssh-ingress if { dst_port 22 }
    use_backend postgres-ingress if { dst_port 5432 }
    use_backend mysql-ingress if { dst_port 3306 }
    use_backend redis-ingress if { dst_port 6379 }
    use_backend rabbitmq-ingress if { dst_port 5672 }
    use_backend cassandra-ingress if { dst_port 9042 }
    use_backend mongodb-ingress if { dst_port 27017 }

backend ssh-ingress
    mode tcp
    balance leastconn
    option tcp-check
    timeout server 24h
    timeout connect 10s
    server app-w1 10.0.5.11:22 check send-proxy-v2 inter 10s fall 3
    server app-w2 10.0.5.12:22 check send-proxy-v2 inter 10s fall 3
    server app-w3 10.0.5.13:22 check send-proxy-v2 inter 10s fall 3
    server app-w4 10.0.5.14:22 check send-proxy-v2 inter 10s fall 3
    server app-w5 10.0.5.15:22 check send-proxy-v2 inter 10s fall 3

backend postgres-ingress
    mode tcp
    balance leastconn
    option tcp-check
    timeout server 30m
    timeout connect 5s
    tcp-check connect port 5432
    server app-w1 10.0.5.11:5432 check send-proxy-v2 inter 5s fall 3
    server app-w2 10.0.5.12:5432 check send-proxy-v2 inter 5s fall 3
    server app-w3 10.0.5.13:5432 check send-proxy-v2 inter 5s fall 3
    server app-w4 10.0.5.14:5432 check send-proxy-v2 inter 5s fall 3
    server app-w5 10.0.5.15:5432 check send-proxy-v2 inter 5s fall 3

backend mysql-ingress
    mode tcp
    balance leastconn
    option tcp-check
    timeout server 30m
    timeout connect 5s
    tcp-check connect port 3306
    server app-w1 10.0.5.11:3306 check send-proxy-v2 inter 5s fall 3
    server app-w2 10.0.5.12:3306 check send-proxy-v2 inter 5s fall 3
    server app-w3 10.0.5.13:3306 check send-proxy-v2 inter 5s fall 3
    server app-w4 10.0.5.14:3306 check send-proxy-v2 inter 5s fall 3
    server app-w5 10.0.5.15:3306 check send-proxy-v2 inter 5s fall 3

backend redis-ingress
    mode tcp
    balance leastconn
    option tcp-check
    timeout server 2h
    timeout connect 5s
    tcp-check connect port 6379
    server app-w1 10.0.5.11:6379 check send-proxy-v2 inter 5s fall 3
    server app-w2 10.0.5.12:6379 check send-proxy-v2 inter 5s fall 3
    server app-w3 10.0.5.13:6379 check send-proxy-v2 inter 5s fall 3
    server app-w4 10.0.5.14:6379 check send-proxy-v2 inter 5s fall 3
    server app-w5 10.0.5.15:6379 check send-proxy-v2 inter 5s fall 3

backend rabbitmq-ingress
    mode tcp
    balance leastconn
    option tcp-check
    timeout server 1h
    timeout connect 5s
    tcp-check connect port 5672
    server app-w1 10.0.5.11:5672 check send-proxy-v2 inter 5s fall 3
    server app-w2 10.0.5.12:5672 check send-proxy-v2 inter 5s fall 3
    server app-w3 10.0.5.13:5672 check send-proxy-v2 inter 5s fall 3
    server app-w4 10.0.5.14:5672 check send-proxy-v2 inter 5s fall 3
    server app-w5 10.0.5.15:5672 check send-proxy-v2 inter 5s fall 3

backend cassandra-ingress
    mode tcp
    balance leastconn
    option tcp-check
    timeout server 30m
    timeout connect 10s
    tcp-check connect port 9042
    server app-w1 10.0.5.11:9042 check send-proxy-v2 inter 10s fall 3
    server app-w2 10.0.5.12:9042 check send-proxy-v2 inter 10s fall 3
    server app-w3 10.0.5.13:9042 check send-proxy-v2 inter 10s fall 3
    server app-w4 10.0.5.14:9042 check send-proxy-v2 inter 10s fall 3
    server app-w5 10.0.5.15:9042 check send-proxy-v2 inter 10s fall 3

backend mongodb-ingress
    mode tcp
    balance leastconn
    option tcp-check
    timeout server 30m
    timeout connect 5s
    tcp-check connect port 27017
    server app-w1 10.0.5.11:27017 check send-proxy-v2 inter 5s fall 3
    server app-w2 10.0.5.12:27017 check send-proxy-v2 inter 5s fall 3
    server app-w3 10.0.5.13:27017 check send-proxy-v2 inter 5s fall 3
    server app-w4 10.0.5.14:27017 check send-proxy-v2 inter 5s fall 3
    server app-w5 10.0.5.15:27017 check send-proxy-v2 inter 5s fall 3
```

---

## Troubleshooting TCP/UDP Services

### Common Issues

```bash
# Check if TCP services are loaded
kubectl -n ingress-nginx exec <ingress-pod> -- nginx -T | grep "listen"

# Check ConfigMap is mounted correctly
kubectl -n ingress-nginx exec <ingress-pod> -- cat /etc/nginx/tcp-services.json

# Check NGINX error logs
kubectl -n ingress-nginx logs <ingress-pod> --tail=100

# Verify HAProxy is listening on the TCP port
ss -tlnp | grep 5432

# Test connectivity from outside
nc -zv 10.0.1.20 5432

# Check if backend service endpoints are ready
kubectl get endpoints postgres -n production
```

### Debugging Steps

1. **Verify ConfigMap is applied:**
   ```bash
   kubectl -n ingress-nginx get configmap tcp-services -o yaml
   ```

2. **Check NGINX configuration reload:**
   ```bash
   kubectl -n ingress-nginx logs <ingress-pod> | grep "Configuration changes detected"
   ```

3. **Verify HAProxy backend health:**
   ```bash
   echo "show stat" | socat stdio /var/run/haproxy.sock | grep postgres
   ```

4. **Test end-to-end:**
   ```bash
   # From a pod inside the cluster
   kubectl run test --image=harbor.corp.internal/system/netshoot --rm -it -- \
     nc -zv postgres.production.svc.cluster.local 5432
   
   # From outside the cluster
   nc -zv 10.0.1.20 5432
   ```
