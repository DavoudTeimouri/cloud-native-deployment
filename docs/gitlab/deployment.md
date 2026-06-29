# GitLab Deployment Guide

> GitLab CE/EE deployment: Native, Container, and Kubernetes

---

## 1. Deployment Methods Overview

| Method | Complexity | Best For | HA Support |
|--------|-----------|----------|------------|
| **Native (deb/rpm)** | Low-Medium | Single server, traditional ops | Via external DB + NFS |
| **Container (docker-compose)** | Medium | Quick setup, reproducible | Via Docker Swarm/K8s |
| **Kubernetes (Helm)** | Medium-High | Cloud-native, auto-scaling | Native via StatefulSets |
| **Docker Swarm** | Medium | Lightweight orchestration | Native via services |

---

## 2. Native Installation (Ubuntu 22.04)

### 2.1 Install Dependencies

```bash
sudo apt-get update
sudo apt-get install -y curl openssh-server ca-certificates tzdata perl \
  postfix git

# Configure postfix as "Internet Site" during install
```

### 2.2 Install GitLab via DEB Package

#### From GitLab Official Repository

```bash
# Add official GitLab DEB repository
curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash

# Install GitLab CE (or ee for Enterprise Edition)
sudo EXTERNAL_URL="https://gitlab.internal" apt-get install -y gitlab-ce

# For GitLab EE, use:
# sudo EXTERNAL_URL="https://gitlab.internal" apt-get install -y gitlab-ee

# Configure GitLab
sudo gitlab-ctl reconfigure
```

#### From Nexus Repository (Air-Gap)

```bash
# Ensure Nexus repository for GitLab is set up
# Nexus Repository → repository/gitlab/gitlab-ce-latest.deb
wget https://nexus.internal/repository/gitlab/gitlab-ce_16.0.0-ee_amd64.deb
sudo dpkg -i gitlab-ce_16.0.0-ee_amd64.deb

# Configure GitLab
sudo EXTERNAL_URL="https://gitlab.internal" sudo gitlab-ctl reconfigure
```

### 2.3 Initial Configuration

```bash
# Check initial admin password (valid for 24 hours after install)
cat /etc/gitlab/initial_root_password

# Access GitLab URL: https://gitlab.internal
# NOTE: Change default root password immediately after first login.
#      Default username is 'root'.
```

**⚠️ Default Authentication: GitLab creates the 'root' user with the password from `/etc/gitlab/initial_root_password` during the first reconfigure.**

### 2.4 External PostgreSQL (Recommended)

Edit `/etc/gitlab/gitlab.rb`:

```ruby
# Disable bundled PostgreSQL
postgresql['enable'] = false

# Configure external PostgreSQL
gitlab_rails['db_adapter'] = 'postgresql'
gitlab_rails['db_encoding'] = 'unicode'
gitlab_rails['db_host'] = 'postgres.internal'
gitlab_rails['db_port'] = 5432
gitlab_rails['db_username'] = 'gitlab'
gitlab_rails['db_password'] = 'gitlab_password'
gitlab_rails['db_database'] = 'gitlab_production'
```

### 2.5 External Redis

```ruby
redis['enable'] = false

gitlab_rails['redis_host'] = 'redis.internal'
gitlab_rails['redis_port'] = 6379
gitlab_rails['redis_password'] = 'redis_password'
```

### 2.6 GitLab Container Registry

```ruby
registry_external_url 'https://gitlab.internal:5050'

registry['enable'] = true
registry['registry_http_addr'] = '0.0.0.0:5000'

# Registry SSL
registry_nginx['ssl_certificate'] = '/etc/gitlab/ssl/gitlab.internal.crt'
registry_nginx['ssl_certificate_key'] = '/etc/gitlab/ssl/gitlab.internal.key'
```

### 2.7 GitLab Pages

```ruby
pages_external_url 'https://gitlab.internal:9090'
gitlab_pages['enable'] = true
pages_nginx['enable'] = true
```

### 2.8 Object Storage (Git LFS, Artifacts, Uploads)

