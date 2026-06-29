# Health Check Guide

> Comprehensive health checks for all components — quick status and deep diagnostics

---

## 1. Quick Health Check Dashboard

Run this single command to get overall cluster health:

```bash
#!/bin/bash
# quick-health-check.sh — Run from management server

echo "============================================"
echo "  CLUSTER HEALTH CHECK — $(date)"
echo "============================================"

echo ""
echo "=== Nodes ==="
kubectl get nodes -o wide
echo ""
echo "=== Node Conditions ==="
kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].type,REASON:.status.conditions[?(@.type=="Ready")].reason

echo ""
echo "=== System Pods ==="
kubectl get pods -n kube-system
echo ""
echo "=== All Pods (non-running) ==="
kubectl get pods --all-namespaces --field-selector status.phase!=Running,status.phase!=Succeeded

echo ""
echo "=== Persistent Volumes ==="
kubectl get pv
echo ""
echo "=== PVC (non-bound) ==="
kubectl get pvc --all-namespaces | grep -v Bound

echo ""
echo "=== Ingress ==="
kubectl get ingress --all-namespaces

echo ""
echo "=== Services ==="
kubectl get svc --all-namespaces

echo ""
echo "=== Events (warnings) ==="
kubectl get events --all-namespaces --field-selector type=Warning --sort-by='.lastTimestamp' | tail -20

echo ""
echo "=== Resource Usage ==="
kubectl top nodes 2>/dev/null || echo "metrics-server not available"
echo ""
kubectl top pods --all-namespaces --sort-by=memory 2>/dev/null | head -20

echo ""
echo "=== Ceph ==="
ceph -s 2>/dev/null || echo "Ceph not configured"
echo ""

echo "=== etcd ==="
kubectl exec -it etcd-master-1 -n kube-system -- etcdctl endpoint health --cluster 2>/dev/null || echo "etcd check failed"

echo ""
echo "=== Certificates ==="
kubeadm certs check-expiration 2>/dev/null || echo "kubeadm not available"

echo ""
echo "============================================"
echo "  HEALTH CHECK COMPLETE"
echo "============================================"
```

---

## 2. Kubernetes Component Health Checks

### 2.1 Control Plane Components

```bash
# Check all static pods on masters
kubectl get pods -n kube-system -l component=kube-apiserver
kubectl get pods -n kube-system -l component=kube-scheduler
kubectl get pods -n kube-system -l component=kube-controller-manager

# Check static pod manifests on each master
ssh deploy@master-1 ls -la /etc/kubernetes/manifests/

# Check component status
kubectl get componentstatuses
# or
kubectl get --raw '/healthz?verbose'
kubectl get --raw '/livez?verbose'
kubectl get --raw '/readyz?verbose'

# Check API server specifically
curl -k https://<master-ip>:6443/healthz
curl -k https://<master-ip>:6443/livez
curl -k https://<master-ip>:6443/readyz

# Check API server metrics
curl -k https://<master-ip>:6443/metrics | grep apiserver_request_total

# Check scheduler
kubectl get endpoints kube-scheduler -n kube-system -o yaml | grep -A 5 holderIdentity

# Check controller manager
kubectl get endpoints kube-controller-manager -n kube-system -o yaml | grep -A 5 holderIdentity
```

### 2.2 etcd Health

```bash
# Quick health check
kubectl exec -it etcd-master-1 -n kube-system -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health --cluster

# Detailed status
kubectl exec -it etcd-master-1 -n kube-system -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --cluster --write-out=table

# Check member list
kubectl exec -it etcd-master-1 -n kube-system -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list --write-out=table

# Check alarm list
kubectl exec -it etcd-master-1 -n kube-system -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  alarm list

# Check DB size
kubectl exec -it etcd-master-1 -n kube-system -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint hashkey --cluster
```

### 2.3 Kubelet Health

```bash
# Check kubelet status on each node
ssh deploy@<node> systemctl status kubelet

# Check kubelet logs
ssh deploy@<node> journalctl -u kubelet --since "10 minutes ago" --no-pager

# Check kubelet metrics
curl -k https://<node-ip>:10250/metrics | head -20

# Check kubelet readiness
curl -k https://<node-ip>:10250/healthz

# Check kubelet config
ssh deploy@<node> cat /var/lib/kubelet/config.yaml
```

