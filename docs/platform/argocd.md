# ArgoCD — Platform Guide

## Overview

ArgoCD is a declarative GitOps continuous delivery tool for Kubernetes. It runs on the **management cluster** and deploys applications to both management and application clusters.

> **Air-gap note:** All ArgoCD images from Harbor. Repo server connects to internal GitLab only. No external internet access required.

---

## Deployment via Helm on Management Cluster

### Add Helm Repo (Nexus — Air-gapped)

```bash
helm repo add argocd https://nexus.internal.example.com/repository/helm-argocd/
helm repo update
```

### Values File

```yaml
# argocd-values.yaml
global:
  image:
    repository: harbor.internal.example.com/platform/argocd
    tag: v2.11.3
    imagePullPolicy: IfNotPresent

configs:
  cm:
    # Resource tracking method (annotation-based recommended for v2.11+)
    application.resourceTrackingMethod: annotation
    # Disable download capabilities (air-gap)
    exec.enabled: false
  params:
    # Repo server uses local GitLab
    reposerver.repo.server: argocd-repo-server.argocd.svc.cluster.local
  rbac:
    policy.csv: |
      g, platform-admins, role:admin
      g, developers, role:readonly
  secret:
    # argocd-secret — set via sealed secrets or external-secrets

controller:
  replicas: 2
  resources:
    requests: { cpu: 250m, memory: 256Mi }
    limits:   { cpu: 1000m, memory: 1Gi }

repoServer:
  replicas: 2
  resources:
    requests: { cpu: 100m, memory: 128Mi }
    limits:   { cpu: 500m, memory: 512Mi }

server:
  replicas: 2
  resources:
    requests: { cpu: 100m, memory: 128Mi }
    limits:   { cpu: 500m, memory: 512Mi }
  ingress:
    enabled: true
    ingressClassName: nginx
    hostname: argocd.example.com
    tls: true
    annotations:
      cert-manager.io/cluster-issuer: internal-ca

redis:
  resources:
    requests: { cpu: 50m, memory: 64Mi }
    limits:   { cpu: 250m, memory: 256Mi }

dex:
  enabled: true
  resources:
    requests: { cpu: 50m, memory: 64Mi }
    limits:   { cpu: 250m, memory: 256Mi }

# ServiceMonitor for Prometheus
serviceMonitor:
  enabled: true
  labels: { release: kube-prometheus-stack }
```

```bash
helm upgrade --install argocd argocd/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f argocd-values.yaml
```

---

## Initial Admin Password

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-secret \
  -o jsonpath='{.data.admin\.password}' | base64 -d
echo

# Port-forward for initial access
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login via CLI
argocd login argocd.example.com --username admin --password <password>

# Change password
argocd account update-password
```

---

## Connecting GitLab Repository

### Internal GitLab (Air-gap)

```bash
# Add repository via CLI
argocd repo add https://gitlab.internal.example.com/platform/app-manifests.git \
  --username git --password <git-token>

# Or via SSH
argocd repo add git@gitlab.internal.example.com:platform/app-manifests.git \
  --ssh-private-key-path ~/.ssh/id_ed25519
```

### Repository Credential Template

For multiple repos with shared credentials:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-credentials
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  url: https://gitlab.internal.example.com
  username: git
  password: <git-token>
```

### Configure via ArgoCD ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  repositories: |
    - url: https://gitlab.internal.example.com/platform/app-manifests.git
      type: git
    - url: https://gitlab.internal.example.com/platform/helm-charts.git
      type: helm
      name: internal-charts
```

---

## SSO/LDAP Integration

Configure Dex for LDAP/Active Directory:

```yaml
# argocd-values.yaml (dex section)
configs:
  cm:
    dex.config: |
      connectors:
      - type: ldap
        name: ActiveDirectory
        config:
          host: ad.internal.example.com:636
          insecureNoSSL: false
          startTLS: true
          bindDN: CN=argocd-bind,OU=ServiceAccounts,DC=example,DC=com
          bindPW: ${LDAP_BIND_PASSWORD}
          usernamePrompt: "Username"
          userSearch:
            baseDN: OU=Users,DC=example,DC=com
            filter: "(objectClass=user)"
            username: sAMAccountName
            idAttr: DN
            emailAttr: mail
            nameAttr: displayName
          groupSearch:
            baseDN: OU=Groups,DC=example,DC=com
            filter: "(objectClass=group)"
            userMatchers:
            - userAttr: DN
              groupAttr: member
            nameAttr: cn
