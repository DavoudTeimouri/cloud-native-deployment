# Repository & Registry Manager Guide

> Nexus and Harbor deployment with custom ports, advanced path handling, and reverse proxy integration

---

## 1. Architecture Overview

```
                    ┌─────────────────────────────────────────┐
  Server ──────────►│         Reverse Proxy (NGINX)           │
  (static config)   │         10.0.0.10 (VIP)                 │
                    ├─────────────────────────────────────────┤
                    │ /nexus/*        ──► Nexus (10.0.0.201)   │
                    │ /harbor/*       ──► Harbor (10.0.0.200)  │
                    │ /repository/*   ──► Apt repos (Nexus)    │
                    │ /docker/*       ──► Harbor (docker.io)   │
                    └─────────────────────────────────────────┘

  DNS Server (CoreDNS/on-proxy):
    nexus.internal.lan  → 10.0.0.10
    harbor.internal.lan → 10.0.0.10
    registry.internal.lan → 10.0.0.10
```

This way:
- All servers use **one static proxy address** — never change.
- containerd/docker pull canonical paths (`nginx:1.25`, not `harbor.internal/library/nginx:1.25`).
- Packages install from `nexus.internal.lan/repository/...` (like online).
- DNS: `nexus/harbor/registry.internal.lan` → proxy IP.
- SSL: single SAN cert on the proxy covers all service names.

---

## 2. Nexus Repository Manager

### 2.1 Deployment Options

| Method | Port | Config Path | Best For |
|--------|------|-------------|----------|
| **Native (deb/rpm)** | 8081 | `/opt/nexus/etc/` | Single server, traditional ops |
| **Docker Container** | 9091 (custom) | `/nexus-data/etc/` | Quick setup, reproducible |
| **Kubernetes (Helm)** | 8081 | ConfigMap/Secret | Cloud-native, auto-scaling |

### 2.2 Custom Port Configuration

#### Native Installation

```bash
# Edit /opt/nexus/etc/nexus-default.properties
nexus.http.port=9091
nexus.https.port=9443
nexus.https.connector.host=0.0.0.0
nexus.https.connector.force-https=true
nexus.https.connector.redirect-https=true
nexus.https.connector.scheme=https
nexus.https.connector.proxy-name=nexus.internal.lan
nexus.https.connector.proxy-port=443
nexus.http.connector.host=0.0.0.0
nexus.http.connector.port=9091
nexus.http.connector.force-https=true
nexus.http.connector.redirect-https=true
nexus.http.connector.scheme=https
nexus.http.connector.proxy-name=nexus.internal.lan
nexus.http.connector.proxy-port=443
```

#### Docker Container

```bash
docker run -d \
  --name nexus \
  -p 9091:8081 \
  -p 9443:8443 \
  -p 5000:5000 \
  -p 5001:5001 \
  -p 5002:5002 \
  -v /opt/nexus/data:/nexus-data \
  --restart always \
  sonatype/nexus3:latest
```

#### Kubernetes (Helm)

```yaml
# values-nexus.yaml
service:
  type: ClusterIP
  port: 8081
  targetPort: 8081
  annotations: {}

ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "500m"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  hosts:
    - name: nexus.internal.lan
      path: /
      port: 8081
    - name: nexus.internal.lan
      path: /repository
      port: 8081
  tls:
    - secretName: nexus-tls
      hosts:
        - nexus.internal.lan

persistence:
  enabled: true
  storageClass: ceph-rbd
  accessMode: ReadWriteOnce
  size: 500Gi

nexus:
  properties:
    - name: NEXUS_HTTP_PORT
      value: "8081"
    - name: NEXUS_HTTPS_PORT
      value: "8443"
    - name: NEXUS_CONTEXT_PATH
      value: "/nexus"
    - name: NEXUS_SECURITY_INITIALSUPERUSERADMIN
      value: "true"
    - name: NEXUS_SECURITY_RANDOMPASSWORD
      value: "false"
    - name: NEXUS_DATASTORE_NEXUS_JDBCURL
      value: "jdbc:postgresql://postgres:5432/nexus"
    - name: NEXUS_DATASTORE_NEXUS_USERNAME
      value: "nexus"
    - name: NEXUS_DATASTORE_NEXUS_PASSWORD
      value: "nexus_password"
```

