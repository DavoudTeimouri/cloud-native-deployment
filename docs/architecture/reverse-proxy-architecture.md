# Reverse Proxy & Transparent Registry Architecture

> Canonical URLs with zero client configuration — the reverse proxy handles everything

---

## 1. Core Principle

**Clients use the same URLs they would use on the internet.**

- `archive.ubuntu.com` — not `nexus.internal.lan/repository/ubuntu`
- `docker.io/library/nginx:1.25` — not `harbor.internal.lan/library/nginx:1.25`
- `registry.k8s.io` — not `nexus.internal.lan/k8s-gcr`
- `quay.io` — not `harbor.internal.lan/quay`

**No client-side configuration changes are needed.** The reverse proxy
intercepts these requests via DNS and serves them transparently.

```
Client wants: archive/ubuntu.com/ubuntu/dists/noble/...
       │
       │ DNS resolves archive.ubuntu.com → 10.0.0.10 (proxy IP)
       ▼
┌─────────────────────────────────────────┐
│ Reverse Proxy (10.0.0.10) │
│ │
│ Sees: archive.ubuntu.com │
│ → Checks cache │
│ → If cached: serve directly │
│ → If not: fetch from real archive.ubuntu.com │
│ (or from pre-staged Nexus data in air-gap) │
└─────────────────────────────────────────┘
```

---

## 2. How It Works

### 2.1 DNS Configuration

The DNS server (CoreDNS or BIND) resolves **public domain names** to the
reverse proxy IP:

```bash
# /etc/bind/zones/internal.lan.zone
; All public repository domains → reverse proxy
archive.ubuntu.com.    IN  A   10.0.0.10
security.ubuntu.com.  IN  A   10.0.0.10
download.docker.com.  IN  A   10.0.0.10
registry-1.docker.io. IN  A   10.0.0.10
quay.io.              IN  A   10.0.0.10
registry.k8s.io.     IN  A   10.0.0.10
ghcr.io.             IN  A   10.0.0.10
gcr.io.              IN  A   10.0.0.10
pkgs.k8s.io.         IN  A   10.0.0.10
download.ceph.com.   IN  A   10.0.0.10
github.com.          IN  A   10.0.0.10
pypi.org.            IN  A   10.0.0.10
npmjs.org.           IN  A   10.0.0.10
maven.org.           IN  A   10.0.0.10
```

### 2.2 Reverse Proxy Logic

```
Request: GET archive.ubuntu.com/ubuntu/dists/noble/Release
    │
    ▼
┌─────────────────────────────────────────┐
│ NGINX Reverse Proxy │
│ │
│ 1. Check local cache │
│ ├── Cache HIT → serve immediately │
│ └── Cache MISS → continue │
│ │
│ 2. Check Nexus (pre-staged data) │
│ ├── Nexus has it → serve + cache │
│ └── Nexus doesn't have it → continue │
│ │
│ 3. If internet available: │
│ └── Fetch from real archive.ubuntu.com │
│ │
│ 4. If air-gap (no internet): │
│ └── Return 404 (data must be pre-staged) │
└─────────────────────────────────────────┘
```

---

## 3. NGINX Configuration

### 3.1 Main Config

```nginx
# /etc/nginx/nginx.conf
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

    # Logging
    log_format main '$remote_addr [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_user_agent" '
                    'upstream=$upstream_addr';
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    # Proxy cache zones
    proxy_cache_path /var/cache/nginx/apt
                     levels=1:2
                     keys_zone=apt_cache:50m
                     max_size=50g
                     inactive=7d;
    proxy_cache_path /var/cache/nginx/docker
                     levels=1:2
                     keys_zone=docker_cache:100m
                     max_size=200g
                     inactive=30d;
    proxy_cache_path /var/cache/nginx/packages
                     levels=1:2
                     keys_zone=packages_cache:50m
                     max_size=50g
                     inactive=7d;

    # Upstreams (internal services)
    upstream nexus_backend {
        server 10.0.0.201:8081 max_fails=3 fail_timeout=30s;
    }
    upstream nexus_https {
        server 10.0.0.201:8443 max_fails=3 fail_timeout=30s;
    }
    upstream harbor_backend {
        server 10.0.0.200:443 max_fails=3 fail_timeout=30s;
    }
    upstream harbor_registry {
        server 10.0.0.200:5000 max_fails=3 fail_timeout=30s;
    }

    include /etc/nginx/conf.d/*.conf;
}
```

