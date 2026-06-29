# Multi-Cluster Architecture Guide

> Understanding multi-cluster Kubernetes — concepts, patterns, and when to use

---

## 1. What Is Multi-Cluster?

Multi-cluster means running **multiple separate Kubernetes clusters** that work together. Each cluster has its own control plane, nodes, and API server.

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│ Cluster 1 (Prod) │     │ Cluster 2 (Staging) │     │ Cluster 3 (DR) │
│ │     │ │     │ │
│ ┌───────────────┐ │     │ ┌───────────────┐ │     │ ┌───────────────┐ │
│ │ API Server │ │     │ │ API Server │ │     │ │ API Server │ │
│ └───────────────┘ │     │ └───────────────┘ │     │ └───────────────┘ │
│ │     │ │     │ │
│ ┌─────┐ ┌─────┐ │     │ ┌─────┐ ┌─────┐ │     │ ┌─────┐ ┌─────┐ │
│ │Node │ │Node │ │     │ │Node │ │Node │ │     │ │Node │ │Node │ │
│ └─────┘ └─────┘ │     │ └─────┘ └─────┘ │     │ └─────┘ └─────┘ │
│ │     │ │     │ │
│ ┌───────────────┐ │     │ ┌───────────────┐ │     │ ┌───────────────┐ │
│ │ etcd │ │     │ │ etcd │ │     │ │ etcd │ │
│ └───────────────┘ │     │ └───────────────┘ │     │ └───────────────┘ │
└─────────────────────┘     └─────────────────────┘     └─────────────────────┘
```

**Key point**: Each cluster is **independent**. They don't share etcd, they don't share nodes. They only share the network (if configured).

---

## 2. Why Use Multiple Clusters?

### 2.1 Isolation

| Pattern | Description | Use Case |
|---------|-------------|----------|
| **Environment isolation** | Separate clusters for dev/staging/prod | Prevent staging from affecting production |
| **Team isolation** | Each team gets their own cluster | No resource contention, no RBAC conflicts |
| **Workload isolation** | Critical apps in separate cluster | Blast radius reduction |
| **Compliance isolation** | PCI workloads in dedicated cluster | Audit scope reduction |

### 2.2 High Availability

| Pattern | Description | Use Case |
|---------|-------------|----------|
| **Active-Active** | Both clusters serve traffic | Load distribution |
| **Active-Passive** | Primary cluster active, DR idle | Disaster recovery |
| **Geographic** | Clusters in different regions | Low latency for users |

### 2.3 Resource Scaling

| Pattern | Description | Use Case |
|---------|-------------|----------|
| **Horizontal** | Add more clusters when one is full | Beyond single-cluster limits |
| **Vertical** | Different node sizes per cluster | GPU cluster, high-memory cluster |

---

## 3. Multi-Cluster vs Single Cluster

### 3.1 Single Cluster (What You Have Now)

```
┌─────────────────────────────────────────────────────┐
│ Single Cluster │
│ │
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│ │ Namespace│ │Namespace │ │Namespace │ │Namespace │ │
│ │ Prod │ │Staging │ │Dev │ │Monitoring│ │
│ └──────────┘ └──────────┘ └──────────┘ └──────────┘ │
│ │
│ Shared: API server, etcd, nodes, network │
└─────────────────────────────────────────────────────┘
```

**Pros:**
- Simpler to manage
- Shared resources (no idle capacity waste)
- Single pane of glass
- Easier networking between services

**Cons:**
- Blast radius: if cluster goes down, everything goes down
- No hard isolation between environments
- Single-cluster limits (5000 nodes, 150000 pods)
- All teams share the same API server (API contention)

### 3.2 Multiple Clusters

```
┌─────────────────────┐ ┌─────────────────────┐
│ Production Cluster │ │ Staging Cluster │
│ │ │
│ ┌──────────┐ │ │ ┌──────────┐ │
│ │ Prod Apps │ │ │ │Staging Apps│ │
│ └──────────┘ │ │ └──────────┘ │
│ │ │
│ ┌──────────┐ │ │ ┌──────────┐ │
│ │Monitoring│ │ │ │ CI/CD │ │
│ └──────────┘ │ │ └──────────┘ │
└─────────────────────┘ └─────────────────────┘
```

**Pros:**
- Hard isolation between environments
- Independent failure domains
- Each cluster can have different versions
- No API contention between teams
- Geographic distribution

**Cons:**
- More complex to manage
- Resource overhead (each cluster needs control plane)
- Networking between clusters is harder
- Need to replicate configs/secrets

### 3.3 My Recommendation

**Start with a single cluster with strong namespacing.** Add clusters when:

1. You need **hard isolation** (compliance, security)
2. You hit **scaling limits** (>2000 nodes)
3. You need **geographic distribution** (latency < 50ms)
4. You have **multiple teams** that need full control

**For your deployment**: Single cluster is enough now. Plan for 2 clusters (prod + DR) when uptime requirements demand it.

---

## 4. Multi-Cluster Patterns

### 4.1 Environment-Based (Most Common)

```
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│ Dev Cluster │ │ Staging Cluster │ │ Prod Cluster │
│ │ │ │ │ │
│ - Developer apps │ │ - Pre-prod apps │ │ - Production │
│ - CI/CD runners │ │ - QA testing │ │ - Live traffic │
│ - Feature flags │ │ - Performance │ │ - Critical data │
│ │ │ │ │ │
│ Small (2 nodes) │ │ Medium (3 nodes) │ │ Large (5+ nodes) │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