```

---

## Application Creation and Management

### Application Manifest

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  labels:
    app: my-app
    environment: production
  annotations:
    notifications.argoproj.io/subscribe.on-deployed.slack: my-channel
spec:
  project: default
  source:
    repoURL: https://gitlab.internal.example.com/platform/app-manifests.git
    targetRevision: main
    path: apps/my-app/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### CLI Operations

```bash
# Sync application
argocd app sync my-app

# Get app status
argocd app get my-app

# Diff against Git
argocd app diff my-app

# List apps
argocd app list
```

---

## ApplicationSets for Multi-cluster Deployment

ApplicationSets generate Applications dynamically for multiple clusters:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform-apps
  namespace: argocd
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          environment: production
  template:
    metadata:
      name: '{{name}}-platform-apps'
    spec:
      project: default
      source:
        repoURL: https://gitlab.internal.example.com/platform/app-manifests.git
        targetRevision: main
        path: apps/platform-apps
      destination:
        server: '{{server}}'
        namespace: platform-apps
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Git Directory Generator

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: env-apps
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://gitlab.internal.example.com/platform/app-manifests.git
      revision: main
      directories:
      - path: apps/*/overlays/*
  template:
    metadata:
      name: '{{path.basename}}-{{path[2]}}'
    spec:
      project: default
      source:
        repoURL: https://gitlab.internal.example.com/platform/app-manifests.git
        targetRevision: main
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
```

---

## ArgoCD Notifications

Configure notifications for deployment events:

```yaml
# argocd-notifications-cm
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  context: |
    argocdUrl: https://argocd.example.com
  trigger.on-deployed: |
    - when: app.status.operationState.phase in [Succeeded]
      send: [app-deployed]
  trigger.on-health-degraded: |
    - when: app.status.health.status == Degraded
      send: [app-health-degraded]
  template.app-deployed: |
    message: |
      Application {{.app.metadata.name}} deployed successfully.
      Details: {{.context.argocdUrl}}/applications/{{.app.metadata.name}}
  service.webhook.internal-notify: |
    url: https://webhook.internal.example.com/notify
    headers:
      - name: Authorization
        value: Bearer $notification-token
```

---

## ArgoCD Image Updater

Automatically updates container images in Git when new images are pushed to the registry.

> **Air-gap consideration:** Image Updater monitors the Harbor registry. It must have network access to Harbor's API.

```yaml
# argocd-image-updater-values.yaml
image:
  repository: harbor.internal.example.com/platform/argocd-image-updater
  tag: v0.12.2

config:
  registries:
  - name: Harbor
    prefix: harbor.internal.example.com
    api_url: https://harbor.internal.example.com/v2
    credentials: secret:argocd/haror-creds#token
    default: true
    platforms: [linux/amd64, linux/arm64]
```

### Application Annotation for Image Update

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/git-branch: main
    argocd-image-updater.argoproj.io/image-list: |
      my-app=harbor.internal.example.com/apps/my-app:~1.0
spec:
  # ... application spec
