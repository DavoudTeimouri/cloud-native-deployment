# Container Services Guide

> Running repositories, registries, and other services as containers — transparent proxy means zero client config

---

## 1. Architecture Overview

All services run as Docker containers on a dedicated server (or shared management server).
Each service uses host directory mounts for persistent data. **Clients never
connect directly to these services** — all traffic goes through the reverse
proxy using canonical public URLs (e.g., `archive.ubuntu.com`, `docker.io`).

See [Reverse Proxy Architecture](docs/architecture/reverse-proxy-architecture.md)
for how the transparent proxy works.

```
Host Server (10.0.0.10)
├── /opt/nexus/data          ← Nexus persistent data
├── /opt/nexus/config        ← Nexus configuration
├── /opt/harbor/data         ← Harbor storage
├── /opt/harbor/config       ← Harbor configuration
├── /opt/gitlab/data         ← GitLab data
├── /opt/gitlab/config       ← GitLab configuration
├── /opt/postgres/data       ← Database for services
├── /opt/redis/data          ← Cache for services
├── /opt/nginx/config        ← Reverse proxy config
├── /opt/nginx/ssl           ← SSL certificates
└── /opt/backup              ← All service backups

Containers:
├── nexus:9091 → host:9091
├── harbor-core:8443 → host:8443
├── harbor-registry:5000 → host:5000
├── gitlab:8443 → host:9443
├── postgres:5432 → host:5432
├── redis:6379 → host:6379
└── nginx:443 → host:443
```

---

## 2. Directory Structure

```bash
# Create all directories
sudo mkdir -p /opt/{nexus/{data,config,logs},harbor/{data,config,logs,registry},gitlab/{config,data,logs,backups},postgres/data,redis/data,nginx/{config,ssl,logs},backup}

# Set permissions
sudo chown -R 1000:1000 /opt/nexus      # Nexus runs as UID 1000
sudo chown -R 1000:1000 /opt/harbor     # Harbor components
sudo chown -R 999:999 /opt/postgres     # PostgreSQL runs as UID 999
sudo chown -R 999:999 /opt/redis        # Redis runs as UID 999
sudo chown -R www-data:www-data /opt/nginx
```

---

## 3. Docker Compose Stack

### 3.1 Full docker-compose.yml