**How it works:**
- Each environment is a separate cluster
- Code promoted via CI/CD pipelines
- Each cluster has independent configs
- No shared resources between environments

### 4.2 Disaster Recovery (Active-Passive)

```
┌──────────────────┐ ┌──────────────────┐
│ Active Cluster │ │ Passive Cluster │
│ (Production) │ │ (DR) │
│ │ │ │
│ - All traffic │ │ - No traffic │
│ - Real-time │ │ - Sync from │
│ │ │ active │
│ │ │ │
│ ┌──────────┐ │ │ ┌──────────┐ │
│ │ Velero │ │ │ │ Velero │ │
│ │ (backup) │ │ │ │ (restore) │ │
│ └──────────┘ │ │ └──────────┘ │
└──────────────────┘ └──────────────────┘
```

**How it works:**
- Active cluster serves all traffic
- Passive cluster is idle (or runs minimal workloads)
- Velero backs up from active, restores to passive
- If active fails, switch DNS to passive
- RPO (Recovery Point Objective): depends on backup frequency
- RTO (Recovery Time Objective): time to switch DNS + restore

### 4.3 Geographic Distribution (Active-Active)

```
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│ US-East Cluster │ │ EU-West Cluster │ │ Asia Cluster │
│ │ │ │ │ │
│ - US users │ │ - EU users │ │ - Asia users │
│ - Low latency │ │ - Low latency │ │ - Low latency │
│ │ │ │ │ │
│ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │
│ │ App │ │ │ │ App │ │ │ │ App │ │
│ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │
│ │ │ │ │ │
│ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │
│ │ DB │ │ │ │ DB │ │ │ │ DB │ │
│ │ (primary) │ │ │ │ (replica) │ │ │ │ (replica) │ │
│ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

**How it works:**
- Each cluster serves users in its region
- Database replication between clusters
- Global load balancer routes users to nearest cluster
- Each cluster can operate independently if others fail

### 4.4 Workload Specialization

```
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│ General Cluster │ │ GPU Cluster │ │ Storage Cluster │
│ │ │ │ │ │
│ - Web apps │ │ - ML training │ │ - Ceph │
│ - APIs │ │ - Inference │ │ - MinIO │
│ - Microservices │ │ - Data science │ │ - NFS │
│ │ │ │ │ │
│ CPU nodes │ │ GPU nodes │ │ High-disk nodes │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

---

## 5. Multi-Cluster Management Tools

### 5.1 Rancher (You Already Have)

Rancher can manage multiple clusters from a single UI.

```
┌─────────────────────────────────────────────────────┐
│ Rancher Server │
│ │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ │
│ │ Cluster 1 │ │ Cluster 2 │ │ Cluster 3 │ │
│ │ (imported) │ │ (imported) │ │ (provisioned)│ │
│ └─────────────┘ └─────────────┘ └─────────────┘ │
└─────────────────────────────────────────────────────┘
```

**How to add a cluster:**
1. In Rancher UI → Cluster Management → Import Existing
2. Copy the kubectl command
3. Run on the target cluster
4. Cluster appears in Rancher dashboard

### 5.2 ArgoCD (Per Cluster)

Each cluster runs its own ArgoCD instance. They're independent.

```
┌──────────────┐ ┌──────────────┐
│ Cluster 1 │ │ Cluster 2 │
│ │ │ │
│ ┌──────────┐ │ │ ┌──────────┐ │
│ │ ArgoCD │ │ │ │ ArgoCD │ │
│ │ │ │ │ │ │ │
│ │ Watches: │ │ │ │ Watches: │ │
│ │ - Git repo│ │ │ │ - Git repo│ │
│ │ - Apps │ │ │ │ - Apps │ │
│ └──────────┘ │ │ └──────────┘ │
└──────────────┘ └──────────────┘
```

**How to set up:**
```bash
# Install ArgoCD on each cluster
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Create Application pointing to Git repo
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.internal/org/apps.git
    targetRevision: HEAD
    path: apps/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: production
EOF
```