### 3.2 APT Repository Proxy (Transparent)

```nginx
# /etc/nginx/conf.d/apt-proxy.conf

# Redirect all apt requests to Nexus
server {
    listen 80;
    server_name archive.ubuntu.com security.ubuntu.com;

    location / {
        proxy_pass http://nexus_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;

        # Cache apt metadata aggressively
        proxy_cache apt_cache;
        proxy_cache_valid 200 7d;
        proxy_cache_valid 301 302 1d;
        proxy_cache_valid 404 1m;
        proxy_cache_use_stale error timeout updating;
        add_header X-Cache-Status $upstream_cache_status;

        # Don't cache .deb files (they're large, cache by URL)
        location ~* \.deb$ {
            proxy_pass http://nexus_backend;
            proxy_cache apt_cache;
            proxy_cache_valid 200 30d;
        }
    }
}
```

### 3.3 Docker Registry Proxy (Transparent)

```nginx
# /etc/nginx/conf.d/docker-proxy.conf

# Docker Hub mirror
server {
    listen 443 ssl http2;
    server_name registry-1.docker.io;

    ssl_certificate /etc/nginx/ssl/docker.io.crt;
    ssl_certificate_key /etc/nginx/ssl/docker.io.key;

    location /v2/ {
        # First try Harbor proxy cache
        proxy_pass https://harbor_backend/v2/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_ssl_verify off;

        # Cache Docker layers
        proxy_cache docker_cache;
        proxy_cache_valid 200 30d;
        proxy_cache_valid 404 1m;
        proxy_cache_use_stale error timeout updating;
        add_header X-Cache-Status $upstream_cache_status;

        client_max_body_size 500M;
        proxy_request_buffering off;
    }
}

# Quay.io mirror
server {
    listen 443 ssl http2;
    server_name quay.io;

    ssl_certificate /etc/nginx/ssl/quay.io.crt;
    ssl_certificate_key /etc/nginx/ssl/quay.io.key;

    location /v2/ {
        proxy_pass https://harbor_backend/v2/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_ssl_verify off;

        proxy_cache docker_cache;
        proxy_cache_valid 200 30d;
        client_max_body_size 500M;
        proxy_request_buffering off;
    }
}

# Kubernetes GCR mirror
server {
    listen 443 ssl http2;
    server_name registry.k8s.io gcr.io ghcr.io;

    ssl_certificate /etc/nginx/ssl/k8s-gcr.crt;
    ssl_certificate_key /etc/nginx/ssl/k8s-gcr.key;

    location /v2/ {
        proxy_pass http://nexus_backend/v2/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_cache docker_cache;
        proxy_cache_valid 200 30d;
        client_max_body_size 500M;
        proxy_request_buffering off;
    }
}
```

### 3.4 Package Repository Proxy (Transparent)

