# Hardening Guide

> Post-deployment security hardening for Kubernetes, Ceph, OS, and all components

---

## 1. Kubernetes Hardening

### 1.1 Pod Security Standards

```yaml
# Apply Pod Security Standards to all namespaces
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
# For namespaces that need privileged access (monitoring, logging)
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### 1.2 Network Policies

```yaml
# Default deny all ingress/egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
# Allow DNS egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to: []
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
---
# Allow ingress from same namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {}
---
# Allow ingress from monitoring namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
```

### 1.3 RBAC Hardening

```yaml
# Remove cluster-admin from service accounts that don't need it
kubectl delete clusterrolebinding system:controller:endpoint-controller

# Create least-privilege roles
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-deployer
  namespace: production
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps"]
    verbs: ["get", "list", "watch"]
---
# Bind to service account
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-deployer-binding
  namespace: production
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: app-deployer
subjects:
  - kind: ServiceAccount
    name: deploy-bot
    namespace: production
```

### 1.4 Audit Logging

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["pods", "services", "configmaps"]
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets"]
  - level: RequestResponse
    verbs: ["create", "update", "delete"]
    resources:
      - group: "rbac.authorization.k8s.io"
  - level: None
    nonResourceURLs: ["/healthz", "/readyz", "/livez"]
  - level: RequestResponse
    omitStages:
      - RequestReceived
---
# Configure kubelet to audit
# /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: false
authorization:
  mode: Webhook
```

### 1.5 Disable Automounting Service Account Tokens

```yaml
# For pods that don't need API access
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  namespace: production
spec:
  automountServiceAccountToken: false
  containers:
    - name: app
      image: nginx:1.25
---
# For service accounts
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-sa
  namespace: production
automountServiceAccountToken: false
```

### 1.6 Kyverno Security Policies

```yaml
# Require resource limits
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resources
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-limits
      match:
        any:
          - resources:
              kinds:
                - Deployment
                - StatefulSet
      validate:
        message: "All containers must have resource limits."
        pattern:
          spec:
            containers:
              - name: "*"
                resources:
                  limits:
                    memory: "?*"
                    cpu: "?*"
---
# Require non-root user
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-non-root
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-run-as-non-root
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Running as root is forbidden."
        pattern:
          spec:
            containers:
              - name: "*"
                securityContext:
                  runAsNonRoot: true
---
# Require read-only root filesystem
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-read-only-root
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-read-only
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Root filesystem must be read-only."
        pattern:
          spec:
            containers:
              - name: "*"
                securityContext:
                  readOnlyRootFilesystem: true
---
# Restrict image registries
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-registries
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
        message: "Only images from trusted registries."
        pattern:
          spec:
            containers:
              - name: "*"
                image: "harbor.internal.lan/* | nginx:* | registry.k8s.io/*"
---
# Prevent privilege escalation
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: no-privilege-escalation
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-privilege-escalation
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Privilege escalation is forbidden."
        pattern:
          spec:
            containers:
              - name: "*"
                securityContext:
                  allowPrivilegeEscalation: false
```

---

## 2. Ceph Hardening

### 2.1 CephX Authentication

```bash
# Verify CephX is enabled
ceph auth list | grep cephx

# Create restricted user for Kubernetes
ceph auth get-or-create client.kubernetes \
  mon 'profile rbd' \
  osd 'profile rbd pool=k8s-volumes' \
  mgr 'profile rbd pool=k8s-volumes'

# Create restricted user for RGW
ceph auth get-or-create client.rgw \
  mon 'allow r' \
  osd 'allow rwx' \
  mgr 'allow r'
```

### 2.2 Network Segmentation

```bash
# Restrict MON access (Ceph configuration)
cat >> /etc/ceph/ceph.conf <<EOF
[global]
public network = 10.0.0.0/24
cluster network = 10.0.1.0/24
ms bind ipv4 = true
ms bind ipv6 = false

[mon]
mon allow pool delete = false
mon cluster log file = /var/log/ceph/$cluster.$name.log
EOF

# Restart Ceph services
sudo systemctl restart ceph-mon.target
sudo systemctl restart ceph-osd.target
```

