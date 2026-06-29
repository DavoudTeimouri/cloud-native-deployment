# Registry & Repository Reference

> Centralized list of all remote URLs used in the air-gapped deployment.
> Update this file when upstream addresses change — playbooks reference these variables.

---

## 1. Upstream Container Registries (Mirrored via Harbor)

These are the **public registries** that Harbor caches as proxy-cache projects.

| Registry | Remote URL | Harbor Project | Purpose |
|----------|-----------|----------------|---------|
| Docker Hub | `https://docker.io` | `dockerhub-proxy` | Public images (nginx, redis, alpine, etc.) |
| Quay.io | `https://quay.io` | `quay-proxy` | Red Hat images, operators, Helm charts |
| Kubernetes | `https://registry.k8s.io` | `k8s-gcr-proxy` | K8s control plane images (kube-apiserver, etcd, etc.) |
| GitHub Container | `https://ghcr.io` | `ghcr-proxy` | GitHub-published containers |
| Google GCR | `https://gcr.io` | `gcr-proxy` | Google-published images |
| Elastic | `https://docker.elastic.co` | `elastic-proxy` | Elasticsearch, Kibana, Logstash |
| NGINX Inc | `https://pkgs.fury.io/nginx` | `nginx-proxy` | Official NGINX images |
| HashiCorp | `https://registry.hashicorp.com/hashicorp` | `hashicorp-proxy` | Vault, Consul, Terraform images |
| Calico | `https://quay.io/tigera` | `calico-proxy` | Tigera Calico operator images |
| Rancher | `https://registry.rancher.io` | `rancher-proxy` | Rancher system images |
| Ceph | `https://quay.io/ceph` | `ceph-proxy` | Ceph daemon images |
| MetalLB | `https://quay.io/metallb` | `metallb-proxy` | MetalLB controller/speaker images |
| cert-manager | `https://quay.io/jetstack` | `certmanager-proxy` | cert-manager controller/webhook images |

### NGINX Proxy Location Blocks

```nginx
# Each upstream registry maps to a location block on the proxy
# /docker/      → https://docker.io
# /quay/        → https://quay.io
# /k8s-gcr/     → https://registry.k8s.io
# /ghcr/        → https://ghcr.io
# /gcr/         → https://gcr.io
# /elastic/     → https://docker.elastic.co
# /hashicorp/   → https://registry.hashicorp.com/hashicorp
# /calico/      → https://quay.io/tigera
# /rancher/     → https://registry.rancher.io
# /ceph/        → https://quay.io/ceph
# /metallb/     → https://quay.io/metallb
# /certmanager/ → https://quay.io/jetstack
```

---

## 2. Upstream Package Repositories (Proxied via Nexus)

These are the **public package repos** that Nexus proxies and caches.

| Repository | Remote URL | Nexus Format Group | Purpose |
|------------|-----------|--------------------|---------|
| Ubuntu Noble | `http://archive.ubuntu.com/ubuntu` | `apt-ubuntu` | Base OS packages |
| Ubuntu Security | `http://security.ubuntu.com/ubuntu` | `apt-ubuntu` | Security updates |
| Docker CE | `https://download.docker.com/linux/ubuntu` | `apt-docker` | containerd.io, docker-ce |
| Kubernetes | `https://pkgs.k8s.io/core/stable/deb` | `apt-kubernetes` | kubeadm, kubelet, kubectl |
| Ceph Reef | `https://download.ceph.com/debian-reef` | `apt-ceph` | ceph-common, ceph-osd, etc. |
| HashiCorp | `https://apt.releases.hashicorp.com` | `apt-hashicorp` | Vault, Consul, Terraform |
| Helm | `https://baltocdn.com/helm/stable/deb` | `apt-helm` | Helm CLI |
| Helm (GitHub) | `https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3` | `helm-install` | Helm install script |
| Node.js (Nodesource) | `https://deb.nodesource.com/node_20.x` | `apt-nodejs` | Node.js runtime |
| PostgreSQL | `https://apt.postgresql.org/pub/repos/apt` | `apt-postgresql` | PostgreSQL server |
| NGINX | `https://nginx.org/packages/ubuntu` | `apt-nginx` | NGINX web server |

