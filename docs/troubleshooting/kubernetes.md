# Kubernetes Troubleshooting Guide

> Decision-tree style: **Symptom → Possible Causes → Diagnostic Commands → Resolution**

---

## 1. Node Issues

### 1.1 Node NotReady

**Symptom:** `kubectl get nodes` shows `NotReady`

**Possible Causes:**
- kubelet crashed or stopped
- Container runtime (containerd/CRI-O) down
- Network plugin (Calico) not running
- Disk pressure / memory pressure / PID pressure
- Certificate expiry

**Diagnostic Commands:**
```bash
# Check node conditions
kubectl describe node <node-name>

# Check kubelet status
ssh <node> systemctl status kubelet
ssh <node> journalctl -u kubelet --since "10 minutes ago" --no-pager

# Check container runtime
ssh <node> systemctl status containerd
ssh <node> crictl info

# Check kubelet logs
ssh <node> journalctl -u kubelet -f

# Check certificate expiry
ssh <node> kubeadm certs check-expiration
# or
ssh <node> openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -dates
```

**Resolution:**
```bash
# Restart kubelet
ssh <node> systemctl restart kubelet

# If kubelet won't start, check config
ssh <node> kubelet --config=/var/lib/kubelet/config.yaml --dry-run

# Renew certificates if expired
ssh <node> kubeadm certs renew all
ssh <node> systemctl restart kubelet

# If containerd is down
ssh <node> systemctl restart containerd
ssh <node> crictl pods  # verify pods are listed
```

---

### 1.2 Disk Pressure

**Symptom:** Node condition `DiskPressure=True`, pods being evicted

**Diagnostic Commands:**
```bash
# Check disk usage
ssh <node> df -h
ssh <node> du -sh /var/lib/containerd/*
ssh <node> du -sh /var/log/pods/*
ssh <node> du -sh /var/lib/kubelet/*

# Check inode usage
ssh <node> df -i

# Find large files
ssh <node> find /var -type f -size +100M -exec ls -lh {} \;
```

**Resolution:**
```bash
# Clean up container images
ssh <node> crictl images
ssh <node> crictl rmi --prune

# Clean up logs
ssh <node> journalctl --vacuum-time=3d
ssh <node> find /var/log/pods -type f -mtime +7 -delete

# Clean up dead containers
ssh <node> crictl rm $(crictl ps -a -q --state=exited)

# Adjust eviction thresholds (kubelet flag)
# --eviction-hard=memory.available<500Mi,nodefs.available<10%
# --eviction-minimum-reclaim=nodefs.available=500Mi
```

---

### 1.3 Memory Pressure

**Symptom:** `MemoryPressure=True`, OOM kills, pods evicted

**Diagnostic Commands:**
```bash
# Check memory usage
ssh <node> free -h
ssh <node> cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|SwapTotal"

# Check OOM events
ssh <node> dmesg | grep -i "oom\|out of memory"
ssh <node> journalctl -k | grep -i oom

# Check pod memory usage
kubectl top pods --all-namespaces --sort-by=memory
```

**Resolution:**
```bash
# Drain node to move workloads
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Check for memory leaks in system pods
kubectl describe node <node> | grep -A 20 "Allocated resources"

# Adjust kubelet reservation
# --kube-reserved=cpu=500m,memory=1Gi
# --system-reserved=cpu=500m,memory=1Gi
```

---

### 1.4 PID Pressure

**Symptom:** `PIDPressure=True`, cannot create new processes

**Diagnostic Commands:**
```bash
# Check PID usage
ssh <node> cat /proc/sys/kernel/pid_max
ssh <node> ps aux | wc -l
ssh <node> systemctl status kubelet | grep -i pids

# Check cgroup pids
ssh <node> cat /sys/fs/cgroup/pids/kubepods/pids.current
ssh <node> cat /sys/fs/cgroup/pids/kubepods/pids.max
```

**Resolution:**
```bash
# Increase pids limit for kubelet
# In /var/lib/kubelet/config.yaml:
# maxPods: 200
# pidsLimit: -1  (or a high value)

# Kill runaway processes
ssh <node> ps aux --sort=-%cpu | head -20
ssh <node> pkill -f <offending-process>
```

---

## 2. Pod Issues

### 2.1 CrashLoopBackOff