```yaml
version: '3.8'

# ─── NETWORKS ───
networks:
  frontend:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
  backend:
    driver: bridge
    internal: true  # No external access
    ipam:
      config:
        - subnet: 172.20.1.0/24

# ─── VOLUMES ───
volumes:
  postgres_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /opt/postgres/data
  redis_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /opt/redis/data
  nexus_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /opt/nexus/data
  harbor_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /opt/harbor/data
  gitlab_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /opt/gitlab/data

# ─── SERVICES ───
services:

  # ═══════════════════════════════════════════
  # PostgreSQL (shared database for services)
  # ═══════════════════════════════════════════
  postgres:
    image: postgres:15-alpine
    container_name: svc-postgres
    restart: always
    shm_size: 256mb
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: admin_password
      POSTGRES_DB: postgres
      POSTGRES_MULTIPLE_DATABASES: gitlab,nexus,harbor
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./postgres/init-scripts:/docker-entrypoint-initdb.d:ro
    ports:
      - '5432:5432'
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ═══════════════════════════════════════════
  # Redis (shared cache for services)
  # ═══════════════════════════════════════════
  redis:
    image: redis:7-alpine
    container_name: svc-redis
    restart: always
    command: >
      redis-server
      --requirepass redis_password
      --maxmemory 512mb
      --maxmemory-policy allkeys-lru
      --appendonly yes
      --appendfsync everysec
    volumes:
      - redis_data:/data
    ports:
      - '6379:6379'
    networks:
      - backend
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "redis_password", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ═══════════════════════════════════════════
  # Nexus Repository Manager
  # ═══════════════════════════════════════════
  nexus:
    image: sonatype/nexus3:3.64.0
    container_name: svc-nexus
    restart: always
    environment:
      - INSTALL4J_ADD_VM_PARAMS=-Xms2g -Xmx2g -XX:MaxDirectMemorySize=3g
      - NEXUS_CONTEXT_PATH=/nexus
    volumes:
      # Host ↔ Container path mapping
      - nexus_data:/nexus-data
      - /opt/nexus/config:/nexus-data/etc:ro
      - /opt/nexus/logs:/nexus-data/log
      - /opt/nexus/backup:/nexus-data/backup
      - /opt/backup/nexus:/nexus-data/backup-archive
    ports:
      - '9091:8081'       # Nexus web UI (custom port)
      - '9443:8443'       # Nexus HTTPS (custom port)
      - '5000:5000'       # Docker registry
      - '5001:5001'       # Docker registry v2
      - '5002:5002'       # Docker registry SSL
    networks:
      - frontend
      - backend
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/nexus/service/rest/v1/status"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s

  # ═══════════════════════════════════════════
  # Harbor Registry
  # ═══════════════════════════════════════════
  harbor-db:
    image: goharbor/harbor-db:v2.10.0
    container_name: svc-harbor-db
    restart: always
    environment:
      POSTGRES_PASSWORD: harbor_db_password
    volumes:
      - /opt/harbor/db:/var/lib/postgresql/data
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  harbor-core:
    image: goharbor/harbor-core:v2.10.0
    container_name: svc-harbor-core
    restart: always
    environment:
      HARBOR_ADMIN_PASSWORD: Harbor12345
      HARBOR_HOSTNAME: harbor.internal
    volumes:
      # Host ↔ Container path mapping
      - /opt/harbor/config/harbor.yml:/etc/harbor/harbor.yml:ro
      - harbor_data:/storage
      - /opt/harbor/logs:/var/log/harbor
      - /opt/harbor/ca_download:/etc/harbor/ca
      - /opt/backup/harbor:/harbor-backup
    ports:
      - '8443:8443'       # Harbor web UI (custom port)
      - '8080:8080'       # Harbor API
    networks:
      - frontend
      - backend
    depends_on:
      harbor-db:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "https://localhost:8443/api/v2.0/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s

  harbor-registry:
    image: goharbor/registry-photon:v2.10.0
    container_name: svc-harbor-registry
    restart: always
    volumes:
      - /opt/harbor/registry:/storage
      - /opt/harbor/config/registry:/etc/registry:ro
    ports:
      - '5000:5000'       # Docker registry
    networks:
      - frontend
      - backend
    depends_on:
      harbor-core:
        condition: service_healthy

  harbor-jobservice:
    image: goharbor/harbor-jobservice:v2.10.0
    container_name: svc-harbor-jobservice
    restart: always
    volumes:
      - /opt/harbor/jobs:/var/jobs
      - /opt/harbor/config/harbor.yml:/etc/harbor/harbor.yml:ro
    networks:
      - backend
    depends_on:
      harbor-core:
        condition: service_healthy

  harbor-portal:
    image: goharbor/harbor-portal:v2.10.0
    container_name: svc-harbor-portal
    restart: always
    networks:
      - frontend
    depends_on:
      harbor-core:
        condition: service_healthy

  harbor-redis:
    image: redis:7-alpine
    container_name: svc-harbor-redis
    restart: always
    command: redis-server --requirepass harbor_redis_password
    networks:
      - backend

  harbor-trivy:
    image: goharbor/trivy-adapter-photon:v2.10.0
    container_name: svc-harbor-trivy
    restart: always
    volumes:
      - /opt/harbor/trivy:/home/scanner/.cache
      - /opt/harbor/trivy-db:/home/scanner/trivy-db
    networks:
      - backend
    depends_on:
      harbor-core:
        condition: service_healthy

  # ═══════════════════════════════════════════
  # GitLab
  # ═══════════════════════════════════════════
  gitlab:
    image: gitlab/gitlab-ce:latest
    container_name: svc-gitlab
    restart: always
    hostname: 'gitlab.internal'
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'https://gitlab.internal:9443'
        registry_external_url 'https://gitlab.internal:5050'
        gitlab_rails['gitlab_shell_ssh_port'] = 2224
        nginx['listen_port'] = 9443
        nginx['listen_https'] = true
        # Database
        postgresql['enable'] = false
        gitlab_rails['db_adapter'] = 'postgresql'
        gitlab_rails['db_encoding'] = 'unicode'
        gitlab_rails['db_host'] = 'postgres'
        gitlab_rails['db_port'] = 5432
        gitlab_rails['db_username'] = 'gitlab'
        gitlab_rails['db_password'] = 'gitlab_password'
        gitlab_rails['db_database'] = 'gitlab_production'
        # Redis
        redis['enable'] = false
        gitlab_rails['redis_host'] = 'redis'
        gitlab_rails['redis_port'] = 6379
        gitlab_rails['redis_password'] = 'redis_password'
        # Registry
        registry['enable'] = true
        registry['registry_http_addr'] = '0.0.0.0:5050'
        registry_nginx['listen_port'] = 5050
        # Pages
        pages_external_url 'https://gitlab.internal:9090'
        gitlab_pages['enable'] = true
        # SSH
        gitlab_rails['gitlab_shell_ssh_port'] = 2224
        # SMTP
        gitlab_rails['smtp_enable'] = true
        gitlab_rails['smtp_address'] = 'smtp.internal'
        gitlab_rails['smtp_port'] = 25
        # Backup
        gitlab_rails['backup_keep_time'] = 604800
    volumes:
      # Host ↔ Container path mapping
      - /opt/gitlab/config:/etc/gitlab
      - gitlab_data:/var/opt/gitlab
      - /opt/gitlab/logs:/var/log/gitlab
      - /opt/gitlab/backups:/var/opt/gitlab/backups
      - /opt/backup/gitlab:/backup-archive
    ports:
      - '9443:9443'       # GitLab HTTPS (custom port)
      - '8080:80'         # GitLab HTTP
      - '2224:22'         # Git SSH (custom port)
      - '5050:5050'       # Container Registry
      - '9090:9090'       # GitLab Pages
    networks:
      - frontend
      - backend
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/-/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 300s

  # ═══════════════════════════════════════════
  # GitLab Runner
  # ═══════════════════════════════════════════
  gitlab-runner:
    image: gitlab/gitlab-runner:latest
    container_name: svc-gitlab-runner
    restart: always
    volumes:
      - /opt/gitlab-runner/config:/etc/gitlab-runner
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - backend
    depends_on:
      - gitlab

  # ═══════════════════════════════════════════
  # NGINX Reverse Proxy
  # ═══════════════════════════════════════════
  nginx-proxy:
    image: nginx:1.25-alpine
    container_name: svc-nginx-proxy
    restart: always
    volumes:
      # Host ↔ Container path mapping
      - /opt/nginx/config/nginx.conf:/etc/nginx/nginx.conf:ro
      - /opt/nginx/config/conf.d:/etc/nginx/conf.d:ro
      - /opt/nginx/ssl:/etc/nginx/ssl:ro
      - /opt/nginx/logs:/var/log/nginx
    ports:
      - '80:80'           # HTTP
      - '443:443'         # HTTPS
    networks:
      - frontend
    depends_on:
      - nexus
      - harbor-core
      - gitlab
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost/health"]
      interval: 15s
      timeout: 5s
      retries: 3

  # ═══════════════════════════════════════════
  # Certbot (SSL certificate management)
  # ═══════════════════════════════════════════
  certbot:
    image: certbot/certbot:latest
    container_name: svc-certbot
    volumes:
      - /opt/nginx/ssl:/etc/letsencrypt
      - /opt/nginx/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"
    networks:
      - frontend
```

