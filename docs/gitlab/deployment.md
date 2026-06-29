# GitLab Deployment & CI/CD Integration Guide

## Overview

GitLab serves as the source code management and CI/CD platform in the air-gapped environment. It integrates with ArgoCD for GitOps-based deployments and hosts all infrastructure-as-code repositories.

> **Air-Gap Note**: GitLab must be deployed from offline packages. All CI/CD runners must use Harbor as their container registry and Nexus for dependency resolution.

---

## GitLab Deployment

### Architecture Options

| Option | Description | Pros | Cons |
|--------|------------|------|------|
| **Docker Compose** | Single-node, all-in-one | Simple, low resource | Not HA |
| **Omnibus Package** | Single-node, bare-metal | Easy to manage | Not HA |
| **Helm Chart** | On K8s (mgmt cluster) | HA possible, K8s-native | More complex |
| **Reference Architecture** | Multi-node | Full HA | High resource needs |

**Recommendation for this environment**: Omnibus Package on the Ops Linux server (single-node with backup). For HA, deploy via Helm on management cluster.

### Prerequisites

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| Disk | 100 GB | 500 GB (SSD) |
| OS | Ubuntu 22.04 | Ubuntu 22.04 |
| PostgreSQL | Built-in | External (Ceph-backed) |
| Redis | Built-in | External (recommended for 500+ users) |

### Method 1: Omnibus Package (Recommended for Air-Gap)

#### Download on Internet-Connected Machine

```bash
#!/usr/bin/env bash
# offline-download-gitlab.sh
# Run on internet-connected machine

GITLAB_VERSION="17.8.0"
DOWNLOAD_DIR="/tmp/gitlab-offline"

mkdir -p "$DOWNLOAD_DIR"

# Download GitLab CE omnibus package
wget -O "$DOWNLOAD_DIR/gitlab-ce_${GITLAB_VERSION}-ce.0_amd64.deb" \
  "https://packages.gitlab.com/gitlab/gitlab-ce/packages/ubuntu/jammy/gitlab-ce_${GITLAB_VERSION}-ce.0_amd64.deb/download.deb"

# Download runner binary
wget -O "$DOWNLOAD_DIR/gitlab-runner" \
  "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"

# Download Helm chart for GitLab (if deploying on K8s)
helm repo add gitlab https://charts.gitlab.io/
helm repo update
helm pull gitlab/gitlab --version "8.8.0" --destination "$DOWNLOAD_DIR/"

echo "All GitLab artifacts downloaded to $DOWNLOAD_DIR"
ls -lh "$DOWNLOAD_DIR/"
```

#### Install in Air-Gap

```bash
#!/usr/bin/env bash
# deploy-gitlab.sh
set -euo pipefail

GITLAB_VERSION="${GITLAB_VERSION:-17.8.0}"
GITLAB_URL="${GITLAB_URL:-https://gitlab.internal}"
GITLAB_HOSTNAME="${GITLAB_HOSTNAME:-gitlab.internal}"

# Install from local deb (already transferred from internet-connected machine)
dpkg -i "/tmp/gitlab-offline/gitlab-ce_${GITLAB_VERSION}-ce.0_amd64.deb"

# Configure GitLab
cat > /etc/gitlab/gitlab.rb <<EOF
# External URL
external_url '${GITLAB_URL}'

# Disable unnecessary services (minimal for air-gap)
prometheus_monitoring['enable'] = false
grafana['enable'] = false

# PostgreSQL tuning
postgresql['shared_buffers'] = "2GB"
postgresql['max_connections'] = 400

# Redis tuning
redis['maxmemory'] = "1gb"

# Backup configuration
gitlab_rails['backup_path'] = "/var/opt/gitlab/backups"
gitlab_rails['backup_keep_time'] = 604800  # 7 days

# Disable signup (security)
gitlab_rails['gitlab_signup_enabled'] = false

# SMTP (if internal mail server available)
gitlab_rails['smtp_enable'] = true
gitlab_rails['smtp_address'] = "mail.internal"
gitlab_rails['smtp_port'] = 25
gitlab_rails['smtp_domain'] = "internal"

# Package repository (disable, use Nexus)
# CI runners will use Nexus for pip/apt/docker

# Container Registry (optional - Harbor is primary)
registry_external_url '${GITLAB_URL}:5050'
registry['enable'] = false  # Use Harbor instead

# Mattermost (optional, disable if not needed)
mattermost['enable'] = false

# Pages (optional)
gitlab_pages['enable'] = false
EOF

# Reconfigure GitLab
gitlab-ctl reconfigure

# Wait for services to start
echo "Waiting for GitLab to become ready..."
for i in $(seq 1 30); do
  if curl -skf "${GITLAB_URL}/-/readiness" > /dev/null 2>&1; then
    echo "GitLab is ready!"
    break
  fi
  echo "  Attempt $i/30..."
  sleep 10
done

# Retrieve initial root password
echo "Initial root password:"
cat /etc/gitlab/initial_root_password

echo ""
echo "GitLab deployed at: ${GITLAB_URL}"
echo "Please change the root password immediately after first login."
```

