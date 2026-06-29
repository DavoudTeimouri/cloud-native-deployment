# Deployment Wizard

> Step-by-step interactive guide — choose your path and build your cluster

---

## How This Works

Answer a few questions. This guide will walk you through exactly what you
need to do based on your choices. No prior Kubernetes experience required.

```
START
  │
  ├── Q1: What is your deployment target?
  │     ├── Virtual Machine → Path A
  │     └── Physical Server → Path B
  │
  ├── Q2: How many nodes?
  │     ├── 1-5 nodes → K3s (lightweight)
  │     └── 5+ nodes → Full Kubernetes
  │
  ├── Q3: Do you have internet access?
  │     ├── Yes → Direct pull
  │     └── No (Air-gap) → Pre-staging required
  │
  ├── Q4: Do you need a GUI?
  │     ├── Yes → Install Rancher + k9s
  │     └── No → CLI only
  │
  ├── Q5: Which storage backend?
  │     ├── Ceph (full) → Ceph guide
  │     └── MinIO (object only) → MinIO guide
  │
  ├── Q6: DNS Configuration
  │     ├── Use internal DNS (BIND/CoreDNS) → DNS Step
  │     └── Use existing DNS → Skip
  │
  ├── Q7: Which components do you need?
  │     ├── Monitoring → Prometheus/Grafana
  │     ├── GitOps → ArgoCD
  │     ├── Backup → Velero
  │     ├── Registry → Harbor
  │     ├── Policy → Kyverno/Gatekeeper
  │     ├── Logging → Loki
  │     └── All → Full stack
  │
  └── Q8: Do you need post-deployment hardening?
        ├── Yes → Security hardening guide
        └── No → Skip to verification
```

---

## Step 1: Choose Your Deployment Target

### Option A: Virtual Machine

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| **Hypervisor** | Any (see below) | Proxmox, VMware, KVM |
| **CPU per node** | 2 cores | 4+ cores |
| **RAM per node** | 4 GB | 8+ GB |
| **Disk per node** | 50 GB | 100+ GB SSD |
| **Network** | 1 Gbps | 10 Gbps |

**Supported Hypervisors:**

| Hypervisor | Notes |
|------------|-------|
| **Proxmox VE** | Free, open-source, best for self-hosted |
| **VMware vSphere** | Enterprise, mature |
| **KVM/libvirt** | Linux-native, best performance |
| **Hyper-V** | Windows Server |
| **VirtualBox** | Development only |