### 2.3 Advanced Path Handling

#### Custom Context Path

```bash
# Nexus can serve under /nexus or /repo or /
# Edit /opt/nexus/etc/nexus-default.properties
nexus.context-path=/nexus
```

#### Repository Path Structure

```
nexus.internal.lan/repository/
├── ubuntu-noble/          → apt (proxy of archive.ubuntu.com)
├── ubuntu-noble-updates/  → apt (proxy of archive.ubuntu.com)
├── ubuntu-noble-security/ → apt (proxy of security.ubuntu.com)
├── docker-hub/            → docker (proxy of registry-1.docker.io)
├── quay/                  → docker (proxy of quay.io)
├── k8s-gcr/               → docker (proxy of registry.k8s.io)
├── ghcr/                  → docker (proxy of ghcr.io)
├── gcr/                   → docker (proxy of gcr.io)
├── docker-hosted/         → docker (hosted internal images)
├── helm/                  → helm (hosted charts)
├── raw-hosted/            → raw (hosted files)
├── maven-central/         → maven (proxy of repo1.maven.org)
├── npm/                   → npm (proxy of registry.npmjs.org)
├── pypi/                  → pypi (proxy of pypi.org)
├── yum/                   → yum (proxy of centos.org)
└── ansible-galaxy/        → ansible (proxy of galaxy.ansible.com)
```

#### NGINX Path Routing

```nginx
# /etc/nginx/sites-available/nexus.conf

server {
    listen 443 ssl http2;
    server_name nexus.internal.lan;

    ssl_certificate /etc/nginx/ssl/nexus.internal.lan.crt;
    ssl_certificate_key /etc/nginx/ssl/nexus.internal.lan.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    # Nexus Web UI
    location /nexus/ {
        proxy_pass http://nexus_backend/nexus/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Repository paths (apt, yum, docker, etc.)
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

    # Docker registry (v2)
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

    # REST API
    location /service/ {
        proxy_pass http://nexus_backend/service/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
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

### 2.4 Repository Configuration

#### Create Repositories via API

```bash
# Create apt proxy repository
curl -u admin:admin123 -X POST "https://nexus.internal.lan/service/rest/v1/repositories/apt/proxy" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ubuntu-noble",
    "online": true,
    "storage": {
      "blobStoreName": "default",
      "strictContentTypeValidation": true
    },
    "proxy": {
      "remoteUrl": "http://archive.ubuntu.com/ubuntu",
      "contentMaxAge": 1440,
      "metadataMaxAge": 1440
    },
    "negativeCache": {
      "enabled": true,
      "timeToLive": 1440
    },
    "httpClient": {
      autoBlock": true,
      blocked": false
    },
    "apt": {
      distribution": "noble",
      "flat": false
    }
  }'

# Create docker proxy repository
curl -u admin:admin123 -X POST "https://nexus.internal.lan/service/rest/v1/repositories/docker/proxy" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "docker-hub",
    "online": true,
    "storage": {
      "blobStoreName": "default",
      "strictContentTypeValidation": true
    },
    "proxy": {
      "remoteUrl": "https://registry-1.docker.io",
      "contentMaxAge": 1440,
      "metadataMaxAge": 1440
    },
    "dockerProxy": {
      "indexType": "HUB",
      "cacheForeignLayers": true,
      "foreignLayerAllowedTags": ["**/**"]
    },
    "negativeCache": {
      "enabled": true,
      "timeToLive": 1440
    },
    "httpClient": {
      autoBlock": true,
      blocked": false
    },
    "docker": {
      v1Allowed": false,
      "forceBasicAuth": true,
      "httpPort": null,
      "httpsPort": null,
      "subdomain": null
    }
  }'

# Create docker hosted repository (for internal images)
curl -u admin:admin123 -X POST "https://nexus.internal.lan/service/rest/v1/repositories/docker/hosted" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "docker-hosted",
    "online": true,
    "storage": {
      "blobStoreName": "default",
      "strictContentTypeValidation": true
    },
    "docker": {
      v1Allowed": false,
      "forceBasicAuth": true
    },
    "cleanup": {
      "policyNames": ["string"]
    }
  }'