### Method 2: Helm Chart on Management Cluster

```bash
#!/usr/bin/env bash
# deploy-gitlab-k8s.sh
set -euo pipefail

NAMESPACE="gitlab"
HELM_REPO="https://charts.gitlab.io/"
CHART_VERSION="8.8.0"

# Add GitLab Helm repo (from Nexus Helm proxy in air-gap)
helm repo add gitlab "${NEXUS_URL}/repository/helm-proxy/" || \
  helm repo add gitlab "$HELM_REPO"
helm repo update

# Create namespace
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Deploy cert-manager first (prerequisite)
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true \
  --set image.repository="${HARBOR_URL}/jetstack/cert-manager-controller" \
  --wait

# Deploy GitLab
helm upgrade --install gitlab gitlab/gitlab \
  --namespace "$NAMESPACE" \
  --version "$CHART_VERSION" \
  -f helm-values/gitlab-values.yaml \
  --timeout 30m \
  --wait

echo "GitLab deployed on Kubernetes"
kubectl get pods -n "$NAMESPACE"
```

#### GitLab Helm Values (helm-values/gitlab-values.yaml)

```yaml
# gitlab-values.yaml
global:
  hosts:
    domain: internal
    hostSuffix: ""
    gitlab:
      name: gitlab.internal
    registry:
      name: registry.internal
    minio:
      enabled: false  # Using Harbor/Nexus instead
  
  # Air-gap: Use Harbor registry
  imageRegistry: harbor.internal/gitlab
  
  # Ingress configuration
  ingress:
    configureCertmanager: true
    tls:
      enabled: true
  
  # PostgreSQL
  psql:
    host: postgresql.gitlab.svc.cluster.local
    password:
      secret: gitlab-postgresql-password
  
  # Redis
  redis:
    host: redis-master.gitlab.svc.cluster.local
  
  # MinIO disabled (using Harbor/Ceph RGW)
  minio:
    enabled: false
  
  # Object storage (Ceph RGW or MinIO)
  objectStorage:
    enabled: true
    proxy_download: true
    connection:
      secret: gitlab-object-storage
      key: connection
    artifacts:
      bucket: gitlab-artifacts
    lfs:
      bucket: gitlab-lfs
    uploads:
      bucket: gitlab-uploads
    packages:
      bucket: gitlab-packages
    terraformState:
      bucket: gitlab-terraform
    ciSecureFiles:
      bucket: gitlab-ci-secure-files
    externalDiffs:
      bucket: gitlab-mr-diffs
    dependencyProxy:
      bucket: gitlab-dependency-proxy

# GitLab Runner
gitlab-runner:
  install: true
  rbac:
    create: true
  runners:
    privileged: true
    config: |
      [[runners]]
        [runners.kubernetes]
          image = "harbor.internal/library/ubuntu:22.04"
          poll_timeout = 600
        [runners.kubernetes.node_selector]
          "node-role.kubernetes.io/worker" = "true"

# PostgreSQL (if not external)
postgresql:
  install: true
  persistence:
    storageClass: cephfs
    size: 50Gi

# Redis
redis:
  install: true
  persistence:
    storageClass: cephfs
    size: 10Gi

# Prometheus disabled (using standalone kube-prometheus-stack)
prometheus:
  install: false

# Grafana disabled
grafana:
  enabled: false
```

---

## GitLab Configuration

### Initial Setup

```bash
# Set root password
GITLAB_URL="https://gitlab.internal"
ROOT_PASS=$(cat /etc/gitlab/initial_root_password | grep "Password:" | awk '{print $2}')

# Create personal access token
curl -sk --request POST "${GITLAB_URL}/api/v4/personal_access_tokens" \
  --header "PRIVATE-TOKEN: ${ROOT_PASS}" \
  --data "name=setup-token&scopes[]=api&scopes[]=read_repository&scopes[]=write_repository"

# Create groups for organizing projects
for group in infrastructure applications operations platform monitoring; do
  curl -sk --request POST "${GITLAB_URL}/api/v4/groups" \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --data "name=${group}&path=${group}&visibility=internal"
done

# Create infrastructure projects
for project in k8s-manifests helm-values ansible-playbooks scripts; do
  curl -sk --request POST "${GITLAB_URL}/api/v4/projects" \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --data "name=${project}&namespace_id=1&visibility=internal"
done
```

