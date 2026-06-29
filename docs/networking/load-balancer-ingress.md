# Load Balancer & Ingress Controller Guide

> HTTP/TCP load balancing and ingress for bare-metal / air-gapped Kubernetes

---

## 1. Architecture Overview

```
                         Internet / Internal Network
                                │
                    ┌───────────┴───────────┐
                    │   MetalLB (Layer 2)   │
                    │   10.0.0.100-10.0.0.150│
                    └───────────┬───────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
    ┌─────────┴──────┐  ┌──────┴───────┐  ┌──────┴───────┐
    │  Worker Node 1 │  │ Worker Node 2│  │ Worker Node 3│
    │  10.0.0.11     │  │ 10.0.0.12    │  │ 10.0.0.13    │
    └────────────────┘  └──────────────┘  └──────────────┘
              │                 │                 │
              └─────────────────┼─────────────────┘
                                │
                    ┌───────────┴───────────┐
                    │  NGINX Ingress        │
                    │  (DaemonSet)          │
                    │  10.0.0.100 (VIP)     │
                    └───────────┬───────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
        ┌─────┴─────┐    ┌─────┴─────┐    ┌─────┴─────┐
        │  Service A │    │  Service B │    │  Service C │
        └───────────┘    └───────────┘    └───────────┘
```

---

## 2. MetalLB — Bare-Metal Load Balancer

MetalLB provides LoadBalancer services on bare-metal (no cloud provider).

### 2.1 Install MetalLB

```bash
# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.0/config/manifests/metallb-native.yaml

# Wait for pods
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s
```

### 2.2 Configure IP Address Pool

```yaml
# metallb-ipaddresspool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.0.0.100-10.0.0.150  # Range of IPs for LoadBalancer services
  autoAssign: true
  avoidBuggyIPs: true
```

### 2.3 Configure L2 Advertisement

```yaml
# metallb-l2advertisement.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
    - default-pool
  interfaces:
    - eth0  # Interface to announce on
```

### 2.4 Configure BGP (Optional — for larger networks)

```yaml
# metallb-bgp.yaml
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: router-peer
  namespace: metallb-system
spec:
  myASN: 64512
  peerASN: 64513
  peerAddress: 10.0.0.1
  routerID: 10.0.0.100

---
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
    - default-pool
  aggregationLength: 32
  localPref: 100
  communities:
    - 64512:1
```

### 2.5 Verify MetalLB

```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# Check IP address pool
kubectl get ipaddresspool -n metallb-system -o yaml

# Check L2 advertisement
kubectl get l2advertisement -n metallb-system -o yaml

# Test with a LoadBalancer service
kubectl create deployment test --image=nginx
kubectl expose deployment test --type=LoadBalancer --port=80
kubectl get svc test  # Should show EXTERNAL-IP from pool
```

---

## 3. NGINX Ingress Controller

### 3.1 Install via Helm

```bash
# Add repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install with MetalLB
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."metallb\.universe\.ft/address-pool"=default-pool \
  --set controller.service.annotations."metallb\.universe\.ft/allow-shared-ip"=true \
  --set controller.replicaCount=2 \
  --set controller.nodeSelector."node-role\.kubernetes.io/infra"="" \
  --set controller.metrics.enabled=true \
  --set controller.service.externalTrafficPolicy=Local
```

### 3.2 Install via KubeSpray (Already Included)

If you deployed with KubeSpray, NGINX Ingress is already installed:

```bash
# Check existing installation
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

### 3.3 Custom Ports for Ingress

```yaml
# values-custom-ports.yaml
controller:
  service:
    type: LoadBalancer
    ports:
      http: 8080      # Custom HTTP port (default: 80)
      https: 8443     # Custom HTTPS port (default: 443)
    targetPorts:
      http: 8080
      https: 8443
  containerPort:
    http: 8080
    https: 8443
```

### 3.4 TCP/UDP Load Balancing via Ingress

NGINX Ingress can also load balance TCP/UDP services (not just HTTP):

```yaml
# tcp-services-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tcp-services
  namespace: ingress-nginx
data:
  3306: "database/mysql:3306"        # MySQL
  5432: "database/postgres:5432"      # PostgreSQL
  6379: "cache/redis:6379"            # Redis
  6443: "kube-system/kube-apiserver:6443"  # K8s API
  9090: "monitoring/prometheus:9090"  # Prometheus
  3000: "monitoring/grafana:3000"      # Grafana

