# Platform Component Troubleshooting Guide

> Covers: Rancher, ArgoCD, Gatekeeper, cert-manager

---

## 1. Rancher Issues

### 1.1 Rancher Agent Not Connecting

**Symptom:** Imported cluster shows `Waiting` or `Unavailable` in Rancher UI

**Possible Causes:**
- Network connectivity between agent and Rancher server
- DNS resolution failure for Rancher URL
- Certificate issues
- Cluster registration token expired
- Firewall blocking port 443/6443

**Diagnostic Commands:**
```bash
# Check Rancher agent pod
kubectl get pods -n cattle-system
kubectl logs -n cattle-system -l app=rancher-agent --tail=100

# Check cluster agent
kubectl get pods -n cattle-cluster-agent
kubectl logs -n cattle-cluster-agent deployment/cattle-cluster-agent --tail=100

# Check node agent (system)
kubectl get pods -n cattle-system -l app=rancher-agent
kubectl logs -n cattle-system daemonset/cattle-node-agent --tail=100

# Test connectivity from agent to Rancher
kubectl exec -it -n cattle-system <agent-pod> -- curl -vk https://<rancher-url>/ping

# Check cluster registration token
kubectl get clusters.management.cattle.io -o yaml
```

**Resolution:**
```bash
# Re-register cluster: generate new import manifest from Rancher UI
# Cluster Management → Import Existing → Generic → Copy manifest
kubectl apply -f import-manifest.yaml

# Check for DNS resolution
kubectl exec -it -n cattle-system <agent-pod> -- nslookup <rancher-url>

# Check for certificate issues
kubectl exec -it -n cattle-system <agent-pod> -- \
  curl -vk https://<rancher-url> 2>&1 | grep -i "ssl\|cert\|verify"

# Restart Rancher agent
kubectl rollout restart deployment cattle-cluster-agent -n cattle-cluster-agent
kubectl rollout restart daemonset cattle-node-agent -n cattle-system

# If using self-signed certs, ensure CA is trusted
kubectl get secret -n cattle-system tls-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
```

---

### 1.2 Rancher Certificate Issues

**Symptom:** Browser shows certificate warning, API calls fail with TLS error

**Diagnostic Commands:**
```bash
# Check Rancher TLS secret
kubectl get secret -n cattle-system tls-rancher-ingress -o yaml
kubectl describe secret -n cattle-system tls-rancher-ingress

# Check certificate expiry
kubectl get secret -n cattle-system tls-rancher-ingress \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates

# Check cert-manager integration
kubectl get certificate -n cattle-system
kubectl describe certificate -n cattle-system tls-rancher-ingress
```

**Resolution:**
```bash
# Update TLS secret
kubectl create secret tls tls-rancher-ingress \
  --cert=tls.crt --key=tls.key \
  -n cattle-system --dry-run=client -o yaml | kubectl apply -f -

# If using cert-manager, force renewal
kubectl annotate certificate tls-rancher-ingress -n cattle-system \
  cert-manager.io/issue-temporarily-invalid-certificate=true
kubectl delete secret -n cattle-system tls-rancher-ingress
# cert-manager will re-issue

# If using Let's Encrypt, check for rate limits
kubectl get orders,challenges -n cattle-system
```

---

### 1.3 Rancher UI Not Loading

**Symptom:** Cannot access Rancher web UI

**Diagnostic Commands:**
```bash
# Check Rancher pods
kubectl get pods -n cattle-system -l app=rancher
kubectl logs -n cattle-system -l app=rancher --tail=100

# Check Rancher service
kubectl get svc -n cattle-system rancher
kubectl get ingress -n cattle-system rancher

# Check resource usage
kubectl top pods -n cattle-system

# Check for OOM kills
kubectl get events -n cattle-system --field-selector reason=OOMKilling
```