### Docker Registries Hosted in Nexus

| Registry Name | Remote URL | Nexus Type | Purpose |
|--------------|-----------|------------|---------|
| docker-hub-mirror | `https://registry-1.docker.io` | docker (proxy) | Public images |
| quay-mirror | `https://quay.io` | docker (proxy) | Quay images |
| k8s-gcr-mirror | `https://registry.k8s.io` | docker (proxy) | K8s images |
| ghcr-mirror | `https://ghcr.io` | docker (proxy) | GitHub containers |
| gcr-mirror | `https://gcr.io` | docker (proxy) | Google containers |

### Apt Sources on Clients

```bash
# All clients pull from Nexus, which proxies the upstream URLs
deb https://proxy.internal.lan/repository/apt-ubuntu/ubuntu noble main restricted universe multiverse
deb https://proxy.internal.lan/repository/apt-ubuntu/ubuntu noble-updates main restricted universe multiverse
deb https://proxy.internal.lan/repository/apt-ubuntu/ubuntu noble-security main restricted universe multiverse
deb [arch=amd64] https://proxy.internal.lan/repository/apt-docker noble stable
deb https://proxy.internal.lan/repository/apt-kubernetes kubernetes-xenial main
deb https://proxy.internal.lan/repository/apt-ceph reef main
```

---

## 3. Internal Git Repositories

These are the **source code / IaC repos** used for deployment.

| Repository | Remote URL | Branch | Description |
|------------|-----------|--------|-------------|
| Deployment Docs | `https://github.com/DavoudTeimouri/cloud-native-deployment.git` | `main` | This repo — documentation |
| KubeSpray | `https://github.com/kubernetes-sigs/kubespray.git` | `v2.24.0` | K8s deployment/ansible |
| Helm Charts (stable) | `https://github.com/helm/charts.git` | `main` | Legacy Helm charts |
| Prometheus Operator | `https://github.com/prometheus-operator/kube-prometheus.git` | `main` | Monitoring manifests |
| ArgoCD | `https://github.com/argoproj/argo-cd.git` | `stable` | GitOps manifests |
| Ceph | `https://github.com/ceph/ceph.git` | `reef` | Ceph source/docs |
| Calico | `https://github.com/projectcalico/calico.git` | `master` | CNI manifests & docs |
| MetalLB | `https://github.com/metallb/metallb.git` | `main` | LB manifests |
| cert-manager | `https://github.com/cert-manager/cert-manager.git` | `main` | Certificate management |
| Rancher | `https://github.com/rancher/rancher.git` | `release/v2.8` | Rancher source/docs |
| Velero | `https://github.com/vmware-tanzu/velero.git` | `main` | Backup tool |
| Loki | `https://github.com/grafana/loki.git` | `main` | Log aggregation |
| Gatekeeper | `https://github.com/open-policy-agent/gatekeeper.git` | `main` | OPA policies |
| Internal GitLab | `https://git.internal.lan/org/infra.git` | `main` | Custom manifests |

### Ansible Clone Commands

```bash
# Run during management server setup

# KubeSpray
git clone --depth 1 --branch v2.24.0 https://github.com/kubernetes-sigs/kubespray.git \
  ~/projects/kubespray

# Kube-prometheus
git clone https://github.com/prometheus-operator/kube-prometheus.git \
  ~/projects/kube-prometheus

# ArgoCD manifests
git clone --depth 1 --branch v2.6.7 https://github.com/argoproj/argo-cd.git \
  ~/projects/argo-cd

# Calico manifests
git clone --depth 1 https://github.com/projectcalico/calico.git \
  ~/projects/calico

# Gatekeeper policies
git clone --depth 1 https://github.com/open-policy-agent/gatekeeper.git \
  ~/projects/gatekeeper
```

---

## 4. Internal Artifact Repos

These are the **internal Nexus/Harbor repos** where proxied content is stored.