```nginx
# /etc/nginx/conf.d/packages-proxy.conf

# PyPI mirror
server {
    listen 80;
    server_name pypi.org files.pythonhosted.org;

    location / {
        proxy_pass http://nexus_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_cache packages_cache;
        proxy_cache_valid 200 7d;
    }
}

# npm mirror
server {
    listen 80;
    server_name npmjs.org registry.npmjs.org;

    location / {
        proxy_pass http://nexus_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_cache packages_cache;
        proxy_cache_valid 200 7d;
    }
}

# Maven Central mirror
server {
    listen 80;
    server_name maven.org repo1.maven.org;

    location / {
        proxy_pass http://nexus_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_cache packages_cache;
        proxy_cache_valid 200 7d;
    }
}

# HashiCorp mirror
server {
    listen 80;
    server_name apt.releases.hashicorp.com yum.releases.hashicorp.com;

    location / {
        proxy_pass http://nexus_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_cache packages_cache;
        proxy_cache_valid 200 7d;
    }
}

# Ceph packages mirror
server {
    listen 80;
    server_name download.ceph.com;

    location / {
        proxy_pass http://nexus_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_cache packages_cache;
        proxy_cache_valid 200 7d;
    }
}

# Docker CE packages mirror
server {
    listen 80;
    server_name download.docker.com;

    location / {
        proxy_pass http://nexus_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_cache packages_cache;
        proxy_cache_valid 200 7d;
    }
}

# Kubernetes packages mirror
server {
    listen 80;
    server_name pkgs.k8s.io;

    location / {
        proxy_pass http://nexus_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_cache packages_cache;
        proxy_cache_valid 200 7d;
    }
}
```

### 3.5 GitLab (Transparent — Custom Domain)

```nginx
# /etc/nginx/conf.d/gitlab.conf

server {
    listen 443 ssl http2;
    server_name gitlab.internal.lan;

    ssl_certificate /etc/nginx/ssl/gitlab.internal.lan.crt;
    ssl_certificate_key /etc/nginx/ssl/gitlab.internal.lan.key;

    location / {
        proxy_pass https://10.0.0.202:8443;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_ssl_verify off;
        client_max_body_size 500M;
    }
}
```

---

## 4. Client Configuration — ZERO CHANGES

### 4.1 APT Sources (Standard Ubuntu)

```bash
# /etc/apt/sources.list — SAME AS ONLINE
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://archive/ubuntu.com/ubuntu noble-security main restricted universe multiverse

# Docker
deb [arch=amd64] https://download.docker.com/linux/ubuntu noble stable

# Kubernetes
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core/stable/deb kubernetes-xenial main

# Ceph
deb [signed-by=/etc/apt/keyrings/ceph.gpg] https://download.ceph.com/debian-reef reef main
```

### 4.2 Containerd Configuration (Standard)

```toml
# /etc/containerd/config.toml — SAME AS ONLINE
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "registry.k8s.io/pause:3.9"

    [plugins."io.containerd.grpc.v1.cri".registry]
      # Standard docker.io config — no changes needed
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        endpoint = ["https://registry-1.docker.io"]
      [plugins."io.containerd.grpc.v1.cri".registry.configs."docker.io".tls]
        insecure_skip_verify_skip = false

      # Standard k8s.gcr.io config
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io"]
        endpoint = ["https://registry.k8s.io"]

    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true
```

### 4.3 Docker Configuration (Standard)

```json
// /etc/docker/daemon.json — SAME AS ONLINE
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "dns": ["10.0.0.2", "10.0.0.3"]
}
```

### 4.4 Pulling Images (Standard Commands)

```bash
# SAME AS ONLINE — no changes
docker pull nginx:1.25
docker pull redis:7.2
docker pull alpine:3.19
docker pull quay.io/calico/node:v3.27.0
docker pull registry.k8s.io/kube-apiserver:v1.29.0

# Kubernetes deployment — standard images
# image: nginx:1.25  (not harbor.internal/library/nginx:1.25)
```

---

## 5. Air-Gap: Pre-Staging Data

In an air-gap environment, the proxy can't fetch from the internet.
Data must be pre-staged into Nexus/Harbor before going air-gap.

### 5.1 Pre-Staging Script