**Resolution:**
```bash
# Restart Rancher
kubectl rollout restart deployment rancher -n cattle-system

# Increase resources if OOM
kubectl patch deployment rancher -n cattle-system --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"2Gi"}
]'

# Check for database issues (HA mode)
kubectl get pods -n cattle-system | grep mysql|postgres

# Check ingress
kubectl describe ingress rancher -n cattle-system
```

---

### 1.4 Cluster Registration Failures

**Symptom:** Cluster stuck in `Provisioning` or `Waiting` state

**Diagnostic Commands:**
```bash
# Check cluster object
kubectl get clusters.management.cattle.io <cluster-id> -o yaml

# Check cluster registration token
kubectl get clusterregistrationtokens.management.cattle.io -o yaml

# Check fleet agent (for fleet-managed clusters)
kubectl get pods -n cattle-fleet-system
kubectl logs -n cattle-fleet-system -l app=fleet-agent --tail=100
```

**Resolution:**
```bash
# Delete and re-import cluster
kubectl delete cluster <cluster-id> --cascade=orphan  # in Rancher UI
# Then re-import with new manifest

# Check CAPI/RKE2 provisioning logs
kubectl get pods -n cattle-provisioning-system
kubectl logs -n cattle-provisioning-system -l job-name=<cluster>-<id> --tail=100
```

---

## 2. ArgoCD Issues

### 2.1 Sync Failures

**Symptom:** Application shows `SyncStatus: OutOfSync` or `SyncFailed`

**Possible Causes:**
- Git repo inaccessible
- Helm chart errors
- Kustomize build failures
- Resource hooks failing
- Health check failures

**Diagnostic Commands:**
```bash
# Check application status
kubectl get application <app> -n argocd -o yaml
kubectl describe application <app> -n argocd

# Check ArgoCD controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100

# Check sync operation
kubectl get application <app> -n argocd -o jsonpath='{.status.operationState}'

# Check repo connection
kubectl get repo -n argocd
argocd repo get <repo-url>  # using argocd CLI

# Check application events
kubectl get events -n argocd --field-selector involvedObject.name=<app>
```

**Resolution:**
```bash
# Force sync
argocd app sync <app> -n argocd --force
argocd app sync <app> -n argocd --replace  # for Kustomize issues

# Check for manifest errors
argocd app manifests <app> -n argocd | kubeval

# Fix repo credentials
argocd repo add <repo-url> --username <user> --password <pass>

# Check for hook failures
kubectl get application <app> -n argocd -o jsonpath='{.status.operationState}'

# Hard refresh to clear cache
argocd app get <app> -n argocd --hard-refresh
```

---

### 2.2 Repository Connection Issues

**Symptom:** `Repository is unavailable` or `CONNECTION_ERROR`

**Diagnostic Commands:**
```bash
# Test repo connectivity from ArgoCD repo server
kubectl exec -it -n argocd deploy/argocd-repo-server -- \
  git ls-remote <repo-url>

# For Helm repos
kubectl exec -it -n argocd deploy/argocd-repo-server -- \
  helm repo add <name> <url> && helm repo update

# Check repo server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=100

# Check repo secret
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
```

**Resolution:**
```bash
# Add repo with credentials
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: private-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  url: https://github.com/org/repo.git
  username: <user>
  password: <token>
EOF

# For SSH repos
kubectl create secret generic ssh-key-secret -n argocd \
  --from-file=sshPrivateKey=/path/to/id_rsa \
  --dry-run=client -o yaml | kubectl apply -f -
# Then register repo with: argocd repo add git@github.com:org/repo.git --ssh-key-path /path/to/id_rsa

# For air-gap: ensure repo server can reach internal GitLab
kubectl exec -it -n argocd deploy/argocd-repo-server -- curl -I https://git.internal
```

---

### 2.3 Application Stuck in Progressing

**Symptom:** Application shows `Running` sync indefinitely

**Diagnostic Commands:**
```bash
# Check operation
kubectl get application <app> -n argocd -o jsonpath='{.status.operationState.phase}'
kubectl get application <app> -n argocd -o jsonpath='{.status.operationState.message}'

# Check for hooks
kubectl get application <app> -n argocd -o jsonpath='{.spec.syncPolicy.syncOptions}'

# Check resource tree
argocd app resources <app> -n argocd
```

