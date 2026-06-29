# Kubernetes Addons Guide

> Recommended addons for enterprise cloud-native deployments

---

## 1. Classification of Addons

Addons are grouped by function. Not all are required — choose based on your needs.

| Category | Addon | Priority | When to Use |
|----------|-------|----------|-------------|
| **Policy** | Kyverno | High | Replace PSP (deprecated), enforce compliance |
| **Policy** | Gatekeeper | High | Constraint-based policy enforcement |
| **Security** | Falco | High | Runtime threat detection |
| **Security** | Trivy Operator | High | Image vulnerability scanning |
| **Security** | cert-manager | High | Already covered — automated TLS |
| **Security** | Vault (HashiCorp) | Medium | External secrets management |
| **Networking** | Cilium (CNI) | Medium | Replace Calico for eBPF observability |
| **Networking** | CoreDNS Autoscaler | Medium | Scale CoreDNS based on load |
| **Observability** | metrics-server | High | Resource metrics for HPA |
| **Observability** | kube-state-metrics | High | K8s object metrics |
| **Observability** | Grafana Loki | Already covered | Log aggregation |
| **Cost** | OpenCost | Medium | Cost visibility per namespace |
| **Cost** | Kubecost | Medium | Advanced cost analysis |
| **Backup** | Velero | Already covered | Already covered |
| **Ingress** | NGINX Ingress | Already covered | Already covered |
| **GitOps** | ArgoCD | Already covered | Already covered |
| **Service Mesh** | Istio | Low | Only if mTLS between services is needed |
| **Service Mesh** | Linkerd | Low | Lighter alternative to Istio |
| **Multicluster** | Karmada | Low | Multi-cluster orchestration |
| **Local Storage** | Rook-Ceph / OpenEBS | Medium | if not using external Ceph |

---

## 2. Policy Engine: Kyverno vs Gatekeeper

### 2.1 Kyverno (Recommended for Most Cases)

| Aspect | Details |
|--------|---------|
| **Language** | YAML-native (no Rego/OPA needed) |
| **Scope** | Validate, mutate, generate resources |
| **Ease of use** | Very easy — policies are simple YAML |
| ** Mutating** | Built-in support (mutating policies) |
| **Generating** | Built-in (auto-create resources) |
| **Background scan** | Yes — continuously checks existing resources |
| **Reporting** | Native policy reports (Kyverno Reporter) |
| **Performance** | Very fast, low overhead |
| **Best for** | Teams that want simple YAML policies without learning Rego |

**Example Policy — Enforce resource limits:**

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resources
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: check-limits
      match:
        any:
          - resources:
              kinds:
                - Deployment
                - StatefulSet
      validate:
        message: "All containers must have resource limits and requests."
        pattern:
          spec:
            containers:
              - name: "*"
                resources:
                  limits:
                    memory: "?*"
                    cpu: "?*"
                  requests:
                    memory: "?*"
                    cpu: "?*"
```

**Example Policy — Enforce trusted registry:**

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: allow-trusted-registries
spec:
  validationFailureAction: Enforce
  rules:
    - name: trusted-registries
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Only images from trusted registries are allowed."
        pattern:
          spec:
            containers:
              - name: "*"
                image: "harbor.internal.lan/* | nexus.internal.lan:5000/*"
```

**Example Mutating Policy — Add default labels:**

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-default-labels
spec:
  rules:
    - name: add-labels
      match:
        any:
          - resources:
              kinds:
                - Namespace
      mutate:
        patchStrategicMerge:
          metadata:
            labels:
              environment: "production"
              managed-by: "k8s"
```

**Install Kyverno:**
```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set admissionController.replicas=3 \
  --set backgroundController.replicas=2 \
  --set cleanupController.replicas=2
```

### 2.2 Gatekeeper (OPA)

| Aspect | Details |
|--------|---------|
| **Language** | Rego (OPA policy language) |
| **Scope** | Validate only (no mutating) |
| **Ease of use** | Steeper learning curve |
| **Mutating** | Requires Separate Gatekeeper Mutation extension |
| **Generating** | No |
| **Background audit** | Yes — continuous compliance audit |
| **Reporting** | Constraint violations CRDs |
| **Performance** | Very fast |
| **Best for** | Teams familiar with Rego/OPA, complex policy logic |

**Example Constraint — Require labels:**

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-environment-label
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Namespace", "Deployment", "Service"]
  parameters:
    labels:
      - key: "environment"
      - key: "owner"
```

**Example ConstraintTemplate:**

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels
        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Missing required labels: %v", [missing])
        }
