
---

## Exempt Namespaces

System and platform namespaces should be exempt from constraints:

```yaml
# gatekeeper-values.yaml
exemptNamespaces:
  - kube-system
  - gatekeeper-system
  - cert-manager
  - cattle-system
  - cattle-impersonation-system
  - cattle-fleet-system
  - cattle-fleet-local-system
  - cattle-impersonation-system
  - argocd
  - velero
  - monitoring
  - logging
  - ingress-nginx
```

Or use namespace labels for exemption:

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

### Required Images

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
| `enableMutation` | false | true (if needed) | Adds a second webhook, slight latency increase |
| `maxServingThreads` | 1 | 2-4 | Increases webhook throughput |

### Webhook Timeout

Set appropriate webhook timeout to avoid blocking API server:

```yaml
# gatekeeper-values.yaml
webhook:
  timeoutSeconds: 3  # Default; increase for complex policies
```

### Resource Sizing

| Cluster Size | ControllerManager | Audit |
|--------------|-------------------|-------|
| Small (<50 nodes) | 200m CPU / 256Mi | 200m CPU / 256Mi |
| Medium (50-200 nodes) | 500m CPU / 512Mi | 500m CPU / 512Mi |
| Large (>200 nodes) | 1000m CPU / 1Gi | 1000m CPU / 1Gi |

### Monitoring Gatekeeper

```bash
# Check webhook latency
kubectl get --raw /metrics -n gatekeeper-system | grep gatekeeper_webhook

# Constraint violation count
kubectl get constraints -A -o json | jq '[.items[] | {
  name: .metadata.name,
  violations: (.status.violations // [] | length)
}]'
```