### LDAP/AD Integration

```ruby
# /etc/gitlab/gitlab.rb - Add LDAP configuration

gitlab_rails['ldap_enabled'] = true
gitlab_rails['ldap_servers'] = {
  'main' => {
    'label' => 'Corporate AD',
    'host' => 'ad.internal',
    'port' => 636,
    'uid' => 'sAMAccountName',
    'method' => 'ssl',
    'bind_dn' => 'CN=gitlab,OU=ServiceAccounts,DC=internal',
    'password' => '***',
    'active_directory' => true,
    'base' => 'DC=internal',
    'user_filter' => '(memberOf=CN=GitLabUsers,OU=Groups,DC=internal)',
    'attributes' => {
      'username' => ['sAMAccountName'],
      'email' => ['mail'],
      'name' => 'displayName',
      'first_name' => 'givenName',
      'last_name' => 'sn'
    }
  }
}
```

---

## GitLab Runner Configuration

### Shell Runner (on Ops Linux Server)

```bash
#!/usr/bin/env bash
# setup-gitlab-runner.sh

RUNNER_URL="https://gitlab.internal"
RUNNER_TOKEN="${RUNNER_TOKEN:-}"  # Get from GitLab UI: Admin > Runners

# Download runner binary (already in air-gap from offline bundle)
cp /tmp/gitlab-offline/gitlab-runner /usr/local/bin/
chmod +x /usr/local/bin/gitlab-runner

# Create runner user
useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash

# Install and register
gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
gitlab-runner register \
  --non-interactive \
  --url "$RUNNER_URL" \
  --token "$RUNNER_TOKEN" \
  --executor "shell" \
  --description "shell-runner-ops" \
  --tag-list "shell,ops,deploy" \
  --run-untagged="false"

# Configure Nexus as package source for runner environment
cat > /home/gitlab-runner/.pip/pip.conf <<EOF
[global]
index-url = http://nexus:8081/repository/pypi-group/simple
trusted-host = nexus
EOF

# Start runner
gitlab-runner start
```

### Kubernetes Runner (on Management Cluster)

```yaml
# gitlab-runner-k8s-values.yaml
gitlab-runner:
  gitlabUrl: https://gitlab.internal/
  runnerRegistrationToken: "***"

  rbac:
    create: true
  
  runners:
    privileged: true
    config: |
      [[runners]]
        [runners.kubernetes]
          namespace = "gitlab-runner"
          image = "harbor.internal/library/ubuntu:22.04"
          cpu_request = "500m"
          memory_request = "512Mi"
          cpu_limit = "2"
          memory_limit = "2Gi"
          poll_timeout = 600
          [runners.kubernetes.node_selector]
            "node-role.kubernetes.io/worker" = "true"
    
  # Air-gap: Use Harbor registry
  image: harbor.internal/gitlab/gitlab-runner:ubuntu-v17.8.0
  
  # Cache
  cache:
    secretName: gitlab-runner-cache
    cacheType: s3
    s3:
      serverAddress: http://minio.internal:9000
      bucketName: gitlab-runner-cache
      insecure: true
```

---

## CI/CD Pipeline Templates

### Docker Build Pipeline (Air-Gap)

```yaml
# .gitlab-ci.yml - Docker build with Harbor registry
stages:
  - build
  - test
  - deploy

variables:
  HARBOR_URL: "harbor.internal"
  HARBOR_PROJECT: "applications"
  IMAGE_TAG: "$CI_COMMIT_SHORT_SHA"

docker-build:
  stage: build
  tags:
    - shell
  script:
    - docker build -t ${HARBOR_URL}/${HARBOR_PROJECT}/${CI_PROJECT_NAME}:${IMAGE_TAG} .
    - docker push ${HARBOR_URL}/${HARBOR_PROJECT}/${CI_PROJECT_NAME}:${IMAGE_TAG}
    - docker tag ${HARBOR_URL}/${HARBOR_PROJECT}/${CI_PROJECT_NAME}:${IMAGE_TAG} \
        ${HARBOR_URL}/${HARBOR_PROJECT}/${CI_PROJECT_NAME}:latest
    - docker push ${HARBOR_URL}/${HARBOR_PROJECT}/${CI_PROJECT_NAME}:latest
  only:
    - main

deploy-argocd:
  stage: deploy
  tags:
    - shell
  script:
    # Update ArgoCD application manifest with new image tag
    - sed -i "s|image:.*${CI_PROJECT_NAME}:.*|image: ${HARBOR_URL}/${HARBOR_PROJECT}/${CI_PROJECT_NAME}:${IMAGE_TAG}|" \
        k8s/deployment.yaml
    - git config user.name "GitLab CI"
    - git config user.email "ci@gitlab.internal"
    - git add k8s/deployment.yaml
    - git commit -m "Update ${CI_PROJECT_NAME} to ${IMAGE_TAG}"
    - git push origin main
  only:
    - main
  when: manual
```