---

## 4. Advanced Path Handling

### 4.1 Host ↔ Container Directory Map

| Service | Container Path | Host Path | Purpose |
|---------|---------------|-----------|---------|
| Nexus | `/nexus-data` | `/opt/nexus/data` | All Nexus data |
| Nexus | `/nexus-data/etc` | `/opt/nexus/config` | Configuration |
| Nexus | `/nexus-data/log` | `/opt/nexus/logs` | Logs |
| Nexus | `/nexus-data/backup` | `/opt/nexus/backup` | Backups |
| Harbor | `/storage` | `/opt/harbor/data` | Registry storage |
| Harbor | `/etc/harbor` | `/opt/harbor/config` | Configuration |
| Harbor | `/var/log/harbor` | `/opt/harbor/logs` | Logs |
| Harbor | `/var/lib/postgresql` | `/opt/harbor/db` | Database |
| GitLab | `/etc/gitlab` | `/opt/gitlab/config` | Configuration |
| GitLab | `/var/opt/gitlab` | `/opt/gitlab/data` | All GitLab data |
| GitLab | `/var/log/gitlab` | `/opt/gitlab/logs` | Logs |
| GitLab | `/var/opt/gitlab/backups` | `/opt/gitlab/backups` | Backups |
| PostgreSQL | `/var/lib/postgresql/data` | `/opt/postgres/data` | Database files |
| Redis | `/data` | `/opt/redis/data` | Cache data |
| NGINX | `/etc/nginx` | `/opt/nginx/config` | Proxy config |
| NGINX | `/etc/nginx/ssl` | `/opt/nginx/ssl` | Certificates |
| NGINX | `/var/log/nginx` | `/opt/nginx/logs` | Access/error logs |