**Resolution:**
```bash
# Terminate stuck operation
argocd app terminate-op <app> -n argocd

# Retry sync
argocd app sync <app> -n argocd --retry

# Check for infinite hooks (e.g., Jobs that never complete)
kubectl get jobs -n <app-namespace>
kubectl delete job <stuck-job> -n <app-namespace>
```

---

### 2.4 RBAC Issues

**Symptom:** `Permission denied` when using ArgoCD CLI or UI

**Diagnostic Commands:**
```bash
# Check RBAC config
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# Check user roles
argocd proj role list default
argocd account list

# Check policy
kubectl get configmap argocd-rbac-cm -n argocd -o jsonpath='{.data.policy\.csv}'
```

**Resolution:**
```bash
# Update RBAC policy
kubectl edit configmap argocd-rbac-cm -n argocd
# Add policy line:
# p, role:developer, applications, sync, */*, allow
# g, admin, role:admin

# Restart ArgoCD server
kubectl rollout restart deployment argocd-server -n argocd
```

---

## 3. Gatekeeper Issues

### 3.1 Constraint Violations

**Symptom:** Resources being blocked by Gatekeeper constraints

**Diagnostic Commands:**
```bash
# Check constraint templates
kubectl get constrainttemplates

# Check constraints
kubectl get constraints
kubectl describe constraint <constraint-name>

# Check audit results
kubectl get constraint <name> -o yaml | grep -A 20 "violations"

# Check Gatekeeper logs
kubectl logs -n gatekeeper-system -l control-plane=controller-manager --tail=100

# Check specific resource denial
kubectl create -f resource.yaml 2>&1  # Shows denial message
```

**Resolution:**
```bash
# Review constraint violations
kubectl get k8srequiredlabels <constraint> -o yaml | grep -A 5 violations

# Fix the violating resource
# Example: add required label
kubectl label <resource> <key>=<value>

# If constraint is too restrictive, modify it
kubectl edit constraint <constraint-name>
# Adjust spec.parameters or spec.match

# Temporarily dry-run a constraint
kubectl edit constrainttemplate <template>
# Change spec.targets[0].rego to add dryrun logic
# Or change enforcementAction to dryrun
kubectl edit constraint <name>
# spec:
#   enforcementAction: dryrun  # instead of deny
```

---

### 3.2 Audit Failures

**Symptom:** Gatekeeper audit shows errors or high violation counts

**Diagnostic Commands:**
```bash
# Check audit status
kubectl get constraint -o custom-columns=NAME:.metadata.name,VIOLATIONS:status.totalViolations,TIMESTAMP:.status.auditTimestamp

# Check audit logs
kubectl logs -n gatekeeper-system -l control-plane=controller-manager | grep -i "audit\|error"

# Check audit interval
kubectl get gatekeeper-system constrainttemplate <template> -o yaml | grep audit
```

**Resolution:**
```bash
# Increase audit interval if too frequent
kubectl edit gatekeeper-system deployment gatekeeper-controller-manager
# --audit-interval=60  (default 60s)

# Fix rego policy errors
kubectl logs -n gatekeeper-system -l control-plane=controller-manager | grep "rego"
# Fix the constraint template rego code
kubectl edit constrainttemplate <template>
```

---

### 3.3 Gatekeeper OOM

**Symptom:** Gatekeeper pods being OOM killed

**Diagnostic Commands:**
```bash
# Check resource usage
kubectl top pods -n gatekeeper-system

# Check OOM events
kubectl get events -n gatekeeper-system --field-selector reason=OOMKilling

# Check memory limits
kubectl get deployment -n gatekeeper-system gatekeeper-controller-manager \
  -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'
```

