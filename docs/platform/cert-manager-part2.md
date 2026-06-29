
---

## ClusterIssuer Configurations

### CA ClusterIssuer (Primary — Air-gapped)

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

> ⚠️ **Do NOT use self-signed in production.** Use the internal CA issuer.

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
  duration: 8760h    # 1 year
  renewBefore: 720h  # Renew 30 days before expiry
  issuerRef:
    name: internal-ca
    kind: ClusterIssuer
  dnsNames:
  - "*.apps.example.com"
  - "apps.example.com"
```

### Service-Specific Certificate

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
  issuerRef:
    name: internal-ca
    kind: ClusterIssuer
  dnsNames:
  - my-app.apps.example.com
  usages:
  - server auth
  - digital signature
  - key encipherment
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
  duration: 4380h    # 6 months
  renewBefore: 168h
  issuerRef:
    name: internal-ca
    kind: ClusterIssuer
  dnsNames:
  - my-client.apps.example.com
  usages:
  - client auth
  - digital signature
```