# Create helm hosted repository
curl -u admin:admin123 -X POST "https://nexus.internal.lan/service/rest/v1/repositories/helm/hosted" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "helm-hosted",
    "online": true,
    "storage": {
      "blobStoreName": "default",
      "strictContentTypeValidation": true
    }
  }'

# Create raw hosted repository (for generic files)
curl -u admin:admin123 -X POST "https://nexus.internal.lan/service/rest/v1/repositories/raw/hosted" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "raw-hosted",
    "online": true,
    "storage": {
      "blobStoreName": "default",
      "strictContentTypeValidation": true
    }
  }'
```

#### Create Group Repositories

```bash
# Docker group (combines proxy + hosted)
curl -u admin:admin123 -X POST "https://nexus.internal.lan/service/rest/v1/repositories/docker/group" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "docker-group",
    "online": true,
    "storage": {
      "blobStoreName": "default",
      "strictContentTypeValidation": true
    },
    "group": {
      "memberNames": ["docker-hub", "docker-hosted"]
    },
    "docker": {
      v1Allowed": false,
      "forceBasicAuth": true
    }
  }'
```

### 2.5 Containerd Configuration for Nexus

```toml
# /etc/containerd/config.toml
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "nexus.internal.lan:5000/google_containers/pause:3.9"

    [plugins."io.containerd.grpc.v1.cri".registry]
      # Docker Hub mirror through Nexus
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        endpoint = ["https://nexus.internal.lan:5000"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."docker.io".tls]
          insecure_skip_verify = false

      # Nexus hosted registry
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."nexus.internal.lan:5000"]
        endpoint = ["https://nexus.internal.lan:5000"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."nexus.internal.lan:5000".tls]
          insecure_skip_verify = false

      # Harbor registry
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.internal.lan"]
        endpoint = ["https://harbor.internal.lan"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."harbor.internal.lan".tls]
          insecure_skip_verify = false

    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true
```

### 2.6 Apt Configuration for Nexus

```bash
# /etc/apt/sources.list
deb https://nexus.internal.lan/repository/ubuntu-noble/ noble main restricted universe multiverse
deb https://nexus.internal.lan/repository/ubuntu-noble-updates/ noble-updates main restricted universe multiverse
deb https://nexus.internal.lan/repository/ubuntu-noble-security/ noble-security main restricted universe multiverse

# Docker
deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://nexus.internal.lan/repository/docker-noble/ noble stable

# Kubernetes
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://nexus.internal.lan/repository/kubernetes-noble/ kubernetes-xenial main

# Ceph
deb [signed-by=/etc/apt/keyrings/ceph.gpg] https://nexus.internal.lan/repository/ceph-reef/ reef main
```

---

## 3. Harbor Registry

### 3.1 Deployment Options

| Method | Port | Config Path | Best For |
|--------|------|-------------|----------|
| **Native (offline installer)** | 8443 | `/etc/harbor/` | Air-gap, single server |
| **Docker Compose** | 8443 | `harbor.yml` | Quick setup |
| **Kubernetes (Helm)** | 8080 | values.yaml | Cloud-native |

### 3.2 Custom Port Configuration

#### Docker Compose

```yaml
version: '3.8'

services:
  harbor-db:
    image: goharbor/harbor-db:v2.10.0
    container_name: harbor-db
    restart: always
    environment:
      POSTGRES_PASSWORD: harbor_db_password
    volumes:
      - /opt/harbor/db:/var/lib/postgresql/data
    networks:
      - harbor-net

  harbor-core:
    image: goharbor/harbor-core:v2.10.0
    container_name: harbor-core
    restart: always
    ports:
      - '8443:8443'     # Harbor web UI (custom port)
      - '8080:8080'     # API
    volumes:
      - /opt/harbor/config:/etc/harbor
      - /opt/harbor/data:/storage
      - ./harbor.yml:/etc/harbor/harbor.yml
    depends_on:
      - harbor-db
    networks:
      - harbor-net

  harbor-registry:
    image: goharbor/registry-photon:v2.10.0
    container_name: harbor-registry
    restart: always
    volumes:
      - /opt/harbor/registry:/storage
      - ./harbor.yml:/etc/harbor/harbor.yml
    networks:
      - harbor-net

  harbor-portal:
    image: goharbor/harbor-portal:v2.10.0
    container_name: harbor-portal
    restart: always
    ports:
      - '8081:8081'     # Portal (custom)
    networks:
      - harbor-net

  harbor-jobservice:
    image: goharbor/harbor-jobservice:v2.10.0
    container_name: harbor-jobservice
    restart: always
    volumes:
      - /opt/harbor/jobs:/var/jobs
      - ./harbor.yml:/etc/harbor/harbor.yml
    networks:
      - harbor-net

  harbor-redis:
    image: library/redis:7-alpine
    container_name: harbor-redis
    restart: always
    networks:
      - harbor-net

  harbor-trivy:
    image: goharbor/trivy-adapter-photon:v2.10.0
    container_name: harbor-trivy
    restart: always
    volumes:
      - /opt/harbor/trivy:/home/scanner/.cache
    networks:
      - harbor-net

  harbor-exporter:
    image: goharbor/harbor-exporter:v2.10.0
    container_name: harbor-exporter
    restart: always
    networks:
      - harbor-net