**Resolution:**
```bash
# Increase memory limits
kubectl patch deployment gatekeeper-controller-manager -n gatekeeper-system --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"1Gi"}
]'

# Reduce audit scope
# --audit-from-cache=true  (use informer cache instead of live queries)
# --constraint-violations-limit=1000  (limit violations stored)

# Disable unused constraint templates
kubectl delete constrainttemplate <unused-template>
```

---

## 4. cert-manager Issues

### 4.1 Certificate Not Issued

**Symptom:** Certificate stuck in `False` / `Ready` condition

**Diagnostic Commands:**
```bash
# Check certificate status
kubectl get certificate -n <namespace>
kubectl describe certificate <cert> -n <namespace>

# Check CertificateRequest
kubectl get certificaterequest -n <namespace>
kubectl describe certificaterequest <cr> -n <namespace>

# Check Order (ACME)
kubectl get orders.acme.cert-manager.io -n <namespace>
kubectl describe order <order> -n <namespace>

# Check Challenge (ACME)
kubectl get challenges.acme.cert-manager.io -n <namespace>
kubectl describe challenge <challenge> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100
```

**Resolution:**
```bash
# Check for ACME challenge failures
kubectl describe challenge <challenge> -n <namespace>
# Common: DNS-01 record not propagated, HTTP-01 ingress not routing

# For DNS-01: verify DNS provider credentials
kubectl get secret <dns-provider-secret> -n cert-manager -o yaml

# For HTTP-01: verify ingress is routing to solver pod
kubectl get challenge <challenge> -n <namespace> -o jsonpath='{.spec.dnsName}'
# Check ingress for that hostname

# For CA issuer: verify CA secret exists
kubectl get secret -n cert-manager <ca-secret> -o yaml
# Must contain tls.crt and tls.key

# Force re-issue
kubectl delete secret <tls-secret> -n <namespace>
kubectl annotate certificate <cert> -n <namespace> cert-manager.io/issue-temporarily-allowed=true
kubectl delete certificaterequest -n <namespace> --all
```

---

### 4.2 CA Issues

**Symptom:** CA issuer not working, certificates not signed

**Diagnostic Commands:**
```bash
# Check CA issuer
kubectl get issuer -n <namespace>
kubectl describe issuer <issuer> -n <namespace>

# Check CA secret
kubectl get secret -n <namespace> <ca-secret> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text

# Check self-signed issuer
kubectl get issuer selfsigned -n cert-manager -o yaml
```

**Resolution:**
```bash
# Create CA issuer from existing CA keypair
kubectl create secret tls ca-key-pair \
  --cert=ca.crt --key=ca.key \
  -n cert-manager --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: ca-issuer
  namespace: <namespace>
spec:
  ca:
    secretName: ca-key-pair
EOF
```

---

### 4.3 Webhook Failures

**Symptom:** `Error from server: webhook "webhook.cert-manager.io" denied the request`

**Diagnostic Commands:**
```bash
# Check webhook pods
kubectl get pods -n cert-manager -l app=webhook
kubectl logs -n cert-manager -l app=webhook --tail=100

# Check webhook configuration
kubectl get validatingwebhookconfiguration cert-manager-webhook -o yaml
kubectl get mutatingwebhookconfiguration cert-manager-webhook -o yaml

# Check webhook service
kubectl get svc -n cert-manager cert-manager-webhook
kubectl get endpoints -n cert-manager cert-manager-webhook
```

**Resolution:**
```bash
# Restart webhook
kubectl rollout restart deployment cert-manager-webhook -n cert-manager

# Check for certificate issues with webhook itself
kubectl get secret -n cert-manager cert-manager-webhook-ca -o yaml
kubectl get certificate -n cert-manager cert-manager-webhook-ca -o yaml

# If webhook is completely broken, temporarily disable
kubectl delete validatingwebhookconfiguration cert-manager-webhook
kubectl delete mutatingwebhookconfiguration cert-manager-webhook
# Fix the issue, then re-enable by restarting cert-manager
kubectl rollout restart deployment -n cert-manager
```