```ruby
git_data_dirs({
  "default" => {
    "path" => "/var/opt/gitlab/git-data/repositories"
  },
  "alternative" => {
    "path" => "/mnt/storage/git-data/repositories"
  }
})

# S3-compatible storage (MinIO/Ceph RGW)
gitlab_rails['object_store']['enabled'] = true
gitlab_rails['object_store']['proxy_download'] = true
gitlab_rails['object_store']['storage_options'] = {
  'provider' => 'AWS',
  'region' => 'us-east-1',
  'aws_access_key_id' => 'minio_access_key',
  'aws_secret_access_key' => 'minio_secret_key',
  'endpoint' => 'https://minio.internal',
  'path_style' => true
}
gitlab_rails['object_store']['connection'] = {
  'provider' => 'AWS',
  'region' => 'us-east-1',
  'aws_access_key_id' => 'minio_access_key',
  'aws_secret_access_key' => 'minio_secret_key',
  'endpoint' => 'https://minio.internal:9000',
  'path_style' => true
}
```

### 2.9 GitLab CI/CD Runners

```bash
# Install GitLab Runner on separate server(s)
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install -y gitlab-runner

# Register Runner
sudo gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.internal" \
  --registration-token "<REGISTRATION_TOKEN>" \
  --executor "docker" \
  --docker-image "docker:latest" \
  --description "docker-runner" \
  --docker-privileged \
  --docker-volumes "/certs/client"

# List registered runners
sudo gitlab-runner list
sudo gitlab-runner verify
```

### 2.10 LDAP/AD Integration (Optional)

```ruby
gitlab_rails['ldap_enabled'] = true
gitlab_rails['ldap_servers'] = {
  'main' => {
    'label' => 'LDAP',
    'host' => 'ldap.internal',
    'port' => 636,
    'uid' => 'sAMAccountName',
    'bind_dn' => 'CN=gitlab,OU=Service Accounts,DC=internal,DC=lan',
    'password' => 'ldap_password',
    'encryption' => 'simple_tls',
    'verify_certificates' => true,
    'tls_options' => {
      'ca_file' => '/etc/gitlab/ssl/ldap-ca.crt'
    },
    'timeout' => 10,
    'active_directory' => true,
    'allow_username_or_email_login' => false,
    'block_auto_created_users' => false,
    'base' => 'OU=Users,DC=internal,DC=lan',
    'user_filter' => '(memberOf=CN=GitLab_Users,OU=Groups,DC=internal,DC=lan)'
  }
}
```

### 2.11 Service Health

```bash
sudo gitlab-ctl status
sudo gitlab-rake gitlab:check
sudo gitlab-rake gitlab:env:info
sudo gitlab-ctl tail  # live logs
```

---

## 3. Container Deployment (Docker Compose)

### 3.1 Architecture

```
┌─────────────────────────────────────────────────────┐
│ Docker Compose Stack │
│ ┌───────────┐ ┌──────────┐ ┌──────────────────────┐ │
│ │ GitLab │ │ Redis │ │ PostgreSQL │ │
│ │ Ports: │ │ 6379 │ │ 5432 │ │
│ │ 80,443,22│ │ │ │ │ │
│ └───────────┘ └──────────┘ └──────────────────────┘ │
│ ┌────────────────────────────────────────────────┐ │
│ │ Shared Volume │ │
│ │ /mnt/ → data/, config/, logs/ │ │
│ └────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

### 3.2 Create Directory Structure

```bash
sudo mkdir -p /opt/gitlab/{config,data,logs}
sudo mkdir -p /opt/gitlab-runner/config
sudo mkdir -p /opt/postgres/data
sudo mkdir -p /opt/redis/data
sudo mkdir -p /opt/minio/data

sudo chown -R 1000:1000 /opt/gitlab*
```

### 3.3 docker-compose.yml

```yaml
version: '3.8'

