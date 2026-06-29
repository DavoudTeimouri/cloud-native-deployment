# OPA Gatekeeper — Platform Guide

## Overview

OPA Gatekeeper enforces admission policies on Kubernetes clusters using OPA (Open Policy Agent) Rego policies. It works via `ConstraintTemplate` (Rego logic) and `Constraint` (policy parameters) resources.

> **Air-gap note:** All Gatekeeper images must be mirrored to Harbor. Standard library constraint templates must be pre-loaded from Nexus or baked into the deployment.

---

## Deployment via Helm

### Add Helm Repo (Nexus — Air-gapped)

```bash
helm repo add gatekeeper https://nexus.internal.example.com/repository/helm-remote/
helm repo update
```

### Values File

```yaml
# gatekeeper-values.yaml
replicas: 3
auditInterval: 60
logLevel: INFO
auditFromCache: true

image:
  repository: harbor.internal.example.com/platform/gatekeeper
  release: v3.15.1
  pullPolicy: IfNotPresent

crd:
  repository: harbor.internal.example.com/platform/gatekeeper-crds
  release: v3.15.1

audit:
  replicas: 1
  resources:
    requests: { cpu: 200m, memory: 256Mi }
    limits:   { cpu: 1000m, memory: 512Mi }

controllerManager:
  resources:
    requests: { cpu: 200m, memory: 256Mi }
    limits:   { cpu: 1000m, memory: 512Mi }

# Exempt namespaces
exemptNamespaces:
  - kube-system
  - gatekeeper-system
  - cert-manager
  - cattle-system
  - cattle-impersonation-system
  - cattle-fleet-system
  - cattle-fleet-local-system
  - argocd

# Enable mutation
enableMutation: true

# Disable default constraints (we manage our own)
disableDefaultConstraints: true

# Prometheus
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    labels: { release: kube-prometheus-stack }
```

```bash
helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  -f gatekeeper-values.yaml
```

---

## Constraint Templates Library