```bash
#!/bin/bash
# pre-stage-data.sh — Run on internet-connected machine before air-gap

NEXUS_URL="http://10.0.0.201:8081"

# 1. Pull all required images locally
IMAGES=(
    "nginx:1.25"
    "redis:7.2"
    "alpine:3.19"
    "busybox:1.28"
    "quay.io/calico/node:v3.27.0"
    "registry.k8s.io/kube-apiserver:v1.29.0"
    "registry.k8s.io/kube-controller-manager:v1.29.0"
    "registry.k8s.io/kube-scheduler:v1.29.0"
    "registry.k8s.io/kube-proxy:v1.29.0"
    "registry.k8s.io/pause:3.9"
    "registry.k8s.io/etcd:3.5.10"
    "registry.k8s.io/coredns/coredns:v1.11.0"
)

for img in "${IMAGES[@]}"; do
    docker pull "$img"
    docker save "$img" -o "/tmp/images/$(echo $img | tr '/' '_' | tr ':' '_').tar"
done

# 2. Upload images to Nexus
for tar in /tmp/images/*.tar; do
    img=$(basename "$tar" | tr '_' '/' | rev | cut -d'_' -f2- | rev)
    docker load -i "$tar"
    docker tag "$img" "10.0.0.201:5000/$img"
    docker push "10.0.0.201:5000/$img"
done

# 3. Sync apt packages to Nexus
# (Use Nexus apt proxy — it caches automatically on first request)

# 4. Sync containerd pause image
docker tag registry.k8s.io/pause:3.9 10.0.0.201:5000/google_containers/pause:3.9
docker push 10.0.0.201:5000/google_containers/pause:3.9

echo "Pre-staging complete. Disconnect from internet."
```

### 5.2 Air-Gap Proxy Behavior

```
Client: apt-get install nginx
    │
    ▼
Proxy: archive/ubuntu.com/ubuntu/noble/...
    │
    ├── Cache HIT → serve (from pre-staged data)
    │
    └── Cache MISS → Check Nexus
        ├── Nexus has it → serve + cache
        │
        └── Nexus doesn't have it → 404
            (must pre-stage this package first)
```

---

## 6. DNS Server Configuration

### 6.1 BIND Configuration

```bash
# /etc/bind/named.conf.local
zone "archive.ubuntu.com" {
    type master;
    file "/etc/bind/zones/forward-ubuntu.conf";
};

zone "registry-1.docker.io" {
    type master;
    file "/etc/bind/zones/forward-docker.conf";
};

zone "quay.io" {
    type master;
    file "/etc/bind/zones/forward-quay.conf";
};

zone "registry.k8s.io" {
    type master;
    file "/etc/bind/zones/forward-k8s.conf";
};

zone "download.docker.com" {
    type master;
    file "/etc/bind/zones/forward-docker-com.conf";
};

zone "pkgs.k8s.io" {
    type master;
    file "/etc/bind/zones/forward-k8s-pkgs.conf";
};

zone "download.ceph.com" {
    type master;
    file "/etc/bind/zones/forward-ceph.conf";
};

zone "github.com" {
    type master;
    file "/etc/bind/zones/forward-github.conf";
};

zone "pypi.org" {
    type master;
    file "/etc/bind/zones/forward-pypi.conf";
};

zone "npmjs.org" {
    type master;
    file "/etc/bind/zones/forward-npm.conf";
};
```

```bash
# /etc/bind/zones/forward-ubuntu.conf
$TTL 86400
@   IN  SOA ns1.internal.lan. admin.internal.lan. (
        2024010101 3600 900 604800 86400 )
    IN  NS  ns1.internal.lan.
*   IN  A   10.0.0.10
```

