# Reverse Proxy & Unified Registry Architecture

> Single entry point for all internal services — abstract addresses from consumers

## Overview

All servers (management + K8s nodes) point to **one reverse proxy** that routes
to Nexus, Harbor, and package repositories. This eliminates:

- **Address changes** — servers never need reconfiguration when backend IPs change
- **Custom image tags** — pull canonical paths like `nexus.internal.lan:5000/nginx:1.25`
- **Special configs** — containerd/docker work identical to online environments
- **DNS complexity** — single or two records pointing to the proxy

```
                    ┌─────────────────────────────────────────┐
  Server ──────────►│         Reverse Proxy (NGINX)           │
  (static config)   │         10.0.0.10 (VIP)                 │
                    ├─────────────────────────────────────────┤
                    │ /nexus/*        ──► Nexus (10.0.0.201)   │
                    │ /harbor/*       ──► Harbor (10.0.0.200)  │
                    │ /repository/*   ──► Apt repos (Nexus)    │
                    │ /docker/*       ──► Harbor (docker.io)   │
                    │ /quay/*         ──► Harbor (quay.io)     │
                    └─────────────────────────────────────────┘

  DNS Server (CoreDNS/on-proxy):
    nexus.internal.lan  → 10.0.0.10
    harbor.internal.lan → 10.0.0.10
    registry.internal.lan → 10.0.0.10
```

---

## 1. Reverse Proxy Server (NGINX)

### 1.1 Install NGINX

```bash
# On the proxy server (or co-located with management server)
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

### 1.2 NGINX Configuration

```nginx
# /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
    multi_accept on;
}