### 2.3 Dashboard Security

```bash
# Enable dashboard authentication
ceph dashboard set-login-credentials admin <strong-password>

# Restrict dashboard to specific IPs
ceph dashboard set-grafana-api-url https://grafana.internal

# Disable dashboard on monitors (security)
ceph mgr module disable dashboard
# Then enable only on a dedicated node
ssh <dashboard-node> ceph mgr module enable dashboard
```

### 2.4 OSD Encryption

```bash
# Enable dm-crypt for OSD encryption
ceph-volume lvm create --data /dev/sdb --dmcrypt
```

### 2.5 Pool Security

```bash
# Set pool quotas
ceph osd pool set-quota k8s-volumes max_bytes 100G
ceph osd pool set-quota k8s-volumes max_objects 10000

# Enable application pools
ceph osd pool application enable k8s-volumes rbd
```

---

## 3. Operating System Hardening

### 3.1 SSH Hardening

```bash
# /etc/ssh/sshd_config
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
MaxAuthTries 3
MaxSessions 4
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
Protocol 2
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
LogLevel VERBOSE
AllowUsers deploy

sudo systemctl restart sshd
```

### 3.2 Firewall (UFW)

```bash
# Enable UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH from internal only
sudo ufw allow from 10.0.0.0/8 to any port 22 proto tcp

# Allow K8s API
sudo ufw allow from 10.0.0.0/8 to any port 6443 proto tcp

# Allow etcd (control plane only)
sudo ufw allow from 10.0.0.11 to any port 2379:2380 proto tcp
sudo ufw allow from 10.0.0.12 to any port 2379:2380 proto tcp
sudo ufw allow from 10.0.0.13 to any port 2379:2380 proto tcp

# Allow Calico BGP
sudo ufw allow 179/tcp

# Enable
sudo ufw enable
sudo ufw status verbose
```

### 3.3 Fail2ban

```bash
# Install
sudo apt-get install -y fail2ban

# Configure
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
banaction = ufw

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log

[kube-apiserver]
enabled = true
port = 6443
filter = kube-apiserver
logpath = /var/log/kubernetes/kube-apiserver.log
EOF

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
```

### 3.4 Auditd

```bash
# Install
sudo apt-get install -y auditd audispd-plugins

# Configure rules
cat > /etc/audit/rules.d/hardening.rules <<EOF
# Monitor authentication files
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Monitor SSH config
-w /etc/ssh/sshd_config -p wa -k ssh-config

# Monitor Kubernetes binaries
-w /usr/bin/kubepaddle -p wa -k kubernetes
-w /usr/bin/kubelet -p wa -k kubernetes
-w /usr/bin/kubectl -p wa -k kubernetes

# Monitor containerd
-w /usr/bin/containerd -p wa -k containerd
-w /usr/bin/ctr -p wa -k containerd

# Monitor mount operations
-w /bin/mount -p x -k mounts
-w /bin/umount -p x -k mounts

# Monitor privileged operations
-a always,exit -F arch=b64 -S setuid -S setgid -S setreuid -S setregid -k privilege_escalation
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k root_commands

# Make immutable
-e 2
EOF

sudo systemctl restart auditd
```

### 3.5 Automatic Security Updates

```bash
# Install unattended-upgrades
sudo apt-get install -y unattended-upgrades

# Enable
sudo dpkg-reconfigure -plow unattended-upgrades

# Configure
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
```

### 3.6 Kernel Hardening

```bash
# /etc/sysctl.d/99-hardening.conf
# Disable IP forwarding (if not running K8s)
# net.ipv4.ip_forward = 0

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Enable TCP SYN cookies
net.ipv4.tcp_syncookies = 1

# Disable IPv6 (if not needed)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# Restrict kernel pointers
kernel.kptr_restrict = 2

# Restrict dmesg
kernel.dmesg_restrict = 1

# Restrict perf events
kernel.perf_event_paranoid = 3

# Restrict user namespaces (if not needed for containers)
# kernel.unprivileged_userns_clone = 0

sudo sysctl --system
```