### 2.4 CoreDNS Health

```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# Check CoreDNS service
kubectl get svc -n kube-system kube-dns
kubectl get endpoints -n kube-system kube-dns

# Test DNS resolution
kubectl run dns-test --image=busybox:1.28 --restart=Never -it --rm -- \
  nslookup kubernetes.default.svc.cluster.local

# Test external DNS
kubectl run dns-test --image=busybox:1.28 --restart=Never -it --rm -- \
  nslookup google.com

# Check CoreDNS config
kubectl get configmap coredns -n kube-system -o yaml

# Check CoreDNS metrics
kubectl exec -n kube-system <coredns-pod> -- localhost:9153/metrics
```

### 2.5 Calico Health

```bash
# Check Calico pods
kubectl get pods -n kube-system -l k8s-app=calico-node
kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers
kubectl get pods -n kube-system -l k8s-app=calico-typha

# Check BGP peer status
calicoctl node status

# Check Calico configuration
calicoctl get ippool -o wide
calicoctl get bgpconfig -o wide
calicoctl get bgppeer -o wide

# Check Felix metrics
kubectl exec -n kube-system <calico-node-pod> -- calico-node -felix-metrics

# Check BIRD routing
kubectl exec -n kube-system <calico-node-pod> -- birdcl show protocols
kubectl exec -n kube-system <calico-node-pod> -- birdcl show route

# Check network policies
calicoctl get networkpolicy --all-namespaces -o wide
```

---

## 3. Pod Health Deep Dive

### 3.1 Pod Status Overview

```bash
# All pods with status
kubectl get pods --all-namespaces -o wide

# Pods not running
kubectl get pods --all-namespaces --field-selector status.phase!=Running,status.phase!=Succeeded

# Pods by restart count (high restart = problem)
kubectl get pods --all-namespaces --sort-by='.status.containerStatuses[0].restartCount'

# Pods by age
kubectl get pods --all-namespaces --sort-by='.metadata.creationTimestamp'

# Pending pods
kubectl get pods --all-namespaces --field-selector status.phase=Pending

# Failed pods
kubectl get pods --all-namespaces --field-selector status.phase=Failed

# Unknown state pods
kubectl get pods --all-namespaces --field-selector status.phase=Unknown
```

### 3.2 Pod Resource Health

```bash
# Top pods by CPU
kubectl top pods --all-namespaces --sort-by=cpu

# Top pods by memory
kubectl top pods --all-namespaces --sort-by=memory

# Resource usage per container
kubectl top pods --all-namespaces --containers

# Check resource quotas
kubectl get resourcequotas --all-namespaces

# Check limit ranges
kubectl get limitranges --all-namespaces

# Check HPA status
kubectl get hpa --all-namespaces

# Check VPA status (if installed)
kubectl get vpa --all-namespaces

# Check PDB status
kubectl get pdb --all-namespaces
```

### 3.3 Pod Probes Health

```bash
# Check liveness probe failures
kubectl get events --all-namespaces --field-selector reason=Unhealthy | grep Liveness

# Check readiness probe failures
kubectl get events --all-namespaces --field-selector reason=Unhealthy | grep Readiness

# Check startup probe failures
kubectl get events --all-namespaces --field-selector reason=BackOff | grep Startup

# Describe a specific pod for probe details
kubectl describe pod <pod> -n <namespace> | grep -A 10 "Liveness\|Readiness\|Startup"

# Check probe configuration
kubectl get pod <pod> -n <namespace> -o jsonpath='{.spec.containers[*].livenessProbe}'
kubectl get pod <pod> -n <namespace> -o jsonpath='{.spec.containers[*].readinessProbe}'
```

### 3.4 Pod Network Health

```bash
# Check pod-to-pod connectivity
kubectl run net-test --image=nicolaka/netshoot --restart=Never -it --rm -- \
  ping -c 3 <target-pod-ip>

# Check service connectivity
kubectl run net-test --image=nicolaka/netshoot --restart=Never -it --rm -- \
  wget -qO- http://<service>.<namespace>.svc.cluster.local:<port>

# Check DNS from pod
kubectl run net-test --image=nicolaka/netshoot --restart=Never -it --rm -- \
  nslookup <service>.<namespace>.svc.cluster.local

# Check pod network policies
kubectl get networkpolicies -n <namespace>
kubectl describe networkpolicy <policy> -n <namespace>

# Check CNI connectivity
kubectl run net-test --image=nicolaka/netshoot --restart=Never -it --rm -- \
  traceroute <target-pod-ip>
```

