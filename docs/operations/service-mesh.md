# Service Mesh Guide

> Understanding service mesh for Kubernetes — when to use, which one, and how it fits your deployment

---

## 1. What Is a Service Mesh?

A service mesh is a dedicated infrastructure layer for managing service-to-service communication in a microservices architecture. It provides:

- **mTLS** — automatic encryption between all services
- **Traffic management** — canary deployments, blue-green, circuit breaking
- **Observability** — latency, error rates, retries per service
- **Traffic policies** — timeouts, retries, rate limiting
- **Access control** — which services can talk to which

```
Without Mesh:
  Service A ────plain HTTP────→ Service B
  (no encryption, no observability, no policies)

With Mesh:
  Service A ──sidecar── mTLS ──sidecar── Service B
              (envoy)            (envoy)
  (encrypted, observable, policy-driven)
```

---

## 2. Do You Need a Service Mesh?

### 2.1 When You DON'T Need a Service Mesh

| Scenario | Alternative |
|----------|-------------|
| < 10 services | Direct HTTP + NetworkPolicy |
| All services in one namespace | Calico NetworkPolicy is enough |
| Only need TLS at ingress | cert-manager + NGINX Ingress |
| Simple request/response patterns | No mesh needed |
| Team < 5 people | Operational overhead too high |
| Latency-sensitive workloads | Sidecar adds ~1-3ms per hop |

### 2.2 When You DO Need a Service Mesh

| Scenario | Why |
|----------|-----|
| Compliance requires mTLS everywhere | PCI-DSS, HIPAA, FedRAMP |
| 20+ microservices with complex communication | Need observability and policies |
| Zero-trust networking required | Every connection must be authenticated |
| Canary/blue-green deployments | Traffic splitting per weight |
| Multi-cluster services | Cross-cluster mTLS |
| Need per-service metrics without code changes | Automatic telemetry |

### 2.3 My Recommendation for Your Deployment

**You probably don't need a service mesh right now.** Here's why:

1. **You have Calico** — provides NetworkPolicy for network-level security
2. **You have cert-manager** — provides TLS at ingress
3. **You have Prometheus/Grafana** — provides observability
4. **You have ArgoCD** — provides deployment management
5. **You have Kyverno/Gatekeeper** — provides policy enforcement

**What you get without a mesh:**
- ✅ NetworkPolicy for network isolation
- ✅ cert-manager for TLS certificates
- ✅ Prometheus for metrics
- ✅ ArgoCD for GitOps deployments
- ✅ Kyverno for policy enforcement
- ✅ No sidecar overhead
- ✅ No additional operational complexity