### Nexus Repositories

| Nexus Repo Name | Type | Remote URL | Stored At |
|----------------|------|-----------|--------|
| apt-ubuntu | apt (proxy) | `http://archive.ubuntu.com/ubuntu` | Ubuntu packages |
| apt-ubuntu-security | apt (proxy) | `http://security.ubuntu.com/ubuntu` | Security updates |
| apt-docker | apt (proxy) | `https://download.docker.com/linux/ubuntu` | Docker packages |
| apt-kubernetes | apt (proxy) | `https://pkgs.k8s.io/core/stable/deb` | K8s packages |
| apt-ceph | apt (proxy) | `https://download.ceph.com/debian-reef` | Ceph packages |
| apt-hashicorp | apt (proxy) | `https://apt.releases.hashicorp.com` | HashiCorp packages |
| apt-helm | apt (proxy) | `https://baltocdn.com/helm/stable/deb` | Helm packages |
| docker-hub | docker (proxy) | `https://registry-1.docker.io` | Docker Hub images |
| quay-proxy | docker (proxy) | `https://quay.io` | Quay images |
| k8s-gcr-proxy | docker (proxy) | `https://registry.k8s.io` | K8s control plane |
| ghcr-proxy | docker (proxy) | `https://ghcr.io` | GitHub containers |
| gcr-proxy | docker (proxy) | `https://gcr.io` | Google containers |
| kubespray-raw | raw (proxy) | `https://github.com/` | KubeSpray binaries |
| helm-install | raw (hosted) | — | get-helm-3 script |
| internal-raw | raw (hosted) | — | Internal builds |
| certs-raw | raw (hosted) | — | SSL certificates |
| ansible-galaxy | raw (proxy) | `https://galaxy.ansible.com` | Ansible roles |

### Harbor Projects

| Harbor Project | Type | Remote Target | Purpose |
|---------------|------|--------------|---------|
| dockerhub-proxy | proxy-cache | `docker.io` | Docker Hub mirror |
| quay-proxy | proxy-cache | `quay.io` | Quay mirror |
| k8s-gcr-proxy | proxy-cache | `registry.k8s.io` | K8s images |
| ghcr-proxy | proxy-cache | `ghcr.io` | GitHub containers |
| library | private | — | Internal images |
| k8s-system | private | — | K8s add-on images |
| monitoring | private | — | Monitoring stack images |
| platform | private | — | Platform component images |

---

## 5. Ansible Variable Reference

These are the variables used in playbooks — update them when URLs change:

```yaml
# group_vars/all/registry.yml

# === Upstream Registries ===
upstream_registries:
  docker_hub: "https://registry-1.docker.io"
  quay: "https://quay.io"
  k8s_gcr: "https://registry.k8s.io"
  ghcr: "https://ghcr.io"
  gcr: "https://gcr.io"
  elastic: "https://docker.elastic.co"
  calico: "https://quay.io/tigera"
  rancher: "https://registry.rancher.io"
  ceph: "https://quay.io/ceph"
  metallb: "https://quay.io/metallb"
  certmanager: "https://quay.io/jetstack"

# === Upstream Package Repos ===
upstream_packages:
  ubuntu: "http://archive.ubuntu.com/ubuntu"
  ubuntu_security: "http://security.ubuntu.com/ubuntu"
  docker: "https://download.docker.com/linux/ubuntu"
  kubernetes: "https://pkgs.k8s.io/core/stable/deb"
  ceph: "https://download.ceph.com/debian-reef"
  hashicorp: "https://apt.releases.hashicorp.com"
  helm: "https://baltocdn.com/helm/stable/deb"

# === Internal Proxy (single address for all) ===
proxy_host: "proxy.internal.lan"
proxy_ip: "10.0.0.10"

# === Internal Services (behind proxy) ===
nexus_host: "nexus.internal.lan"
nexus_ip: "10.0.0.201"
nexus_port: 8081
harbor_host: "harbor.internal.lan"
harbor_ip: "10.0.0.200"
harbor_port: 443

# === Internal Git Repos ===
git_repos:
  deployment: "https://github.com/DavoudTeimouri/cloud-native-deployment.git"
  kubespray: "https://github.com/kubernetes-sigs/kubespray.git"
  kube_prometheus: "https://github.com/prometheus-operator/kube-prometheus.git"
  argocd: "https://github.com/argoproj/argo-cd.git"
  calico: "https://github.com/projectcalico/calico.git"
  rancher: "https://github.com/rancher/rancher.git"
  ceph: "https://github.com/ceph/ceph.git"
  velero: "https://github.com/vmware-tanzu/velero.git"
  gatekeeper: "https://github.com/open-policy-agent/gatekeeper.git"
  loki: "https://github.com/grafana/loki.git"

# === Internal Services Direct ===
internal_git: "https://git.internal.lan"
internal_registry: "harbor.internal.lan"
internal_repo: "nexus.internal.lan"
internal_dns_primary: "10.0.0.2"
internal_dns_secondary: "10.0.0.3"

# === Versions ===
kube_version: "1.29.0"
helm_version: "3.14.0"
containerd_version: "1.7.12"
calico_version: "v3.27.0"
nexus_version: "3.64.0"
harbor_version: "v2.10.0"
rancher_version: "2.8.2"
argocd_version: "v2.9.3"
```

