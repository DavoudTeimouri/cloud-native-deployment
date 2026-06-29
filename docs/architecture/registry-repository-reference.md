# Registry & Repository Reference

> Centralized list of all remote URLs — all transparent via reverse proxy, zero client config

---

## 1. Canonical URLs (What Clients Use)

Clients use **exactly the same URLs** as on the internet. No custom mirror
hostnames. No special configuration.

### Container Registries

| Registry | Client URL | Proxy Cache | Purpose |
|----------|-----------|-------------|---------|
| Docker Hub | `https://registry-1.docker.io` | Harbor proxy-cache | Public images |
| Quay.io | `https://quay.io` | Harbor proxy-cache | Red Hat, operators |
| Kubernetes GCR | `https://registry.k8s.io` | Nexus proxy-cache | K8s system images |
| GitHub Container | `https://ghcr.io` | Nexus proxy-cache | GitHub containers |
| Google GCR | `https://gcr.io` | Nexus proxy-cache | Google containers |
| Elastic | `https://docker.elastic.co` | Nexus proxy-cache | Elastic stack |
| Calico | `https://quay.io/tigera` | Nexus proxy-cache | Calico images |

### Package Repositories

| Repository | Client URL | Proxy Cache | Purpose |
|------------|-----------|-------------|---------|
| Ubuntu | `http://archive.ubuntu.com/ubuntu` | Nexus apt-proxy | Base OS packages |
| Ubuntu Security | `http://security.ubuntu.com/ubuntu` | Nexus apt-proxy | Security updates |
| Docker CE | `https://download.docker.com/linux/ubuntu` | Nexus apt-proxy | containerd, docker-ce |
| Kubernetes | `https://pkgs.k8s.io/core/stable/deb` | Nexus apt-proxy | kubeadm, kubelet, kubectl |
| Ceph Reef | `https://download.ceph.com/debian-reef` | Nexus apt-proxy | ceph-common, ceph-osd |
| PyPI | `https://pypi.org` | Nexus pypi-proxy | Python packages |
| npm | `https://registry.npmjs.org` | Nexus npm-proxy | Node.js packages |
| Maven Central | `https://repo1.maven.org/maven2` | Nexus maven-proxy | Java packages |
| HashiCorp | `https://apt.releases.hashicorp.com` | Nexus apt-proxy | Vault, Consul, Terraform |

---

## 2. Internal Service Locations (Behind Proxy)

These are **NOT configured on clients**. The reverse proxy routes to them
automatically based on the public domain name.

| Service | Internal Address | Purpose | Serves |
|---------|----------------|---------|--------|
| Nexus | `10.0.0.201:8081` | Package/repo proxy | archive.ubuntu.com, pypi.org, npmjs.org, etc. |
| Harbor | `10.0.0.200:443` | Container registry cache | registry-1.docker.io, quay.io, etc. |
| Reverse Proxy | `10.0.0.10:443` | Transparent proxy | All public domains |

---

## 3. Air-Gap: Pre-Staging Requirements

In air-gap mode, the proxy cannot reach the internet. All data must be
pre-staged into Nexus and Harbor.

### Nexus Must Cache

- All apt packages your servers need (Ubuntu noble)
- All Docker images your pods need (via Nexus Docker proxy)
- All Python/Node/Java/Maven dependencies
- All Helm charts

### Harbor Must Cache

- All public container images you use (via proxy-cache projects)
- K8s system images (pause, etcd, coredns, kube-apiserver, etc.)
- Calico, ArgoCD, Rancher, etc.

---

## 4. Ansible Variable Reference

```yaml
# group_vars/all/registry.yml

# === Canonical URLs (clients use these) ===
canonical_urls:
  apt_ubuntu: "http://archive.ubuntu.com/ubuntu"
  apt_ubuntu_security: "http://security.ubuntu.com/ubuntu"
  apt_docker: "https://download.docker.com/linux/ubuntu"
  apt_kubernetes: "https://pkgs.k8s.io/core/stable/deb"
  apt_ceph: "https://download.ceph.com/debian-reef"
  docker_hub: "https://registry-1.docker.io"
  quay: "https://quay.io"
  k8s_gcr: "https://registry.k8s.io"
  ghcr: "https://ghcr.io"
  pypi: "https://pypi.org"
  npm: "https://registry.npmjs.org"
  maven: "https://repo1.maven.org/maven2"
  hashicorp: "https://apt.releases.hashicorp.com"

# === Internal addresses (NOT configured on clients) ===
internal_addresses:
  nexus: "10.0.0.201"
  nexus_port: 8081
  harbor: "10.0.0.200"
  harbor_port: 443
  proxy: "10.0.0.10"
  proxy_port: 443

# === DNS zones (all resolve to proxy IP) ===
dns_proxy_domains:
  - archive.ubuntu.com
  - security.ubuntu.com
  - download.docker.com
  - registry-1.docker.io
  - quay.io
  - registry.k8s.io
  - ghcr.io
  - gcr.io
  - pkgs.k8s.io
  - download.ceph.com
  - github.com
  - pypi.org
  - npmjs.org
  - files.pythonhosted.org
```

---

## 5. DNS Configuration Reference

All public repository domains → proxy IP (10.0.0.10):

```bash
# BIND zone entries
archive.ubuntu.com.    IN  A  10.0.0.10
security.ubuntu.com.  IN  A  10.0.0.10
download.docker.com.  IN  A  10.0.0.10
registry-1.docker.io. IN  A  10.0.0.10
quay.io.              IN  A  10.0.0.10
registry.k8s.io.     IN  A  10.0.0.10
ghcr.io.             IN  A  10.0.0.10
gcr.io.              IN  A  10.0.0.10
pkgs.k8s.io.         IN  A  10.0.0.10
download.ceph.com.   IN  A  10.0.0.10
github.com.          IN  A  10.0.0.10
pypi.org.            IN  A  10.0.0.10
npmjs.org.           IN  A  10.0.0.10
```

---

## 6. URL Change Procedure

When a remote URL changes:

1. **No client changes needed** — the canonical URL stays the same
2. **Update Nexus/Harbor proxy config** — point to new upstream
3. **Clear cache** — purge old cached data
4. **Verify** — test pull from client

```bash
# Example: Docker Hub changes its registry URL

# Step 1: Update Harbor proxy-cache project
curl -u admin:password -X PUT \
  "https://harbor.internal/api/v2.0/projects/dockerhub-proxy" \
  -H "Content-Type: application/json" \
  -d '{"registry":{"url":"https://new-registry-url.example.com"}}'

# Step 2: Clear NGINX cache
sudo rm -rf /var/cache/nginx/docker/*

# Step 3: Test from client (no changes needed)
docker pull nginx:1.25
```
