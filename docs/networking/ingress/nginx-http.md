# NGINX Ingress Controller — HTTP Guide

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Deployment as DaemonSet](#deployment-as-daemonset)
- [Helm Chart Configuration](#helm-chart-configuration)
- [IngressClass Configuration](#ingressclass-configuration)
- [TLS Termination](#tls-termination)
- [HTTP Routing Examples](#http-routing-examples)
- [Path-Based Routing](#path-based-routing)
- [Name-Based Virtual Hosting](#name-based-virtual-hosting)
- [Rate Limiting](#rate-limiting)
- [IP Whitelisting](#ip-whitelisting)
- [Custom NGINX Snippets](#custom-nginx-snippets)
- [Proxy Buffer Tuning](#proxy-buffer-tuning)
- [WebSocket Support](#websocket-support)
- [HAProxy Configuration for NGINX Ingress](#haproxy-configuration-for-nginx-ingress)
- [Air-Gap: NGINX Ingress Images from Harbor](#air-gap-nginx-ingress-images-from-harbor)

---

## Overview

The NGINX Ingress Controller handles HTTP/HTTPS traffic routing within the Application cluster. It works in conjunction with the external HAProxy load balancers to provide a complete ingress solution.

**Traffic Flow:**

```
External User
     │
     ▼
DNS: app.example.com → 10.0.1.20 (HAProxy VIP)
     │
     ▼
HAProxy (LB-APP-01 / LB-APP-02)
     │
     ▼
NGINX Ingress Controller (DaemonSet on worker nodes)
     │
     ▼
Service → Pod
```

---

## Architecture

### Two-Layer Load Balancing

| Layer | Component | Role |
|-------|-----------|------|
| External | HAProxy + keepalived | L4 load balancing, VIP failover, SSL offloading (optional) |
| Internal | NGINX Ingress Controller | L7 routing, TLS termination, rate limiting, path-based rules |

### Why Two Layers?

1. **HAProxy** provides high-availability VIPs via keepalived and handles raw TCP/SSL passthrough
2. **NGINX Ingress** provides Kubernetes-native L7 routing with Ingress resource integration
3. Separation of concerns: network team manages HAProxy, platform team manages Ingress

### Deployment Models

| Model | Description | Use Case |
|-------|-------------|----------|
| DaemonSet + hostNetwork | NGINX runs on host network, one pod per node | Production (recommended) |
| Deployment + MetalLB | NGINX gets LoadBalancer IP from MetalLB | Alternative |
| Deployment + NodePort | NGINX exposed via NodePort | Development |

---

## Deployment as DaemonSet

### Production Best Practice: DaemonSet with hostNetwork

```yaml
# nginx-ingress-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/component: controller
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
      app.kubernetes.io/component: controller
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ingress-nginx
        app.kubernetes.io/component: controller
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      nodeSelector:
        node-role.kubernetes.io/worker: ""
        ingress-nginx: "true"
      tolerations:
      - effect: NoSchedule
        operator: Exists
      containers:
      - name: controller
        image: harbor.corp.internal/k8s/ingress-nginx/controller:v1.9.4
        ports:
        - name: http
          containerPort: 80
          hostPort: 80
          protocol: TCP
        - name: https
          containerPort: 443
          hostPort: 443
          protocol: TCP
        args:
        - /nginx-ingress-controller
        - --election-id=ingress-nginx-leader
        - --controller-class=k8s.io/ingress-nginx
        - --ingress-class=nginx
        - --configmap=$(POD_NAMESPACE)/ingress-nginx-controller
        - --validating-webhook=:8443
        - --validating-webhook-certificate=/usr/local/certificates/cert
        - --validating-webhook-key=/usr/local/certificates/key
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2000m"
            memory: "1Gi"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 10254
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /healthz
            port: 10254
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 10
```

### Node Labeling

```bash
# Label worker nodes for NGINX Ingress placement
kubectl label nodes app-w1 app-w2 app-w3 app-w4 app-w5 ingress-nginx=true
```

---

## Helm Chart Configuration

### Helm Values (Production)

```yaml
# values-nginx-ingress.yaml
controller:
  replicaCount: 5                    # Match worker node count for DaemonSet-like behavior
  
  # Use DaemonSet instead of Deployment
  kind: DaemonSet
  
  # Host network for direct port binding
  hostNetwork: true
  dnsPolicy: ClusterFirstWithHostNet
  
  # Image (air-gap)
  image:
    registry: harbor.corp.internal
    image: k8s/ingress-nginx/controller
    tag: v1.9.4
    digest: ""
    pullPolicy: IfNotPresent
  
  # Node selector
  nodeSelector:
    ingress-nginx: "true"
  
  # Tolerations
  tolerations:
  - effect: NoSchedule
    operator: Exists
  
  # Resources
  resources:
    requests:
      cpu: "500m"
      memory: "512Mi"
    limits:
      cpu: "2000m"
      memory: "1Gi"
  
  # Metrics for Prometheus
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      namespace: monitoring
      additionalLabels:
        release: prometheus
  
  # Config (passed to ConfigMap)
  config:
    use-proxy-protocol: "true"
    use-forwarded-headers: "true"
    compute-full-forwarded-for: "true"
    proxy-body-size: "100m"
    proxy-connect-timeout: "10"
    proxy-read-timeout: "120"
    proxy-send-timeout: "120"
    proxy-buffers: "16 64k"
    proxy-buffer-size: "32k"
    enable-underscores-in-headers: "true"
    log-format-upstream: '$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_length $request_time [$proxy_upstream_name] [$proxy_alternative_upstream_name] $upstream_addr $upstream_response_length $upstream_response_time $upstream_status $req_id'
  
  # Service (disabled for hostNetwork DaemonSet)
  service:
    enabled: false
  
  # IngressClass
  ingressClassResource:
    name: nginx
    enabled: true
    default: true
    controllerValue: "k8s.io/ingress-nginx"
  
  # Topology spread
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: ingress-nginx

# Default backend
defaultBackend:
  enabled: true
  image:
    registry: harbor.corp.internal
    image: k8s/defaultbackend-amd64
    tag: 1.5

# TCP/UDP services (see nginx-tcp.md)
tcp: {}
udp: {}
```

### Helm Installation

```bash
# Add repo (from Nexus in air-gap)
helm repo add ingress-nginx https://nexus.corp.internal/repository/helm-proxy/ingress-nginx
helm repo update

# Install
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --create-namespace \
  -f values-nginx-ingress.yaml

# Or from local chart
helm install ingress-nginx ./charts/ingress-nginx \
  -n ingress-nginx \
  --create-namespace \
  -f values-nginx-ingress.yaml
```

---

## IngressClass Configuration

### Define IngressClass

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: k8s.io/ingress-nginx
```

### Using IngressClass in Ingress Resources

```yaml
# Explicit IngressClass reference
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: production
spec:
  ingressClassName: nginx
  rules:
  - host: app.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app-service
            port:
              number: 80
```

---

## TLS Termination

### cert-manager Integration

```yaml
# ClusterIssuer for internal CA
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ca-issuer
spec:
  ca:
    secretName: internal-ca-key-pair
---
# Certificate for Ingress
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-tls
  namespace: production
spec:
  secretName: app-tls-secret
  issuerRef:
    name: internal-ca-issuer
    kind: ClusterIssuer
  dnsNames:
  - app.corp.internal
  - www.corp.internal
  duration: 2160h          # 90 days
  renewBefore: 360h        # 15 days before expiry
```

### Ingress with TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-https
  namespace: production
  annotations:
    cert-manager.io/cluster-issuer: internal-ca-issuer
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app.corp.internal
    secretName: app-tls-secret
  rules:
  - host: app.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-frontend
            port:
              number: 80
```

### TLS Configuration in ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  # TLS protocols and ciphers
  ssl-protocols: "TLSv1.2 TLSv1.3"
  ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384"
  ssl-early-data: "false"
  # HSTS
  hsts: "true"
  hsts-max-age: "31536000"
  hsts-include-subdomains: "true"
  # OCSP stapling
  enable-ocsp: "true"
```

---

## HTTP Routing Examples

### Basic HTTP Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: basic-http
  namespace: production
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-frontend
            port:
              number: 80
```

### Multiple Hosts

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-host
  namespace: production
spec:
  ingressClassName: nginx
  rules:
  - host: app.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-frontend
            port:
              number: 80
  - host: api.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-server
            port:
              number: 8080
```

### Default Backend (Catch-All 404)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: catch-all
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/default-backend: custom-error-page
spec:
  ingressClassName: nginx
  defaultBackend:
    service:
      name: custom-error-page
      port:
        number: 80
```

---

## Path-Based Routing

### Single Host, Multiple Paths

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-routing
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
  - host: app.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
      - path: /api(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: api-backend
            port:
              number: 8080
      - path: /admin(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: admin-panel
            port:
              number: 9090
```

### Path Types

| PathType | Behavior | Example |
|----------|----------|---------|
| `Exact` | Exact match only | `/foo` matches `/foo` only |
| `Prefix` | Prefix match | `/foo` matches `/foo`, `/foo/`, `/foo/bar` |
| `ImplementationSpecific` | Regex (NGINX) | `/api(/|$)(.*)` uses regex capture |

### Rewrite Target

```yaml
# Strip /api prefix before forwarding to backend
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rewrite-example
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/use-regex: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: app.corp.internal
    http:
      paths:
      - path: /api/v1(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: api-v1
            port:
              number: 8080
      - path: /api/v2(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: api-v2
            port:
              number: 8080
```

---

## Name-Based Virtual Hosting

### Wildcard Host

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wildcard-ingress
  namespace: production
spec:
  ingressClassName: nginx
  rules:
  - host: "*.apps.corp.internal"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: default-app
            port:
              number: 80
```

### Multiple Applications

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-frontend
  namespace: production
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - frontend.apps.corp.internal
    secretName: frontend-tls
  rules:
  - host: frontend.apps.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-svc
            port:
              number: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-backend
  namespace: production
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - backend.apps.corp.internal
    secretName: backend-tls
  rules:
  - host: backend.apps.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: backend-svc
            port:
              number: 8080
```

---

## Rate Limiting

### Global Rate Limiting

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rate-limited
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "10"
    nginx.ingress.kubernetes.io/limit-connections: "5"
    nginx.ingress.kubernetes.io/limit-rpm: "100"
    nginx.ingress.kubernetes.io/limit-burst-multiplier: "3"
spec:
  ingressClassName: nginx
  rules:
  - host: api.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-server
            port:
              number: 8080
```

### Per-IP Rate Limiting

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: per-ip-limit
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "5"
    nginx.ingress.kubernetes.io/limit-whitelist: "10.0.0.0/8,172.16.0.0/12"
spec:
  ingressClassName: nginx
  rules:
  - host: api.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-server
            port:
              number: 8080
```

### Rate Limit Configuration in ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  # Rate limiting
  limit-req-status-code: "429"
  # Global rate limit zone
  http-snippet: |
    limit_req_zone $binary_remote_addr zone=global:10m rate=100r/s;
    limit_conn_zone $binary_remote_addr zone=conn_per_ip:10m;
```

---

## IP Whitelisting

### Allow Specific CIDRs

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ip-whitelist
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
spec:
  ingressClassName: nginx
  rules:
  - host: admin.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: admin-panel
            port:
              number: 9090
```

### Block Specific IPs

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ip-blocklist
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/server-snippet: |
      deny 203.0.113.50;
      deny 198.51.100.0/24;
      allow all;
spec:
  ingressClassName: nginx
  rules:
  - host: app.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-frontend
            port:
              number: 80
```

### Internal-Only Services

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: internal-only
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8"
    nginx.ingress.kubernetes.io/server-snippet: |
      if ($remote_addr !~ "^10\\.") {
        return 403;
      }
spec:
  ingressClassName: nginx
  rules:
  - host: internal.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: internal-app
            port:
              number: 80
```

---

## Custom NGINX Snippets

### ConfigMap for Global Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  # Custom log format
  log-format-upstream: '$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_length $request_time [$proxy_upstream_name] $upstream_addr $upstream_response_length $upstream_response_time $upstream_status'
  
  # Proxy headers
  proxy-set-headers: "ingress-nginx/custom-headers"
  
  # Custom error pages
  custom-http-errors: "502,503,504"
  default-backend: "ingress-nginx/custom-error-page"
  
  # Enable CORS globally
  enable-cors: "true"
  cors-allow-headers: "DNT,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization"
  cors-allow-methods: "GET,PUT,POST,DELETE,PATCH,OPTIONS"
  cors-allow-origin: "https://app.corp.internal"
  cors-max-age: "86400"
```

### Custom Headers ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-headers
  namespace: ingress-nginx
data:
  X-Frame-Options: "DENY"
  X-Content-Type-Options: "nosniff"
  X-XSS-Protection: "1; mode=block"
  Strict-Transport-Security: "max-age=31536000; includeSubDomains"
  Content-Security-Policy: "default-src 'self'"
  X-Request-ID: "$req_id"
```

### Per-Ingress Snippets

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: custom-snippet
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Custom-Header: my-value";
      more_set_headers "X-Request-ID: $req_id";
      proxy_set_header X-Original-URI $request_uri;
spec:
  ingressClassName: nginx
  rules:
  - host: app.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-frontend
            port:
              number: 80
```

### Server Snippet (Advanced)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: server-snippet-example
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/server-snippet: |
      # Custom NGINX directives at server block level
      location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
      }
      
      # Block specific user agents
      if ($http_user_agent ~* (bot|crawler|spider)) {
        return 403;
      }
spec:
  ingressClassName: nginx
  rules:
  - host: app.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-frontend
            port:
              number: 80
```

---

## Proxy Buffer Tuning

### ConfigMap Settings

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  # Proxy buffer settings
  proxy-buffers: "16 64k"           # 16 buffers of 64KB each
  proxy-buffer-size: "32k"          # Buffer for response headers
  proxy-busy-buffers-size: "128k"   # Max size of busy buffers
  
  # Proxy timeouts
  proxy-connect-timeout: "10"       # Connection timeout to upstream
  proxy-read-timeout: "120"         # Read timeout from upstream
  proxy-send-timeout: "120"         # Send timeout to upstream
  
  # Proxy body
  proxy-body-size: "100m"           # Max request body size
  proxy-max-temp-file-size: "1024m" # Max temp file size
  
  # Keep-alive
  upstream-keepalive-connections: "256"
  upstream-keepalive-timeout: "120"
  upstream-keepalive-requests: "10000"
```

### Per-Ingress Buffer Tuning

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: large-upload
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "500m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-buffers: "32 128k"
    nginx.ingress.kubernetes.io/proxy-buffer-size: "64k"
spec:
  ingressClassName: nginx
  rules:
  - host: upload.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: file-upload-service
            port:
              number: 80
```

---

## WebSocket Support

### WebSocket Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: websocket-app
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-http-version: "1.1"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
spec:
  ingressClassName: nginx
  rules:
  - host: ws.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: websocket-service
            port:
              number: 8080
```

### WebSocket with Sticky Sessions

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: websocket-sticky
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "ws-route"
    nginx.ingress.kubernetes.io/session-cookie-expires: "86400"
    nginx.ingress.kubernetes.io/session-cookie-max-age: "86400"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  rules:
  - host: ws.corp.internal
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: websocket-service
            port:
              number: 8080
```

---

## HAProxy Configuration for NGINX Ingress

### HAProxy Frontend for HTTP/HTTPS

```haproxy
# /etc/haproxy/haproxy.cfg (Application Cluster LB nodes)

frontend app-http
    bind 10.0.1.20:80
    mode http
    option httplog
    
    # Redirect HTTP to HTTPS
    redirect scheme https code 301 if !{ ssl_fc }

frontend app-https
    bind 10.0.1.20:443
    mode tcp
    option tcplog
    
    # Use SNI for routing decisions
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    
    # Route to NGINX Ingress nodes
    default_backend nginx-ingress-https

backend nginx-ingress-https
    mode tcp
    balance roundrobin
    option tcp-check
    
    # Health check on port 443
    tcp-check connect port 443
    
    # All worker nodes running NGINX Ingress
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
```

### HAProxy with SSL Offloading

```haproxy
frontend app-https-offload
    bind 10.0.1.20:443 ssl crt /etc/haproxy/certs/ alpn h2,http/1.1
    mode http
    option httplog
    
    # Forward to NGINX on HTTP (SSL terminated at HAProxy)
    default_backend nginx-ingress-http

backend nginx-ingress-http
    mode http
    balance roundrobin
    option httpchk GET /healthz
    
    http-check expect status 200
    
    # Forward as HTTP (SSL already terminated)
    server app-w1 10.0.5.11:80 check inter 2s fall 3 rise 2
    server app-w2 10.0.5.12:80 check inter 2s fall 3 rise 2
    server app-w3 10.0.5.13:80 check inter 2s fall 3 rise 2
    server app-w4 10.0.5.14:80 check inter 2s fall 3 rise 2
    server app-w5 10.0.5.15:80 check inter 2s fall 3 rise 2
```

---

## Air-Gap: NGINX Ingress Images from Harbor

### Required Images

| Image | Purpose | Tag |
|-------|---------|-----|
| ingress-nginx/controller | Main controller | v1.9.4 |
| ingress-nginx/kube-webhook-certgen | Admission webhook | v20231011 |
| defaultbackend-amd64 | Default backend | 1.5 |

### Mirroring Script

```bash
#!/bin/bash
# mirror-nginx-ingress-images.sh

HARBOR="harbor.corp.internal"
PROJECT="k8s"

# Controller
docker pull registry.k8s.io/ingress-nginx/controller:v1.9.4
docker tag registry.k8s.io/ingress-nginx/controller:v1.9.4 \
  ${HARBOR}/${PROJECT}/ingress-nginx/controller:v1.9.4
docker push ${HARBOR}/${PROJECT}/ingress-nginx/controller:v1.9.4

# Webhook certgen
docker pull registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20231011-5b340885db
docker tag registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20231011-5b340885db \
  ${HARBOR}/${PROJECT}/ingress-nginx/kube-webhook-certgen:v20231011
docker push ${HARBOR}/${PROJECT}/ingress-nginx/kube-webhook-certgen:v20231011

# Default backend
docker pull registry.k8s.io/defaultbackend-amd64:1.5
docker tag registry.k8s.io/defaultbackend-amd64:1.5 \
  ${HARBOR}/${PROJECT}/defaultbackend-amd64:1.5
docker push ${HARBOR}/${PROJECT}/defaultbackend-amd64:1.5
```

### Helm Chart from Nexus

```bash
# Download chart from Nexus
curl -LO https://nexus.corp.internal/repository/helm-hosted/ingress-nginx-4.8.3.tgz

# Install from local chart
helm install ingress-nginx ./ingress-nginx-4.8.3.tgz \
  -n ingress-nginx \
  --create-namespace \
  -f values-nginx-ingress.yaml
```
