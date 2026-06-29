# Rancher — Platform Guide

## Overview

Rancher is a centralized management platform for Kubernetes clusters. It runs on the **management cluster** and provides RBAC, multi-cluster management, monitoring, logging, CIS scanning, and app deployment.

> **Air-gap note:** All Rancher images (server, agent, UI) must be mirrored to Harbor. Helm charts are served from Nexus.

---

## Deployment via Helm on Management Cluster

### Prerequisites

- cert-manager installed and a ClusterIssuer configured
- NGINX Ingress Controller deployed
- Internal CA certificate trusted

### Add Helm Repo (Nexus — Air-gapped)

```bash
helm repo add rancher https://nexus.internal.example.com/repository/helm-rancher/
helm repo update
```

### Install Rancher

```bash
helm upgrade --install rancher rancher/rancher \
  --namespace cattle-system \
  --create-namespace \
  -f rancher-values.yaml
```

### Values File

```yaml
# rancher-values.yaml
hostname: rancher.example.com

# TLS configuration — uses cert-manager
ingress:
  tls:
    source: rancher       # Rancher generates certs via cert-manager
  configurationSnippet: |
    proxy-buffer-size "16k";

# Private registry (air-gap)
privateRegistry:
  url: harbor.internal.example.com
  user: rancher-pull
  password: "${HARBOR_PASSWORD}"
  # CA cert for Harbor TLS
  caCert: |
    -----BEGIN CERTIFICATE-----
    MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRJP...
    -----END CERTIFICATE-----

# Replicas
replicas: 3

# Resource limits
resources:
  requests: { cpu: 500m, memory: 512Mi }
  limits:   { cpu: 2000m, memory: 2Gi }

# cert-manager issuer reference
certmanager:
  issuerName: internal-ca
  issuerType: ClusterIssuer
  issuerRancherCAName: internal-ca

# Features
features:
  multiClusterManagement: true
  multiClusterApps: true
  monitoring: true
  logging: true
  istio: false
  fleet: true

# Bootstrap password (set on first install)
bootstrapPassword: "initial-admin-password"

# Additional CA certs to trust
additionalTrustedCAs: |
  -----BEGIN CERTIFICATE-----
  <internal-ca-cert-here>
  -----END CERTIFICATE-----
```

### Custom CA Certificate

If using a custom TLS certificate instead of cert-manager auto-generation:

```yaml
ingress:
  tls:
    source: secret
    secretName: rancher-tls
```

```bash
# Create the TLS secret
kubectl create secret tls rancher-tls \
  --cert=rancher.crt --key=rancher.key \
  -n cattle-system
```

---

## Initial Admin Password Setup

After first deployment, retrieve the bootstrap password:

```bash
# Get initial password
kubectl get secret --namespace cattle-system bootstrap-secret \
  -o go-template='{{.data.bootstrapPassword|base64decode}}{{"\n"}}'
```

Then access `https://rancher.example.com` and:
1. Log in with admin / bootstrap password
2. Set a new strong admin password
3. Configure server URL (must match the hostname)

---

## Adding Application Cluster to Rancher

### Registered Cluster (Recommended for Air-gap)

1. In Rancher UI: **Clusters → Create → Register existing cluster**
2. Select `Import` mode
3. Copy the registration command, e.g.:

```bash
kubectl apply -f https://rancher.example.com/v3/import/xxx.yaml
```

> **Air-gap:** The import YAML references `rancher-agent` images. These must be available in Harbor.

### rancher-agent Air-gap Configuration

The `cattle-cluster-agent` and `cattle-node-agent` must pull images from Harbor:

```yaml
# cattle-cluster-agent Deployment patch
spec:
  template:
    spec:
      containers:
      - name: cluster-register
        image: harbor.internal.example.com/rancher/rancher-agent:v2.8.3
      imagePullSecrets:
      - name: harbor-registry-secret
```

Set the private registry in the cluster registration:

```bash
# When importing cluster, set cluster agent custom values
clusterAgent:
  image: harbor.internal.example.com/rancher/rancher-agent:v2.8.3
  imagePullSecrets:
  - name: harbor-registry-secret
```

### Create Harbor Registry Secret

```bash
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=harbor.internal.example.com \
  --docker-username=rancher-pull \
  --docker-password="${HARBOR_PASSWORD}" \
  -n cattle-system
```

---

## RBAC and Authentication

### LDAP/Active Directory Integration

1. **Rancher UI → Users & Authentication → External Authentication**
2. Configure LDAP/AD:

| Setting | Value |
|---------|-------|
| Hostname | `ad.internal.example.com` |
| Port | 636 (LDAPS) |
| TLS | Enabled |
| CA Certificate | Internal CA cert |
| Service Account DN | `CN=rancher-bind,OU=ServiceAccounts,DC=example,DC=com` |
| User Search Base | `OU=Users,DC=example,DC=com` |
| Group Search Base | `OU=Groups,DC=example,DC=com` |
| User Login Attribute | `sAMAccountName` |
| Group Member Attribute | `member` |

