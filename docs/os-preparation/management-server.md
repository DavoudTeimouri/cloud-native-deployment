# Management Server Setup Guide

> Linux server preparation for Ansible control node and cluster management

---

## Overview

The management server acts as the central control plane for your entire
cloud-native deployment. It runs:

- **Ansible** — Infrastructure automation and KubeSpray deployments
- **kubectl** — Kubernetes cluster administration
- **Helm** — Chart-based application deployments
- **ctx (kubectx/kubens)** — Fast context and namespace switching
- **Cockpit** — Web-based server monitoring (optional)
- **Git** — Version control for IaC and manifests
- **Docker/Podman** — Local image management and testing

This server is **not** a Kubernetes node — it manages clusters from outside.

---

## 1. OS Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| Disk | 100 GB SSD | 250 GB SSD |
| Network | 1 Gbps | 10 Gbps |

---

## 2. Base System Setup

### 2.1 Update System

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y \
  curl wget gnupg2 software-properties-common \
  apt-transport-https ca-certificates lsb-release \
  bash-completion vim htop tmux git jq tree \
  unzip zip net-tools dnsutils iputils-ping \
  python3 python3-pip python3-venv
```

### 2.2 Configure Hostname and Hosts

```bash
sudo hostnamectl set-hostname mgmt-server.internal.lan

cat >> /etc/hosts <<EOF
10.0.0.10   mgmt-server.internal.lan mgmt-server
10.0.0.11   master-1.internal.lan master-1
10.0.0.12   master-2.internal.lan master-2
10.0.0.13   master-3.internal.lan master-3
10.0.0.20   worker-1.internal.lan worker-1
10.0.0.21   worker-2.internal.lan worker-2
10.0.0.100  vip.internal.lan vip
10.0.0.200  harbor.internal.lan harbor
10.0.0.201  nexus.internal.lan nexus
EOF
```

### 2.3 Configure Time Sync

```bash
sudo apt-get install -y chrony

cat > /etc/chrony/chrony.conf <<EOF
server ntp1.internal.lan iburst prefer
server ntp2.internal.lan iburst
driftfile /var/lib/chrony/chrony.drift
allow 10.0.0.0/8
local stratum 10
logdir /var/log/chrony
rtcsync
makestep 1.0 3
EOF

sudo systemctl enable chrony
sudo systemctl restart chrony
chronyc tracking
chronyc sources
```

### 2.4 Configure DNS

```bash
cat > /etc/resolv.conf <<EOF
nameserver 10.0.0.2
nameserver 10.0.0.3
search internal.lan cluster.local
options timeout:2 attempts:3
EOF
```

---

## 3. SSH Configuration

### 3.1 Harden SSH Server

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat > /etc/ssh/sshd_config <<EOF
Protocol 2
Port 22

# Authentication
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey

# Ciphers
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Limits
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# Features
X11Forwarding no
AllowTcpForwarding yes
AllowAgentForwarding no
PermitTunnel no
LogLevel VERBOSE

# Allow management user
AllowUsers deploy
EOF

sudo systemctl restart sshd
```

### 3.2 Create Deploy User

```bash
sudo useradd -m -s /bin/bash -c "Ansible Deploy User" deploy
sudo usermod -aG sudo,adm,systemd-journal deploy
echo "deploy ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/deploy
sudo chmod 440 /etc/sudoers.d/deploy
```

### 3.3 SSH Key Generation

```bash
# On management server (as deploy user)
sudo su - deploy
ssh-keygen -t ed25519 -C "deploy@mgmt-server" -f ~/.ssh/id_ed25519 -N ""

# Copy to all target nodes
for host in master-1 master-2 master-3 worker-1 worker-2; do
  ssh-copy-id -i ~/.ssh/id_ed25519 deploy@${host}.internal.lan
done
```

### 3.4 SSH Config for Quick Access

```bash
cat > ~/.ssh/config <<EOF
Host *
    User deploy
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host master-1
    HostName 10.0.0.11

Host master-2
    HostName 10.0.0.12

Host master-3
    HostName 10.0.0.13

Host worker-1
    HostName 10.0.0.20

Host worker-2
    HostName 10.0.0.21

Host vip
    HostName 10.0.0.100

Host harbor
    HostName 10.0.0.200

Host nexus
    HostName 10.0.0.201
EOF

chmod 600 ~/.ssh/config
```

---

## 4. Ansible Installation

### 4.1 Install Ansible (Latest)

```bash
sudo su - deploy

# Create Python virtual environment for isolation
python3 -m venv ~/ansible-venv
source ~/ansible-venv/bin/activate

# Install Ansible and dependencies
pip install --upgrade pip
pip install ansible-core ansible-lint yamllint molecule

# Verify
ansible --version
```