### ArgoCD Sync Pipeline

```yaml
# .gitlab-ci.yml - ArgoCD sync trigger
stages:
  - sync

argocd-sync:
  stage: sync
  tags:
    - shell
  script:
    - argocd login argocd.internal --grpc-web --username admin --password "$ARGOCD_PASSWORD"
    - argocd app sync ${CI_PROJECT_NAME} --prune
    - argocd app wait ${CI_PROJECT_NAME} --health
  only:
    - main
  when: manual
```

---

## Integrating with ArgoCD

### Connect ArgoCD to GitLab

```yaml
# ArgoCD repository connection
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://gitlab.internal/infrastructure/k8s-manifests.git
  username: argocd-robot
  password: "***"
---
# ArgoCD application that reads from GitLab
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: workload-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.internal/infrastructure/k8s-manifests.git
    targetRevision: main
    path: apps/workload/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: workload
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## GitLab Backup & Restore

### Automated Backup

```bash
# /etc/cron.d/gitlab-backup
# Daily backup at 2 AM
0 2 * * * root /opt/gitlab/bin/gitlab-backup create CRON=1

# Backup configuration separately
0 2 * * * root cp /etc/gitlab/gitlab.rb /var/opt/gitlab/backups/gitlab.rb.$(date +\%F)
0 2 * * * root cp /etc/gitlab/gitlab-secrets.json /var/opt/gitlab/backups/gitlab-secrets.json.$(date +\%F)
```

### Backup to Ceph RGW / MinIO

```ruby
# /etc/gitlab/gitlab.rb
# Upload backups to S3 (Ceph RGW or MinIO)

gitlab_rails['backup_upload_connection'] = {
  'provider' => 'AWS',
  'region' => 'us-east-1',
  'aws_access_key_id' => '***',
  'aws_secret_access_key' => '***',
  'endpoint' => 'http://rgw.internal:8080',
  'force_path_style' => true
}
gitlab_rails['backup_upload_remote_directory'] = 'gitlab-backups'
```

### Restore Procedure

```bash
# Stop services
gitlab-ctl stop puma
gitlab-ctl stop sidekiq

# Restore from backup
BACKUP_TIMESTAMP=$(ls /var/opt/gitlab/backups/ | tail -1 | sed 's/_gitlab_backup.tar//')
gitlab-backup restore BACKUP=$BACKUP_TIMESTAMP

# Restart
gitlab-ctl restart
gitlab-rake gitlab:check SANITIZE=true
```

---

## GitLab High Availability (Optional)

For production HA on the management cluster:

```yaml
# GitLab HA on K8s with Helm
# Requires: external PostgreSQL, external Redis, object storage

global:
  # Anti-affinity for pod distribution
  pod:
    antiAffinityLabels:
      - topology.kubernetes.io/zone

# Gitaly (Git storage) - 3 replicas
gitaly:
  persistence:
    storageClass: cephfs
    size: 100Gi
  resources:
    requests:
      cpu: "1"
      memory: "4Gi"

# Webservice (Puma) - 3 replicas
webservice:
  minReplicas: 3
  maxReplicas: 5
  persistence:
    enabled: false

# Sidekiq - 3 replicas
sidekiq:
  minReplicas: 3
  maxReplicas: 5
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Runner cannot connect | TLS cert not trusted | Copy internal CA to `/etc/gitlab-runner/certs/` |
| Pipeline fails on `docker build` | Docker not installed on runner | Install Docker on shell runner host |
| ArgoCD cannot clone repo | Secret misconfigured | Verify repo credentials in ArgoCD |
| Backup upload fails | S3 credentials wrong | Verify RGW/MinIO credentials |
| 502 errors | Puma workers not ready | Increase `puma['worker_processes']` |
| Disk full | Logs/artifacts accumulation | Configure cleanup policies |