```

---

## RBAC Configuration

```yaml
# argocd-rbac-cm
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    # Platform admins have full access
    g, platform-admins, role:admin
    # Developers can sync their apps only
    g, developers, role:developer
    # Read-only for auditors
    g, auditors, role:readonly
    # Project-level permissions
    p, role:developer, applications, sync, my-project/*, allow
    p, role:developer, applications, get, my-project/*, allow
  policy.default: role:readonly
  scopes: "[groups]"
```

---

## Resource Tracking

ArgoCD v2.11+ supports annotation-based tracking (recommended over label-based):

```yaml
# argocd-cm
data:
  application.resourceTrackingMethod: annotation
```

| Method | Pros | Cons |
|--------|------|------|
| Label | Works with older versions | 63-char limit, conflicts possible |
| Annotation | No 63-char limit, more reliable | Requires ArgoCD v2.11+ |

---

## Project Configuration

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: my-project
  namespace: argocd
spec:
  description: "My Application Project"
  sourceRepos:
  - "https://gitlab.internal.example.com/platform/*"
  destinations:
  - server: "https://kubernetes.default.svc"
    namespace: "my-app-*"
  - server: "https://app-cluster.example.com"
    namespace: "my-app-*"
  clusterResourceWhitelist:
  - group: ""
    kind: Namespace
  namespaceResourceBlacklist:
  - group: ""
    kind: ResourceQuota
  roles:
  - name: developer
    policies:
    - p, proj:my-project:developer, applications, *, my-project/*, allow
    groups:
    - developers
```

---

## Sync Policies

### Automated Sync (Recommended for Production)

```yaml
syncPolicy:
  automated:
    prune: true      # Delete resources no longer in Git
    selfHeal: true    # Revert manual cluster changes
    allowEmpty: false # Prevent accidental empty app
  syncOptions:
  - CreateNamespace=true
  - ServerSideApply=true
  - PrunePropagationPolicy=foreground
```

### Manual Sync (For Critical Apps)

```yaml
syncPolicy:
  syncOptions:
  - CreateNamespace=true
# Trigger manually: argocd app sync <app-name>
```

---

## Cross-cluster Deployment

ArgoCD on the management cluster deploys to the application cluster:

### Register App Cluster

```bash
# Add app cluster context to ArgoCD
argocd cluster add app-cluster-context \
  --name app-cluster \
  --grpc-web
```

### Deploy to App Cluster

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-cluster-workloads
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.internal.example.com/platform/app-manifests.git
    targetRevision: main
    path: clusters/app-cluster
  destination:
    name: app-cluster     # References the registered cluster
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## Air-gap: Images and Repository

### Required Images

| Component | Harbor Image |
|-----------|-------------|
| Server | `harbor.internal.example.com/platform/argocd:v2.11.3` |
| Repo Server | `harbor.internal.example.com/platform/argocd-repo-server:v2.11.3` |
| Controller | `harbor.internal.example.com/platform/argocd-application-controller:v2.11.3` |
| Redis | `harbor.internal.example.com/platform/redis:7.2.4-alpine` |
| Dex | `harbor.internal.example.com/platform/dex:v2.38.1` |
| Image Updater | `harbor.internal.example.com/platform/argocd-image-updater:v0.12.2` |

### Repo Server Uses Local GitLab

The repo server must only access internal GitLab:

```yaml
configs:
  cm:
    # Restrict repo server to internal GitLab only
    repositories: |
      - url: https://gitlab.internal.example.com
        type: git
```

Network policy to prevent external access:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-external-egress
  namespace: argocd
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: argocd-repo-server
  policyTypes: [Egress]
  egress:
  - to:
    - ipBlock:
        cidr: 10.0.0.0/8  # Internal network only
```

---

## ArgoCD as Single Source of Truth for GitOps

Key principles:

1. **All configuration in Git** — no manual kubectl apply
2. **ArgoCD syncs Git → Cluster** — never the reverse
3. **Drift detection** — ArgoCD detects out-of-sync resources
4. **Self-heal** — automated sync reverts manual changes
5. **Audit trail** — all changes tracked in Git history
6. **Declarative** — desired state declared in YAML, not imperative scripts

### GitOps Workflow

```
Developer → Git Push → GitLab → ArgoCD Detects Change → Syncs to Cluster
                                                  ↓
                                          Health Check & Alerts
```

### Directory Structure

```
app-manifests/
├── apps/
│   └── my-app/
│       ├── base/           # Shared kustomize base
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   └── kustomization.yaml
│       └── overlays/
│           ├── development/
│           └── production/
├── clusters/
│   ├── mgmt-cluster/       # Management cluster resources
│   └── app-cluster/        # Application cluster resources
├── platform/               # Platform components
│   ├── cert-manager/
│   ├── gatekeeper/
│   ├── monitoring/
│   └── logging/
└── infrastructure/         # Infra-level configs
    └── namespaces/
```