```

### 2.3 Kyverno vs Gatekeeper — When to Choose

| Scenario | Recommendation |
|----------|---------------|
| Team knows YAML, not Rego | **Kyverno** |
| Need mutating policies | **Kyverno** |
| Need auto-generate resources | **Kyverno** |
| Already using OPA elsewhere | **Gatekeeper** |
| Very complex policy logic | **Gatekeeper** (more expressive) |
| Compliance audit requirements | Both work; Gatekeeper has edge |
| Want both | **Yes — they coexist well** |

**Recommendation**: Start with **Kyverno** — it covers 90% of use cases with much lower operational overhead. Add Gatekeeper later if you need advanced Rego policies.

---

## 3. Security Addons

### 3.1 Falco — Runtime Security

Detects anomalous activity in containers at kernel level (eBPF).

**Detects:**
- Shell spawned inside container
- Sensitive file reads (`/etc/shadow`, `/etc/passwd`)
- Unexpected network connections
- Privilege escalation
- Binary execution outside allowlist

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set driver.kind=ebpf \
  --set collectors.enabled=false \
  --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=true
```

**Custom Rule Example:**

```yaml
- rule: Shell Spawned in Container
  desc: Detect shell spawned inside a container
  condition: >
    spawned_process and container and
    proc.name in (bash, sh, zsh, dash, ash) and
    not proc.pname in (cron, crond, supervisord)
  output: >
    Shell spawned in container
    (user=%user.name container=%container.name
     image=%container.image.repository
     shell=%proc.name parent=%proc.pname)
  priority: WARNING
  tags: [container, shell, mitre_execution]
```

### 3.2 Trivy Operator — Continuous Security Scanning

Scans images, configs, and cluster itself for vulnerabilities.

```bash
helm repo add aqua https://aquasecurity.github.io/helm-charts
helm repo update

helm install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --set operator.scannerReportTTL=24h \
  --set operator.scanNodeVulnerabilities=true
```

**What it produces:**
- VulnerabilityReports (per pod)
- ConfigAuditReports (per workload)
- ClusterComplianceReports
- SbomReports (SBOM generation)

### 3.3 HashiCorp Vault — Secrets Management

**Why Vault over native K8s Secrets:**
- Dynamic secrets (generate on-demand, expire)
- Encryption as a service
- PKI certificate management
- Audit logging
- Policy-based access

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "server.dev.enabled=false" \
  --set "injector.enabled=true" \
  --set "csi.enabled=true"
```

**External Secrets Operator (recommended companion):**
```bash
helm repo add external-secrets https://charts.external-secrets.io

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace
```

---

## 4. Observability Addons

### 4.1 metrics-server

Required for HPA (Horizontal Pod Autoscaler) and `kubectl top`.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Or via Helm
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args[0]=--kubelet-preferred-address-types=InternalIP \
  --set args[1]=--kubelet-insecure-tls
```

### 4.2 kube-state-metrics

Exports K8s object metrics ( deployment replicas, pod restarts, etc.)

```bash
helm repo add kube-state-metrics https://kubernetes-sigs.github.io/kube-state-metrics

helm install kube-state-metrics kube-state-metrics/kube-state-metrics \
  --namespace monitoring
```

### 4.3 node_exporter (Already in Prometheus stack)

Hardware and OS metrics. Deployed via kube-prometheus-stack.

---

## 5. Cost Management

### 5.1 OpenCost

Open-source cost monitoring (alternative to Kubecost).

```bash
helm repo add opencost https://opencost.github.io/opencost-helm-chart

helm install opencost opencost/opencost \
  --namespace opencost \
  --create-namespace \
  --set opencost.exporter.defaultClusterId=cluster1 \
  --set opencost.ui.enabled=true
```

**Metrics available:**
- cost per namespace
- cost per deployment
- cost per node
- idle cost allocation
- right-sizing recommendations

---

## 6. Service Mesh (Optional)

### 6.1 When You Need a Service Mesh
- mTLS required between all services
- Traffic policies (canary, blue-green)
- Observability at service level (latency, retries)
- Zero-trust networking

### 6.2 When You Don't Need a Service Mesh
- You use a simple ingress-based architecture
- You use NetworkPolicy for security
- You use cert-manager for TLS termination
- Your team wants to minimize operational complexity

### 6.3 Comparison

| Feature | Istio | Linkerd | Cilium Service Mesh |
|---------|-------|---------|---------------------|
| Weight | Heavy (~1GB/sidecar) | Light (~20MB/sidecar) | None (eBPF, no sidecar) |
| mTLS | Yes | Yes | Yes |
| Observability | Excellent | Good | Good |
| Complexity | High | Low | Low |
| Latency | Higher (sidecar) | Medium (sidecar) | Lowest (eBPF) |
| Learning curve | Steep | Moderate | Low |
| Community | Largest | Medium | Growing fast |

### 6.4 My Recommendation

For enterprise air-gapped deployments:
1. **Start with cert-manager** + **Calico NetworkPolicy** (no mesh)
2. Add **Cilium CNI** (if you want eBPF observability without sidecars)
3. Only add **Istio** if you absolutely need mTLS between all services or traffic splitting
4. **Linkerd** if you want mTLS without the Istio complexity

**Most enterprise deployments don't need a service mesh** — the operational overhead is significant. Use simpler alternatives first.

---

## 7. Multicluster Management

### 7.1 Why Multicluster?
- High availability across failure domains
- Geographic distribution
- Environment isolation (prod/staging in separate clusters)
- Avoid blast radius

