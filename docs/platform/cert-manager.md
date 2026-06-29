# cert-manager — Platform Guide

## Overview

cert-manager automates TLS certificate management in Kubernetes. It adds `Certificate`, `ClusterIssuer`, and `Issuer` resource types and handles issuance, renewal, and rotation via configured CA or ACME issuers.

> **Air-gap note:** ACME (Let's Encrypt) is **not available** in air-gapped environments. All certificates are issued by an **internal CA** (step-ca or cfssl).

---

## Deployment via Helm

### Add Helm Repo (Nexus — Air-gapped)

```bash
helm repo add jetstack https://nexus.internal.example.com/repository/helm-remote/
helm repo update
```

### Values File

```yaml
# cert-manager-values.yaml
installCRDs: true
replicaCount: 2

image:
  repository: harbor.internal.example.com/platform/cert-manager-controller
  tag: v1.14.4
cainjector:
  image:
    repository: harbor.internal.example.com/platform/cert-manager-cainjector
    tag: v1.14.4
webhook:
  image:
    repository: harbor.internal.example.com/platform/cert-manager-webhook
    tag: v1.14.4
  replicaCount: 2
acmesolver:
  image:
    repository: harbor.internal.example.com/platform/cert-manager-acmesolver
    tag: v1.14.4

resources:
  requests: { cpu: 100m, memory: 128Mi }
  limits:   { cpu: 500m, memory: 512Mi }

prometheus:
  enabled: true
  servicemonitor:
    enabled: true
    labels: { release: kube-prometheus-stack }
```

```bash
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  -f cert-manager-values.yaml
```

---

## Internal CA Setup (Air-gapped)

### Option A: step-ca (Smallstep CA)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: step-ca
  namespace: cert-manager
spec:
  replicas: 1
  selector:
    matchLabels: { app: step-ca }
  template:
    spec:
      containers:
      - name: step-ca
        image: harbor.internal.example.com/platform/step-ca:0.25.0
        args: ["ca", "serve"]
        env:
        - name: STEP_CA_PASSWORD
          valueFrom:
            secretKeyRef: { name: step-ca-password, key: password }
        ports: [{ containerPort: 443 }]
        volumeMounts: [{ name: ca-data, mountPath: /home/step }]
      volumes:
      - name: ca-data
        persistentVolumeClaim: { claimName: step-ca-data }
```

### Option B: cfssl

```bash
cat > ca-csr.json <<EOF
{
  "CN": "Internal CA",
  "key": { "algo": "rsa", "size": 4096 },
  "names": [{ "C": "US", "O": "Example Corp", "OU": "Platform Eng" }],
  "ca": { "expiry": "87600h" }
}
EOF
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
kubectl create secret tls internal-ca-key-pair \
  --cert=ca.pem --key=ca-key.pem --namespace cert-manager
```

---

## ClusterIssuer Configurations

### CA ClusterIssuer (Production)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ca
spec:
  ca:
    secretName: internal-ca-key-pair
```

### SelfSigned ClusterIssuer (Dev/Test Only)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
```

---

## Certificate Resource Examples

### Wildcard Certificate for Ingress

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-apps-example-com
  namespace: ingress-nginx
spec:
  secretName: wildcard-apps-example-com-tls
  duration: 8760h
  renewBefore: 720h
  issuerRef: { name: internal-ca, kind: ClusterIssuer }
  dnsNames: ["*.apps.example.com", "apps.example.com"]
```

### Service Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-app-tls
  namespace: my-app
spec:
  secretName: my-app-tls
  duration: 8760h
  renewBefore: 360h
  issuerRef: { name: internal-ca, kind: ClusterIssuer }
  dnsNames: [my-app.apps.example.com]
  usages: [server auth, digital signature, key encipherment]
```

### Client Certificate (mTLS)

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-client-cert
  namespace: my-app
spec:
  secretName: my-client-cert
  duration: 4380h
  renewBefore: 168h
  issuerRef: { name: internal-ca, kind: ClusterIssuer }
  dnsNames: [my-client.apps.example.com]
  usages: [client auth, digital signature]
```

---

## Integration with NGINX Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: my-app
  annotations:
    cert-manager.io/cluster-issuer: internal-ca
    cert-manager.io/duration: "8760h"
    cert-manager.io/renew-before: "720h"
spec:
  ingressClassName: nginx
  tls:
  - hosts: [my-app.apps.example.com]
    secretName: my-app-tls
  rules:
  - host: my-app.apps.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service: { name: my-app, port: { number: 8080 } }
```

### Default Wildcard TLS for Ingress Controller

```yaml
# nginx-ingress-values.yaml
extraArgs:
  default-ssl-certificate: ingress-nginx/default-ingress-tls
```

---

## Integration with Rancher

Rancher **requires** cert-manager before deployment. Configure TLS source:

```yaml
# rancher-values.yaml
hostname: rancher.example.com
ingress:
  tls:
    source: rancher  # Uses cert-manager internally
```

### Trust Internal CA in Rancher

```bash
kubectl get secret internal-ca-key-pair -n cert-manager \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > internal-ca.crt
```

---

## Integration with ArgoCD

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: argocd-server-tls
  namespace: argocd
spec:
  secretName: argocd-server-tls
  duration: 8760h
  renewBefore: 720h
  issuerRef: { name: internal-ca, kind: ClusterIssuer }
  dnsNames:
  - argocd.example.com
  - argocd-server.argocd.svc.cluster.local
  - argocd-repo-server.argocd.svc.cluster.local
```

---

## Troubleshooting Certificate Issuance

| Issue | Symptoms | Resolution |
|-------|----------|------------|
| CA Secret missing | `CertificateRequest` stuck Pending | Verify `internal-ca-key-pair` secret exists |
| CA cert expired | Renewals fail with x509 expired | Rotate CA certificate |
| DNS mismatch | SAN errors in logs | Verify `dnsNames` match intended host |
| Webhook failure | Validation fails | Check cert-manager webhook pod and DNS |
| Image pull failure | `ImagePullBackOff` | Verify Harbor has cert-manager images |

### Diagnostic Commands

```bash
kubectl get certificate -A
kubectl describe certificate <name> -n <namespace>
kubectl get certificaterequest -A
kubectl describe clusterissuer internal-ca
kubectl logs -n cert-manager -l app.kubernetes.io/component=controller --tail=100

# Verify issued certificate
kubectl get secret <secret-name> -n <ns> -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -text
```

---

## Air-gap: Images from Harbor

### Required Images

| Component | Upstream Image | Harbor Image |
|-----------|---------------|--------------|
| Controller | `quay.io/jetstack/cert-manager-controller:v1.14.4` | `harbor.internal.example.com/platform/cert-manager-controller:v1.14.4` |
| Webhook | `quay.io/jetstack/cert-manager-webhook:v1.14.4` | `harbor.internal.example.com/platform/cert-manager-webhook:v1.14.4` |
| CA Injector | `quay.io/jetstack/cert-manager-cainjector:v1.14.4` | `harbor.internal.example.com/platform/cert-manager-cainjector:v1.14.4` |
| ACME Solver | `quay.io/jetstack/cert-manager-acmesolver:v1.14.4` | `harbor.internal.example.com/platform/cert-manager-acmesolver:v1.14.4` |

### Mirror Script

```bash
#!/bin/bash
HARBOR=harbor.internal.example.com/platform
VERSION=v1.14.4
for IMG in controller webhook cainjector acmesolver; do
  SRC="quay.io/jetstack/cert-manager-${IMG}:${VERSION}"
  DST="${HARBOR}/cert-manager-${IMG}:${VERSION}"
  docker pull "$SRC" && docker tag "$SRC" "$DST" && docker push "$DST"
done
```

---

## Rotating CA Certificates

1. **Generate new CA:**
```bash
cfssl gencert -initca ca-csr-new.json | cfssljson -bare ca-new
```

2. **Update the secret:**
```bash
kubectl create secret tls internal-ca-key-pair \
  --cert=ca-new.pem --key=ca-new-key.pem \
  --namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
```

3. **Force re-issuance of all certificates:**
```bash
kubectl get certificate -A -o json | jq -r '.items[] | "\(.metadata.name) \(.metadata.namespace)"' | \
  while read name ns; do
    kubectl annotate certificate "$name" -n "$ns" \
      cert-manager.io/issue-manual-certificate="$(date +%s)" --overwrite
  done
```

4. **Distribute new CA to all nodes:**
```bash
sudo cp ca-new.pem /usr/local/share/ca-certificates/internal-ca.crt
sudo update-ca-certificates
```