### 3.5 Pod Storage Health

```bash
# Check PVC status
kubectl get pvc --all-namespaces

# Check PV status
kubectl get pv

# Check StorageClass
kubectl get sc

# Check CSI driver
kubectl get csidrivers

# Check CSI pods
kubectl get pods -n kube-system -l app=csi-<driver>

# Check volume attachments
kubectl get volumeattachments

# Check PVC events
kubectl get events --all-namespaces --field-selector reason=FailedBinding

# Describe a PVC for details
kubectl describe pvc <pvc> -n <namespace>
```

### 3.6 Pod Security Health

```bash
# Check Pod Security Standards
kubectl get pss

# Check security context
kubectl get pod <pod> -n <namespace> -o jsonpath='{.spec.securityContext}'

# Check container security context
kubectl get pod <pod> -n <namespace> -o jsonpath='{.spec.containers[*].securityContext}'

# Check service accounts
kubectl get sa --all-namespaces

# Check RBAC
kubectl get roles --all-namespaces
kubectl get rolebindings --all-namespaces
kubectl get clusterroles
kubectl get clusterrolebindings

# Check who can do what
kubectl auth can-i --list --as=<user> -n <namespace>
```

---

## 4. Component-Specific Health Checks

### 4.1 Rancher

```bash
# Check Rancher pods
kubectl get pods -n cattle-system

# Check Rancher agent
kubectl get pods -n cattle-cluster-agent
kubectl get pods -n cattle-system -l app=rancher-agent

# Check Rancher version
kubectl get deployment rancher -n cattle-system -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check Rancher health endpoint
curl -k https://rancher.internal.lan/ping

# Check cluster registration
kubectl get clusters.management.cattle.io

# Check fleet agent
kubectl get pods -n cattle-fleet-system
```

### 4.2 ArgoCD

```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Check ArgoCD health
argocd admin health

# Check application status
kubectl get applications -n argocd
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status

# Check repo connection
kubectl get repo -n argocd

# Check ArgoCD server health
curl -k https://argocd.internal.lan/api/v1/health

# Check application sync status
argocd app get <app> -n argocd
```

### 4.3 cert-manager

```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Check certificate status
kubectl get certificates --all-namespaces
kubectl get certificaterequests --all-namespaces
kubectl get orders.acme.cert-manager.io --all-namespaces
kubectl get challenges.acme.cert-manager.io --all-namespaces

# Check expiring certificates (within 30 days)
kubectl get certificates --all-namespaces -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,EXPIRY:.status.expiry -o json | \
  jq -r '.items[] | select(.status.expiry != null) | [.metadata.name, .metadata.namespace, .status.expiry] | @tsv'

# Check CA issuer
kubectl get issuers --all-namespaces
kubectl get clusterissuers

# Check webhook
kubectl get validatingwebhookconfiguration cert-manager-webhook
kubectl get mutatingwebhookconfiguration cert-manager-webhook
```

### 4.4 Prometheus/Grafana

```bash
# Check Prometheus pods
kubectl get pods -n monitoring -l app=prometheus
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Check Prometheus rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | {name: .name, health: .health}'

# Check Grafana
kubectl get pods -n monitoring -l app=grafana
curl -s http://localhost:3000/api/health

# Check Alertmanager
kubectl get pods -n monitoring -l app=alertmanager
curl -s http://localhost:9093/api/v2/alerts | jq '.[] | {alertname: .labels.alertname, state: .status.state}'

# Check ServiceMonitors
kubectl get servicemonitors --all-namespaces
kubectl get podmonitors --all-namespaces
```

### 4.5 Loki

```bash
# Check Loki pods
kubectl get pods -n monitoring -l app=loki

# Check Promtail
kubectl get pods -n monitoring -l app=promtail

# Check Loki readiness
curl -s http://localhost:3100/ready

# Check Loki metrics
curl -s http://localhost:3100/metrics | grep loki_ingester_memory_chunks

# Test log query
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"nginx\"}" | jq '.data.result | length'
```