networks:
  harbor-net:
    driver: bridge
```

#### harbor.yml Configuration

```yaml
# harbor.yml — Custom port configuration

# HTTP or HTTPS
hostname: harbor.internal

http:
  port: 8080          # Custom HTTP port (default: 80)

https:
  port: 8443          # Custom HTTPS port (default: 443)
  certificate: /etc/harbor/ssl/harbor.internal.crt
  private_key: /etc/harbor/ssl/harbor.internal.key

# Harbor admin password
harbor_admin_password: Harbor12345

# Database
database:
  password: harbor_db_password
  max_idle_conns: 100
  max_open_conns: 900
  conn_max_lifetime: 5m
  conn_max_idle_time: 0

# Default data volume
data_volume: /storage

# Trivy vulnerability scanner
trivy:
  ignore_unfixed: false
  skip_update: false
  offline_scan: true       # Air-gap: no online updates
  security_check: vuln
  insecure: false

# Registry
registry:
  credentials:
    username: admin
    password: Harbor12345
  registry_db: postgres
  # Storage
  storage_provider:
    name: filesystem
    rootdirectory: /storage
    maxlayerchunk: 524288000
  middleware:
    registry:
      - name: proxy
        endpoint: https://harbor.internal
        # Proxy cache settings
        cache_ttl: 168h
        insecure_skip_verify: false

# Proxy cache projects
proxy_cache:
  enabled: true
  projects:
    - name: dockerhub-proxy
      endpoint: https://docker.io
      username:
      password:
    - name: quay-proxy
      endpoint: https://quay.io
      username:
      password:
    - name: k8s-gcr-proxy
      endpoint: https://registry.k8s.io
      username:
      password:
    - name: ghcr-proxy
      endpoint: https://ghcr.io
      username:
      password:

# Jobservice
jobservice:
  max_job_workers: 10
  job_loggers:
    - STD_OUTPUT
    - FILE
  logger_sweeper_duration: 1 #days

# Notification
notification:
  webhook_job_max_retry: 3
  webhook_job_http_client_timeout: 3 #seconds

# Chart repository
chart:
  absolute_url: disabled

# Log
log:
  level: info
  local:
    rotate_count: 50
    rotate_size: 200M
    location: /var/log/harbor

# External database (recommended for production)
external_database:
  host: postgres.internal
  port: 5432
  username: harbor
  password: harbor_db_password
  sslmode: disable
  database: harbor_db

# External Redis
external_redis:
  host: redis.internal
  port: 6379
  password: redis_password
  registry_db_index: 1
  jobservice_db_index: 2
  chartmuseum_db_index: 3
  trivy_db_index: 5
  idle_timeout_seconds: 30

# Cache
cache:
  enabled: false
  expire_hours: 24

# Quota
quota_per_project_enable: true
storage_per_project: -1  # Unlimited

# Scanner
scanner:
  base_url: https://harbor.internal:8443
  skip_update_pull_utc_time: true
  offline: true
  drive: trivy
  vuln_provider:
    sources:
      - github
      - govdirectory
      - nvd
      - osv
      - ph
    update_interval: 24h
```

### 3.3 Advanced Path Handling for Harbor

#### NGINX Path Routing

```nginx
# /etc/nginx/sites-available/harbor.conf