**Symotom:** Pod status `CrashLoopBackOff`, restart count increasing

**Possible Causes:**
- Application error / panic
- Missing config / environment variables
- Liveness probe too aggressive
- Init container failing
- Resource limits too low

**Diagnostic Commands:**
```bash
# Check pod events
kubectl describe pod <pod> -n <namespace>

# Check current container logs
kubectl logs <pod> -n <namespace> --tail=100

# Check previous (crashed) container logs
kubectl logs <pod> -n <namespace> --previous

# Check all containers in pod
kubectl logs <pod> -n <namespace> --all-containers

# Check events
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod> --sort-by='.lastTimestamp'
```

**Resolution:**
```bash
# Fix application config
kubectl edit deployment <deployment> -n <namespace>

# Adjust liveness probe
kubectl patch deployment <deployment> -n <namespace> --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":30}
]'

# Check resource limits
kubectl describe pod <pod> -n <namespace> | grep -A 5 "Limits\|Requests"

# Debug interactively
kubectl debug -it <pod> -n <namespace> --image=busybox --target=<container>
```

---

### 2.2 ImagePullBackOff / ErrImagePull

**Symptom:** Pod status `ImagePullBackOff` or `ErrImagePull`

**Possible Causes:**
- Image doesn't exist in registry
- Registry authentication failure
- Network connectivity to registry
- Air-gap: image not mirrored in Harbor
- Image tag typo

**Diagnostic Commands:**
```bash
# Check pod events for pull error
kubectl describe pod <pod> -n <namespace> | grep -A 10 "Events:"

# Test registry connectivity
kubectl run test --image=busybox --restart=Never -it --rm -- sh -c 'wget -qO- https://harbor.internal:443/v2/'

# Check image pull secrets
kubectl get pod <pod> -n <namespace> -o jsonpath='{.spec.imagePullSecrets}'

# Test pull manually on node
ssh <node> crictl pull <image>:<tag>
```

**Resolution:**
```bash
# Create/update image pull secret
kubectl create secret docker-registry regcred \
  --docker-server=harbor.internal \
  --docker-username=admin \
  --docker-password='<password>' \
  -n <namespace>

kubectl patch serviceaccount default -n <namespace> \
  -p '{"imagePullSecrets": [{"name": "regcred"}]}'

# For air-gap: verify image exists in Harbor
curl -u admin:password https://harbor.internal/api/v2.0/projects/<project>/repositories/<repo>/artifacts

# Mirror missing image
# On a machine with internet access:
docker pull <image>:<tag>
docker tag <image>:<tag> harbor.internal/<project>/<image>:<tag>
docker push harbor.internal/<project>/<image>:<tag>
```

---

### 2.3 Pod Pending

**Symptom:** Pod stuck in `Pending` state

**Possible Causes:**
- No node with sufficient resources
- Node selector / affinity mismatch
- Taints without tolerations
- PVC not bound
- Pod topology spread constraints

**Diagnostic Commands:**
```bash
# Check scheduling events
kubectl describe pod <pod> -n <namespace> | grep -A 15 "Events:"

# Check resource availability
kubectl top nodes
kubectl describe node <node> | grep -A 10 "Allocated resources"

# Check PVC status
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>

# Check taints
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

**Resolution:**
```bash
# Add node if resources insufficient
# Or adjust resource requests
kubectl edit deployment <deployment> -n <namespace>

# Add toleration for taints
kubectl edit pod <pod> -n <namespace>
# Add:
# tolerations:
# - key: "node-role.kubernetes.io/control-plane"
#   operator: "Exists"
#   effect: "NoSchedule"

# Fix PVC - check StorageClass
kubectl get sc
kubectl edit pvc <pvc-name> -n <namespace>
```

---

### 2.4 Pod Evicted

**Symptom:** Pod status `Evicted`, node under pressure

**Diagnostic Commands:**
```bash
# Check eviction reason
kubectl get events -n <namespace> --field-selector reason=Evicted --sort-by='.lastTimestamp'

# Check node conditions
kubectl describe node <node> | grep "Conditions" -A 10