### 4.2 Ansible Configuration

```bash
mkdir -p ~/ansible
cat > ~/ansible/ansible.cfg <<EOF
[defaults]
inventory = ./inventory
remote_tmp = /tmp/.ansible/tmp
local_tmp = /tmp/.ansible/tmp
host_key_checking = False
retry_files_enabled = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts_cache
fact_caching_timeout = 3600
stdout_callback = yaml
timeout = 30
forks = 20

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o PreferredAuthentications=publickey
control_path_dir = /tmp/.ansible/cp
control_path = %%h-%%r
EOF
```

### 4.3 Install Ansible Collections

```bash
ansible-galaxy collection install \
  kubernetes.core \
  community.general \
  community.docker \
  community.crypto \
  ansible.posix \
  ansible.netcommon
```

### 4.4 Create Inventory Structure

```bash
cd ~/ansible
mkdir -p inventory/{mgmt-cluster,app-cluster}/{group_vars,host_vars}
mkdir -p playbooks roles collections
mkdir -p files templates

# Create base inventory
cat > inventory/hosts.yml <<EOF
all:
  children:
    mgmt_cluster:
      children:
        kube_control_plane:
          hosts:
            master-1:
              ansible_host: 10.0.0.11
            master-2:
              ansible_host: 10.0.0.12
            master-3:
              ansible_host: 10.0.0.13
        kube_node:
          hosts:
            worker-1:
              ansible_host: 10.0.0.20
            worker-2:
              ansible_host: 10.0.0.21
        etcd:
          hosts:
            master-1:
            master-2:
            master-3:
    app_cluster:
      children:
        kube_control_plane:
          hosts:
            app-master-1:
              ansible_host: 10.0.1.11
        kube_node:
          hosts:
            app-worker-1:
              ansible_host: 10.0.1.20
EOF
```

### 4.5 Test Connectivity

```bash
cd ~/ansible
source ~/ansible-venv/bin/activate
ansible all -i inventory/hosts.yml -m ping
```

---

## 5. kubectl Installation

```bash
# Download specific version
KUBE_VERSION="1.29.0"
curl -LO "https://dl.k8s.io/release/v${KUBE_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Verify
kubectl version --client

# Bash completion
echo 'source <(kubectl completion bash)' >> ~/.bashrc
source ~/.bashrc
```

---

## 6. ctx (kubectx/kubens) Installation

```bash
# Install kubectx and kubens
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens

# Verify
kubectx
kubens
```

**Usage:**
```bash
# Switch cluster context
kubectx mgmt-cluster
kubectx app-cluster

# Switch namespace
kubens kube-system
kubens monitoring

# Show current context/namespace
kubectx -c
kubens -c
```

---

## 7. Helm Installation

```bash
# Install latest Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version

# Bash completion
echo 'source <(helm completion bash)' >> ~/.bashrc
source ~/.bashrc

# Add common repos
helm repo add stable https://charts.helm.sh/stable
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add argo https://argo-cd.github.io/argo-helm
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo add metallb https://metallb.github.io/metallb
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update
```

---

## 8. Docker Installation (Optional — for local image testing)

```bash
# Install Docker
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add deploy user to docker group
sudo usermod -aG docker deploy
newgrp docker

# Configure Docker for air-gap
cat > /etc/docker/daemon.json <<EOF
{
  "insecure-registries": ["harbor.internal.lan:443", "nexus.internal.lan:5000"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

sudo systemctl restart docker
```

---

## 9. Additional Tools

### 9.1 k9s — Kubernetes CLI Dashboard

```bash
curl -sS https://webinstall.dev/k9s | bash
# or
K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name)
curl -sL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" | tar xz
sudo mv k9s /usr/local/bin/
```

### 9.2 Stern — Multi-Pod Log Tail

```bash
STERN_VERSION=$(curl -s https://api.github.com/repos/stern/stern/releases/latest | jq -r .tag_name)
curl -sL "https://github.com/stern/stern/releases/download/${STERN_VERSION}/stern_${STERN_VERSION#v}_linux_amd64.tar.gz" | tar xz
sudo mv stern /usr/local/bin/
```

### 9.3 Cilium CLI (for Calico troubleshooting)

```bash
CILIUM_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -sL "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_VERSION}/cilium-linux-amd64.tar.gz" | tar xz
sudo mv cilium /usr/local/bin/
```

### 9.4 Velero CLI

```bash
VELERO_VERSION=$(curl -s https://api.github.com/repos/vmware-tanzu/velero/releases/latest | jq -r .tag_name)
curl -sL "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz" | tar xz
sudo mv velero-${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/
```

### 9.5 Ceph CLI (for Ceph management)