### 7.2 Tools

| Tool | Purpose | Complexity |
|------|---------|------------|
| **ArgoCD** (multiple instances) | Per-cluster GitOps | Low |
| **Karmada** | Native K8s multicluster orchestration | Medium |
| **Rancher** | Fleet management across clusters | Low |
| **KubeFed** (deprecated) | Federated resources | High (deprecated) |
| **Liqo** | Cluster peering (shared services) | Medium |

### 7.3 My Recommendation
- **Rancher** if you're already using it — handles fleet management well
- **Karmada** if you want native K8s multicluster scheduling
- **ExternalDNS + ArgoCD** for DNS-based multi-cluster GitOps

---

## 8. Additional Recommended Addons

### 8.1 Goldilocks — VPA Dashboard

Shows Vertical Pod Autoscaler recommendations in a web UI.
```bash
helm repo add fairwinds https://charts.fairwinds.com/stable
helm install goldilocks fairwinds/goldilocks \
  --namespace goldilocks \
  --create-namespace
```

### 8.2 Descheduler — Rebalance Pods

Evicts pods that can be better placed (e.g., after adding nodes).
```bash
helm repo add descheduler https://kubernetes-sigs.github.io/descheduler
helm install descheduler descheduler/descheduler \
  --namespace kube-system \
  --set kind=Deployment
```

### 8.3 Kube-bench — CIS Security Benchmark

Runs CIS Kubernetes Benchmark checks.
```bash
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# View results
kubectl logs job/kube-bench -n default
```

### 8.4 Kubescape — Security Posture

Comprehensive security scanning (vulnerabilities, compliance, RBAC).
```bash
helm repo add armosec https://armosec.github.io/kubescape
helm install kubescape armosec/kubescape-cloud-operator \
  --namespace kubescape \
  --create-namespace
```

### 8.5 Reflector — Mirror Secrets/ConfigMaps

Automatically mirrors secrets to new namespaces.
```bash
helm repo add emberstack https://emberstack.github.io/helm-charts
helm install reflector emberstack/reflector \
  --namespace reflector \
  --create-namespace
```

### 8.6 Kubernetes Dashboard (Optional)

Web UI for basic management (ArgoCD CLI is better for daily operations).
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Get token
kubectl create token admin-user -n kubernetes-dashboard
```

---

## 9. Addon Selection Matrix

| Addon | Small Cluster | Medium Cluster | Enterprise | Air-Gap Friendly |
|-------|--------------|----------------|------------|-----------------|
| Kyverno | ✅ | ✅ | ✅ | ✅ |
| Gatekeeper | ❌ | ✅ | ✅ | ✅ |
| Falco | ❌ | ✅ | ✅ | ✅ |
| Trivy Operator | ❌ | ✅ | ✅ | ✅ |
| metrics-server | ✅ | ✅ | ✅ | ✅ |
| kube-state-metrics | ❌ | ✅ | ✅ | ✅ |
| OpenCost | ❌ | ✅ | ✅ | ✅ |
| cert-manager | ✅ | ✅ | ✅ | ✅ |
| External DNS | ❌ | ✅ | ✅ | ✅ |
| Goldilocks | ❌ | ✅ | ✅ | ✅ |
| Descheduler | ❌ | ✅ | ✅ | ✅ |
| Vault | ❌ | ❌ | ✅ | ✅ |
| Istio | ❌ | ❌ | Maybe | ❌ (large images, frequent updates) |
| Linkerd | ❌ | Maybe | ✅ | ✅ |
| Karmada | ❌ | ❌ | ✅ | ✅ |
| Goldilocks | ❌ | ✅ | ✅ | ✅ |

---

## 10. My Recommended Stack for Your Deployment

Based on what you've built so far (Ceph, Rancher, ArgoCD, KubeSpray, air-gap):

| Layer | Tool | Reason |
|-------|------|--------|
| **Policy** | **Kyverno** (without Gatekeeper) | YAML-native, mutating, generating — lower ops overhead |
| **Runtime Security** | **Falco** | Lightweight eBPF, great detection |
| **Image Scanning** | **Trivy Operator** | Continuous scanning of running workloads |
| **Secrets** | **HashiCorp Vault + ESO** | Dynamic secrets, audit trail |
| **Cost** | **OpenCost** | Free, air-gap friendly |
| **Observability** | kube-state-metrics + metrics-server | Already in your stack |
| **Service Mesh** | **None initially** | Add Cilium CNI later if needed |
| **Multicluster** | **Rancher Fleet** | Already using Rancher |
| **Right-sizing** | **Goldilocks + Descheduler** | Optimize resource usage |
| **Compliance** | **Kube-bench + Kyverno** | CIS benchmarks + policy enforcement |

### Prioritized Installation Order

```
Phase 1 (Immediate):  Kyverno, metrics-server
Phase 2 (Soon):       Falco, Trivy Operator
Phase 3 (Soon):       OpenCost, Goldilocks
Phase 4 (If needed): Vault, Istio/Linkerd
```