---

## 6. URL Change Procedure

When a remote URL changes:

1. **Update this doc** — change the URL in the relevant table above
2. **Update Ansible vars** — update `group_vars/all/registry.yml`
3. **Re-run the playbook** — `ansible-playbook client-proxy-config.yml`
4. **Verify** — test pull from all affected registries/repos

```bash
# Example: Docker Hub changes its registry URL

# Step 1: Update in this doc (section 1)
# Step 2: Update in Ansible vars
vim group_vars/all/registry.yml
# Change: docker_hub: "https://registry-1.docker.io" → new URL

# Also update Harbor proxy-cache project remote URL
curl -u admin:password -X PUT \
  "https://proxy.internal.lan/api/v2.0/projects/dockerhub-proxy" \
  -H "Content-Type: application/json" \
  -d '{"registry":{"url":"https://new-url.example.com"}}'

# Step 3: Push changes
git add -A && git commit -m "Update Docker Hub remote URL" && git push

# Step 4: Re-run config
ansible-playbook -i inventory/hosts.yml client-proxy-config.yml

# Step 5: Test
docker pull proxy.internal.lan/docker/library/nginx:1.25
```

---

## 7. Summary Matrix

| Category | Service | Remote URL | Internal Access |
|----------|---------|-----------|-----------------|
| Container Registry | Docker Hub | `registry-1.docker.io` | `proxy.internal.lan/docker/` |
| Container Registry | Quay.io | `quay.io` | `proxy.internal.lan/quay/` |
| Container Registry | K8s GCR | `registry.k8s.io` | `proxy.internal.lan/k8s-gcr/` |
| Container Registry | GitHub CR | `ghcr.io` | `proxy.internal.lan/ghcr/` |
| Apt Repo | Ubuntu | `archive.ubuntu.com` | `nexus.internal.lan/repository/apt-ubuntu/` |
| Apt Repo | Docker | `download.docker.com` | `nexus.internal.lan/repository/apt-docker/` |
| Apt Repo | Kubernetes | `pkgs.k8s.io` | `nexus.internal.lan/repository/apt-kubernetes/` |
| Apt Repo | Ceph | `download.ceph.com` | `nexus.internal.lan/repository/apt-ceph/` |
| Git Repo | Deployment | `github.com/DavoudTeimouri/...` | `git.internal.lan/org/infra.git` |
| Git Repo | KubeSpray | `github.com/kubernetes-sigs/...` | Mirrored locally |
| Git Repo | Monitoring | `github.com/prometheus-operator/...` | Mirrored locally |
| Artifact Store | Nexus | `nexus.internal.lan` | Direct |
| Artifact Store | Harbor | `harbor.internal.lan` | Direct |