http {
    # General
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;  # For large image layers
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;

    # Buffering for large layer uploads
    proxy_buffering on;
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" '
                    'upstream=$upstream_addr '
                    'upstream_status=$upstream_status '
                    'upstream_response_time=$upstream_response_time';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml;

    # Upstream definitions
    upstream nexus_backend {
        server 10.0.0.201:8081 max_fails=3 fail_timeout=30s;
        # Add more Nexus replicas for HA:
        # server 10.0.0.202:8081 max_fails=3 fail_timeout=30s;
    }

    upstream harbor_backend {
        server 10.0.0.200:443 max_fails=3 fail_timeout=30s;
        # Add more Harbor replicas for HA:
        # server 10.0.0.203:443 max_fails=3 fail_timeout=30s;
    }

    upstream harbor_80_backend {
        server 10.0.0.200:80 max_fails=3 fail_timeout=30s;
    }

    # Include server blocks
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
```

### 1.3 Nexus Reverse Proxy

```nginx
# /etc/nginx/sites-available/nexus.conf

# HTTP → HTTPS redirect
server {
    listen 80;
    server_name nexus.internal.lan;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name nexus.internal.lan;

    # SSL certificates (internal CA or Let's Encrypt)
    ssl_certificate /etc/nginx/ssl/nexus.internal.lan.crt;
    ssl_certificate_key /etc/nginx/ssl/nexus.internal.lan.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Client certificate authentication (optional)
    # ssl_client_certificate /etc/nginx/ssl/ca.crt;
    # ssl_verify_client on;

    # Nexus Web UI
    location /nexus/ {
        proxy_pass http://nexus_backend/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        # WebSocket support (Nexus uses WebSockets)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Nexus raw repositories (for direct file downloads)
    location /repository/raw/ {
        proxy_pass http://nexus_backend/repository/raw/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Nexus repositories (apt, yum, docker, etc.)
    location /repository/ {
        proxy_pass http://nexus_backend/repository/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Cache package metadata
        location ~* \.(deb|rpm|xml|gz)$ {
            proxy_pass http://nexus_backend/repository/;
            proxy_set_header Host $host;
            proxy_cache_valid 200 1h;
            add_header X-Cache-Status $upstream_cache_status;
        }
    }

    # Nexus Docker registry (v2)
    location /v2/ {
        proxy_pass http://nexus_backend/v2/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Docker registry requires these
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        # Large layer uploads
        client_max_body_size 500M;
        proxy_request_buffering off;
    }

    # Nexus REST API
    location /service/ {
        proxy_pass http://nexus_backend/service/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Health check
    location /health {
        proxy_pass http://nexus_backend/service/rest/v1/status;
        access_log off;
    }
}
```

### 1.4 Harbor Reverse Proxy

```nginx
# /etc/nginx/sites-available/harbor.conf

# HTTP → HTTPS redirect
server {
    listen 80;
    server_name harbor.internal.lan;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name harbor.internal.lan;

    ssl_certificate /etc/nginx/ssl/harbor.internal.lan.crt;
    ssl_certificate_key /etc/nginx/ssl/harbor.internal.lan.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Harbor Web UI
    location /harbor/ {
        proxy_pass https://harbor_backend/harbor/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Don't verify Harbor's self-signed cert
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
    }

    # Harbor API
    location /api/ {
        proxy_pass https://harbor_backend/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
    }

    # Harbor Docker registry v2 (core for image pulls)
    location /v2/ {
        proxy_pass https://harbor_backend/v2/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Docker registry requirements
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_ssl_verify off;
        proxy_ssl_server_name on;

        # Large layers
        client_max_body_size 500M;
        proxy_request_buffering off;

        # Authenticate against Harbor
        # Basic auth or token-based
        proxy_set_header Authorization $http_authorization;
    }

    # Harbor service endpoints
    location /service/ {
        proxy_pass https://harbor_backend/service/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
    }

    # Harbor health
    location /health {
        proxy_pass https://harbor_backend/api/v2.0/health;
        proxy_ssl_verify off;
        access_log off;
    }
}
```

### 1.5 Unified Registry Proxy (Docker Hub Mirror)

This allows pulling `docker.io/library/nginx:1.25` directly through the proxy:

```nginx
# /etc/nginx/sites-available/registry-mirror.conf

server {
    listen 443 ssl http2;
    server_name registry.internal.lan;

    ssl_certificate /etc/nginx/ssl/registry.internal.lan.crt;
    ssl_certificate_key /etc/nginx/ssl/registry.internal.lan.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    # Docker Hub mirror through Harbor
    location /v2/ {
        # Harbor acts as a proxy cache for Docker Hub
        proxy_pass https://harbor_backend/v2/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_ssl_verify off;

        client_max_body_size 500M;
        proxy_request_buffering off;

        # Cache pulled images
        proxy_cache_path /var/cache/nginx/registry levels=1:2
                         keys_zone=registry_cache:10m max_size=10g
                         inactive=7d use_temp_path=off;

        proxy_cache registry_cache;
        proxy_cache_valid 200 7d;
        proxy_cache_valid 404 1m;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503;
        add_header X-Cache-Status $upstream_cache_status;
    }
}
```

### 1.6 Enable Sites and Test

```bash
# Enable sites
sudo ln -s /etc/nginx/sites-available/nexus.conf /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/harbor.conf /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/registry-mirror.conf /etc/nginx/sites-enabled/

# Remove default
sudo rm /etc/nginx/sites-enabled/default

# Test config
sudo nginx -t

# Reload
sudo systemctl restart nginx

# Test
curl -k https://nexus.internal.lan/nexus/
curl -k https://harbor.internal.lan/v2/
curl -k https://harbor.internal.lan/harbor/
```

---

## 2. DNS Configuration

### 2.1 CoreDNS / BIND Configuration

All internal DNS records point to the **proxy IP only**:

```bash
# /etc/bind/zones/internal.lan.zone
$TTL 86400
@   IN  SOA ns1.internal.lan. admin.internal.lan. (
        2024010101  ; Serial
        3600        ; Refresh
        900         ; Retry
        604800      ; Expire
        86400 )     ; Minimum TTL

; Nameserver
    IN  NS  ns1.internal.lan.

; Reverse Proxy (single entry point for all services)
proxy      IN  A   10.0.0.10

; All service names point to the proxy
nexus      IN  CNAME   proxy.internal.lan.
harbor     IN  CNAME   proxy.internal.lan.
registry   IN  CNAME   proxy.internal.lan.

; Kubernetes API
k8s-api    IN  A       10.0.0.100

; Other services (direct, not proxied)
mgmt       IN  A       10.0.0.10
```

### 2.2 Or via CoreDNS ConfigMap (if running on K8s)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  internal.lan.server: |
    internal.lan {
      forward . 10.0.0.2 10.0.0.3
    }
  proxy.server: |
    # Static entries pointing to proxy
    nexus.internal.lan {
      template {
        answer "{{ .Name }} 60 IN A 10.0.0.10"
      }
    }
    harbor.internal.lan {
      template {
        answer "{{ .Name }} 60 IN A 10.0.0.10"
      }
    }
    registry.internal.lan {
      template {
        answer "{{ .Name }} 60 IN A 10.0.0.10"
      }
    }
```

---

## 3. Containerd Configuration (No Custom Tags)

With the reverse proxy, containerd pulls canonical image paths — no `harbor.internal/library/` prefix needed:

```toml
# /etc/containerd/config.toml
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "registry.internal.lan/google_containers/pause:3.9"

    [plugins."io.containerd.grpc.v1.cri".registry]
      # Docker Hub mirror through proxy
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        endpoint = ["https://registry.internal.lan"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."docker.io".tls]
          insecure_skip_verify_skip = false

      # Nexus as docker registry
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."nexus.internal.lan"]
        endpoint = ["https://nexus.internal.lan:5000"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."nexus.internal.lan".tls]
          insecure_skip_verify = false

      # Harbor as docker registry
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.internal.lan"]
        endpoint = ["https://harbor.internal.lan"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."harbor.internal.lan".tls]
          insecure_skip_verify = false

      # Default docker.io config (falls through to proxy)
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry-1.docker.io"]
        endpoint = ["https://registry.internal.lan"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."registry-1.docker.io".tls]
          insecure_skip_verify_skip = false

    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true

[plugins."io.containerd.grpc.v1.cri".cni]
  bin_dir = "/opt/cni/bin"
  conf_dir = "/etc/cni/net.d"
```

### Usage Examples (Same as Online)

```bash
# Pull from Docker Hub (through proxy cache)
crictl pull nginx:1.25
crictl pull redis:7.2
crictl pull alpine:3.19

# Pull from Nexus (internal images)
crictl pull nexus.internal.lan:5000/my-app:v1.0

# Pull from Harbor (internal images)
crictl pull harbor.internal.lan/library/nginx:1.25

# Kubernetes deployment (standard images, no custom tags)
# image: nginx:1.25  (not harbor.internal.lan/library/nginx:1.25)
```

---

## 4. Package Repository Configuration (Apt)

### 4.1 Nexus Repository Setup

Configure Nexus to proxy these repositories:
- `noble` → `http://archive.ubuntu.com/ubuntu` (cached)
- `noble-updates` → `http://archive.ubuntu.com/ubuntu` (cached)
- `noble-security` → `http://security.ubuntu.com/ubuntu` (cached)
- `docker` → `https://download.docker.com/linux/ubuntu` (cached)
- `kubernetes` → `https://apt.kubernetes.io` (cached)
- `ceph` → `https://download.ceph.com/debian-reef` (cached)

### 4.2 Client Configuration

```bash
# /etc/apt/sources.list — all point to the proxy
deb https://nexus.internal.lan/repository/ubuntu-noble noble main restricted universe multiverse
deb https://nexus.internal.lan/repository/ubuntu-noble-updates noble-updates main restricted universe multiverse
deb https://nexus.internal.lan/repository/ubuntu-noble-security noble-security main restricted universe multiverse

# Docker
deb [arch=amd64] https://nexus.internal.lan/repository/docker-noble noble stable

# Kubernetes
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://nexus.internal.lan/repository/kubernetes-noble kubernetes-xenial main

# Ceph
deb [signed-by=/etc/apt/keyrings/ceph.gpg] https://nexus.internal.lan/repository/ceph-reef reef main
```

### 4.3 Install GPG Keys

```bash
# Docker
curl -fsSL https://nexus.internal.lan/repository/keys/docker.gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Kubernetes
curl -fsSL https://nexus.internal.lan/repository/keys/kubernetes.gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Ceph
curl -fsSL https://nexus.internal.lan/repository/keys/ceph.gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/ceph.gpg

# Update
sudo apt-get update

# Install (same as online)
sudo apt-get install -y containerd.io kubelet kubeadm kubectl ceph-common
```

---

## 5. Docker Configuration

```json
// /etc/docker/daemon.json
{
  "registry-mirrors": ["https://registry.internal.lan"],
  "insecure-registries": [],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-address-pools": [
    {"base": "172.17.0.0/16", "size": 24}
  ],
  "dns": ["10.0.0.2", "10.0.0.3"],
  "metrics-addr": "0.0.0.0":9323",
  "experimental": true
}
```

### Docker Pull Examples

```bash
# Through proxy cache (same as online)
docker pull nginx:1.25
docker pull redis:7.2
docker pull alpine:3.19

# Internal images from Nexus
docker pull nexus.internal.lan:5000/my-app:v1.0

# Internal images from Harbor
docker pull harbor.internal.lan/my-project/my-app:v2.0
```

---

## 6. SSL Certificates

### 6.1 Internal CA Setup

```bash
# Create internal CA
openssl genrsa -out /etc/nginx/ssl/ca.key 4096
openssl req -new -x509 -days 3650 -key /etc/nginx/ssl/ca.key \
  -out /etc/nginx/ssl/ca.crt \
  -subj "/C=US/ST=State/L=City/O=Internal/CN=Internal CA"

# Create certificate for proxy
openssl genrsa -out /etc/nginx/ssl/proxy.key 2048
openssl req -new -key /etc/nginx/ssl/proxy.key \
  -out /etc/nginx/ssl/proxy.csr \
  -subj "/C=US/ST=State/L=City/O=Internal/CN=proxy.internal.lan"

# Create extensions file for SAN
cat > /etc/nginx/ssl/proxy.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = nexus.internal.lan
DNS.2 = harbor.internal.lan
DNS.3 = registry.internal.lan
DNS.4 = proxy.internal.lan
IP.1 = 10.0.0.10
EOF

# Sign certificate
openssl x509 -req -in /etc/nginx/ssl/proxy.csr \
  -CA /etc/nginx/ssl/ca.crt -CAkey /etc/nginx/ssl/ca.key \
  -CAcreateserial -out /etc/nginx/ssl/proxy.crt \
  -days 825 -sha256 -extfile /etc/nginx/ssl/proxy.ext

# Combine for NGINX
cat /etc/nginx/ssl/proxy.crt /etc/nginx/ssl/ca.crt > /etc/nginx/ssl/proxy.fullchain.crt
```

### 6.2 Distribute CA Certificate

```bash
# On all servers, install the CA certificate
sudo cp ca.crt /usr/local/share/ca-certificates/internal-ca.crt
sudo update-ca-certificates

# For containerd (if not using system trust)
sudo mkdir -p /etc/container.d/certs.d/nexus.internal.lan:5000
sudo cp ca.crt /etc/container.d/certs.d/nexus.internal.lan:5000/ca.crt

# For Docker
sudo mkdir -p /etc/docker/certs.d/registry.internal.lan
sudo cp ca.crt /etc/docker/certs.d/registry.internal.lan/ca.crt
```

---

## 7. Ansible Playbook for Proxy Server

```yaml
---
# ansible/playbooks/proxy-server-prep.yml
- name: Reverse Proxy Server Preparation
  hosts: proxy_server
  become: true
  gather_facts: true
  vars:
    proxy_ip: "10.0.0.10"
    nexus_ip: "10.0.0.201"
    harbor_ip: "10.0.0.200"
    domain: "internal.lan"
    nexus_port: 8081
    harbor_port: 443

  tasks:
    - name: Install NGINX and dependencies
      ansible.builtin.apt:
        name:
          - nginx
          - openssl
          - python3-certbot-nginx
        state: present

    - name: Create SSL directory
      ansible.builtin.file:
        path: /etc/nginx/ssl
        state: directory
        mode: '0700'

    - name: Generate internal CA key
      ansible.builtin.command:
        cmd: openssl genrsa -out /etc/nginx/ssl/ca.key 4096
        creates: /etc/nginx/ssl/ca.key

    - name: Generate internal CA certificate
      ansible.builtin.command:
        cmd: >
          openssl req -new -x509 -days 3650
          -key /etc/nginx/ssl/ca.key
          -out /etc/nginx/ssl/ca.crt
          -subj "/C=US/ST=State/L=City/O=Internal/CN=Internal CA"
        creates: /etc/nginx/ssl/ca.crt

    - name: Generate proxy certificate key
      ansible.builtin.command:
        cmd: openssl genrsa -out /etc/nginx/ssl/proxy.key 2048
        creates: /etc/nginx/ssl/proxy.key

    - name: Generate proxy CSR
      ansible.builtin.command:
        cmd: >
          openssl req -new
          -key /etc/nginx/ssl/proxy.key
          -out /etc/nginx/ssl/proxy.csr
          -subj "/C=US/ST=State/L=City/O=Internal/CN=proxy.{{ domain }}"
        creates: /etc/nginx/ssl/proxy.csr

    - name: Create certificate extensions
      ansible.builtin.copy:
        dest: /etc/nginx/ssl/proxy.ext
        content: |
          authorityKeyIdentifier=keyid,issuer
          basicConstraints=CA:FALSE
          keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
          subjectAltName = @alt_names

          [alt_names]
          DNS.1 = nexus.{{ domain }}
          DNS.2 = harbor.{{ domain }}
          DNS.3 = registry.{{ domain }}
          DNS.4 = proxy.{{ domain }}
          IP.1 = {{ proxy_ip }}
        mode: '0644'

    - name: Sign proxy certificate
      ansible.builtin.command:
        cmd: >
          openssl x509 -req
          -in /etc/nginx/ssl/proxy.csr
          -CA /etc/nginx/ssl/ca.crt
          -CAkey /etc/nginx/ssl/ca.key
          -CAcreateserial
          -out /etc/nginx/ssl/proxy.crt
          -days 825 -sha256
          -extfile /etc/nginx/ssl/proxy.ext
        creates: /etc/nginx/ssl/proxy.crt

    - name: Create full chain certificate
      ansible.builtin.assemble:
        src: /etc/nginx/ssl
        dest: /etc/nginx/ssl/proxy.fullchain.crt
        regexp: '(proxy.crt|ca.crt)'
        mode: '0644'

    - name: Deploy NGINX main config
      ansible.builtin.copy:
        dest: /etc/nginx/nginx.conf
        content: |
          user www-data;
          worker_processes auto;
          pid /run/nginx.pid;

          events {
              worker_connections 4096;
              multi_accept on;
          }

          http {
              sendfile on;
              tcp_nopush on;
              tcp_nodelay on;
              keepalive_timeout 65;
              client_max_body_size 500M;
              proxy_read_timeout 300;
              proxy_connect_timeout 60;
              proxy_send_timeout 300;

              log_format main '$remote_addr [$time_local] "$request" '
                              '$status $body_bytes_sent "$http_user_agent" '
                              'upstream=$upstream_addr';
              access_log /var/log/nginx/access.log main;
              error_log /var/log/nginx/error.log warn;

              gzip on;
              gzip_vary on;
              gzip_proxied any;
              gzip_comp_level 6;

              upstream nexus_backend {
                  server {{ nexus_ip }}:{{ nexus_port }} max_fails=3 fail_timeout=30s;
              }

              upstream harbor_backend {
                  server {{ harbor_ip }}:{{ harbor_port }} max_fails=3 fail_timeout=30s;
              }

              include /etc/nginx/conf.d/*.conf;
              include /etc/nginx/sites-enabled/*;
          }
        mode: '0644'
      notify: Reload NGINX

    - name: Deploy Nexus site config
      ansible.builtin.copy:
        dest: /etc/nginx/sites-available/nexus.conf
        content: |
          server {
              listen 80;
              server_name nexus.{{ domain }};
              return 301 https://$host$request_uri;
          }

          server {
              listen 443 ssl http2;
              server_name nexus.{{ domain }};

              ssl_certificate /etc/nginx/ssl/proxy.fullchain.crt;
              ssl_certificate_key /etc/nginx/ssl/proxy.key;
              ssl_protocols TLSv1.2 TLSv1.3;

              location / {
                  proxy_pass http://nexus_backend;
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_http_version 1.1;
                  proxy_set_header Upgrade $http_upgrade;
                  proxy_set_header Connection "upgrade";
              }

              location /v2/ {
                  proxy_pass http://nexus_backend/v2/;
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_http_version 1.1;
                  proxy_set_header Connection "";
                  client_max_body_size 500M;
                  proxy_request_buffering off;
              }
          }
        mode: '0644'
      notify: Reload NGINX

    - name: Deploy Harbor site config
      ansible.builtin.copy:
        dest: /etc/nginx/sites-available/harbor.conf
        content: |
          server {
              listen 80;
              server_name harbor.{{ domain }};
              return 301 https://$host$request_uri;
          }

          server {
              listen 443 ssl http2;
              server_name harbor.{{ domain }};

              ssl_certificate /etc/nginx/ssl/proxy.fullchain.crt;
              ssl_certificate_key /etc/nginx/ssl/proxy.key;
              ssl_protocols TLSv1.2 TLSv1.3;

              location / {
                  proxy_pass https://harbor_backend;
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_ssl_verify off;
                  proxy_http_version 1.1;
                  proxy_set_header Upgrade $http_upgrade;
                  proxy_set_header Connection "upgrade";
              }

              location /v2/ {
                  proxy_pass https://harbor_backend/v2/;
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_ssl_verify off;
                  proxy_http_version 1.1;
                  proxy_set_header Connection "";
                  client_max_body_size 500M;
                  proxy_request_buffering off;
              }
          }
        mode: '0644'
      notify: Reload NGINX

    - name: Enable sites
      ansible.builtin.file:
        src: "/etc/nginx/sites-available/{{ item }}.conf"
        dest: "/etc/nginx/sites-enabled/{{ item }}.conf"
        state: link
      loop:
        - nexus
        - harbor
      notify: Reload NGINX

    - name: Remove default site
      ansible.builtin.file:
        path: /etc/nginx/sites-enabled/default
        state: absent
      notify: Reload NGINX

    - name: Create cache directory
      ansible.builtin.file:
        path: /var/cache/nginx/registry
        state: directory
        owner: www-data
        mode: '0755'

    - name: Test NGINX config
      ansible.builtin.command: nginx -t
      changed_when: false

    - name: Enable and start NGINX
      ansible.builtin.systemd:
        name: nginx
        state: started
        enabled: true

  handlers:
    - name: Reload NGINX
      ansible.builtin.systemd:
        name: nginx
        state: reloaded
```

---

## 8. Client Configuration Playbook

This playbook configures all servers (management + K8s nodes) to use the proxy:

```yaml
---
# ansible/playbooks/client-proxy-config.yml
- name: Configure Clients to Use Reverse Proxy
  hosts: all
  become: true
  gather_facts: true
  vars:
    proxy_ip: "10.0.0.10"
    proxy_domain: "internal.lan"
    nexus_domain: "nexus.internal.lan"
    harbor_domain: "harbor.internal.lan"
    registry_domain: "registry.internal.lan"
    dns_servers:
      - 10.0.0.2
      - 10.0.0.3

  tasks:
    # === DNS ===
    - name: Configure DNS to use internal servers
      ansible.builtin.copy:
        dest: /etc/resolv.conf
        content: |
          {% for dns in dns_servers %}
          nameserver {{ dns }}
          {% endfor %}
          search {{ proxy_domain }} cluster.local
          options timeout:2 attempts:3
        mode: '0644'

    # === CA Certificate ===
    - name: Install internal CA certificate
      ansible.builtin.copy:
        src: files/internal-ca.crt
        dest: /usr/local/share/ca-certificates/internal-ca.crt
        mode: '0644'
      notify: Update CA certificates

    # === Apt Sources ===
    - name: Remove default apt sources
      ansible.builtin.file:
        path: /etc/apt/sources.list
        state: absent

    - name: Configure Nexus apt proxy
      ansible.builtin.copy:
        dest: /etc/apt/sources.list
        content: |
          # Ubuntu base
          deb https://{{ nexus_domain }}/repository/ubuntu-noble noble main restricted universe multiverse
          deb https://{{ nexus_domain }}/repository/ubuntu-noble-updates noble-updates main restricted universe multiverse
          deb https://{{ nexus_domain }}/repository/ubuntu-noble-security noble-security main restricted universe multiverse

          # Docker
          deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://{{ nexus_domain }}/repository/docker-noble noble stable

          # Kubernetes
          deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://{{ nexus_domain }}/repository/kubernetes-noble kubernetes-xenial main

          # Ceph
          deb [signed-by=/etc/apt/keyrings/ceph.gpg] https://{{ nexus_domain }}/repository/ceph-reef reef main
        mode: '0644'

    - name: Install Docker GPG key
      ansible.builtin.shell: |
        curl -fsSL https://{{ nexus_domain }}/repository/keys/docker.gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      args:
        creates: /etc/apt/keyrings/docker.gpg

    - name: Install Kubernetes GPG key
      ansible.builtin.shell: |
        curl -fsSL https://{{ nexus_domain }}/repository/keys/kubernetes.gpg | \
        gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      args:
        creates: /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    - name: Install Ceph GPG key
      ansible.builtin.shell: |
        curl -fsSL https://{{ nexus_domain }}/repository/keys/ceph.gpg | \
        gpg --dearmor -o /etc/apt/keyrings/ceph.gpg
      args:
        creates: /etc/apt/keyrings/ceph.gpg

    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: yes
        cache_valid_time: 3600

    # === Containerd ===
    - name: Configure containerd registry mirrors
      ansible.builtin.copy:
        dest: /etc/containerd/config.toml
        content: |
          version = 2

          [plugins]
            [plugins."io.containerd.grpc.v1.cri"]
              sandbox_image = "{{ registry_domain }}/google_containers/pause:3.9"

              [plugins."io.containerd.grpc.v1.cri".registry]
                # Docker Hub mirror
                [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
                  endpoint = ["https://{{ registry_domain }}"]
                [plugins."io.containerd.grpc.v1.cri".registry.configs."docker.io".tls]
                  insecure_skip_verify_skip = false

                # Nexus registry
                [plugins."io.containerd.grpc.v1.cri".registry.mirrors."{{ nexus_domain }}"]
                  endpoint = ["https://{{ nexus_domain }}"]
                [plugins."io.containerd.grpc.v1.cri".registry.configs."{{ nexus_domain }}".tls]
                  insecure_skip_verify = false

                # Harbor registry
                [plugins."io.containerd.grpc.v1.cri".registry.mirrors."{{ harbor_domain }}"]
                  endpoint = ["https://{{ harbor_domain }}"]
                [plugins."io.containerd.grpc.v1.cri".registry.configs."{{ harbor_domain }}".tls]
                  insecure_skip_verify = false

                # Default fallback
                [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry-1.docker.io"]
                  endpoint = ["https://{{ registry_domain }}"]
                [plugins."io.containerd.grpc.v1.cri".registry.configs."registry-1.docker.io".tls]
                  insecure_skip_verify_skip = false

              [plugins."io.containerd.grpc.v1.cri".containerd]
                [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
                  runtime_type = "io.containerd.runc.v2"
                  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
                    SystemdCgroup = true

            [plugins."io.containerd.grpc.v1.cri".cni]
              bin_dir = "/opt/cni/bin"
              conf_dir = "/etc/cni/net.d"
        mode: '0644'
      notify: Restart containerd

    # === Docker (if used) ===
    - name: Configure Docker registry mirror
      ansible.builtin.copy:
        dest: /etc/docker/daemon.json
        content: |
          {
            "registry-mirrors": ["https://{{ registry_domain }}"],
            "log-driver": "json-file",
            "log-opts": {
              "max-size": "10m",
              "max-file": "3"
            },
            "storage-driver": "overlay2",
            "dns": ["{{ dns_servers[0] }}", "{{ dns_servers[1] }}"]
          }
        mode: '0644'
      notify: Restart docker

    # === Docker CA certs ===
    - name: Install Docker CA certificate
      ansible.builtin.file:
        path: /etc/docker/certs.d/{{ registry_domain }}
        state: directory
        mode: '0755'

    - name: Copy CA cert for Docker
      ansible.builtin.copy:
        src: files/internal-ca.crt
        dest: /etc/docker/certs.d/{{ registry_domain }}/ca.crt
        mode: '0644'

    # === Containerd CA certs ===
    - name: Install containerd CA certs
      ansible.builtin.file:
        path: /etc/containerd/certs.d
        state: directory
        mode: '0755'

    - name: Copy CA cert for containerd
      ansible.builtin.copy:
        src: files/internal-ca.crt
        dest: /etc/containerd/certs.d/ca.crt
        mode: '0644'

  handlers:
    - name: Update CA certificates
      ansible.builtin.command: update-ca-certificates

    - name: Restart containerd
      ansible.builtin.systemd:
        name: containerd
        state: restarted
        enabled: true

    - name: Restart docker
      ansible.builtin.systemd:
        name: docker
        state: restarted
        enabled: true
```

---

## 9. Verification

```bash
# From any client server:

# DNS resolution
nslookup nexus.internal.lan    # → 10.0.0.10
nslookup harbor.internal.lan   # → 10.0.0.10

# Nexus web UI
curl -k https://nexus.internal.lan/nexus/

# Harbor web UI
curl -k https://harbor.internal.lan/harbor/

# Docker pull (through proxy)
docker pull nginx:1.25
docker pull redis:7.2

# Crictl pull (through proxy)
crictl pull nginx:1.25

# Apt install (through proxy)
apt-get update
apt-get install -y containerd.io kubelet kubeadm kubectl

# Check image source (should show proxy)
docker images | grep nginx
```

---

## 10. Architecture Benefits Summary

| Concern | Without Proxy | With Proxy |
|---------|--------------|------------|
| Backend IP change | Update all servers | Update proxy only |
| Image tags | `harbor.internal/library/nginx:1.25` | `nginx:1.25` (through mirror) |
| Apt sources | `harbor.internal` or direct IPs | `nexus.internal.lan/repository/...` |
| Containerd config | Custom mirror endpoints | Standard docker.io mirror |
| DNS records | One per service | One (proxy) for all |
| SSL certs | Per-service certs | Single cert on proxy |
| Offline migration | Reconfigure everything | Move proxy, update DNS |