server {
    listen 443 ssl http2;
    server_name harbor.internal.lan;

    ssl_certificate /etc/nginx/ssl/harbor.internal.lan.crt;
    ssl_certificate_key /etc/nginx/ssl/harbor.internal.lan.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    # Harbor Web UI
    location /harbor/ {
        proxy_pass https://harbor_backend/harbor/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
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

    # Docker registry v2 (core for image pulls)
    location /v2/ {
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
    }

    # Service endpoints
    location /service/ {
        proxy_pass https://harbor_backend/service/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
    }

    # Health check
    location /health {
        proxy_pass https://harbor_backend/api/v2.0/health;
        proxy_ssl_verify off;
        access_log off;
    }
}
```

#### Containerd Configuration for Harbor

```toml
# /etc/containerd/config.toml
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "harbor.internal.lan/library/google_containers/pause:3.9"

    [plugins."io.containerd.grpc.v1.cri".registry]
      # Harbor as default registry
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.internal.lan"]
        endpoint = ["https://harbor.internal.lan"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."harbor.internal.lan".tls]
          insecure_skip_verify = false

      # Docker Hub mirror through Harbor proxy cache
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        endpoint = ["https://harbor.internal.lan"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."docker.io".tls]
          insecure_skip_verify = false

      # Quay mirror through Harbor
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]
        endpoint = ["https://harbor.internal.lan"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."quay.io".tls]
          insecure_skip_verify = false

      # K8s GCR mirror through Harbor
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io"]
        endpoint = ["https://harbor.internal.lan"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."registry.k8s.io".tls]
          insecure_skip_verify = false

    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true
```

### 3.4 Harbor Proxy Cache Setup

```bash
# Create proxy cache projects via API

# Docker Hub proxy
curl -u admin:Harbor12345 -X POST "https://harbor.internal/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{
    "project_name": "dockerhub-proxy",
    "public": false,
    "metadata": {
      "auto_scan": true,
      "enable_content_trust": false,
      "prevent_vul": "disabled",
      "public": "false",
      "reuse_sys_cve_allowlist": true,
      "retention_id": null,
      "reuse_project_level_config": true,
      "security_severity": "high",
      "auto_scan": true
    },
    "storage_limit": -1,
    "registry_id": null
  }'

# Configure proxy cache endpoint
curl -u admin:Harbor12345 -X PUT "https://harbor.internal/api/v2.0/projects/dockerhub-proxy" \
  -H "Content-Type: application/json" \
  -d '{
    "metadata": {
      "proxy_cache": true,
      "proxy_cache_endpoint": "https://docker.io"
    }
  }'
```

### 3.5 Push and Pull Images

```bash
# Login to Harbor
docker login https://harbor.internal

# Pull from Docker Hub (through Harbor proxy cache)
docker pull harbor.internal/library/nginx:1.25
docker pull harbor.internal/library/redis:7.2

# Push internal images
docker tag my-app:v1.0 harbor.internal/my-project/my-app:v1.0
docker push harbor.internal/my-project/my-app:v1.0