**What a mesh adds (that you don't have yet):**
- 🔒 mTLS between every pair of services (encrypted, authenticated)
- 📊 Per-service latency/error metrics (without code changes)
- 🔄 Canary deployments (5% traffic to new version)
- 🔁 Automatic retries with backoff
- 🚦 Circuit breaking (prevent cascade failures)

**Verdict**: Start without a mesh. Add one later when you actually need mTLS between services or canary deployments.

---

## 3. Service Mesh Comparison

### 3.1 Istio

| Aspect | Details |
|--------|---------|
| **Sidecar** | Envoy proxy per pod |
| **Resource usage** | ~100MB memory per sidecar, ~0.5 vCPU |
| **Control plane** | istiod (single binary) |
| **mTLS** | Automatic via SPIFFE |
| **Traffic management** | VirtualService, DestinationRule, Gateway |
| **Observability** | Kiali, Jaeger, Prometheus integration |
| **Learning curve** | Steep |
| **Community** | Largest (Google, IBM, Lyft) |
| **Maturity** | Very mature (v1.0 in 2018) |
| **Best for** | Large-scale, complex microservices |

**Pros:**
- Most feature-rich
- Best observability stack (Kiali dashboard)
- Most documentation and community support
- Supports multi-cluster natively

**Cons:**
- Heaviest resource usage
- Steepest learning curve
- Configuration can be overwhelming
- Overkill for small deployments

### 3.2 Linkerd

| Aspect | Details |
|--------|---------|
| **Sidecar** | Linkerd-proxy (Rust, ultra-light) |
| **Resource usage** | ~20MB memory per sidecar, ~0.1 vCPU |
| **Control plane** | linkerd-controller (small binaries) |
| **mTLS** | Automatic (no configuration needed) |
| **Traffic management** | ServiceProfile, TrafficSplit |
| **Observability** | linkerd-viz (dashboard) |
| **Learning curve** | Low |
| **Community** | Medium (CNCF, Buoyant) |
| **Maturity** | Mature (v1.0 in 2018) |
| **Best for** | Teams wanting simplicity |

**Pros:**
- Lightest resource usage
- Simplest to install and operate
- mTLS works out of the box (zero config)
- Rust-based proxy is very fast
- Excellent for small-medium deployments

**Cons:**
- Fewer features than Istio
- No advanced traffic policies (circuit breaking is basic)
- Smaller community
- No native multi-cluster support

### 3.3 Cilium Service Mesh

| Aspect | Details |
|--------|---------|
| **Sidecar** | None (eBPF in kernel) |
| **Resource usage** | Near-zero (kernel-level) |
| **Control plane** | Cilium operator |
| **mTLS** | Via WireGuard or IPsec |
| **Traffic management** | CiliumNetworkPolicy |
| **Observability** | Hubble (built-in) |
| **Learning curve** | Medium |
| **Community** | Growing fast (CNCF, Isovalent) |
| **Maturity** | Newer (service mesh features in 2022+) |
| **Best for** | Teams already using Cilium CNI |

**Pros:**
- No sidecars — lowest latency
- eBPF-based — kernel-level performance
- Built-in observability (Hubble)
- Network policies + service mesh in one
- Transparent encryption (no proxy)

**Cons:**
- Newer — less battle-tested for service mesh
- Requires kernel 5.10+
- Fewer features than Istio
- Smaller community than Istio/Linkerd

### 3.4 Consul Connect

| Aspect | Details |
|--------|---------|
| **Sidecar** | Envoy proxy per pod |
| **Resource usage** | ~100MB memory per sidecar |
| **Control plane** | Consul servers |
| **mTLS** | Automatic via Connect |
| **Traffic management** | Service Router, Service Splitter |
| **Observability** | Consul UI |
| **Learning curve** | Medium-High |
| **Community** | Medium (HashiCorp) |
| **Maturity** | Mature |
| **Best for** | Teams already using HashiCorp stack |

**Pros:**
- Integrates with Vault, Terraform, Nomad
- Multi-datacenter support
- Good UI
- Service discovery + mesh in one

**Cons:**
- Tied to HashiCorp ecosystem
- Heavier than Linkerd
- Consul can be complex to operate

---

## 4. Feature Comparison Matrix

| Feature | Istio | Linkerd | Cilium | Consul |
|---------|-------|---------|--------|--------|
| **Sidecar** | Envoy | linkerd-proxy | None (eBPF) | Envoy |
| **Memory/pod** | ~100MB | ~20MB | ~0 | ~100MB |
| **Latency overhead** | ~3ms | ~1ms | ~0.1ms | ~3ms |
| **mTLS** | ✅ Auto | ✅ Auto | ✅ WireGuard | ✅ Auto |
| **Canary** | ✅ | ✅ Basic | ❌ | ✅ Basic |
| **Circuit breaking** | ✅ | ✅ Basic | ❌ | ✅ |
| **Rate limiting** | ✅ | ❌ | ❌ | ✅ |
| **Observability** | Kiali+Jaeger | linkerd-viz | Hubble | Consul UI |
| **Multi-cluster** | ✅ Native | ❌ | ✅ | ✅ |
| **L7 policies** | ✅ Full | ✅ Basic | ✅ CiliumNetworkPolicy | ✅ |
| **L4 policies** | ✅ | ✅ | ✅ | ✅ |
| **Gateway** | ✅ Istio Gateway | ❌ | ✅ CiliumGateway | ✅ |
| **External auth** | ✅ OPA | ❌ | ❌ | ✅ |
| **Install complexity** | High | Low | Medium | Medium-High |
| **Operational overhead** | High | Low | Low-Medium | Medium |
| **CNCF** | ✅ | ✅ | ✅ | ❌ (HashiCorp) |

---

## 5. Architecture Deep Dive

### 5.1 Sidecar Pattern (Istio, Linkerd, Consul)

```
┌─────────────────────────────────────────┐
│ Pod │
│ ┌──────────────┐ ┌──────────────────┐ │
│ │ App Container │ │ Sidecar Proxy │ │
│ │ │ │ (Envoy/ │ │
│ │ Sends traffic │───→ linkerd) │ │
│ │ │ │ │ │
│ │ │ │ Intercepts, │ │
│ │ │ │ encrypts, │ │
│ │ │ │ forwards │ │
│ └──────────────┘ └──────────────────┘ │
│ │
└─────────────────────────────────────────┘
```

**How it works:**
1. Sidecar proxy is injected into each pod (automatically or manually)
2. All outbound traffic is intercepted by the sidecar
3. Sidecar looks up the destination service, finds the mTLS certificate
4. Encrypts traffic with mTLS, sends to destination sidecar
5. Destination sidecar decrypts, forwards to app container

### 5.2 eBPF Pattern (Cilium)

```
┌─────────────────────────────────────────┐
│ Pod │
│ ┌──────────────┐ │
│ │ App Container │ │
│ │ │ │
│ │ Sends traffic │──────┐ │
│ │ │ │ │
│ └──────────────┘ │ │
│ │ │
│ ┌─────────────────┘ │
│ │ Kernel (eBPF) │
│ │ │ │
│ │ • Intercepts │
│ │ • Encrypts (WireGuard) │
│ │ • Routes │
│ │ • Observes │
│ └─────────────────────────────┘
│
└─────────────────────────────────────────┘
```

**How it works:**
1. eBPF programs are loaded into the kernel
2. Traffic is intercepted at the kernel level (no userspace proxy)
3. Policies are applied in-kernel
4. Encryption via WireGuard or IPsec (kernel-native)
5. Hubble provides observability via eBPF

---

## 6. Performance Impact

### 6.1 Latency

| Mesh | P50 Latency | P99 Latency | Notes |
|------|------------|-------------|-------|
| No mesh | 0.1ms | 0.5ms | Direct connection |
| Linkerd | 0.3ms | 1.2ms | Rust proxy, minimal overhead |
| Istio | 0.5ms | 3.0ms | Envoy proxy, more features |
| Cilium | 0.15ms | 0.7ms | eBPF, near-zero overhead |
| Consul | 0.5ms | 2.5ms | Envoy proxy |

### 6.2 Resource Usage (per pod)

| Mesh | Memory | CPU | Notes |
|------|--------|-----|-------|
| No mesh | 0 | 0 | — |
| Linkerd | 20MB | 10m | Rust proxy |
| Istio | 100MB | 50m | Envoy proxy |
| Cilium | 0 | 0 | Kernel-level |
| Consul | 100MB | 50m | Envoy proxy |

### 6.3 For a 50-pod cluster:

| Mesh | Total Memory | Total CPU |
|------|-------------|-----------|
| No mesh | 0 | 0 |
| Linkerd | 1GB | 500m |
| Istio | 5GB | 2500m |
| Cilium | 0 | 0 |
| Consul | 5GB | 2500m |

---

## 7. Installation Guide (Conceptual)

> This is a discussion guide — not a full implementation. When you're ready to add a mesh, follow these steps.

### 7.1 Install Linkerd (Simplest)

```bash
# Install CLI
curl -fsL https://run.linkerd.io/install | sh

# Verify cluster
linkerd check --pre

# Install control plane
linkerd install | kubectl apply -f -

# Verify installation
linkerd check

# Enable mTLS (automatic — no config needed)
# All new pods get sidecars automatically

# Inject sidecar into existing namespace
kubectl annotate namespace default linkerd.io/inject=enabled

# Restart pods to get sidecars
kubectl rollout restart deployment -n default

# View dashboard
linkerd viz dashboard
```

### 7.2 Install Istio

```bash
# Download Istio
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
cd istio-1.20.0

# Install with default profile
./bin/istioctl install --set profile=default -y

# Enable sidecar injection
kubectl label namespace default istio-injection=enabled

# Restart pods
kubectl rollout restart deployment -n default

# View Kiali dashboard
istioctl dashboard kiali
```

### 7.3 Install Cilium Service Mesh

```bash
# Install Cilium CNI (if not already)
helm repo add cilium https://helm.cilium.io
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=api.cluster.local \
  --set k8sServicePort=6443

# Enable service mesh features
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --set clustermesh.useAPIServer=true \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true

# View Hubble dashboard
cilium hubble ui
```

---

## 8. Migration Strategy (When You're Ready)

### Phase 1: Prepare
- Audit current service communication patterns
- Identify which services need mTLS
- Set up monitoring baseline (latency, error rates)

### Phase 2: Install Mesh in Permissive Mode
- Install mesh with mTLS in "permissive" mode (accepts both encrypted and plain traffic)
- No disruption to existing services
- Monitor mesh metrics

### Phase 3: Enforce mTLS
- Switch to "strict" mode
- Verify all services are communicating via mTLS
- Fix any broken communication

### Phase 4: Add Policies
- Add traffic policies (retries, timeouts)
- Add observability dashboards
- Add canary deployment configs

### Phase 5: Optimize
- Tune resource limits for sidecars
- Optimize configuration
- Remove any unnecessary policies

---

## 9. My Final Recommendation

For your deployment, if you eventually need a service mesh:

| Priority | Choice | Reason |
|----------|--------|--------|
| **1st** | **Linkerd** | Simplest, lightest, mTLS out of the box |
| **2nd** | **Cilium** | If you switch CNI, get mesh for free |
| **3rd** | **Istio** | If you need advanced features (canary, circuit breaking) |
| **Skip** | Consul | Tied to HashiCorp ecosystem, no advantage for your stack |

**When to add it:**
- When compliance requires mTLS between all services
- When you have 20+ services with complex communication
- When you need canary deployments with traffic splitting
- When you need per-service latency metrics without code changes

**When to skip it:**
- < 15 services
- Simple request/response patterns
- NetworkPolicy + cert-manager is sufficient
- Team doesn't have bandwidth to operate a mesh