services:
  # PostgreSQL
  postgres:
    image: nexus.internal/repository/docker/library/postgres:15-alpine
    container_name: gitlab-postgres
    restart: always
    environment:
      POSTGRES_USER: gitlab
      POSTGRES_PASSWORD: gitlab_password
      POSTGRES_DB: gitlab_production
    volumes:
      - /opt/postgres/data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U gitlab"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - gitlab-net

  # Redis
  redis:
    image: nexus.internal/repository/docker/library/redis:7-alpine
    container_name: gitlab-redis
    restart: always
    command: >
      redis-server
      --requirepass redis_password
      --maxmemory 512mb
      --maxmemory-policy allkeys-lru
    volumes:
      - /opt/redis/data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "redis_password", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - gitlab-net

  # GitLab
  gitlab:
    image: nexus.internal/repository/docker/gitlab/gitlab-ce:latest
    container_name: gitlab
    restart: always
    hostname: 'gitlab.internal'
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'https://gitlab.internal:8443'
        registry_external_url 'https://gitlab.internal:5050'
        gitlab_rails['gitlab_shell_ssh_port'] = 2224
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
        registry_nginx['listen_https'] = false
        # Pages
        pages_external_url 'https://gitlab.internal:9090'
        gitlab_pages['enable'] = true
        pages_nginx['enable'] = true
        # Git data
        git_data_dirs({
          "default" => {
            "path" => "/var/opt/gitlab/git-data/repositories"
          }
        })
        # SMTP
        gitlab_rails['smtp_enable'] = true
        gitlab_rails['smtp_address'] = 'smtp.internal'
        gitlab_rails['smtp_port'] = 25
        # Backup
        gitlab_rails['backup_keep_time'] = 604800  # 7 days
        # SSH
        gitlab_rails['gitlab_shell_ssh_port'] = 2224
    ports:
      - '8443:443'
      - '8080:80'
      - '2224:22'
      - '5050:5050'
      - '9090:9090'
    volumes:
      - /opt/gitlab/config:/etc/gitlab
      - /opt/gitlab/data:/var/opt/gitlab
      - /opt/gitlab/logs:/var/log/gitlab
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/-/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 300s
    networks:
      - gitlab-net

  # GitLab Runner
  gitlab-runner:
    image: gitlab/gitlab-runner:latest
    container_name: gitlab-runner
    restart: always
    volumes:
      - /opt/gitlab-runner/config:/etc/gitlab-runner
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      - gitlab
    networks:
      - gitlab-net

networks:
  gitlab-net:
    driver: bridge
```

### 3.4 Advanced Port Configuration

```yaml
# Use non-default ports (avoid conflicts)
services:
  gitlab:
    ports:
      - '8443:443'     # GitLab HTTPS (default: 443)
      - '8080:80'      # GitLab HTTP (default: 80)
      - '2224:22'      # Git SSH (default: 22)
      - '5050:5050'    # Container Registry (custom)
      - '9090:9090'    # GitLab Pages (custom)
      - '9091:9091'    # GitLab Workhorse
```

### 3.5 Start the Stack

```bash
cd /opt/gitlab
docker-compose up -d
docker-compose logs -f gitlab
```

### 3.6 Initial Setup

```bash
# Get initial root password
docker-compose exec gitlab grep 'Password:' /etc/gitlab/initial_root_password

# Register runner
docker-compose exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.internal:8443" \
  --registration-token "<TOKEN>" \
  --executor "docker" \
  --docker-image "docker:latest" \
  --docker-privileged \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock"

# Check status
sudo docker-compose exec gitlab gitlab-ctl status
sudo docker-compose exec gitlab gitlab-rake gitlab:check SANITIZE=true
```

### 3.7 Service Health in a Container Environment

```bash
# Check GitLab health
curl -k https://gitlab.internal:8443/-/health
curl -k https://gitlab.internal:8443/-/live
curl -k https://gitlab.internal:8443/-/ready

# Check individual services
docker-compose exec gitlab gitlab-ctl status
docker-compose exec redis redis-cli -a redis_password ping
docker-compose exec postgres pg_isready -U gitlab

# Logs
docker-compose exec gitlab gitlab-ctl tail
docker-compose logs -f --tail=100 gitlab
```

### 3.8 Backups in Container Deployment

```bash
# Create backup
docker-compose exec gitlab gitlab-backup create

# Backup repositories and uploads
docker-compose exec gitlab tar -czf /var/opt/gitlab/backups/uploads.tar.gz /var/opt/gitlab/git-rails/uploads/