### 4.2 Custom Port Map

| Service | Container Port | Host Port | Protocol | Purpose |
|---------|---------------|-----------|----------|---------|
| Nexus | 8081 | 9091 | HTTP | Web UI |
| Nexus | 8443 | 9443 | HTTPS | Web UI SSL |
| Nexus | 5000 | 5000 | HTTP | Docker registry |
| Nexus | 5001 | 5001 | HTTP | Docker registry v2 |
| Nexus | 5002 | 5002 | HTTPS | Docker registry SSL |
| Harbor | 8443 | 8443 | HTTPS | Web UI |
| Harbor | 8080 | 8080 | HTTP | API |
| Harbor | 5000 | 5000 | HTTP | Docker registry |
| GitLab | 9443 | 9443 | HTTPS | Web UI |
| GitLab | 80 | 8080 | HTTP | Web UI |
| GitLab | 22 | 2224 | TCP | Git SSH |
| GitLab | 5050 | 5050 | HTTP | Container Registry |
| GitLab | 9090 | 9090 | HTTP | Pages |
| PostgreSQL | 5432 | 5432 | TCP | Database |
| Redis | 6379 | 6379 | TCP | Cache |
| NGINX | 80 | 80 | HTTP | Proxy HTTP |
| NGINX | 443 | 443 | HTTPS | Proxy HTTPS |

### 4.3 NGINX Reverse Proxy Configuration

```nginx
# /opt/nginx/config/nginx.conf
user nginx;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 4096;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_user_agent" '
                    'upstream=$upstream_addr';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    client_max_body_size 500M;
    proxy_read_timeout 300;
    proxy_connect_timeout 60;
    proxy_send_timeout 300;

    # Upstreams
    upstream nexus {
        server svc-nexus:8081;
    }
    upstream nexus_https {
        server svc-nexus:8443;
    }
    upstream harbor {
        server svc-harbor-core:8443;
    }
    upstream harbor_api {
        server svc-harbor-core:8080;
    }
    upstream gitlab {
        server svc-gitlab:9443;
    }
    upstream gitlab_ssh {
        server svc-gitlab:22;
    }

    include /etc/nginx/conf.d/*.conf;
}
```

```nginx
# /opt/nginx/config/conf.d/nexus.conf
server {
    listen 443 ssl http2;
    server_name nexus.internal.lan;

    ssl_certificate /etc/nginx/ssl/nexus.internal.lan.crt;
    ssl_certificate_key /etc/nginx/ssl/nexus.internal.lan.key;

    location /nexus/ {
        proxy_pass http://nexus/nexus/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /repository/ {
        proxy_pass http://nexus/repository/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /v2/ {
        proxy_pass http://nexus/v2/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 500M;
        proxy_request_buffering off;
    }

    location /service/ {
        proxy_pass http://nexus/service/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```nginx