### 5.3 Karmada (Multi-Cluster Orchestration)

Karmada lets you deploy to multiple clusters from a single YAML manifest.

```
┌─────────────────────────────────────────────────────┐
│ Karmada Control Plane │
│ │
│ Single manifest → deploys to multiple clusters │
│ │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ │
│ │ Cluster 1 │ │ Cluster 2 │ │ Cluster 3 │ │
│ │ (member) │ │ (member) │ │ (member) │ │
│ └─────────────┘ └─────────────┘ └─────────────┘ │
└─────────────────────────────────────────────────────┘
```

**Example — Deploy to all clusters:**

```yaml
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: app-propagation
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      name: my-app
  placement:
    clusterAffinity:
      clusterNames:
        - cluster-1
        - cluster-2
        - cluster-3
  replicaScheduling:
    replicaDivisionPreference: Weighted
    replicaSchedulingType: Divided
    weightPreference:
      staticWeightList:
        - targetCluster:
            clusterNames: [cluster-1]
          weight: 1
        - targetCluster:
            clusterNames: [cluster-2]
          weight: 1
```

### 5.4 Cluster API (CAPI)

Cluster API provisions and manages the lifecycle of clusters declaratively.

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: production-cluster
spec:
  controlPlaneRef:
    name: production-control-plane
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
  infrastructureRef:
    name: production-infra
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: DockerCluster  # or AWSCluster, AzureCluster, etc.
```

---

## 6. Multi-Cluster Networking

### 6.1 Service Discovery Across Clusters

Services in one cluster are not automatically discoverable from another cluster.

**Solutions:**

| Tool | How It Works | Complexity |
|------|-------------|------------|
| **ExternalDNS** | Creates DNS records for services | Low |
| **Submariner** | Connects services across clusters via VPN | Medium |
| **Cilium Cluster Mesh** | Native service routing via eBPF | Medium |
| **Istio Multi-Cluster** | Service mesh across clusters | High |
| **Skupper** | Application-layer networking | Medium |

### 6.2 Submariner (Recommended for Most)

```bash
# Install Submariner on both clusters
subctl join --kubeconfig cluster1-config ./cluster2-info.exported.yaml \
  --clusterid cluster1 --natt=false

# Verify
subctl show connections --kubeconfig cluster1-config

# Services are now accessible via:
# <service>.<namespace>.svc.clusterset.local
```

---

## 7. Multi-Cluster Storage

### 7.1 Velero Cross-Cluster Backup

```bash
# Cluster 1: Backup to shared S3
velero install --bucket velero-backups \
  --secret-file credentials \
  --backup-location-config region=minio,s3Url=http://shared-minio:9000

# Cluster 2: Restore from same S3
velero install --bucket velero-backups \
  --secret-file credentials \
  --backup-location-config region=minio,s3Url=http://shared-minio:9000

velero restore create --from-backup latest
```

### 7.2 Ceph RBD Cross-Cluster

```bash
# Both clusters can use the same Ceph cluster
# Each cluster gets its own pool or user
ceph osd pool create k8s-cluster1 128
ceph osd pool create k8s-cluster2 128

# Create separate keyrings for each cluster
ceph auth get-or-create client.cluster1 \
  mon 'profile rbd' osd 'profile rbd pool=k8s-cluster1' \
  mgr 'profile rbd pool=k8s-cluster1'
```

---

## 8. Decision Matrix

| Question | Single Cluster | Multi-Cluster |
|----------|---------------|---------------|
| How many teams? | 1-3 | 4+ |
| How many nodes? | < 1000 | > 1000 |
| Compliance isolation needed? | No | Yes |
| Geographic distribution? | No | Yes |
| 99.99% uptime required? | No | Yes |
| Team autonomy needed? | No | Yes |
| Budget for extra control planes? | No | Yes |

---

## 9. My Recommendation for Your Deployment

**Current state**: Single cluster is correct.

**Future plan** (when needed):

```
Phase 1 (Now): Single production cluster
  └── Namespaces for isolation (prod, staging, dev)
  └── RBAC for team access control
  └── NetworkPolicy for network isolation

Phase 2 (When needed): Add DR cluster
  └── Active-Passive with Velero backup/restore
  └── Same region, different failure domain
  └── Switch DNS when primary fails

Phase 3 (When needed): Add geographic clusters
  └── Active-Active with global load balancing
  └── Database replication between regions
  └── Submariner for cross-cluster services

Phase 4 (If needed): Karmada for orchestration
  └── Single manifest → multiple clusters
  └── Automatic failover between clusters
  └── Centralized policy management
```

**When to add a second cluster:**
- When you need 99.99% uptime (single cluster can't guarantee this)
- When compliance requires physical isolation
- When you hit scaling limits
- When you need geographic distribution
