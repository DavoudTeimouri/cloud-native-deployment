# KubeSpray Cheat Sheet

> Quick reference for KubeSpray deployment and operations

---

## Common Playbooks

| Playbook | Purpose | Command |
|----------|---------|---------|
| `cluster.yml` | Deploy new cluster | `ansible-playbook -i inventory/hosts.yaml cluster.yml -b` |
| `scale.yml` | Add nodes | `ansible-playbook -i inventory/hosts.yaml scale.yml -b` |
| `upgrade-cluster.yml` | Upgrade cluster | `ansible-playbook -i inventory/hosts.yaml upgrade-cluster.yml -b` |
| `reset.yml` | Reset/destroy cluster | `ansible-playbook -i inventory/hosts.yaml reset.yml -b` |
| `remove-node.yml` | Remove node | `ansible-playbook -i inventory/hosts.yaml remove-node.yml -b -e node=<name>` |
| `reconfigure.yml` | Reconfigure cluster | `ansible-playbook -i inventory/hosts.yaml reconfigure.yml -b` |
| `recover-control-plane.yml` | Recover control plane | `ansible-playbook -i inventory/hosts.yaml recover-control-plane.yml -b` |
| `download.yml` | Download container images | `ansible-playbook -i inventory/hosts.yaml download.yml` |

---

## Inventory Management

### Directory Structure
```
inventory/
└── mycluster/
    ├── hosts.yaml              # Node inventory
    ├── group_vars/
    │   ├── all/
    │   │   ├── all.yml         # Global vars
    │   │   └── offline.yml     # Air-gap vars
    │   └── k8s_cluster/
    │       ├── k8s-cluster.yml # K8s config
    │       ├── k8s-net-calico.yml
    │       └── etcd.yml
    └── inventory.cfg
```

### hosts.yaml Template
```yaml
all:
  hosts:
    master-1:
      ansible_host: 10.0.0.1
      ip: 10.0.0.1
      access_ip: 10.0.0.1
    master-2:
      ansible_host: 10.0.0.2
      ip: 10.0.0.2
      access_ip: 10.0.0.2
    master-3:
      ansible_host: 10.0.0.3
      ip: 10.0.0.3
      access_ip: 10.0.0.3
    worker-1:
      ansible_host: 10.0.0.10
      ip: 10.0.0.10
      access_ip: 10.0.0.10
  children:
    kube_control_plane:
      hosts:
        master-1:
        master-2:
        master-3:
    kube_node:
      hosts:
        worker-1:
    etcd:
      hosts:
        master-1:
        master-2:
        master-3:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
```

### Validate Inventory
```bash
# List all hosts
ansible -i inventory/mycluster/hosts.yaml all -m ping

# Show inventory structure
ansible-inventory -i inventory/mycluster/hosts.yaml --list --yaml

# Show variables for a host
ansible -i inventory/mycluster/hosts.yaml master-1 -m debug -a "var=hostvars[inventory_hostname]"
```

---

## Variable Overrides

### Key Variables (group_vars/all/all.yml)

```yaml
# Kubernetes version
kube_version: v1.29.0

# Container runtime
container_manager: containerd

# CNI
kube_network_plugin: calico

# DNS
dns_mode: coredns

# etcd
etcd_deployment_type: docker  # or 'host'

# Load balancer
loadbalancer_apiserver:
  address: 10.0.0.100
  port: 6443

# Download settings
download_run_once: true
download_localhost: true

# Node settings
kubelet_max_pods: 200
kubelet_infra_container_image: harbor.internal/library/pause:3.9
```

### Override via Command Line
```bash
ansible-playbook -i inventory/hosts.yaml cluster.yml \
  -e "kube_version=v1.29.0" \
  -e "container_manager=containerd" \
  -e "kube_network_plugin=calico" \
  -b
```

### Override via Extra Vars File
```bash
ansible-playbook -i inventory/hosts.yaml cluster.yml \
  -e "@extra-vars.yml" \
  -b
```

---

## Air-Gap Specific Commands

### Configuration (group_vars/all/offline.yml)

```yaml
# Enable offline mode
offline: true

# Registry configuration
registry_host: "harbor.internal:443"
kube_image_repo: "harbor.internal/library"
gcr_image_repo: "harbor.internal/library"
github_image_repo: "harbor.internal/library"
docker_image_repo: "harbor.internal/library"
quay_image_repo: "harbor.internal/library"

# Download settings
download_run_once: true
download_localhost: true
download_always_pull: false

# Container registry credentials
registry_auth:
  enabled: true
  credentials:
    harbor.internal:443:
      username: admin
      password: "{{ registry_password }}"

# etcd
etcd_deployment_type: host
etcd_image_repo: "harbor.internal/library/etcd"

# CNI images
calico_image_repo: "harbor.internal/library/calico"
```