# Check resource usage
kubectl top node <node>
```

**Resolution:**
```bash
# Address root cause (disk/memory/PID pressure) per sections 1.2-1.4
# Increase resource requests/limits
# Add more nodes
# Configure priority classes to protect critical pods
```

---

## 3. Service & Networking Issues

### 3.1 DNS Resolution Failure

**Symptom:** Pods cannot resolve service names or external domains

**Diagnostic Commands:**
```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# Test DNS from a pod
kubectl run dns-test --image=busybox:1.28 --restart=Never -it --rm -- nslookup kubernetes.default
kubectl run dns-test --image=busybox:1.28 --restart=Never -it --rm -- nslookup google.com

# Check CoreDNS config
kubectl get configmap coredns -n kube-system -o yaml

# Check /etc/resolv.conf inside pod
kubectl exec <pod> -n <namespace> -- cat /etc/resolv.conf
```

**Resolution:**
```bash
# Restart CoreDNS
kubectl rollout restart deployment coredns -n kube-system

# Check for CoreDNS crash loop
kubectl logs -n kube-system -l k8s-app=kube-dns --previous

# Verify CoreDNS service
kubectl get svc -n kube-system kube-dns
kubectl get endpoints -n kube-system kube-dns

# Fix CoreDNS config if needed
kubectl edit configmap coredns -n kube-system
# Ensure forward points to correct upstream DNS
# forward . /etc/resolv.conf
```

---

### 3.2 Service Connectivity Issues

**Symptom:** Cannot reach a Service from within or outside the cluster

**Diagnostic Commands:**
```bash
# Check service endpoints
kubectl get endpoints <service> -n <namespace>
kubectl describe svc <service> -n <namespace>

# Check if endpoints are populated (empty = no matching pods)
kubectl get endpoints <service> -n <namespace> -o wide

# Test from a pod
kubectl run test --image=busybox --restart=Never -it --rm -- wget -qO- http://<service>.<namespace>.svc.cluster.local:<port>

# Check network policies
kubectl get networkpolicies -n <namespace>
kubectl describe networkpolicy <policy> -n <namespace>
```

**Resolution:**
```bash
# Verify pod labels match service selector
kubectl get pods -n <namespace> --show-labels
kubectl get svc <service> -n <namespace> -o jsonpath='{.spec.selector}'

# Check if pods are ready
kubectl get pods -n <namespace> -l <selector-labels>

# Check Calico network policy
calicoctl get networkpolicy -n <namespace> -o wide
```

---

### 3.3 Port Conflicts

**Symptom:** Service not binding, port already in use

**Diagnostic Commands:**
```bash
# Check NodePort range conflict
kubectl get svc --all-namespaces -o jsonpath='{range .items[*]}{.spec.ports[*].nodePort}{"\n"}{end}' | sort -n

# Check host port conflicts
ssh <node> ss -tlnp | grep <port>
```

---

## 4. etcd Issues

### 4.1 Quorum Loss

**Symptom:** `etcdctl endpoint health` shows unhealthy members, cluster unavailable

**Diagnostic Commands:**
```bash
# Check etcd member list
kubectl exec -it etcd-master-0 -n kube-system -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list

# Check endpoint health
kubectl exec -it etcd-master-0 -n kube-system -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health --cluster

# Check etcd logs
ssh <master-node> crictl logs $(crictl ps --label io.kubernetes.container.name=etcd -q) --tail=100
```

**Resolution:**
```bash
# If one member is down, restart it
ssh <failed-master> systemctl restart etcd
# or if static pod:
ssh <master> docker restart $(docker ps | grep etcd | awk '{print $1}')

# If majority is lost, restore from snapshot
etcdctl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restored \
  --name=master-1 \
  --initial-cluster=master-1=https://10.0.0.1:2380,master-2=https://10.0.0.2:2380 \
  --initial-cluster-token=etcd-cluster \
  --initial-advertise-peer-urls=https://10.0.0.1:2380

# Remove failed member and re-add
etcdctl member remove <member-id>
etcdctl member add master-3 --peer-urls=https://10.0.0.3:2380
```

---

### 4.2 Slow etcd Performance

**Symptom:** API server slow, high latency on etcd requests

**Diagnostic Commands:**
```bash
# Check etcd disk latency
kubectl exec -it etcd-master-0 -n kube-system -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  check perf

# Check disk IO
ssh <master> iostat -x 1 5

# Check etcd metrics
curl -k https://127.0.0.1:2379/metrics | grep etcd_disk_wal_fsync_duration
```

**Resolution:**
```bash
# Move etcd to SSD/NVMe if on spinning disk
# Defrag etcd
etcdctl defrag --cluster