# /opt/nginx/config/conf.d/harbor.conf
server {
    listen 443 ssl http2;
    server_name harbor.internal.lan;

    ssl_certificate /etc/nginx/ssl/harbor.internal.lan.crt;
    ssl_certificate_key /etc/nginx/ssl/harbor.internal.lan.key;

    location /harbor/ {
        proxy_pass https://harbor/harbor/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
    }

    location /api/ {
        proxy_pass https://harbor/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
    }

    location /v2/ {
        proxy_pass https://harbor/v2/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
        client_max_body_size 500M;
        proxy_request_buffering off;
    }
}
```

```nginx
# /opt/nginx/config/conf.d/gitlab.conf
server {
    listen 443 ssl http2;
    server_name gitlab.internal.lan;

    ssl_certificate /etc/nginx/ssl/gitlab.internal.lan.crt;
    ssl_certificate_key /etc/nginx/ssl/gitlab.internal.lan.key;

    location / {
        proxy_pass https://gitlab/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
        client_max_body_size 500M;
    }
}

server {
    listen 443 ssl http2;
    server_name registry.internal.lan;

    ssl_certificate /etc/nginx/ssl/registry.internal.lan.crt;
    ssl_certificate_key /etc/nginx/ssl/registry.internal.lan.key;

    location /v2/ {
        proxy_pass https://gitlab/v2/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
        client_max_body_size 500M;
        proxy_request_buffering off;
    }
}
```

---

## 5. Containerd Configuration (No Custom Tags)

```toml
# /etc/containerd/config.toml
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "nexus.internal.lan:5000/google_containers/pause:3.9"

    [plugins."io.containerd.grpc.v1.cri".registry]
      # Docker Hub mirror through proxy
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        endpoint = ["https://nexus.internal.lan:5000"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."docker.io".tls]
          insecure_skip_verify = false

      # Nexus registry
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."nexus.internal.lan:5000"]
        endpoint = ["https://nexus.internal.lan:5000"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."nexus.internal.lan:5000".tls]
          insecure_skip_verify = false

      # Harbor registry
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.internal.lan"]
        endpoint = ["https://harbor.internal.lan"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."harbor.internal.lan".tls]
          insecure_skip_verify = false

      # GitLab registry
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."gitlab.internal.lan:5050"]
        endpoint = ["https://gitlab.internal.lan:5050"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."gitlab.internal.lan:5050".tls]
          insecure_skip_verify = false

    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true
```

### Usage (Same as Online)

```bash
# Pull from Docker Hub (through proxy cache)
crictl pull nginx:1.25
crictl pull redis:7.2
crictl pull alpine:3.19

# Pull from Nexus (internal images)
crictl pull nexus.internal.lan:5000/my-app:v1.0

# Pull from Harbor (internal images)
crictl pull harbor.internal.lan/library/nginx:1.25

# Pull from GitLab registry
crictl pull gitlab.internal.lan:5050/my-project/my-app:v2.0

# Kubernetes deployment (standard images, no custom tags)
# image: nginx:1.25  (not harbor.internal.lan/library/nginx:1.25)
```

---

## 6. Start the Stack

```bash
cd /opt/services

# Start all services
docker-compose up -d

# Check status
docker-compose ps
docker-compose logs -f

# Check specific service
docker-compose logs nexus
docker-compose logs harbor-core
docker-compose logs gitlab
```

---

## 7. Service Health (All Services)

```bash
# ─── Nexus ───
curl -sf http://localhost:9091/nexus/service/rest/v1/status
curl -sf https://localhost:9443/nexus/service/rest/v1/status
curl -sf https://localhost:5000/v2/

# ─── Harbor ───
curl -sfk https://localhost:8443/api/v2.0/health
curl -sfk https://localhost:5000/v2/

# ─── GitLab ───
curl -sfk https://localhost:9443/-/health
curl -sfk https://localhost:5050/v2/

# ─── PostgreSQL ───
docker exec svc-postgres pg_isready -U admin

# ─── Redis ───
docker exec svc-redis redis-cli -a redis_password ping

# ─── NGINX Proxy ───
curl -sf http://localhost/health
curl -sfk https://nexus.internal.lan/nexus/
curl -sfk https://harbor.internal.lan/v2/
curl -sfk https://gitlab.internal.lan/-/health
```

---

## 8. Backup Script

```bash
#!/bin/bash
# /opt/backup/backup-all.sh