### Download and Mirror Images
```bash
# Download all images to local machine
ansible-playbook -i inventory/mycluster/hosts.yaml download.yml \
  -e "download_run_once=true" \
  -e "download_localhost=true" \
  -e "kube_version=v1.29.0"

# Upload to Harbor
for image in $(cat /tmp/kubespray_image_list.txt); do
  docker pull $image
  harbor_image="harbor.internal/library/$(echo $image | sed 's|.*/||')"
  docker tag $image $harbor_image
  docker push $harbor_image
done

# Deploy with offline settings
ansible-playbook -i inventory/mycluster/hosts.yaml cluster.yml \
  -e "@inventory/mycluster/group_vars/all/offline.yml" \
  -b
```

### Air-Gap Upgrade
```bash
# 1. Download new version images
ansible-playbook -i inventory/mycluster/hosts.yaml download.yml \
  -e "kube_version=v1.29.0" \
  -e "download_run_once=true" \
  -e "download_localhost=true"

# 2. Push to Harbor
# (same as above)

# 3. Update inventory version
# Edit: kube_version: v1.29.0

# 4. Run upgrade
ansible-playbook -i inventory/mycluster/hosts.yaml upgrade-cluster.yml \
  -e "@inventory/mycluster/group_vars/all/offline.yml" \
  -b
```

---

## Common Issues and Quick Fixes

| Issue | Quick Fix |
|-------|-----------|
| SSH connection failed | `ssh-copy-id root@<node>` |
| Python not found | `ansible -i inventory/hosts.yaml all -m raw -a "apt-get install -y python3"` |
| Docker not installed | `ansible -i inventory/hosts.yaml all -m raw -a "apt-get install -y docker.io"` |
| Port already in use | `ss -tlnp \| grep <port>` → kill process |
| Certificate expired | `kubeadm certs renew all && systemctl restart kubelet` |
| etcd unhealthy | `etcdctl endpoint health --cluster` → restart etcd |
| Node NotReady | `systemctl restart kubelet` on node |
| ImagePullBackOff | Check registry auth, verify image in Harbor |
| DNS not working | `kubectl rollout restart deploy/coredns -n kube-system` |
| Stuck on task | Add `-vvvv` for verbose output |
| Inventory error | `ansible-inventory -i inventory/hosts.yaml --list` |
| Variable not applied | Check group_vars precedence, use `-e` to override |
| Timeout on download | Increase `download_timeout: 600` in vars |
| Kubelet won't start | `journalctl -u kubelet -f` on node |
| API server down | `crictl restart $(crictl ps --label io.kubernetes.container.name=kube-apiserver -q)` |

---

## Useful Flags

| Flag | Purpose |
|------|---------|
| `-b` | Become (run as root) |
| `--check` | Dry run |
| `--diff` | Show changes |
| `-v` to `-vvvv` | Verbose output |
| `--tags <tag>` | Run specific tags |
| `--skip-tags <tag>` | Skip specific tags |
| `--limit <host>` | Limit to specific hosts |
| `--start-at-task <task>` | Start at specific task |
| `--step` | Confirm each task |
| `-e "key=value"` | Extra variable |
| `-e "@file.yml"` | Extra variables from file |
| `--flush-cache` | Clear fact cache |
| `--force-handlers` | Force handlers on failure |

---

## Tags Reference

| Tag | Description |
|-----|-------------|
| `all` | Everything |
| `kubernetes` | Kubernetes components |
| `etcd` | etcd deployment |
| `network` | CNI/network plugin |
| `addons` | Cluster add-ons |
| `registry` | Container registry |
| `download` | Image downloads |
| `preinstall` | Pre-installation tasks |
| `k8s_cluster` | K8s cluster setup |
| `deploy_nodes` | Node deployment |
| `master` | Control plane only |
| `node` | Worker nodes only |

---

## Post-Deployment Verification

```bash
# Verify cluster
ansible-playbook -i inventory/mycluster/hosts.yaml cluster.yml --check

# Check nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# Check etcd
ansible -i inventory/hosts.yaml kube_control_plane[0] -m shell -a "etcdctl endpoint health --cluster"

# Check Calico
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check DNS
kubectl run test --image=busybox:1.28 --restart=Never -it --rm -- nslookup kubernetes.default

# Check certificates
ansible -i inventory/hosts.yaml kube_control_plane[0] -m shell -a "kubeadm certs check-expiration"
```