---
# udp-services-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: udp-services
  namespace: ingress-nginx
data:
  53: "kube-system/kube-dns:53"       # CoreDNS
```

### 3.5 Ingress Resource Examples

```yaml
# ingress-example.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - app.internal.lan
      secretName: app-tls
  rules:
    - host: app.internal.lan
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-service
                port:
                  number: 80
    - host: api.internal.lan
      http:
        paths:
          - path: /v1
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 8080
          - path: /v2
            pathType: Prefix
            backend:
              service:
                name: api-v2-service
                port:
                  number: 8080
```

### 3.6 Ingress for Internal Services (Behind MetalLB)

```yaml
# ingress-internal.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: prometheus-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - prometheus.internal.lan
      secretName: prometheus-tls
  rules:
    - host: prometheus.internal.lan
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kube-prometheus-stack-prometheus
                port:
                  number: 9090
```

---

## 4. HAProxy + Keepalived (Alternative to MetalLB)

For environments where MetalLB doesn't work (e.g., complex BGP setups):

### 4.1 Install Keepalived

```bash
# On all master nodes
sudo apt-get install -y keepalived haproxy

# Configure keepalived (master)
cat > /etc/keepalived/keepalived.conf <<EOF
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass secret
    }
    virtual_ipaddress {
        10.0.0.100/24
    }
}

vrrp_script chk_haproxy {
    script "killall -0 haproxy"
    interval 2
    weight 2
    fall 3
    rise 2
}

track_script {
    chk_haproxy
}
EOF

# On backup nodes, change: state BACKUP, priority 90
```

### 4.2 Configure HAProxy

```bash
# /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    maxconn 4096
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client 30s
    timeout server 30s

# Kubernetes API
frontend k8s-api
    bind 10.0.0.100:6443
    default_backend k8s-masters

backend k8s-masters
    balance roundrobin
    option tcp-check
    server master-1 10.0.0.11:6443 check
    server master-2 10.0.0.12:6443 check
    server master-3 10.0.0.13:6443 check

# HTTP Ingress
frontend http-ingress
    bind 10.0.0.100:80
    default_backend http-nodes

backend http-nodes
    balance roundrobin
    option tcp-check
    server worker-1 10.0.0.20:30080 check
    server worker-2 10.0.0.21:30080 check
    server worker-3 10.0.0.22:30080 check

# HTTPS Ingress
frontend https-ingress
    bind 10.0.0.100:443
    default_backend https-nodes

backend https-nodes
    balance roundrobin
    option tcp-check
    server worker-1 10.0.0.20:30443 check
    server worker-2 10.0.0.21:30443 check
    server worker-3 10.0.0.22:30443 check
```

---

## 5. Comparison: MetalLB vs HAProxy/Keepalived

| Feature | MetalLB | HAProxy/Keepalived |
|---------|---------|-------------------|
| **Setup complexity** | Low (Helm/YAML) | Medium (config files) |
| **Protocol** | L2 (ARP) or BGP | L4 (TCP) |
| **VIP failover** | Automatic | Keepalived VRRP |
| **Load balancing** | L2 only (equal) | L4 (roundrobin, leastconn) |
| **HTTP awareness** | No (L2) | No (L4) |
| **Works with Ingress** | Yes (provides IP) | Yes (provides IP) |
| **BGP support** | Yes | No |
| **Air-gap friendly** | Yes | Yes |
| **Maintenance** | Low | Medium |

**Recommendation**: Use **MetalLB** for simplicity. Use **HAProxy/Keepalived** if you need advanced L4 load balancing or BGP isn't available.

---

## 6. Service Health (Load Balancer & Ingress)

```bash
# MetalLB
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# NGINX Ingress
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
kubectl get ingress --all-namespaces

# Test LoadBalancer
kubectl get svc -n ingress-nginx | grep EXTERNAL-IP
curl -I http://<EXTERNAL-IP>/

# Test Ingress
curl -v -H "Host: app.internal.lan" http://<EXTERNAL-IP>/

# HAProxy/Keepalived
systemctl status keepalived
systemctl status haproxy
echo "show stat" | socat stdio /var/run/haproxy.sock | cut -d, -f1,2,18
ip addr show eth0 | grep 10.0.0.100
```