BACKUP_DIR="/opt/backup"
DATE=$(date +%Y%m%d_%H%M%S)

echo "Starting backup: $DATE"

# Stop non-critical services (optional)
# docker-compose stop gitlab-runner

# Backup Nexus
docker exec svc-nexus tar -czf /backup-archive/nexus-$DATE.tar.gz /nexus-data

# Backup Harbor registry
docker exec svc-harbor-registry tar -czf /backup/harbor-registry-$DATE.tar.gz /storage

# Backup GitLab
docker exec svc-gitlab gitlab-backup create

# Backup PostgreSQL
docker exec svc-postgres pg_dumpall -U admin > $BACKUP_DIR/postgres-$DATE.sql

# Backup Redis
docker exec svc-redis redis-cli -a redis_password BGSAVE
docker cp svc-redis:/data/dump.rdb $BACKUP_DIR/redis-$DATE.rdb

# Backup configurations
tar -czf $BACKUP_DIR/configs-$DATE.tar.gz \
  /opt/nexus/config \
  /opt/harbor/config \
  /opt/gitlab/config \
  /opt/nginx/config

# Cleanup old backups (keep 7 days)
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "*.rdb" -mtime +7 -delete

echo "Backup completed: $DATE"
```

---

## 9. Ansible Playbook for Container Services

```yaml
---
# ansible/playbooks/container-services.yml
- name: Deploy Container Services Stack
  hosts: service_server
  become: true
  gather_facts: true
  vars:
    service_dir: /opt/services
    nexus_port: 9091
    harbor_port: 8443
    gitlab_port: 9443
    postgres_port: 5432
    redis_port: 6379

  tasks:
    - name: Install Docker
      ansible.builtin.apt:
        name:
          - docker-ce
          - docker-ce-cli
          - containerd.io
          - docker-compose-plugin
        state: present

    - name: Install Python Docker module
      ansible.builtin.pip:
        name:
          - docker
          - docker-compose

    - name: Create service directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        mode: '0755'
      loop:
        - "{{ service_dir }}"
        - /opt/nexus/{data,config,logs}
        - /opt/harbor/{data,config,logs,registry,db}
        - /opt/gitlab/{config,data,logs,backups}
        - /opt/postgres/data
        - /opt/redis/data
        - /opt/nginx/{config,ssl,logs,conf.d}
        - /opt/backup/{nexus,harbor,gitlab,postgres}

    - name: Deploy docker-compose.yml
      ansible.builtin.copy:
        src: files/docker-compose.yml
        dest: "{{ service_dir }}/docker-compose.yml"

    - name: Deploy NGINX config
      ansible.builtin.copy:
        src: files/nginx/
        dest: /opt/nginx/config/

    - name: Deploy Harbor configuration
      ansible.builtin.copy:
        src: files/harbor.yml
        dest: /opt/harbor/config/harbor.yml

    - name: Start services
      community.docker.docker_compose:
        project_src: "{{ service_dir }}"
        state: present
        restarted: true

    - name: Wait for services to be healthy
      ansible.builtin.wait_for:
        host: localhost
        port: "{{ item.port }}"
        delay: 30
        timeout: 120
      loop:
        - { name: "Nexus", port: "{{ nexus_port }}" }
        - { name: "Harbor", port: "{{ harbor_port }}" }
        - { name: "GitLab", port: "{{ gitlab_port }}" }
        - { name: "PostgreSQL", port: "{{ postgres_port }}" }
        - { name: "Redis", port: "{{ redis_port }}" }

    - name: Verify all services
      ansible.builtin.uri:
        url: "{{ item.url }}"
        status_code: 200
        validate_certs: false
      loop:
        - { name: "Nexus", url: "http://localhost:{{ nexus_port }}/nexus/service/rest/v1/status" }
        - { name: "Harbor", url: "https://localhost:{{ harbor_port }}/api/v2.0/health" }
        - { name: "GitLab", url: "http://localhost:8080/-/health" }
      register: service_health
      retries: 5
      delay: 10
      until: service_health is success