→ Continue to [Step 2: Choose Cluster Size](#step-2-choose-cluster-size)

### Option B: Physical Server (Bare Metal)

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| **CPU** | 1 socket, 4 cores | 2 sockets, 8+ cores |
| **RAM** | 32 GB | 64+ GB ECC |
| **System disk** | 256 GB SSD | 512 GB SSD |
| **Storage disk** | 1 TB HDD/NVMe | 2+ TB (for Ceph) |
| **Network** | 1 Gbps | 10 Gbps, bonded |
| **BMC/IPMI** | For remote management | IPMI 2.0 / iDRAC / iLO |

**Additional bare-metal steps:**

```bash
# 1. Configure IPMI for remote management
ipmitool -H <bmc-ip> -U admin -P pass power on
ipmitool -H <bmc-ip> -U admin -P bootdev pxe

# 2. Set up PXE boot for automated OS install
sudo apt-get install -y dnsmasq tftpd-hpa
# Configure /etc/dnsmasq.d/pxe.conf

# 3. Configure network bonding (if multiple NICs)
cat > /etc/netplan/01-bond.yaml <<EOF
network:
  version: 2
  ethernets:
    enp1s0: {}
    enp2s0: {}
  bonds:
    bond0:
      addresses: [10.0.0.20/24]
      interfaces: [enp1s0, enp2s0]
      parameters:
        mode: 802.3ad
        transmit-hash-policy: layer3+4
EOF
sudo netplan apply

# 4. Configure RAID (if not using Ceph for all storage)
sudo mdadm --create /dev/md0 --level=10 --raid-devices=4 /dev/sd[abcd]
```

→ Continue to [Step 2: Choose Cluster Size](#step-2-choose-cluster-size)

---

## Step 2: Choose Cluster Size

### Option A: Small Cluster (1-5 nodes) → K3s

K3s is perfect for small deployments. It's a lightweight, easy-to-install
Kubernetes distribution.

| Component | Specification |
|-----------|--------------|
| **Nodes** | 1-5 |
| **Control plane** | Embedded in nodes (no separate masters) |
| **etcd** | Built-in (SQLite or embedded etcd) |
| **Installation** | Single command |
| **Resource usage** | Very low |

**Quick install:**
```bash
# On first node (server)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--system-default-registry=harbor.internal" sh -

# On additional nodes (agents)
curl -sfL https://get.k3s.io | K3S_URL=https://<server>:6443 K3S_TOKEN=<token> sh -

# Verify
kubectl get nodes
```

**Variables to change:**
| Variable | Default | Your Value |
|----------|---------|------------|
| `K3S_URL` | `https://<server>:6443` | Your server IP |
| `K3S_TOKEN` | From `/var/lib/rancher/k3s/server/node-token` | Your token |
| `--system-default-registry` | `harbor.internal` | Your registry |

→ Continue to [Step 3: Network & Internet Access](#step-3-network--internet-access)

### Option B: Production Cluster (5+ nodes) → Full Kubernetes

Full Kubernetes via KubeSpray for production deployments.

| Component | Specification |
|-----------|--------------|
| **Control plane** | 3 dedicated master nodes |
| **Workers** | 3+ worker nodes |
| **etcd** | Dedicated disk on masters (SSD/NVMe) |
| **Installation** | KubeSpray (Ansible) |
| **High availability** | Built-in |

**Node layout:**
```
┌─────────────────────────────────────────────────────┐
│ Production Cluster │
│ │
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│ │ Master 1 │ │ Master 2 │ │ Master 3 │ │
│ │ 10.0.0.11│ │ 10.0.0.12│ │ 10.0.0.13│ │
│ │ │ │ │ │ │ │
│ │ API Srv │ │ API Srv │ │ API Srv │ │
│ │ etcd │ │ etcd │ │ etcd │ │
│ │ Scheduler│ │ Ctr Mgr │ │ Scheduler│ │
│ └──────────┘ └──────────┘ └──────────┘ │
│ │
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│ │ Worker 1 │ │ Worker 2 │ │ Worker 3 │ │
│ │ 10.0.0.21│ │ 10.0.0.22│ │ 10.0.0.23│ │
│ │ │ │ │ │ │ │
│ │ kubelet │ │ kubelet │ │ kubelet │ │
│ │ Ceph OSD│ │ Ceph OSD│ │ Ceph OSD│ │
│ └──────────┘ └──────────┘ └──────────┘ │
└─────────────────────────────────────────────────────┘
```

**Variables to change** (in KubeSpray inventory):
| Variable | Default | Your Value |
|----------|---------|------------|
| `kube_version` | `v1.29.0` | Your K8s version |
| `kube_network_plugin` | `calico` | Your CNI choice |
| `kube_apiserver_ip` | `10.0.0.100` | Your VIP IP |
| Master IPs | `10.0.0.11-13` | Your master IPs |
| Worker IPs | `10.0.0.21-23` | Your worker IPs |
| `etcd_disk` | `/dev/sdb` | Your dedicated etcd disk |

→ Continue to [Step 4: DNS Configuration](#step-4-dns-configuration)

---

## Step 4: DNS Configuration

DNS is critical for the transparent proxy architecture. Clients use
canonical public domain names (like `archive.ubuntu.com`), and your DNS
server resolves them to the reverse proxy IP.

### Option A: Dedicated BIND Server

```bash
# Install BIND
sudo apt-get install -y bind9

# Configure named.conf.local
cat > /etc/bind/named.conf.local <<EOF
zone "archive.ubuntu.com" {
    type master;
    file "/etc/bind/zones/forward.conf";
};

zone "registry-1.docker.io" {
    type master;
    file "/etc/bind/zones/forward.conf";
};

zone "quay.io" {
    type master;
    file "/etc/bind/zones/forward.conf";
};

zone "registry.k8s.io" {
    type master;
    file "/etc/bind/zones/forward.conf";
};

zone "download.docker.com" {
    type master;
    file "/etc/bind/zones/forward.conf";
};

zone "pkgs.k8s.io" {
    type master;
    file "/etc/bind/zones/forward.conf";
};

zone "download.ceph.com" {
    type master;
    file "/etc/bind/zones/forward.conf";
};

zone "github.com" {
    type master;
    file "/etc/bind/zones/forward.conf";
};

zone "pypi.org" {
    type master;
    file "/etc/bind/zones/forward.conf";
};

zone "npmjs.org" {
    type master;
    file "/etc/bind/zones/forward.conf";
};
EOF

# All zones point to proxy IP
cat > /etc/bind/zones/forward.conf <<EOF
\$TTL 86400
@   IN  SOA ns1.internal.lan. admin.internal.lan. (
        2024010101 3600 900 604800 86400 )
    IN  NS  ns1.internal.lan.
*   IN  A   10.0.0.10
EOF

sudo systemctl restart bind9
```

### Option B: CoreDNS (If Using K8s DNS)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  forward.conf: |
    archive.ubuntu.com {
      forward . 10.0.0.10
    }
    registry-1.docker.io {
      forward . 10.0.0.10
    }
    quay.io {
      forward . 10.0.0.10
    }
    registry.k8s.io {
      forward . 10.0.0.10
    }
    download.docker.com {
      forward . 10.0.0.10
    }
    pkgs.k8s.io {
      forward . 10.0.0.10
    }
    download.ceph.com {
      forward . 10.0.0.10
    }
    github.com {
      forward . 10.0.0.10
    }
    pypi.org {
      forward . 10.0.0.10
    }
    npmjs.org {
      forward . 10.0.0.10
    }
```

### Option C: /etc/hosts (Development Only)

```bash
# Add to /etc/hosts on every machine
echo "10.0.0.10 archive.ubuntu.com" | sudo tee -a /etc/hosts
echo "10.0.0.10 registry-1.docker.io" | sudo tee -a /etc/hosts
echo "10.0.0.10 quay.io" | sudo tee -a /etc/hosts
echo "10.0.0.10 registry.k8s.io" | sudo tee -a /etc/hosts
echo "10.0.0.10 download.docker.com" | sudo tee -a /etc/hosts
echo "10.0.0.10 pkgs.k8s.io" | sudo tee -a /etc/hosts
echo "10.0.0.10 download.ceph.com" | sudo tee -a /etc/hosts
echo "10.0.0.10 github.com" | sudo tee -a /etc/hosts
echo "10.0.0.10 pypi.org" | sudo tee -a /etc/hosts
echo "10.0.0.10 npmjs.org" | sudo tee -a /etc/hosts
```

### Internal DNS Records

Also configure internal service names:

```bash
# Add to your DNS server
cat >> /etc/bind/zones/internal.lan.conf <<EOF
proxy       IN  A   10.0.0.10
nexus       IN  CNAME   proxy.internal.lan.
harbor      IN  CNAME   proxy.internal.lan.
registry    IN  CNAME   proxy.internal.lan.
gitlab      IN  A   10.0.0.202
k8s-api     IN  A   10.0.0.100
mgmt        IN  A   10.0.0.10
EOF
```

### Verify DNS

```bash
# Test from any client
dig archive.ubuntu.com          # Should return 10.0.0.10
dig registry-1.docker.io       # Should return 10.0.0.10
dig k8s-api.internal.lan       # Should return 10.0.0.100

# Or use nslookup
nslookup archive.ubuntu.com
nslookup registry-1.docker.io
```

**Variables to change:**
| Variable | Defaults | Your Value |
|----------|---------|------------|
| Proxy IP | `10.0.0.10` | Your proxy server IP |
| GitLab IP | `10.0.0.202` | Your GitLab server IP |
| K8s API IP | `10.0.0.100` | Your K8s VIP IP |
| Management IP | `10.0.0.10` | Your management server IP |

→ Continue to [Step 5: GUI Preference](#step-5-gui-preference)

### Option A: Internet Available

You can pull images and packages directly. No special configuration needed.

**What you need:**
- DNS resolution (8.8.8.8 or your ISP's DNS)
- Outbound HTTPS (port 443) to:
  - `registry-1.docker.io`
  - `quay.io`
  - `github.com`
  - `archive.ubuntu.com`

→ Continue to [Step 4: GUI Preference](#step-4-gui-preference)

### Option B: Air-Gap (No Internet)

All data must be pre-staged before disconnecting from the internet.

**Pre-staging checklist:**
```bash
# 1. Download all container images
./scripts/pre-stage-images.sh

# 2. Sync apt packages to Nexus
./scripts/sync-apt-packages.sh

# 3. Sync Docker images to Nexus
./scripts/sync-docker-images.sh

# 4. Verify all data is in Nexus/Harbor
curl -s http://nexus.internal:8081/service/rest/v1/status
curl -s https://harbor.internal/api/v2.0/health

# 5. Disconnect from internet
```

**After air-gap, the reverse proxy serves from Nexus/Harbor cache:**
```
Client: apt-get install nginx
    → archive.ubuntu.com → Proxy → Nexus cache → serve

Client: docker pull nginx:1.25
    → registry-1.docker.io → Proxy → Harbor cache → serve
```

→ Continue to [Step 4: GUI Preference](#step-4-gui-preference)

---

## Step 5: GUI Preference

### Option A: With GUI (Recommended for Beginners)

Install these tools for visual management:

| Tool | Type | What It Does | Install |
|------|------|-------------|---------|
| **Rancher** | Web UI | Multi-cluster management, monitoring | Helm |
| **k9s** | Terminal | Terminal-based K8s dashboard | Binary |
| **Lens** | Desktop | Full K8s IDE | Desktop app |
| **Cockpit** | Web UI | Linux server monitoring | apt |
| **Grafana** | Web UI | Metrics dashboards | Helm |
| **ArgoCD UI** | Web UI | GitOps dashboard | Built-in |

**Quick install:**
```bash
# Rancher
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm install rancher rancher-latest/rancher \
  --namespace cattle-system --create-namespace \
  --set hostname=rancher.internal.lan \
  --set replicas=3

# k9s
curl -sS https://webinstall.dev/k9s | bash

# Cockpit (on each server)
sudo apt-get install -y cockpit cockpit-storaged
sudo systemctl enable --now cockpit.socket
# Access: https://<server-ip>:9090
```

→ Continue to [Step 5: Storage Backend](#step-5-storage-backend)

### Option B: CLI Only (Advanced Users)

Use command-line tools only:

| Tool | Purpose | Install |
|------|---------|---------|
| **kubectl** | K8s management | Binary |
| **helm** | Package manager | Binary |
| **k9s** | Terminal UI (optional) | Binary |
| **stern** | Log tailing | Binary |

**Quick install:**
```bash
# kubectl
curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# stern
curl -sL https://github.com/stern/stern/releases/latest/download/stern_linux_amd64.tar.gz | tar xz
sudo mv stern /usr/local/bin/
```

→ Continue to [Step 6: Storage Backend](#step-6-storage-backend)

---

## Step 6: Storage Backend

### Option A: Ceph (Full Storage — Recommended)

Ceph provides block storage (RBD), object storage (RGW), and filesystem
(CephFS) in one cluster.

| Component | Nodes | Disks | Purpose |
|-----------|-------|-------|---------|
| **MON** | 3 | Small SSD | Cluster state |
| **OSD** | 3+ | HDD/SSD/NVMe | Data storage |
| **MDS** | 2 | SSD | CephFS metadata |
| **RGW** | 2 | SSD | S3-compatible object |

**Minimum hardware:**
- 3 nodes (can be the same as K8s workers)
- 1 dedicated SSD per node for etcd
- 1+ HDD/SSD per node for OSD data

**Quick start:**
```bash
# Deploy Ceph via Rook-Ceph operator
kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/operator.yaml

# Create Ceph cluster
kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/cluster.yaml

# Verify
kubectl -n rook-ceph get pods
```

**Variables to change:**
| Variable | Default | Your Value |
|----------|---------|------------|
| `ceph_cluster_name` | `rook-ceph` | Your name |
| `ceph_osd_path` | `/dev/sdb` | Your OSD disk |
| `ceph_mon_count` | `3` | 3 or 5 |
| `ceph_replica_size` | `3` | 2 or 3 |

→ Continue to [Step 6: Select Components](#step-6-select-components)

### Option B: MinIO (Object Storage Only)

MinIO is a lightweight S3-compatible object storage. Use if you only need
object storage (backups, artifacts) and not block/filesystem.

| Component | Nodes | Disks | Purpose |
|-----------|-------|-------|---------|
| **MinIO** | 1+ | HDD/SSD | Object storage |

**Quick start:**
```bash
# Single-node MinIO
docker run -d \
  --name minio \
  -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=*** \
  -v /opt/minio/data:/data \
  minio/minio:latest server /data --console-address ":9001"

# Or via Helm
helm repo add minio https://charts.min.io/
helm install minio minio/minio \
  --namespace minio --create-namespace \
  --set mode=standalone \
  --set persistence.size=100Gi \
  --set rootUser=minioadmin,rootPassword=***
```

**Variables to change:**
| Variable | Default | Your Value |
|----------|---------|------------|
| `MINIO_ROOT_USER` | `minioadmin` | Your username |
| `MINIO_ROOT_PASSWORD` | `minioadmin` | Your password |
| `/opt/minio/data` | `/data` | Your data path |
| `persistence.size` | `100Gi` | Your storage size |

→ Continue to [Step 7: Select Components](#step-7-select-components)

---

## Step 7: Select Components

Choose which components you need. Each includes installation and
configuration.

### Option A: Full Stack (All Components)

Install everything:
- Monitoring (Prometheus/Grafana)
- GitOps (ArgoCD)
- Backup (Velero)
- Registry (Harbor)
- Source Control (GitLab)
- Policy (Kyverno)
- Logging (Loki)

→ Go to [Full Stack Deployment](#full-stack-deployment)

### Option B: Custom Selection

Check the components you need:

| Component | I need this | Guide |
|-----------|------------|-------|
| ☐ Monitoring | Prometheus + Grafana + Loki | [Monitoring](docs/monitoring/) |
| ☐ GitOps | ArgoCD | [Platform](docs/platform/argocd.md) |
| ☐ Backup | Velero | [Velero](docs/velero/) |
| ☐ Registry | Harbor | [Container Services](docs/operations/container-services.md) |
| ☐ Source Control | GitLab | [GitLab](docs/gitlab/deployment.md) |
| ☐ Policy | Kyverno | [Addons](docs/operations/kubernetes-addons.md) |
| ☐ Logging | Loki | [Monitoring](docs/monitoring/logging.md) |
| ☐ Policy | Kyverno | [Addons](docs/operations/kubernetes-addons.md) |
| ☐ Logging | Loki | [Monitoring](docs/monitoring/logging.md) |
| ☐ Service Mesh | Linkerd/Istio | [Service Mesh](docs/operations/service-mesh.md) |
| ☐ Ingress | NGINX Ingress | [Networking](docs/networking/) |
| ☐ Load Balancer | MetalLB | [Networking](docs/networking/load-balancer-ingress.md) |
| ☐ Hardening | K8s/Ceph/OS security | [Hardening](docs/operations/hardening.md) |

---

## Step 8: Post-Deployment Hardening

After deployment, you should secure your cluster. This is **recommended for
all production deployments**.

### Hardening Checklist

| Area | Task | Priority |
|------|------|----------|
| **Kubernetes** | Enable Pod Security Standards | High |
| **Kubernetes** | Enable NetworkPolicies | High |
| **Kubernetes** | Enable audit logging | High |
| **Kubernetes** | Disable automounting service account tokens | Medium |
| **Kubernetes** | Configure RBAC (remove cluster-admin from service accounts) | High |
| **Kubernetes** | Enable Kyverno/Gatekeeper policies | High |
| **Ceph** | Enable Ceph dashboard authentication | High |
| **Ceph** | Restrict Ceph MON network access | High |
| **Ceph** | Enable CephX authentication | High |
| **OS** | Disable root SSH login | High |
| **OS** | Enable UFW firewall | High |
| **OS** | Enable automatic security updates | Medium |
| **OS** | Disable unnecessary services | Medium |
| **OS** | Enable auditd | Medium |
| **OS** | Configure fail2ban | Medium |
| **Network** | Enable TLS everywhere | High |
| **Network** | Restrict etcd access to control plane only | High |
| **Secrets** | Enable Vault for secrets management | Medium |
| **Backup** | Verify Velero backups work | High |

→ Go to [Hardening Guide](docs/operations/hardening.md) for detailed steps.

---

## Full Stack Deployment

### Pre-Deployment Checklist

Before starting, ensure you have:

- [ ] All servers provisioned (VMs or bare metal)
- [ ] SSH access to all servers (key-based, no passwords)
- [ ] DNS configured (all names resolve to proxy IP)
- [ ] Time synchronized (chrony running on all nodes)
- [ ] Swap disabled on all K8s nodes
- [ ] Firewall rules configured (ports open for K8s)
- [ ] If air-gap: all data pre-staged in Nexus/Harbor

### Deployment Order

```
Step 1: Prepare OS
    │
    ▼
Step 2: Deploy Kubernetes (or K3s)
    │
    ▼
Step 3: Deploy Storage (Ceph or MinIO)
    │
    ▼
Step 4: Deploy Reverse Proxy + Load Balancer
    │
    ▼
Step 5: Deploy Platform Components
    │
    ├── Rancher (if GUI selected)
    ├── ArgoCD (if GitOps selected)
    ├── Kyverno (if Policy selected)
    │
    ▼
Step 6: Deploy Monitoring
    │
    ├── Prometheus + Grafana
    ├── Loki
    │
    ▼
Step 7: Deploy Backup (Velero)
    │
    ▼
Step 8: Deploy Development Tools
    │
    ├── GitLab (if Source Control selected)
    ├── Harbor (if Registry selected)
    │
    ▼
Step 9: Verify Everything
```

### Step 1: Prepare OS

```bash
# Run on ALL servers
ansible-playbook -i inventory/hosts.yml ansible/playbooks/os-preparation.yml
```

**Variables to change:**
| Variable | Default | Your Value |
|----------|---------|------------|
| `timezone` | `America/New_York` | Your timezone |
| `ntp_servers` | `10.0.0.1, 10.0.0.2` | Your NTP servers |
| `dns_servers` | `10.0.0.2, 10.0.0.3` | Your DNS servers |
| `deploy_user` | `deploy` | Your SSH user |

### Step 2: Deploy Kubernetes

**For full Kubernetes (5+ nodes):**
```bash
ansible-playbook -i inventory/hosts.yml ansible/playbooks/kubespray-deploy.yml
```

**For K3s (1-5 nodes):**
```bash
curl -sfL https://get.k3s.io | sh -
```

### Step 3: Deploy Storage

**For Ceph:**
```bash
kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/operator.yaml
kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/cluster.yaml
```

**For MinIO:**
```bash
helm install minio minio/minio --namespace minio --create-namespace
```

### Step 4: Deploy Reverse Proxy + Load Balancer

```bash
# MetalLB (Load Balancer)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.0/config/manifests/metallb-native.yaml

# NGINX Ingress
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer
```

### Step 5: Deploy Platform Components

```bash
# Rancher
helm install rancher rancher-latest/rancher \
  --namespace cattle-system --create-namespace \
  --set hostname=rancher.internal.lan

# ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Kyverno
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace
```

### Step 6: Deploy Monitoring

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

### Step 7: Deploy Backup

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=minio,s3ForcePathStyle=true,s3Url=http://minio.internal:9000 \
  --use-restic
```

### Step 8: Deploy Development Tools

```bash
# GitLab
helm install gitlab gitlab/gitlab --namespace gitlab --create-namespace

# Harbor
helm install harbor goharbor/harbor --namespace harbor --create-namespace
```

### Step 9: Verify Everything

```bash
# Run the health check script
./scripts/health-check.sh

# Or check manually
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get svc -n ingress-nginx
```

---

## Quick Reference: Variables to Change

This table lists every variable you need to customize for your environment:

| Category | Variable | Where | Your Value |
|----------|----------|-------|------------|
| **Network** | Master IPs | KubeSpray inventory | |
| | Worker IPs | KubeSpray inventory | |
| | VIP IP | KubeSpray `loadbalancer_apiserver` | |
| | Proxy IP | DNS records | |
| **DNS** | All `*.internal.lan` | BIND/CoreDNS | |
| | Public domains | DNS forward zones | |
| **Time** | Timezone | `os-preparation.yml` | |
| | NTP servers | `os-preparation.yml` | |
| **Storage** | Ceph OSD disk | Rook cluster spec | |
| | MinIO credentials | Helm values | |
| | MinIO data path | Docker mount | |
| **Kubernetes** | K8s version | KubeSpray `kube_version` | |
| | CNI plugin | KubeSpray `kube_network_plugin` | |
| | Container runtime | KubeSpray `container_manager` | |
| **Components** | Rancher hostname | Helm `set hostname` | |
| | GitLab URL | Helm `set global.hosts.domain` | |
| | Harbor URL | Helm `set externalURL` | |
| **Monitoring** | Grafana admin password | Helm `set grafana.adminPassword` | |
| **Backup** | S3 endpoint | Velero `s3Url` | |
| | S3 bucket | Velero `bucket` | |
| | S3 credentials | `credentials-velero` file | |

---

## What's Next?

- **Need help?** Each step links to the detailed guide for that component.
- **Want to change something later?** Use the [Alternatives](docs/alternatives.md) guide.
- **Something broken?** Check the [Troubleshooting](docs/troubleshooting/) section.
- **Need a GUI?** See [Step 4: GUI Preference](#step-4-gui-preference).