### 6.2 CoreDNS Configuration (If Using K8s DNS)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  server.conf: |
    archive.ubuntu.com:53 {
      forward . 10.0.0.10
    }
    registry-1.docker.io:53 {
      forward . 10.0.0.10
    }
    quay.io:53 {
      forward . 10.0.0.10
    }
    registry.k8s.io:53 {
      forward . 10.0.0.10
    }
    download.docker.com:53 {
      forward . 10.0.0.10
    }
    pkgs.k8s.io:53 {
      forward . 10.0.0.10
    }
    download.ceph.com:53 {
      forward . 10.0.0.10
    }
    github.com:53 {
      forward . 10.0.0.10
    }
    pypi.org:53 {
      forward . 10.0.0.10
    }
    npmjs.org:53 {
      forward . 10.0.0.10
    }
```

---

## 7. SSL Certificates for Public Domains

Since clients connect to public domain names, the proxy needs valid
SSL certificates for those domains.

### 7.1 Option A: Internal CA + Wildcard Cert

```bash
# Generate wildcard cert for your internal domains
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/proxy.key \
  -out /etc/nginx/ssl/proxy.crt \
  -subj "/CN=*.internal.lan" \
  -addext "subjectAltName=DNS:archive.ubuntu.com,DNS:registry-1.docker.io,DNS:quay.io,DNS:registry.k8s.io"

# Distribute CA cert to all clients
sudo cp /etc/nginx/ssl/ca.crt /usr/local/share/ca-certificates/internal-ca.crt
sudo update-ca-certificates
```

### 7.2 Option B: Let's Encrypt (If Internet Available)

```bash
# Get real certificates
certbot certonly --standalone \
  -d archive.ubuntu.com \
  -d registry-1.docker.io \
  -d quay.io \
  -d registry.k8s.io

# Auto-renew
certbot renew --dry-run
```

### 7.3 Option C: Per-Domain Certificates

```bash
# Generate self-signed cert for each domain
for domain in archive.ubuntu.com registry-1.docker.io quay.io registry.k8s.io; do
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/${domain}.key \
      -out /etc/nginx/ssl/${domain}.crt \
      -subj "/CN=${domain}"
done
```

---

## 8. Service Health (Reverse Proxy)

```bash
# Check NGINX
sudo systemctl status nginx
sudo nginx -t

# Test transparent proxy
curl -I http://archive/ubuntu.com/ubuntu/dists/noble/Release
curl -I https://registry-1.docker.io/v2/
curl -I https://quay.io/v2/
curl -I https://registry.k8s.io/v2/

# Check cache status
sudo ls -la /var/cache/nginx/apt/
sudo ls -la /var/cache/nginx/docker/
sudo ls -la /var/cache/nginx/packages/

# Check DNS resolution
dig archive.ubuntu.com
dig registry-1.docker.io
dig quay.io

# Check upstream health
curl -sf http://10.0.0.201:8081/service/rest/v1/status
curl -sfk https://10.0.0.200:8443/api/v2.0/health
```

---

## 9. Architecture Benefits

| Concern | Without Proxy | With Transparent Proxy |
|---------|--------------|----------------------|
| Client config | Custom mirror URLs | **Zero changes** |
| Backend IP change | Update all clients | **Update DNS only** |
| Image tags | `harbor.internal/library/nginx:1.25` | **`nginx:1.25`** |
| Apt sources | `nexus.internal.lan/repository/...` | **`archive.ubuntu.com`** |
| Containerd config | Custom mirror endpoints | **Standard docker.io** |
| DNS records | One per backend | **One per public domain** |
| SSL certs | Per-backend certs | **Single proxy cert** |
| Offline migration | Reconfigure everything | **Move proxy, update DNS** |

---

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| DNS resolves to real public IP | DNS not configured | Check CoreDNS/BIND zones |
| SSL certificate error | Client doesn't trust proxy CA | Install CA cert on client |
| 404 on package request | Not pre-staged | Run pre-staging script |
| Slow first request | Cache miss (fetching from internet or Nexus) | Normal — subsequent requests are fast |
| Docker pull fails | Registry not reachable | Check harbor-registry container |
| apt update fails | Nexus not responding | Check nexus container |
| Cache not working | Cache zone full or misconfigured | Check cache path, increase max_size |