### 4.6 Velero

```bash
# Check Velero pod
kubectl get pods -n velero

# Check backup storage location
velero backup-location get

# Check recent backups
velero backup get

# Check backup status
velero backup describe <backup> --details

# Check schedules
velero schedule get

# Check restore status
velero restore get
```

### 4.7 MetalLB

```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# Check IP address pool
kubectl get ipaddresspool -n metallb-system -o yaml

# Check L2 advertisement
kubectl get l2advertisement -n metallb-system -o yaml

# Check BGP peers
kubectl get bgppeers -n metallb-system -o yaml

# Check LoadBalancer services
kubectl get svc --all-namespaces | grep LoadBalancer
```

### 4.8 NGINX Ingress

```bash
# Check ingress controller pods
kubectl get pods -n ingress-nginx

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50

# Check ingress controller config
kubectl get configmap -n ingress-nginx ingress-nginx-controller -o yaml

# Check ingress resources
kubectl get ingress --all-namespaces

# Test ingress endpoint
curl -v -H "Host: <host>" http://<ingress-ip>/

# Check ingress controller metrics
curl -s http://localhost:10254/metrics | grep nginx_ingress_controller_requests
```

### 4.9 Gatekeeper

```bash
# Check Gatekeeper pods
kubectl get pods -n gatekeeper-system

# Check constraint templates
kubectl get constrainttemplates

# Check constraints
kubectl get constraints

# Check audit violations
kubectl get constraints -o custom-columns=NAME:.metadata.name,VIOLATIONS:status.totalViolations

# Check Gatekeeper metrics
kubectl get svc -n gatekeeper-system gatekeeper-webhook-service
```

---

## 5. Ceph Health Checks

```bash
# Overall health
ceph -s
ceph health detail

# OSD status
ceph osd tree
ceph osd df
ceph osd perf

# PG status
ceph pg stat
ceph pg ls active+clean | wc -l  # should equal total PGs

# MON status
ceph mon stat
ceph mon quorum_status

# MGR status
ceph mgr dump
ceph mgr module ls

# Pool status
ceph osd pool ls detail
ceph df

# CephFS status
ceph fs status
ceph fs dump

# RGW status
radosgw-admin status

# RBD mirror status
rbd mirror pool status <pool>

# Scrub status
ceph pg dump | grep -E "scrub|deep-scrub"

# Slow ops
ceph osd dump_slow_ops <osd-id>
```

---

## 6. OS-Level Health Checks

### 6.1 Node System Health

```bash
# CPU usage
top -bn1 | head -20
mpstat 1 3

# Memory usage
free -h
cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|SwapTotal"

# Disk usage
df -h
df -i  # inode usage

# Disk IO
iostat -x 1 3
iotop -o

# Network
ss -tlnp
netstat -i
ip -s link

# System load
uptime
cat /proc/loadavg

# Dmesg errors
dmesg | grep -i "error\|fail\|oom\|panic" | tail -20

# Hardware errors
mcelog --client  # machine check exceptions
```

### 6.2 Service Health

```bash
# Check critical services
systemctl is-active kubelet
systemctl is-active containerd
systemctl is-active chrony
systemctl is-active auditd

# Check failed services
systemctl --failed

# Check service logs
journalctl -p err --since "1 hour ago" --no-pager
journalctl -u kubelet --since "10 minutes ago" --no-pager
journalctl -u containerd --since "10 minutes ago" --no-pager
```

---

## 7. Automated Health Check Script