# Compact etcd
etcdctl compact $(etcdctl endpoint status --write-out=table | awk '{print $8}' | head -1)

# Increase etcd quota
# --quota-backend-bytes=8589934592  (8GB)
```

---

### 4.3 etcd Certificate Expiry

**Diagnostic Commands:**
```bash
# Check certificate dates
kubectl exec -it etcd-master-0 -n kube-system -- \
  openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -noout -dates

# Or on host
ssh <master> openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -noout -dates
```

**Resolution:**
```bash
# Renew via kubeadm
kubeadm certs renew etcd-peer
kubeadm certs renew etcd-server
kubeadm certs renew etcd-healthcheck-client

# Restart etcd and API server
ssh <master> crictl restart $(crictl ps --label io.kubernetes.container.name=etcd -q)
ssh <master> crictl restart $(crictl ps --label io.kubernetes.container.name=kube-apiserver -q)
```

---

## 5. API Server Issues

### 5.1 API Server Unresponsive

**Symptom:** `kubectl` commands timeout or fail

**Diagnostic Commands:**
```bash
# Check API server pod
kubectl get pods -n kube-system -l component=kube-apiserver

# Check API server logs
kubectl logs -n kube-system kube-apiserver-<master> --tail=100

# Check on host
ssh <master> crictl logs $(crictl ps --label io.kubernetes.container.name=kube-apiserver -q) --tail=100

# Check connectivity
curl -k https://<master-ip>:6443/healthz
curl -k https://<master-ip>:6443/livez
curl -k https://<master-ip>:6443/readyz
```

**Resolution:**
```bash
# Restart API server
ssh <master> crictl restart $(crictl ps --label io.kubernetes.container.name=kube-apiserver -q)

# Check for certificate issues
ssh <master> openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates

# Check etcd connectivity from API server
# Check --etcd-servers flag in /etc/kubernetes/manifests/kube-apiserver.yaml

# Check for too many objects causing OOM
kubectl get all --all-namespaces | wc -l
```

---

### 5.2 API Server Certificate Expiry

**Diagnostic Commands:**
```bash
kubeadm certs check-expiration
openssl x509 -in /etc/kubernetes/pki/apiserver-kubelet-client.crt -noout -dates
```

**Resolution:**
```bash
# Renew all certificates
kubeadm certs renew all

# Restart control plane components
ssh <master> mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/
sleep 10
ssh <master> mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/

# Distribute new kubeconfig if needed
kubeadm init phase kubeconfig all
```

---

## 6. Controller Manager & Scheduler Issues

### 6.1 Controller Manager Not Running

**Symptom:** Deployments not reconciling, nodes not monitored, PVCs not provisioned

**Diagnostic Commands:**
```bash
kubectl get pods -n kube-system -l component=kube-controller-manager
kubectl logs -n kube-system kube-controller-manager-<master> --tail=100

# Check leader election
kubectl get endpoints kube-controller-manager -n kube-system -o yaml
```

**Resolution:**
```bash
# Restart controller manager
ssh <master> crictl restart $(crictl ps --label io.kubernetes.container.name=kube-controller-manager -q)

# Check for certificate issues
ssh <master> openssl x509 -in /etc/kubernetes/pki/controller-manager.crt -noout -dates
```

---

### 6.2 Scheduler Not Scheduling

**Symptom:** New pods remain `Pending` indefinitely

**Diagnostic Commands:**
```bash
kubectl get pods -n kube-system -l component=kube-scheduler
kubectl logs -n kube-system kube-scheduler-<master> --tail=100

# Check leader election
kubectl get endpoints kube-scheduler -n kube-system -o yaml
```

**Resolution:**
```bash
# Restart scheduler
ssh <master> crictl restart $(crictl ps --label io.kubernetes.container.name=kube-scheduler -q)
```

---

## 7. KubeSpray-Specific Issues

### 7.1 Deployment Failures

**Symptom:** `cluster.yml` playbook fails

**Diagnostic Commands:**
```bash
# Run with verbose output
ansible-playbook -i inventory/mycluster/hosts.yaml cluster.yml -vvvv

# Check specific task failure
ansible-playbook -i inventory/mycluster/hosts.yaml cluster.yml --tags all --step