# Download backup
docker-compose cp gitlab:/var/opt/gitlab/backups/*.tar ./

# Restore from backup (stop all services first)
docker-compose stop gitlab
docker-compose run --rm gitlab gitlab-backup restore BACKUP=<timestamp>
docker-compose start gitlab
```

---

## 4. Kubernetes Deployment (Helm)

### 4.1 Prerequisites

```bash
# Add GitLab Helm repo
helm repo add gitlab https://charts.gitlab.io
helm repo update

# Create namespace
kubectl create namespace gitlab

# Create SSL secret
kubectl create secret tls gitlab-tls \
  --namespace gitlab \
  --cert=/path/to/gitlab.crt \
  --key=/path/to/gitlab.key
```

### 4.2 values.yaml for Helm Install

```yaml
# values-gitlab.yaml
global:
  hosts:
    domain: gitlab.internal
    https: true
    external: true

  ingress:
    configureCertmanager: true
    tls:
      secretName: gitlab-tlab
    annotations:
      nginx.ingress.kubernetes.io/proxy-body-size: "500m"
      nginx.ingress.kubernetes.io/ssl-redirect: "true"

  gitlab:
    host: gitlab.internal
    https: true
    time_zone: UTC

  # PostgreSQL
  psql:
    host: postgres-service.gitlab.svc.cluster.local
    port: 5432
    username: gitlab
    password:
      secret: gitlab-db-secret
      key: password
    database: gitlab_production

  # Redis
  redis:
    host: redis-service.gitlab.svc.cluster.local
    port: 6379
    password:
      secret: gitlab-redis-secret
      key: password

  # Persistent storage (Ceph RBD or NFS)
  persistence:
    enabled: true
    storageClass: ceph-rbd
    size: 100Gi
    accessMode: ReadWriteOnce

  # External MinIO
  minio:
    enabled: false
  object_store:
    enabled: true
    connection:
      secret: gitlab-object-storage
      key: connection

# GitLab components
gitlab:
  # Unicorn/Puma (web handler)
  unicorn:
    minReplicas: 2
    maxReplicas: 5
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 2
        memory: 4Gi

  # Sidekiq (background jobs)
  sidekiq:
    minReplicas: 1
    maxReplicas: 3
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1
        memory: 2Gi

  # GitLab Shell (SSH handling)
  gitlab-shell:
    enabled: true

  # Workhorse
  workhorse:
    enabled: true

  # Registry
  registry:
    enabled: true
    ingress:
      enabled: true
      tls:
        enabled: true
        secretName: registry-tlab
    storage:
      secret: registry-s3
      key: connection.yaml

  # Pages
  pages:
    enabled: true

  # Gitaly (Git RPC)
  gitaly:
    enabled: true
    persistence:
      size: 50Gi
      storageClass: ceph-rbd

# Monitoring
monitoring:
  enabled: true
```

### 4.3 Install via Helm

```bash
# Create secrets for external services
kubectl create secret generic gitlab-db-secret \
  --namespace gitlab \
  --from-literal=password='gitlab_password'

kubectl create secret generic gitlab-redis-secret \
  --namespace gitlab \
  --from-literal=password='redis_password'

# Install GitLab
helm install gitlab gitlab/gitlab \
  --namespace gitlab \
  --version 7.1.0 \
  --values values-gitlab.yaml \
  --timeout 10m

# Watch pods
kubectl get pods -n gitlab -w
kubectl get ingress -n gitlab
```

### 4.4 Access GitLab

```bash
# Get initial root password
kubectl get secret gitlab-gitlab-initial-root-password -n gitlab \
  -o jsonpath='{.data.password}' | base64 -d
```

**⚠️ Default Authentication: In Kubernetes Helm deployments, the initial root password is stored in the Secret `gitlab-gitlab-initial-root-password`. See GitLab docs for the username and how to retrieve it.**

### 4.5 High Availability Configuration

```yaml
# values-ha.yaml
global:
  hosts:
    domain: gitlab.internal

  # PostgreSQL (external or Patroni)
  psql:
    host: postgres-cluster.gitlab.svc.cluster.local
    port: 5432
    username: gitlab
    password:
      secret: gitlab-db-secret
      key: password
    database: gitlab_production
    preparedStatements: false

  # Redis (external Sentinel/Cluster)
  redis:
    host: redis-cluster.gitlab.svc.cluster.local
    port: 6379

gitlab:
  unicorn:
    minReplicas: 3
    maxReplicas: 10

  sidekiq:
    minReplicas: 2
    maxReplicas: 5

  gitaly:
    enabled: true
    persistence:
      size: 100Gi
      storageClass: ceph-rbd

    # Multiple Gitaly instances for HA
    hpa:
      minReplicas: 2
      maxReplicas: 5
      targetCPUUtilizationPercentage: 75

# Sentinel for Redis HA
sentinel:
  enabled: true

# Object storage (S3/MinIO)
object_store:
  enabled: true
  connection:
    secret: gitlab-object-storage
    key: connection

# Configure for Ceph storage
certmanager:
  install: true

ingress:
  class: nginx
  tls:
    enabled: true
```

### 4.6 Post-Install Tasks

```bash
# Check all pods are running
kubectl get pods -n gitlab

# Check GitLab install status
helm status gitlab -n gitlab

# Get initial root password
kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -ojson

# Watch readiness
kubectl wait --for=condition=ready pod -l app=unicorn -n gitlab --timeout=300s
kubectl wait --for=condition=ready pod -l app=sidekiq -n gitlab --timeout=300s
```

---

## 5. Configuration Comparison

| Setting | Native (deb) | Container (compose) | Kubernetes (Helm) |
|---------|-------------|--------------------|--------------------|
| **GitLab URL** | `EXTERNAL_URL` | `external_url` | `global.hosts.domain` |
| **Git SSH Port** | `gitlab_shell_ssh_port` | `gitlab_shell_ssh_port` | `global.ssh.port` |
| **Registry URL** | `registry_external_url` | `registry_external_url` | `registry.ingress` |
| **Database** | `gitlab_rails['db_*']` | `GITLAB_OMNIBUS_CONFIG` | `global.psql` |
| **Redis** | `gitlab_rails['redis_*']` | `GITLAB_OMNIBUS_CONFIG` | `global.redis` |
| **Backups** | `gitlab-backup create` | `docker exec` | CronJob |
| **Scaling** | Manual | Docker Compose replicas | HPA |
| **Self-healing** | systemd | restart policies | ReplicaSets |
| **Logs** | `gitlab-ctl tail` | `docker logs` | Prometheus + Grafana |

---

## 6. Service Health (All Deployment Methods)

```bash
# ─── Native ───
sudo gitlab-ctl status
sudo gitlab-ctl tail postgresql
sudo gitlab-ctl tail redis
sudo gitlab-ctl unicorn

# ─── Container ───
sudo docker-compose exec gitlab gitlab-ctl status
sudo docker-compose exec postgres pg_isready
sudo docker-compose exec redis redis-cli ping

# ─── Kubernetes ───
kubectl get pods -n gitlab
kubectl logs -n gitlab -l app=unicorn --tail=50
kubectl top pod -n gitlab
kubectl exec -it gitlab-postgres-0 -n gitlab -- pg_isready
kubectl exec -it gitlab-redis-0 -n gitlab -- redis-cli ping
```

### Health Check URLs

```bash
# GitLab web
curl -k https://gitlab.internal/-/health
curl -k https://gitlab.internal/-/live
curl -k https://gitlab.internal/-/ready

# Container Registry
curl -k https://gitlab.internal:5050/v2/

# Git SSH
ssh -T git@gitlab.internal -p 2224
```

---

## 7. Recommendations

| Method | Recommendation |
|--------|---------------|
| **Native** | Best if GitLab is the only service on the dedicated server — simplest to manage, no container overhead. |
| **Container** | Best for rapid deployment, reproducible setups, or when migrating from/to Kubernetes. Good balance of simplicity and flexibility. |
| **Kubernetes** | Best if GitLab must be part of the cloud-native ecosystem — auto-scaling, self-healing, consistent monitoring. Requires Ceph or NFS for storage. |

**For your air-gapped deployment:** I recommend **Container (docker-compose)** start. It's the fastest to deploy, easy to reconfigure (ports, volumes), and provides all features including registry and pages. Move to Kubernetes later if you need auto-scaling.