# Pull from Harbor directly
docker pull harbor.internal/my-project/my-app:v1.0
```

---

## 4. Multi-Distribution Repository Support

### 4.1 Ubuntu (apt)

```bash
# Nexus repositories
ubuntu-noble          → http://archive.ubuntu.com/ubuntu (noble)
ubuntu-noble-updates  → http://archive.ubuntu.com/ubuntu (noble-updates)
ubuntu-noble-security → http://security.ubuntu.com/ubuntu (noble-security)
ubuntu-jammy          → http://archive.ubuntu.com/ubuntu (jammy)
ubuntu-jammy-updates  → http://archive.ubuntu.com/ubuntu (jammy-updates)
ubuntu-jammy-security → http://security.ubuntu.com/ubuntu (jammy-security)
```

### 4.2 CentOS/RHEL (yum)

```bash
# Nexus repositories
centos-7-base        → http://mirror.centos.org/centos/7/os/x86_64
centos-7-updates     → http://mirror.centos.org/centos/7/updates/x86_64
centos-7-extras      → http://mirror.centos.org/centos/7/extras/x86_64
centos-8-base        → http://mirror.centos.org/centos/8/BaseOS/x86_64
centos-8-appstream   → http://mirror.centos.org/centos/8/AppStream/x86_64
rocky-8-base         → https://dl.rockylinux.org/pub/rocky/8/BaseOS/x86_64
rocky-8-appstream    → https://dl.rockylinux.org/pub/rocky/8/AppStream/x86_64
```

### 4.3 Alpine (apk)

```bash
# Nexus repositories
alpine-3.18-main     → https://dl-cdn.alpinelinux.org/alpine/v3.18/main
alpine-3.18-community → https://dl-cdn.alpinelinux.org/alpine/v3.18/community
alpine-3.19-main     → https://dl-cdn.alpinelinux.org/alpine/v3.19/main
alpine-3.19-community → https://dl-cdn.alpinelinux.org/alpine/v3.19/community
```

### 4.4 Debian (apt)

```bash
# Nexus repositories
debian-bookworm      → http://deb.debian.org/debian (bookworm)
debian-bookworm-updates → http://deb.debian.org/debian (bookworm-updates)
debian-bookworm-security → http://security.debian.org/debian-security (bookworm-security)
debian-bullseye      → http://deb.debian.org/debian (bullseye)
debian-bullseye-updates → http://deb.debian.org/debian (bullseye-updates)
```

### 4.5 Kubernetes Components

```bash
# Nexus repositories
kubernetes-apt       → https://pkgs.k8s.io/core/stable/deb
kubernetes-yum       → https://pkgs.k8s.io/core/stable/rpm
```

### 4.6 Docker CE

```bash
# Nexus repositories
docker-ce-stable     → https://download.docker.com/linux/ubuntu (noble/stable)
docker-ce-stable-centos → https://download.docker.com/linux/centos/7/stable
```

### 4.7 Ceph

```bash
# Nexus repositories
ceph-reef            → https://download.ceph.com/debian-reef
ceph-quincy          → https://download.ceph.com/debian-quincy
```

### 4.8 HashiCorp

```bash
# Nexus repositories
hashicorp-apt        → https://apt.releases.hashicorp.com (noble)
hashicorp-yum        → https://yum.releases.hashicorp.com
```

### 4.9 GitLab

```bash
# Nexus repositories
gitlab-ce            → https://packages.gitlab.com/gitlab/gitlab-ce/deb
gitlab-ee            → https://packages.gitlab.com/gitlab/gitlab-ee/deb
```

---

## 5. Service Health (Nexus & Harbor)

### 5.1 Nexus Health

```bash
# Check Nexus status
curl -s https://nexus.internal.lan/service/rest/v1/status
curl -s https://nexus.internal.lan/service/rest/v1/status/writable

# Check repository health
curl -s https://nexus.internal.lan/service/rest/v1/repositories | jq '.[] | {name, type, format, status}'

# Check blob stores
curl -s https://nexus.internal.lan/service/rest/v1/blobstores | jq '.[] | {name, type}'

# Check system info
curl -s https://nexus.internal.lan/service/rest/v1/system/info | jq '.'

# Check search
curl -s "https://nexus.internal.lan/service/rest/v1/search?repository=docker-hub&name=nginx" | jq '.items[] | {name, format}'

# Docker registry health
curl -s https://nexus.internal.lan:5000/v2/ | head -1
curl -s -o /dev/null -w "%{http_code}" https://nexus.internal.lan:5000/v2/
```

### 5.2 Harbor Health

```bash
# Check Harbor health
curl -s https://harbor.internal/api/v2.0/health | jq '.'

# Check system info
curl -s https://harbor.internal/api/v2.0/systeminfo | jq '.'

# Check projects
curl -s -u admin:Harbor12345 https://harbor.internal/api/v2.0/projects | jq '.[] | {name, project_id}'

# Check repositories
curl -s -u admin:Harbor12345 "https://harbor.internal/api/v2.0/projects/dockerhub-proxy/repositories" | jq '.[] | {name, artifact_count}'

# Check registry catalog
curl -s https://harbor.internal/v2/_catalog | jq '.repositories[]'

# Check specific image tags
curl -s "https://harbor.internal/v2/library/nginx/tags/list" | jq '.'

# Check proxy cache status
curl -s -u admin:Harbor12345 "https://harbor.internal/api/v2.0/projects/dockerhub-proxy" | jq '{name, metadata, storage_limit}'

# Check vulnerability scans
curl -s -u admin:Harbor12345 "https://harbor.internal/api/v2.0/projects/dockerhub-proxy/repositories/library/nginx/artifacts?with_scan_overview=true" | jq '.[].scan_overview'