```bash
#!/bin/bash
# comprehensive-health-check.sh
# Run from management server

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check() {
    local name="$1"
    local result="$2"
    if [ "$result" = "OK" ]; then
        echo -e "${GREEN}[PASS]${NC} $name"
        ((PASS++))
    elif [ "$result" = "WARN" ]; then
        echo -e "${YELLOW}[WARN]${NC} $name"
        ((WARN++))
    else
        echo -e "${RED}[FAIL]${NC} $name"
        ((FAIL++))
    fi
}

echo "============================================"
echo "  COMPREHENSIVE HEALTH CHECK"
echo "  $(date)"
echo "============================================"

# Nodes
NOT_READY=$(kubectl get nodes --no-headers | grep -v Ready | wc -l)
[ "$NOT_READY" -eq 0 ] && check "All nodes Ready" "OK" || check "All nodes Ready ($NOT_READY not ready)" "FAIL"

# System pods
FAILED_PODS=$(kubectl get pods -n kube-system --field-selector status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)
[ "$FAILED_PODS" -eq 0 ] && check "All system pods running" "OK" || check "System pods ($FAILED_PODS failed)" "FAIL"

# All pods
ALL_FAILED=$(kubectl get pods --all-namespaces --field-selector status.phase=Failed,status.phase=Unknown --no-headers 2>/dev/null | wc -l)
[ "$ALL_FAILED" -eq 0 ] && check "No failed pods" "OK" || check "Failed pods ($ALL_FAILED)" "FAIL"

# etcd
ETCD_HEALTHY=$(kubectl exec -it etcd-master-1 -n kube-system -- etcdctl endpoint health --cluster 2>/dev/null | grep -c "is healthy")
[ "$ETCD_HEALTHY" -ge 3 ] && check "etcd healthy ($ETCD_HEALTHY/3)" "OK" || check "etcd unhealthy ($ETCD_HEALTHY/3)" "FAIL"

# CoreDNS
COREDNS_RUNNING=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l)
[ "$COREDNS_RUNNING" -ge 2 ] && check "CoreDNS running ($COREDNS_RUNNING pods)" "OK" || check "CoreDNS ($COREDNS_RUNNING pods)" "WARN"

# PVCs
UNBOUND_PVCS=$(kubectl get pvc --all-namespaces --field-selector status.phase!=Bound --no-headers 2>/dev/null | wc -l)
[ "$UNBOUND_PVCS" -eq 0 ] && check "All PVCs bound" "OK" || check "Unbound PVCs ($UNBOUND_PVCS)" "WARN"

# Certificates
EXPIRING=$(kubeadm certs check-expiration 2>/dev/null | grep -c "less than\|expired" || echo 0)
[ "$EXPIRING" -eq 0 ] && check "Certificates valid" "OK" || check "Certificates expiring ($EXPIRING)" "WARN"

# Ceph
CEPH_HEALTH=$(ceph -s 2>/dev/null | grep -o "HEALTH_OK\|HEALTH_WARN\|HEALTH_ERR")
[ "$CEPH_HEALTH" = "HEALTH_OK" ] && check "Ceph HEALTH_OK" "OK" || check "Ceph $CEPH_HEALTH" "WARN"

# Prometheus targets
DOWN_TARGETS=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq '.data.activeTargets[] | select(.health=="down") | .labels.job' | wc -l)
[ "$DOWN_TARGETS" -eq 0 ] && check "Prometheus targets all up" "OK" || check "Prometheus targets down ($DOWN_TARGETS)" "WARN"

# Events
WARN_EVENTS=$(kubectl get events --all-namespaces --field-selector type=Warning --no-headers 2>/dev/null | wc -l)
[ "$WARN_EVENTS" -lt 10 ] && check "Warning events ($WARN_EVENTS)" "OK" || check "Warning events ($WARN_EVENTS)" "WARN"

echo ""
echo "============================================"
echo -e "Results: ${GREEN}$PASS passed${NC}, ${YELLOW}$WARN warnings${NC}, ${RED}$FAIL failed${NC}"
echo "============================================"

exit $FAIL
```

---

## 8. Health Check Schedule

| Check | Frequency | Tool |
|-------|-----------|------|
| Node Ready status | Continuous | Prometheus alert |
| Pod status | Continuous | Prometheus alert |
| etcd health | Every 60s | CronJob |
| Ceph health | Every 60s | Prometheus alert |
| Certificate expiry | Daily | CronJob |
| Disk usage | Every 5m | Node exporter |
| Memory usage | Every 5m | Node exporter |
| DNS resolution | Every 60s | Blackbox exporter |
| Ingress endpoints | Every 60s | Blackbox exporter |
| Full health report | Daily | CronJob → Slack/Email |
| Capacity review | Weekly | Manual review |