> **Air-gap:** Ensure the LDAP server is reachable from the management cluster network.

### RBAC Roles

| Role | Scope | Use Case |
|------|-------|----------|
| Administrator | Global | Platform team |
| Cluster Owner | Cluster | Cluster admins |
| Cluster Member | Cluster | Read-only cluster access |
| Project Owner | Project | App team leads |
| Project Member | Project | Developers |
| Restricted | Project | Limited dev access |

### Custom Roles

```yaml
# custom-role.yaml
apiVersion: management.cattle.io/v3
kind: RoleTemplate
metadata:
  name: deploy-only
displayName: Deploy Only
description: Can only deploy apps, no delete
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "create", "update"]
```

---

## Project and Namespace Management

### Create Project

```bash
# Via Rancher CLI or UI
rancher projects:create \
  --cluster app-cluster \
  --name "team-alpha" \
  --description "Team Alpha Workloads"
```

### Namespace Resource Quotas

```yaml
apiVersion: management.cattle.io/v3
kind: ProjectResourceQuota
metadata:
  name: team-alpha-quota
spec:
  namespaceDefaultResourceQuota:
    limit:
      limitsCpu: "4"
      limitsMemory: "8Gi"
      pods: "20"
      requestsStorage: "50Gi"
  resourceQuota:
    limit:
      limitsCpu: "16"
      limitsMemory: "32Gi"
      pods: "100"
      requestsStorage: "200Gi"
```

---

## Rancher Monitoring (Built-in)

Rancher includes a built-in monitoring stack based on kube-prometheus-stack.

1. **Cluster → Apps → Monitoring** → Enable
2. Configure alerting and receivers in the UI

> For production, prefer deploying monitoring via ArgoCD/GitOps rather than Rancher built-in, for better version control and reproducibility.

---

## Rancher Logging (Built-in)

1. **Cluster → Apps → Logging** → Enable
2. Configure outputs (Loki, Elasticsearch, etc.)

> Same recommendation as monitoring — prefer GitOps-managed logging for production.

---

## Rancher CIS Scan

Run CIS benchmarks against cluster configuration:

1. **Cluster → Security → CIS Scan** → Run Scan
2. Review results for PASS/WARN/FAIL per benchmark

### CIS Scan Profiles

| Profile | Benchmark | Kubernetes Versions |
|---------|-----------|---------------------|
| CIS Kubernetes 1.8 | CIS-1.8 | 1.26-1.29 |
| CIS Kubernetes 1.23 | CIS-1.23 | 1.23-1.25 |
| rke2-cis-1.23 | RKE2-specific | RKE2 1.23+ |

---

## Rancher Backup/Restore

 Rancher Backup operator captures the complete Rancher state.

### Install Backup Operator

```bash
helm upgrade --install rancher-backup-crd rancher-backup-crd \
  --namespace cattle-resources-system --create-namespace
helm upgrade --install rancher-backup rancher-backup \
  --namespace cattle-resources-system
```

### Create Backup

```yaml
apiVersion: resources.cattle.io/v1
kind: Backup
metadata:
  name: rancher-full-backup
spec:
  resourceSelector:
    includeResources:
    - "*"
  storageLocation:
    s3:
      endpoint: s3.internal.example.com
      bucketName: rancher-backup
      region: default
      credentialSecretName: s3-credentials
  encryptionConfigSecretName: rancher-backup-encryption
```

---

## Multi-cluster App Deployment

Rancher Fleet provides GitOps-based multi-cluster deployment:

```yaml
# GitRepo for Fleet
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: platform-apps
  namespace: fleet-default
spec:
  repo: https://gitlab.internal.example.com/platform/fleet-apps.git
  branch: main
  paths:
  - clusters/app-cluster
  targets:
  - clusterSelector:
      matchLabels:
        env: production
```

---

## Air-gap: Private Registry Configuration

### Required Images for Rancher

| Component | Image |
|-----------|-------|
| Rancher Server | `rancher/rancher:v2.8.3` |
| Rancher Agent | `rancher/rancher-agent:v2.8.3` |
| Rancher CLI | `rancher/rancher-cli:v2.8.3` |
| Fleet Agent | `rancher/fleet-agent:v0.9.5` |
| Shell | `rancher/shell:v0.2.2` |

### Mirror to Harbor

```bash
#!/bin/bash
HARBOR=harbor.internal.example.com/rancher
VERSION=v2.8.3
for IMG in rancher rancher-agent rancher-cli; do
  SRC="rancher/${IMG}:${VERSION}"
  DST="${HARBOR}/${IMG}:${VERSION}"
  docker pull "$SRC" && docker tag "$SRC" "$DST" && docker push "$DST"
done
```

### CA Certificate Trust

All clusters must trust the internal CA:

```bash
# On each node (RKE2/RancherOS)
cp internal-ca.crt /etc/ssl/certs/
update-ca-certificates
```

For RKE2, add to config:

```yaml
# /etc/rancher/rke2/config.yaml
tls-san:
  - rancher.example.com
```