# Validate inventory
ansible -i inventory/mycluster/hosts.yaml all -m ping
```

**Common Issues & Fixes:**
```bash
# SSH key issues
ssh-copy-id root@<node>

# Python not found on target nodes
ansible -i inventory/mycluster/hosts.yaml all -m raw -a "apt-get install -y python3"

# Variable conflicts - check group_vars
grep -r "kube_version" inventory/mycluster/group_vars/

# Reset and retry
ansible-playbook -i inventory/mycluster/hosts.yaml reset.yml
ansible-playbook -i inventory/mycluster/hosts.yaml cluster.yml
```

---

### 7.2 Inventory Errors

**Symptom:** Wrong nodes targeted, variables not applied

**Diagnostic Commands:**
```bash
# Validate inventory structure
ansible-inventory -i inventory/mycluster/hosts.yaml --list --yaml

# Check variable precedence
ansible -i inventory/mycluster/hosts.yaml <node> -m debug -a "var=hostvars[inventory_hostname]"
```

---

## 8. Air-Gap Specific Issues

### 8.1 Image Pull Failures in Air-Gap

**Symptom:** All pods fail with `ImagePullBackOff` after deployment

**Diagnostic Commands:**
```bash
# Verify image_list is complete
cat /tmp/kubespray_image_list.txt | wc -l

# Check Harbor has all required images
curl -u admin:password "https://harbor.internal/api/v2.0/projects/library/repositories" | jq '.[] | .name'

# Check image pull secret in all namespaces
kubectl get secrets --all-namespaces | grep regcred
```

**Resolution:**
```bash
# Re-run image mirroring
ansible-playbook -i inventory/mycluster/hosts.yaml -e "download_run_once=false" download.yml

# Or manually mirror missing images
for image in $(cat required_images.txt); do
  docker pull $image
  docker tag $image harbor.internal/library/$(echo $image | cut -d'/' -f2-)
  docker push harbor.internal/library/$(echo $image | cut -d'/' -f2-)
done
```

---

### 8.2 Registry Authentication in Air-Gap

**Resolution:**
```bash
# Create pull secret in every namespace that needs it
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  kubectl create secret docker-registry harbor-regcred \
    --docker-server=harbor.internal \
    --docker-username=admin \
    --docker-password='<password>' \
    -n $ns --dry-run=client -o yaml | kubectl apply -f -
done
```

---

## 9. Log Locations Reference

| Component | Log Location |
|-----------|-------------|
| kubelet | `journalctl -u kubelet` |
| kube-apiserver | `/var/log/kubernetes/kube-apiserver.log` or `kubectl logs` |
| kube-scheduler | `/var/log/kubernetes/kube-scheduler.log` or `kubectl logs` |
| kube-controller-manager | `/var/log/kubernetes/kube-controller-manager.log` or `kubectl logs` |
| etcd | `crictl logs <etcd-container>` or `/var/log/etcd/` |
| containerd | `journalctl -u containerd` |
| Calico | `/var/log/calico/` or `kubectl logs -n kube-system -l k8s-app=calico-node` |
| CoreDNS | `kubectl logs -n kube-system -l k8s-app=kube-dns` |
| Pod logs | `kubectl logs <pod> -n <namespace>` |
| Node system logs | `journalctl -xe` on the node |
| KubeSpray logs | `ansible-playbook ... -vvvv` output |

---

## 10. Quick Recovery Procedures

### Full Control Plane Recovery
```bash
# 1. Backup etcd first (if possible)
etcdctl snapshot save /backup/etcd-$(date +%Y%m%d).db

# 2. Check all control plane pods
kubectl get pods -n kube-system

# 3. Restart all static pods on master
ssh <master> crictl pods --namespace kube-system
ssh <master> crictl restart <pod-id>

# 4. If masters are unreachable, restore from KubeSpray backup
ansible-playbook -i inventory/mycluster/hosts.yaml cluster.yml
```

### Worker Node Recovery
```bash
# 1. Drain
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# 2. SSH and fix
ssh <node>
systemctl restart kubelet
systemctl restart containerd

# 3. If needed, reset and rejoin
kubeadm reset
kubeadm join <master>:6443 --token <token> --discovery-token-ca-cert-hash <hash>

# 4. Uncordon
kubectl uncordon <node>
```