### 3.7 Disable Unnecessary Services

```bash
# List running services
systemctl list-units --type=service --state=running

# Disable and remove unnecessary
sudo systemctl stop --now snapd
sudo systemctl disable snapd
sudo apt-get purge -y snapd

sudo systemctl stop --now ModemManager
sudo systemctl disable ModemManager

sudo systemctl stop --now avahi-daemon
sudo systemctl disable avahi-daemon

sudo systemctl stop --now cups
sudo systemctl disable cups

sudo systemctl stop --now bluetooth
sudo systemctl disable bluetooth

# Mask so they can't be started
sudo systemctl mask snapd
sudo systemctl mask ModemManager
```

---

## 4. Network Hardening

### 4.1 TLS Everywhere

```bash
# Generate internal CA
openssl genrsa -out /etc/ssl/internal-ca.key 4096
openssl req -new -x509 -days 3650 -key /etc/ssl/internal-ca.key \
  -out /etc/ssl/internal-ca.crt \
  -subj "/C=US/ST=State/L=City/O=Internal/CN=Internal CA"

# Generate service certificates
for svc in rancher argocd gitlab harbor; do
    openssl genrsa -out /etc/ssl/${svc}.key 2048
    openssl req -new -key /etc/ssl/${svc}.key \
      -out /etc/ssl/${svc}.csr \
      -subj "/C=US/ST=State/L=City/O=Internal/CN=${svc}.internal.lan"
    openssl x509 -req -in /etc/ssl/${svc}.csr \
      -CA /etc/ssl/internal-ca.crt -CAkey /etc/ssl/internal-ca.key \
      -CAcreateserial -out /etc/ssl/${svc}.crt -days 365
done
```

### 4.2 etcd Encryption

```bash
# Enable etcd encryption at rest
cat > /etc/kubernetes/encryption-config.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-32-byte-key>
      - identity: {}
EOF
```

### 4.3 Restrict etcd Access

```bash
# Only allow control plane nodes
iptables -A INPUT -p tcp --dport 2379 -s 10.0.0.11 -j ACCEPT
iptables -A INPUT -p tcp --dport 2379 -s 10.0.0.12 -j ACCEPT
iptables -A INPUT -p tcp --dport 2379 -s 10.0.0.13 -j ACCEPT
iptables -A INPUT -p tcp --dport 2379 -j DROP

iptables -A INPUT -p tcp --dport 2380 -s 10.0.0.11 -j ACCEPT
iptables -A INPUT -p tcp --dport 2380 -s 10.0.0.12 -j ACCEPT
iptables -A INPUT -p tcp --dport 2380 -s 10.0.0.13 -j ACCEPT
iptables -A INPUT -p tcp --dport 2380 -j DROP
```

---

## 5. Secrets Management

### 5.1 HashiCorp Vault Integration

```bash
# Install Vault
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --set "server.dev.enabled=false" \
  --set "injector.enabled=true" \
  --set "csi.enabled=true"

# Initialize vault operator init -key-shares=5 -key-threshold=3

# Unseal vault operator unseal <key>

# Enable Kubernetes auth vault auth enable kubernetes
```

### 5.2 External Secrets Operator

```bash
# Install ESO
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace

# Create ClusterSecretStore
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.internal.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
          serviceAccountRef:
            name: "external-secrets"
            namespace: "external-secrets"
---
# Create ExternalSecret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-secrets
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: my-app-secret
  data:
    - secretKey: database-password
      remoteRef:
        key: my-app
        property: database-password
```

---

## 6. Component Hardening

### 6.1 Rancher Hardening

```bash
# Enable audit logging
kubectl edit setting audit-level
# Set to 1 or higher

# Enable TLS termination
helm upgrade rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set ingress.tls.source=secret \
  --set privateCA=true

# Restrict access by IP
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: rancher-access
  namespace: cattle-system
spec:
  podSelector:
    matchLabels:
      app: rancher
  ingress:
    - from:
        - ipBlock:
            cidr: 10.0.0.0/8
      ports:
        - port: 443
```