# Check garbage collection
curl -s -u admin:Harbor12345 "https://harbor.internal/api/v2.0/system/gc/schedule" | jq '.'

# Check replication (if configured)
curl -s -u admin:Harbor12345 "https://harbor.internal/api/v2.0/replication/policies" | jq '.'

# Check labels
curl -s -u admin:Harbor12345 "https://harbor.internal/api/v2.0/labels" | jq '.'

# Check robot accounts
curl -s -u admin:Harbor12345 "https://harbor.internal/api/v2.0/robots" | jq '.'

# Check quotas
curl -s -u admin:Harbor12345 "https://harbor.internal/api/v2.0/quotas" | jq '.'
```

### 5.3 Reverse Proxy Health

```bash
# Check NGINX status
sudo systemctl status nginx
sudo nginx -t

# Check proxy endpoints
curl -sk -o /dev/null -w "%{http_code}" https://nexus.internal.lan/nexus/
curl -sk -o /dev/null -w "%{http_code}" https://harbor.internal/harbor/
curl -sk -o /dev/null -w "%{http_code}" https://harbor.internal/v2/

# Check upstream health
curl -sk https://nexus.internal.lan/health
curl -sk https://harbor.internal/health

# Check NGINX access log
sudo tail -f /var/log/nginx/access.log

# Check NGINX error log
sudo tail -f /var/log/nginx/error.log
```

---

## 6. Backup and Restore

### 6.1 Nexus Backup

```bash
# Backup Nexus data
sudo tar -czf /backup/nexus-$(date +%Y%m%d).tar.gz /opt/nexus/data/

# Or via API (blob stores)
curl -u admin:admin123 -X POST "https://nexus.internal.lan/service/rest/v1/blobstores/default/backup" \
  -H "Content-Type: application/json" \
  -d '{"downloadLocation": "/tmp/nexus-backup"}'

# Backup configuration
sudo cp /opt/nexus/etc/nexus-default.properties /backup/nexus-config-$(date +%Y%m%d).properties
```

### 6.2 Harbor Backup

```bash
# Backup Harbor data
sudo tar -czf /backup/harbor-$(date +%Y%m%d).tar.gz /opt/harbor/

# Backup database
docker exec harbor-db pg_dump -U postgres harbor_db > /backup/harbor-db-$(date +%Y%m%d).sql

# Or via Harbor API
curl -u admin:Harbor12345 -X POST "https://harbor.internal/api/v2.0/system/gc/schedule" \
  -H "Content-Type: application/json" \
  -d '{"schedule": {"type": "Custom", "cron": "0 2 * * *", "parameters": {"delete_untagged": true}}}'
```

---

## 7. Troubleshooting

### 7.1 Nexus Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| 502 Bad Gateway | Nexus not running | `docker restart nexus` or `systemctl restart nexus` |
| Slow repository | Cache miss | Check proxy settings, verify remote URL |
| Disk full | Blob store too large | Run blob cleanup, increase storage |
| Authentication failed | Password expired | Reset via `/opt/nexus/etc/nexus-default.properties` |
| Docker pull fails | Registry not enabled | Enable Docker registry in Nexus UI |
| Out of memory | Heap too small | Increase `-Xmx` in `nexus.vmoptions` |

### 7.2 Harbor Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Image pull denied | Not logged in | `docker login harbor.internal` |
| Vulnerability scan fails | DB not updated | Run offline DB update or disable scanning |
| GC fails | Database issue | Check harbor-db logs |
| Proxy cache miss | First pull is slow | Normal — subsequent pulls are fast |
| 502 on /v2/ | Registry not running | `docker restart harbor-registry` |
| Certificate expired | SSL cert expired | Regenerate certs, restart harbor-core |
| Storage full | Registry too large | Run GC, increase storage, set retention |

### 7.3 Reverse Proxy Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| 502 Bad Gateway | Backend down | Check backend service status |
| 504 Timeout | Backend slow | Increase `proxy_read_timeout` |
| SSL error | Cert mismatch | Regenerate cert with correct SANs |
| Wrong backend | Path misconfig | Check `location` blocks in NGINX config |
| Large upload fails | `client_max_body_size` too small | Increase to 500M |