```bash
# Install Ceph client tools
sudo apt-get install -y ceph-common radosgw

# Or from Nexus in air-gap
# sudo apt-get install -y ceph-common
```

### 9.6 ArgoCD CLI

```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

### 9.7 Terraform (optional, for IaC)

```bash
# Install from internal Nexus or pre-staged package
sudo apt-get install -y terraform
# or
wget https://nexus.internal.lan/repository/terraform/terraform_1.6.5_linux_amd64.zip
unzip terraform_1.6.5_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

### 9.8 Git Configuration

```bash
git config --global user.name "Davoud Teimouri"
git config --global user.email "davoudteimouri@gmail.com"
git config --global init.defaultBranch main
git config --global core.editor vim
git config --global pull.rebase false

# Generate SSH key for GitHub
ssh-keygen -t ed25519 -C "davoudteimouri@gmail.com" -f ~/.ssh/github -N ""
cat ~/.ssh/github.pub  # Add to GitHub
```

---

## 10. Cockpit — Web Monitoring (Optional)

```bash
sudo apt-get install -y cockpit cockpit-storaged cockpit-networkmanager
sudo systemctl enable --now cockpit.socket

# Access at https://mgmt-server.internal.lan:9090
# Login with deploy user credentials
```

---

## 11. Directory Structure for Projects

```bash
mkdir -p ~/projects/{kubespray,manifests,helm-values,scripts,backups}
cd ~/projects

# Clone KubeSpray
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
git checkout v2.24.0
pip install -r requirements.txt

# Clone your deployment repo
cd ~/projects
git clone git@github.com:DavoudTeimouri/cloud-native-deployment.git
```

---

## 12. Environment Profile

```bash
cat >> ~/.bashrc <<'EOF'

# Kubernetes Management Aliases
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias ke='kubectl edit'
alias kx='kubectl exec -it'
alias kl='kubectl logs -f'
alias ktx='kubectx'
alias kns='kubens'
alias h='helm'
alias s='stern'
alias tf='terraform'
alias a='argocd'
alias v='velero'

# Ansible
alias ap='ansible-playbook'
alias ag='ansible-galaxy'
alias ansible-env='source ~/ansible-venv/bin/activate'

# Quick cluster access
alias ssh-mgmt='ssh deploy@master-1'
alias ssh-app='ssh deploy@app-master-1'

# Prompt with context
parse_git_branch() {
    git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}
export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[33m\]$(parse_git_branch)\[\033[00m\]\$ '

# Kubeconfig
export KUBECONFIG=~/.kube/config:~/.kube/mgmt-config:~/.kube/app-config
EOF

source ~/.bashrc
```

---

## 13. Verification Checklist

After completing setup, verify:

```bash
# System
ansible --version          # Ansible installed
kubectl version --client   # kubectl installed
helm version                # Helm installed
kubectx                    # ctx installed
docker version             # Docker installed (if needed)
git --version              # Git installed

# Connectivity
ansible all -i ~/ansible/inventory/hosts.yml -m ping  # All nodes reachable
ssh deploy@master-1 "hostname"                         # SSH key auth works

# Tools
k9s                        # k9s installed
stern --version            # stern installed
argocd version --client    # ArgoCD CLI installed
velero version --client    # Velero CLI installed
```

---

## 14. Air-Gap Considerations

### Package Installation from Nexus

```bash
# Configure apt for Nexus
echo "deb [arch=amd64] https://nexus.internal.lan/repository/ubuntu jammy universe" | \
  sudo tee /etc/apt/sources.list.d/nexus.list

# Add GPG key
curl -fsSL https://nexus.internal.lan/repository/keys/release.asc | sudo apt-key add -

# Install packages
sudo apt-get update
sudo apt-get install -y ansible python3-pip docker-ce
```

### Tool Binaries

For tools not available as packages (kubectl, helm, k9s, etc.):

```bash
# Download on internet-connected machine, then upload to Nexus
# Store in Nexus generic repository: /repository/tools/

# Download from Nexus
wget https://nexus.internal.lan/repository/tools/kubectl/v1.29.0/kubectl
wget https://nexus.internal.lan/repository/tools/helm/v3.14.0/helm-v3.14.0-linux-amd64.tar.gz
```

---

## 15. Security Hardening

```bash
# Disable swap (not needed on management server but good practice)
sudo swapoff -a
sudo sed -i '/\s*swap\s*/d' /etc/fstab

# Enable UFW (management server should have firewall)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 10.0.0.0/8 to any port 22
sudo ufw allow from 10.0.0.0/8 to any port 9090  # Cockpit
sudo ufw enable

# Enable automatic security updates
sudo apt-get install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# Auditd
sudo apt-get install -y auditd
sudo systemctl enable auditd
sudo systemctl start auditd
```