### 6.2 ArgoCD Hardening

```bash
# Enable RBAC
kubectl edit configmap argocd-rbac-cm -n argocd
# Add:
# p, role:readonly, applications, get, */*, allow

# Disable admin account after setting up RBAC
kubectl patch statefulset argocd-application-controller -n argocd \
  --type json -p='[{"op":"remove","path":"/spec/template/spec/containers/0/env/0"}]'

# Enable OIDC
kubectl edit configmap argoidc-config -n argocd
```

### 6.3 Harbor Hardening

```bash
# Enable vulnerability scanning
trivy-adapter enabled

# Set up robot accounts with minimal permissions
# Don't use admin account for CI/CD

# Enable audit logging
# harbor.yml
log:
  level: info
  local:
    rotate_count: 50
    rotate_size: 200M

# Restrict anonymous access
# harbor.yml
auth_mode: db_auth
```

### 6.4 Prometheus/Grafana Hardening

```bash
# Enable Grafana authentication
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.sidecar.dashboards.enabled=true \
  --set grafana.rbac.create=true

# Restrict Prometheus access
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prometheus-access
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app: prometheus
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
      ports:
        - port: 9090
```

### 6.5 GitLab Hardening

```bash
# /etc/gitlab/gitlab.rb
gitlab_rails['gitlab_sign_up_enabled'] = false
gitlab_rails['password_authentication_enabled_for_web'] = false
gitlab_rails['two_factor_grace_period'] = 48
gitlab_rails['session_expire_delay'] = 10

registry['registry_http_addr'] = '0.0.0.0:5000'
registry_nginx['redirect_http_to_https'] = true

# Enable audit log
gitlab_rails['audit_events_enabled'] = true
```

---

## 7. Verification

```bash
# Check Pod Security Standards
kubectl get ns -L pod-security.kubernetes.io/enforce

# Check NetworkPolicies
kubectl get networkpolicies --all-namespaces

# Check RBAC
kubectl auth can-i --list --as=system:serviceaccount:default:default

# Check audit logs
kubectl logs -n kube-system <kube-apiserver-pod> | grep audit

# Check fail2ban
sudo fail2ban-client status sshd

# Check open ports
sudo ss -tlnp

# Check for CVEs with Trivy
trivy image nginx:1.25

# Run kube-bench
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs job/kube-bench -n default
```

---

## 8. Hardening Checklist Summary

| Area | Task | Status |
|------|------|--------|
| **K8s** | Pod Security Standards enforced | ☐ |
| **K8s** | NetworkPolicies applied | ☐ |
| **K8s** | RBAC configured (least privilege) | ☐ |
| **K8s** | Audit logging enabled | ☐ |
| **K8s** | Service account tokens not auto-mounted | ☐ |
| **K8s** | Kyverno security policies applied | ☐ |
| **Ceph** | CephX authentication enabled | ☐ |
| **Ceph** | Network segmentation configured | ☐ |
| **Ceph** | Dashboard authentication enabled | ☐ |
| **OS** | SSH hardened (no root, no password) | ☐ |
| **OS** | UFW firewall enabled | ☐ |
| **OS** | Fail2ban configured | ☐ |
| **OS** | Auditd configured | ☐ |
| **OS** | Automatic security updates enabled | ☐ |
| **OS** | Unnecessary services disabled | ☐ |
| **OS** | Kernel hardening sysctl applied | ☐ |
| **Network** | TLS everywhere | ☐ |
| **Network** | etcd access restricted | ☐ |
| **Secrets** | Vault integrated | ☐ |
| **Components** | Rancher hardened | ☐ |
| **Components** | ArgoCD hardened | ☐ |
| **Components** | Harbor hardened | ☐ |
| **Components** | Prometheus/Grafana hardened | ☐ |
| **Components** | GitLab hardened | ☐ |