Gatekeeper provides a [standard library](https://github.com/open-policy-agent/gatekeeper-library) of constraint templates. In air-gapped environments, load them from your internal GitLab.

```bash
# Clone standard library (pre-mirror to internal GitLab)
git clone https://gitlab.internal.example.com/platform/gatekeeper-library.git
cd gatekeeper-library

# Apply all constraint templates
for dir in src/*/; do
  kubectl apply -f "${dir}template.yaml"
done
```

---

## Common Constraints

### Require Labels on All Resources

```yaml
# ConstraintTemplate
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
              items: { type: string }
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

```yaml
# Constraint
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-app-label
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod", "Deployment", "StatefulSet"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
  parameters:
    labels: ["app", "environment"]
```

### Block Privileged Containers

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPspPrivilegedContainer
metadata:
  name: psp-privileged-container
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    - apiGroups: ["apps"]
      kinds: ["Deployment", "DaemonSet", "StatefulSet", "ReplicaSet"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
```

### Block hostPath Mounts

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPspHostFilesystem
metadata:
  name: psp-host-filesystem
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
```

### Block hostNetwork

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPspHostNetworkingPorts
metadata:
  name: psp-host-networking
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
```

### Require Resource Limits

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredResources
metadata:
  name: require-resource-limits
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
    - cattle-system
```

### Allow Only Harbor Registry Images

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: allow-harbor-only
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
    - cert-manager
    - cattle-system
  parameters:
    repos:
    - "harbor.internal.example.com/"
```

### Block Latest Tag

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sImageTagNotLatest
metadata:
  name: block-latest-tag
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
```

### Require Non-Root User

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPspAllowPrivilegeEscalationContainer
metadata:
  name: psp-allow-privilege-escalation
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
```

---

## Constraint Per Cluster

Different policies for management vs application clusters:

### Management Cluster (Stricter)

```yaml
# mgmt-gatekeeper-constraints.yaml — ArgoCD deploys to mgmt cluster
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: allow-harbor-only
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnDeleteResource=true
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
    - cert-manager
    - cattle-system
    - argocd
  parameters:
    repos:
    - "harbor.internal.example.com/"
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-comprehensive-labels
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod", "Deployment"]
    excludedNamespaces: [kube-system, gatekeeper-system]
  parameters:
    labels: ["app", "environment", "team", "version"]
```

### Application Cluster (Application-focused)

```yaml
# app-gatekeeper-constraints.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-app-labels
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod", "Deployment"]
    excludedNamespaces: [kube-system, gatekeeper-system]
  parameters:
    labels: ["app", "environment"]
```

---

## Audit Configuration

Gatekeeper runs periodic audit to detect existing non-compliant resources:

```yaml
# gatekeeper-values.yaml (audit section)
audit:
  replicas: 1
  interval: 60          # seconds between audit runs
  matchKindOnly: true   # only audit resources matching constraint kinds
  logLevel: INFO
  resources:
    requests: { cpu: 200m, memory: 256Mi }
    limits:   { cpu: 1000m, memory: 512Mi }
```

### View Audit Results

```bash
# Check constraint violations
kubectl get constraints -A -o json | jq '.items[] | {
  name: .metadata.name,
  kind: .kind,
  violations: .status.violations
}'

# Detailed violations for a specific constraint
kubectl describe k8sallowedrepos allow-harbor-only
```

---

## Mutation Policies

Gatekeeper can mutate resources at admission time (e.g., inject default labels, add sidecar containers).

```yaml
# Mutation: Add default labels
apiVersion: mutations.gatekeeper.sh/v1
kind: MutateAssignment
metadata:
  name: add-default-labels
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces: [kube-system, gatekeeper-system]
  location: "metadata.labels.app"
  parameters:
    assign:
      value: "{{ request.object.metadata.name }}"
  condition:
    key: "{{ request.object.metadata.labels.app }}"
    operator: DoesNotExist
```

Enable mutation in Helm values:

```yaml
enableMutation: true
```

> ⚠️ Mutation uses a separate webhook. Ensure the mutation webhook CA is trusted by the API server.

---

## Exempt Namespaces

System and platform namespaces should be exempt from constraints:

```yaml
exemptNamespaces:
  - kube-system
  - gatekeeper-system
  - cert-manager
  - cattle-system
  - cattle-impersonation-system
  - cattle-fleet-system
  - cattle-fleet-local-system
  - argocd
  - velero
  - monitoring
  - logging
  - ingress-nginx
```

Or use a Config resource:

```yaml
apiVersion: config.gatekeeper.sh/v1alpha1
kind: Config
metadata:
  name: config
  namespace: gatekeeper-system
spec:
  match:
    - excludedNamespaces: ["kube-system", "gatekeeper-system"]
      processes: ["*"]
```

---

## Air-gap: Gatekeeper Images from Harbor

| Component | Upstream Image | Harbor Image |
|-----------|---------------|--------------|
| Gatekeeper | `openpolicyagent/gatekeeper:v3.15.1` | `harbor.internal.example.com/platform/gatekeeper:v3.15.1` |
| CRD gen | `openpolicyagent/gatekeeper-crds:v3.15.1` | `harbor.internal.example.com/platform/gatekeeper-crds:v3.15.1` |

### Mirror Script

```bash
#!/bin/bash
HARBOR=harbor.internal.example.com/platform
VERSION=v3.15.1
for IMG in gatekeeper gatekeeper-crds; do
  SRC="openpolicyagent/${IMG}:${VERSION}"
  DST="${HARBOR}/${IMG}:${VERSION}"
  docker pull "$SRC" && docker tag "$SRC" "$DST" && docker push "$DST"
done
```

---

## Performance Considerations

| Parameter | Default | Recommendation | Notes |
|-----------|---------|----------------|-------|
| `replicas` | 3 | 3 (production) | More replicas = higher availability |
| `auditInterval` | 60 | 60-300 | Lower = more load on API server |
| `auditFromCache` | false | true | Uses OPA cache, reduces API server load |
| `logLevel` | INFO | INFO | Use WARN in high-throughput clusters |
| `enableMutation` | false | true (if needed) | Adds a second webhook, slight latency |
| `webhook.timeoutSeconds` | 3 | 3-5 | Increase for complex policies |

### Resource Sizing

| Cluster Size | ControllerManager | Audit |
|--------------|-------------------|-------|
| Small (<50 nodes) | 200m CPU / 256Mi | 200m CPU / 256Mi |
| Medium (50-200 nodes) | 500m CPU / 512Mi | 500m CPU / 512Mi |
| Large (>200 nodes) | 1000m CPU / 1Gi | 1000m CPU / 1Gi |

### Monitoring

```bash
kubectl get --raw /metrics -n gatekeeper-system | grep gatekeeper_webhook
kubectl get constraints -A -o json | jq '[.items[] | {name: .metadata.name, violations: (.status.violations // [] | length)}]'
```
