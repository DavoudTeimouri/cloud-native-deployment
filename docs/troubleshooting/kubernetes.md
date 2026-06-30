# Kubernetes Troubleshooting Guide

## Overview

This guide provides systematic troubleshooting procedures for Kubernetes clusters in an air-gapped environment. Follow the flow-chart style approach: Symptom → Possible Causes → Diagnostic Commands → Resolution.

## 1. Node Issues

### Symptom: Node Shows NotReady
**Possible Causes:**
- Kubelet not running
- Network issues (CNI not configured)
- Certificate expiration
- Disk pressure/Memory pressure/PID pressure
- Container runtime issues

**Diagnostic Commands:**
```bash
# Check node status details
kubectl describe node <node-name>

# Check kubelet status
systemctl status kubelet
journalctl -u kubelet -f

# Check container runtime
systemctl status containerd
crictl info
crictl ps

# Check certificates
kubectl get csr
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep NotAfter

# Check resource pressure
kubectl describe node <node-name> | grep -A5 "Conditions"

# Check CNI plugins
ls /opt/cni/bin/
cat /etc/cni/net.d/10-calico.conflist
```

**Resolution:**
- If kubelet failed: `systemctl restart kubelet`
- If container runtime issue: `systemctl restart containerd`
- If certificate expired: renew via kubeadm or replace manually
- If resource pressure: resolve underlying issue (disk full, memory leak, etc.)
- If CNI missing: reinstall CNI plugins

### Symptom: Node Shows DiskPressure
**Possible Causes:**
- /var/lib/kubelet or /var/lib/containerd filling up
- Log rotation not configured
- Image garbage collection not working
- Etcd database growth

**Diagnostic Commands:**
```bash
# Check disk usage
df -h
du -sh /var/lib/* | sort -hr | head -10

# Check kubelet garbage collection
kubectl get node <node-name> -o jsonpath='{.status.nodeInfo.kubeletVersion}'
kubectl describe node <node-name> | grep -i garbage

# Check containerd garbage collection
crictl info | grep -i runtime

# Check log sizes
du -sh /var/log/* | sort -hr | head -5
```

**Resolution:**
- Clean up old images: `crictl rmi -p`
- Adjust garbage collection thresholds in kubelet config
- Configure log rotation
- Expand disk or clean unnecessary files

### Symptom: Node Shows MemoryPressure
**Possible Causes:**
- Pods using too much memory
- Node processes consuming memory
- Kernel slab usage high

**Diagnostic Commands:**
```bash
# Check memory usage per pod
kubectl top pod -A --sort-by=memory

# Check node processes
ps aux --sort=-%mem | head -10

# Check slab usage
cat /proc/slabinfo | head -20

# Check for memory leaks in system services
journalctl -u <service> -f
```

**Resolution:**
- Identify and kill/restart memory-heavy pods
- Increase node memory or reduce pod density
- Restart problematic system services
- Check for application memory leaks

### Symptom: Node Shows PIDPressure
**Possible Causes:**
- Too many processes created (fork bomb)
- Container without PID limits
- System service spamming processes

**Diagnostic Commands:**
```bash
# Check process count
ps -eLf | wc -l

# Check processes per container
crictl ps -q | xargs crictl inspect --output '{{.info.pid}} {{.status.startTimestamp}}' | sort

# Check systemd services with high process count
systemctl status | grep -E "Tasks:.*[0-9]+"
```

**Resolution:**
- Identify problematic pod/container and restart
- Add PID limits to pod security context
- Fix spawning service
- Increase kernel.pid_max if needed (sysctl)

## 2. Pod Issues

### Symptom: Pod in CrashLoopBackOff
**Possible Causes:**
- Application crashing immediately
- Missing configuration or secrets
- Resource limits too low (OOMKilled)
- Entrypoint/script errors
- Volume mount issues

**Diagnostic Commands:**
```bash
# Get recent events
kubectl describe pod <pod-name> -n <namespace> | grep -A20 Events

# Check logs (previous instance)
kubectl logs <pod-name> -n <namespace> --previous

# Check resource limits
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A5 -B5 "resources"

# Check volume mounts
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A10 -B5 "volumeMounts"

# Check container image
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].image}'
```

**Resolution:**
- Fix application crash (check logs)
- Add missing config/secrets
- Increase memory limits if OOMKilled
- Fix entrypoint or script permissions
- Verify volume mounts exist and are accessible

### Symptom: Pod in ImagePullBackOff
**Possible Causes:**
- Image does not exist in registry
- Registry authentication failed
- Network connectivity to registry
- Image pull policy issues

**Diagnostic Commands:**
```bash
# Describe pod for events
kubectl describe pod <pod-name> -n <namespace> | grep -A10 -B5 "Pulling\|Failed\|BackOff"

# Check image name and tag
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].image}'

# Try to pull image manually (from node)
crictl pull <image>
# or
docker pull <image>

# Check registry credentials
kubectl get secret <registry-secret> -n <namespace> -o yaml
```

**Resolution:**
- Correct image name/tag
- Ensure image exists in Harbor/Nexus
- Fix registry credentials in secret
- Verify network connectivity to registry
- Set imagePullPolicy: IfNotPresent (if image exists locally)

### Symptom: Pod in Pending (unschedulable)
**Possible Causes:**
- Insufficient resources (CPU/Memory)
- Node selector/tolerations mismatch
- Volume binding failure
- Taints on nodes
- PriorityClass issues

**Diagnostic Commands:**
```bash
# Check scheduler events
kubectl describe pod <pod-name> -n <namespace> | grep -A10 -B5 "Events"

# Check node resources
kubectl get nodes -o jsonpath='{.items[*].status.allocatable}'

# Check node labels and taints
kubectl get nodes --show-labels
kubectl get nodes -o jsonpath='{.items[*].spec.taints}'

# Check PVC status if volume bound
kubectl get pvc -n <namespace>
```

**Resolution:**
- Add more nodes or reduce resource requests
- Fix node selector or tolerations
- Ensure storage class exists and PV available
- Remove taints or add tolerations
- Adjust PriorityClass or create one

### Symptom: Pod Evicted
**Possible Causes:**
- Node under disk pressure
- Node under memory pressure
- Node under PID pressure
- Kubelet eviction thresholds exceeded

**Diagnostic Commands:**
```bash
# Check why pod was evicted
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A5 -B5 "message"

# Check node conditions
kubectl describe node <node-name> | grep -A5 -B5 "Conditions"

# Check kubelet eviction settings
ps -ef | grep kubelet
```

**Resolution:**
- Resolve underlying pressure (disk, memory, PID)
- Increase eviction thresholds if appropriate (not recommended)
- Add more resources to node
- Move critical pods to separate node group with higher eviction tolerance

## 3. Networking Issues

### Symptom: Service DNS Not Resolving
**Possible Causes:**
- CoreDNS pods not running
- Network policy blocking DNS
- Service not created or wrong namespace
- Client in hostNetwork mode

**Diagnostic Commands:**
```bash
# Check CoreDNS status
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS resolution from pod
kubectl run -it --rm --image=alpine:3.18 dns-test -- nslookup <service>.<namespace>.svc.cluster.local

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Check service exists service getAddress ' get
```

**Resolution:\n    pods, restart\n-    pod network policy\n- Create service if missing\n- Use fully qualified name (namespace.svc.cluster.local)\n\n### Symptom: Cannot Reach Service via ClusterIP\n**Possible Causes:**\n- Service not created correctly\n- Endpoints not populated\n- Network policy blocking traffic\n- kube-proxy not functioning\n- IPVS/iptables rules not programmed\n\n**Diagnostic Commands:**\n```bash\n# Check service exists\nkubectl get svc <service-name> -n <namespace>\n\n# Check endpoints\nkubectl get ep <service-name> -n <namespace>\n\n# Check kube-proxy mode\nps -ef | grep kube-proxy\n\n# Check iptables rules (if using iptables mode)\niptables -L -t nat | grep KUBE-SVC-\n\n# Check IPVS (if using IPVS mode)\nip vsadm -L -n\n\n# Test from within cluster\nkubectl run -it --rm --image=alpine:3.18 net-test -- wget -O- http://<service>.<namespace>.svc.cluster.local:<port>\n```\n\n**Resolution:**\n- Create service with correct selector\n- Ensure pods matching selector are Ready and Running\n- Adjust network policies to allow traffic\n- Restart kube-proxy if needed\n- Reconcile iptables/IPVS rules\n\n### Symptom: High Latency or Packet Loss Between Pods\n**Possible Causes:**\n- CNI misconfiguration\n- Node NIC issues\n- Overloaded node\n- MTU mismatch\n- Packet filtering/drops\n\n**Diagnostic Commands:**\n```bash\n# Check node-to-node latency\nping <node-ip>\n\n# Check MTU\nip link show\n\n# Check for dropped packets\nnetstat -s | grep -i \"packet loss\"\n\n# Check CNI status\ncalicoctl node status\ncalicoctl node diags\n\n# Capture traffic\ntcpdump -i eth0 port <port> -w capture.pcap\n\n# Check node load\nuptime\nmpstat\n```\n\n**Resolution:**\n- Fix CNI configuration (reinstall if needed)\n- Replace faulty NIC or cable\n- Reduce pod density on overloaded node\n- Ensure consistent MTU across all nodes\n- Adjust firewall/ebpf rules\n\n## 4. etcd Issues\n\n### Symptom: etcd Cluster Unhealthy\n**Possible Causes:**\n- Lost quorum (less than majority of MONs)\n- High latency between etcd members\n- Disk I/O too slow\n- Certificate expired\n- Member corrupted\n\n**Diagnostic Commands:**\n```bash\n# Check etcd health\nETCDCTL_API=3 etcdctl --endpoints=https://[MASTER_IP]:2379 \\\n  --cacert=/etc/kubernetes/pki/etcd/ca.crt \\\n  --cert=/etc/kubernetes/pki/etcd/server.crt \\\n  --key=/etc/kubernetes/pki/etcd/server.key \\\n  endpoint health --cluster\n\n# Check member status\nETCDCTL_API=3 etcdctl --endpoints=https://[MASTER_IP]:2379 \\\n  --cacert=/etc/kubernetes/pki/etcd/ca.crt \\\n  --cert=/etc/kubernetes/pki/etcd/server.crt \\\n  --key=/etc/kubernetes/pki/etcd/server.key \\\n  member list\n\n# Check disk I/O\niostat -x 1 5\n\n# Check network latency between etcd members\nping <etcd-member-ip>\n\n# Check certificate dates\nopenssl x509 -in /etc/kubernetes/pki/etcd/server.crt -text -noout | grep NotAfter\n```\n\n**Resolution:**\n- Restore quorum by fixing/replacing failed members\n- Improve network between members\n- Move etcd to faster storage (NVMe)\n- Renew expired certificates\n- Restore from backup if corruption\n\n### Symptom: High etcd Request Latency\n**Possible Causes:**\n- Slow disk I/O\n- Network issues\n- Too many watchers\n- Large etcd database\n- CPU starvation\n\n**Diagnostic Commands:**\n```bash\n# Check etcd metrics\nETCDCTL_API=3 etcdctl --endpoints=https://[MASTER_IP]:2379 \\\n  --cacert=/etc/kubernetes/pki/etcd/ca.crt \\\n  --cert=/etc/kubernetes/pki/etcd/server.crt \\\n  --key=/etc/kubernetes/pki/etcd/server.key \\\n  endpoint status --write-out=table\n\n# Check database size\ndu -sh /var/lib/etcd/member\n\n# Check watchers\nETCDCTL_API=3 etcdctl --endpoints=https://[MASTER_IP]:2379 \\\n  --cacert=/etc/kubernetes/pki/etcd/ca.crt \\\n  --cert=/etc/kubernetes/pki/etcd/server.crt \\\n  --key=/etc/kubernetes/pki/etcd/server.key \\\n  alarm list\n\n# Check CPU usage\nmpstat -P ALL 1\n```\n\n**Resolution:**\n- Move etcd to NVMe storage\n- Tune garbage collection\n- Reduce number of watches (use informers properly)\n- Compact etcd history\n- Ensure adequate CPU resources\n\n## 5. API Server Issues\n\n### Symptom: API Server Unresponsive\n**Possible Causes:**\n- Certificate expired\n- etcd connection issues\n- Resource exhaustion (CPU/Memory)\n- Admission webhook hanging\n- Audit log filling disk\n\n**Diagnostic Commands:**\n```bash\n# Check API server pods\nkubectl get pods -n kube-system -l component=kube-apiserver\n\n# Check logs\nkubectl logs -n kube-system -l component=kube-apiserver\n\n# Check etcd connectivity from API server\nexec into apiserver pod and etcdctl endpoint health\n\n# Check resource usage\ntop -b -n 1 | grep kube-apiserver\n\n# Check audit log size\nls -lh /var/log/kubernetes/audit.log\n\n# Check webhook configurations\nkubectl get validatingwebhookconfiguration\nkubectl get mutatingwebhookconfiguration\n```\n\n**Resolution:**\n- Renew certificates if expired\n- Fix etcd connectivity\n- Increase API server resources\n- Fix or remove problematic admission webhooks\n- Rotate or expand audit log\n\n### Symptom: API Server Returns 503 Service Unavailable\n**Possible Causes:**\n- All API server pods unready\n- Load balancer misconfiguration\n- etcd unavailable\n- certificate mismatch\n\n**Diagnostic Commands:**\n```bash\n# Check API server pod readiness\nkubectl get pods -n kube-system -l component=kube-apiserver\n\n# Check load balancer (HAProxy) stats\n# http://<lb-ip>:<stats-port>/stats\n\n# Check etcd from apiserver pod\nkubectl exec -n kube-system -it <apiserver-pod> -- etcdctl endpoint health\n\n# Check server certificate\nkubectl exec -n kube-system -it <apiserver-pod> -- \\\n  openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout\n```\n\n**Resolution:**\n- Ensure at least one API server pod is Ready\n- Fix HAProxy configuration\n- Restore etcd health\n- Replace mismatched certificates\n\n## 6. Controller Manager / Scheduler Issues\n\n### Symptom: Controller Manager Not Leader\n**Possible Causes:**\n- Leader election lock not available\n- Resource exhaustion\n- Network partition to etcd\n- Configuration error\n\n**Diagnostic Commands:**\n```bash\n# Check controller manager status\nkubectl get pods -n kube-system -l component=kube-controller-manager\n\n# Check logs\nkubectl logs -n kube-system -l component=kube-controller-manager\n\n# Check leader election status\nkubectl get endpoints -n kube-system kube-controller-manager -o yaml\n\n# Check etcd connectivity\nkubectl exec -n kube-system -it <cm-pod> -- etcdctl endpoint health\n```\n\n**Resolution:**\n- Fix etcd connectivity\n- Increase resources if needed\n- Check for multiple controller managers running (should be 1)\n- Restore leader election configmap/lease\n\n### Symptom: Scheduler Not Placing Pods\n**Possible Causes:**\n- Scheduler not running\n- Predicates failing (node not fit)\n- Resource fragmentation\n- Taints/tolerations mismatch\n\n**Diagnostic Commands:**\n```bash\n# Check scheduler pods\nkubectl get pods -n kube-system -l component=kube-scheduler\n\n# Check logs\nkubectl logs -n kube-system -l component=kube-scheduler\n\n# Check predicate failures for a pod\nkubectl describe pod <pod-name> | grep -A10 -B5 \"predicate\"\n\n# Check node conditions\nkubectl get nodes -o jsonpath='{.items[*].status.conditions}'\n```\n\n**Resolution:**\n- Fix scheduler if crashed\n- Resolve predicate failures (usually resources or taints)\n- Defragment nodes by rescheduling pods\n- Fix taints/tolerations\n\n## 7. KubeSpray-Specific Issues\n\n### Symptom: Inventory Parsing Error\n**Possible Causes:**\n- YAML syntax error\n- Duplicate host definitions\n- Invalid IP address\n- Missing required variables\n\n**Diagnostic Commands:**\n```bash\n# Validate inventory\nansible-inventory -i inventory/my-cluster/hosts.yml --list\n\n# Check YAML syntax\npython3 -c \"import yaml; yaml.safe_load(open('inventory/my-cluster/hosts.yml'))\"\n\n# Look for duplicates\ngrep -n \"ansible_host\" inventory/my-cluster/hosts.yml | sort | uniq -d\n```\n\n**Resolution:**\n- Fix YAML syntax\n- Remove duplicate host entries\n- Correct IP addresses\n- Add missing variables\n\n### Symptom: Playbook Fails on Specific Node\n**Possible Causes:**\n- SSH connectivity issue\n- Missing prerequisites on node\n- Permission issue\n- Time drift\n\n**Diagnostic Commands:**\n```bash\n# Test SSH connectivity\nansible <node> -i inventory/my-cluster/hosts.yml -m ping\n\n# Check prerequisites\nansible <node> -i inventory/my-cluster/hosts.yml -m shell -a \"lsb_release -a\"\n\n# Check time sync\nansible <node> -i inventory/my-cluster/hosts.yml -m shell -a \"chronyc tracking\"\n\n# Run with verbose output\nansible-playbook -i inventory/my-cluster/hosts.yml playbook.yml -vvv\n```\n\n**Resolution:**\n- Fix SSH connectivity (check keys, ports, firewalls)\n- Install missing prerequisites\n- Adjust permissions\n- Synchronize time via NTP\n\n### Symptom: Air-Gap Image Pull Failure\n**Possible Causes:**\n- Image not in Harbor/Nexus\n- Authentication to registry failed\n- TLS certificate not trusted\n- Network blocked to registry\n\n**Diagnostic Commands:**\n```bash\n# Check image exists in registry\ncurl -sk -u \"user:pass\" https://harbor.internal/api/v2.0/projects/<proj>/repositories/<repo>/artifacts\n\n# Try to login to registry\n docker login harbor.internal\n\n# Check TLS certificates\nopenssl s_client -connect harbor.internal:443 -servername harbor.internal\n\n# Check network connectivity\nnc -zv harbor.internal 443\n\n# Check containerd config\ncat /etc/containerd/config.toml | grep -A5 -B5 \"harbor\"\n```\n\n**Resolution:**\n- Push missing image to Harbor\n- Fix registry credentials in secret\n- Add internal CA to trusted certificates\n- Fix network rules\n- Fix network connectivity\n- Ensure containerd mirror config correct\n\n## 8. General Diagnostic Tools\n\n### Essential Commands for All Issues\n```bash\n# Cluster overview\nkubectl get nodes\nkubectl get pods -A\n\n# Node details\nkubectl describe node <node-name>\n\n# Pod details\nkubectl describe pod <pod-name> -n <namespace>\n\n# Events (sorted by time)\nkubectl get events --sort-by='.metadata.timestamp'\n\n# Logs\nkubectl logs <pod-name> -n <namespace> [-c container] [-p --previous]\n\n# Execute into pod\nkubectl exec -it <pod-name> -n <namespace> -- /bin/sh\n\n# Port forward for debugging\nkubectl port-forward <pod-name> <local-port>:<remote-port> -n <namespace>\n\n# Network troubleshooting\nkubectl run -it --rm --image=alpine:3.18 net-debug -- \\\n  apk add --no-cache curl tcpdump netcat-openrsd bind-tools iptables\n\n# System logs\njournalctl -u kubelet -f\njournalctl -u containerd -f\njournalctl -u ssh -f\n```\n\n### Log Locations\n```bash\n# Kubernetes components\n/var/log/kubernetes/\n\n# Containerd\n/var/log/messages\n/var/log/syslog\n\n# System services\n/ctl/\n\n# Calico\n/var/log/calico/node.log\n/var/log/calico/felix.log\n\n# HAProxy\n/var/log/haproxy.log\n\n# Keepalived\n/var/log/keepalived.log\n\n# Ceph\n/var/log/ceph/*.log\n```\n\n## Recovery Procedures\n\n### etcd Disaster Recovery\n1. Stop all etcd members\n2. Restore from snapshot:\n   ```\n   ETCDCTL_API=3 etcdctl --data-dir /var/lib/etcd-from-snapshot \\\n     snapshot restore /var/backups/etcd-snapshot.db\n   ```\n3. Update etcd member URLs in restored config if IPs changed\n4. Start etcd members one by one\n5. Update Kubernetes API server endpoints if needed\n\n### Control Plane Reconstruction\nIf all masters lost:\n1. Provision new VMs with same IPs/hostnames\n2. Run OS preparation\n3. Install containerd\n4. Copy etcd data from backup\n5. Initialize first master with `--experimental-control-plane`\n6. Join additional masters\n7. Rejoin workers\n\n### etcd Snapshot Automation\nAdd to cron:\n```\n0 2 * * * root ETCDCTL_API=3 etcdctl --endpoints=https://10.1.1.1:2379 \\\n  --cacert=/etc/kubernetes/pki/etcd/ca.crt \\\n  --cert=/etc/kubernetes/pki/etcd/server.crt \\\n  --key=/etc/kubernetes/pki/etcd/server.key \\\n  snapshot save /var/etcd-backup/etcd-$(date +\\%F\\%T).db\n```\n\n## Preventive Measures\n\n1. **Monitoring**: Deploy Prometheus/Grafana with alerts for:\n   - Node NotReady\n   - etcd quorum loss\n   - High API server latency\n   - Certificate expiration (<7 days)\n   - Kubelet restart loops\n\n2. **Backups**:\n   - Daily etcd snapshots\n   - Monthly VM/etcd volume snapshots\n   - Git backup of all configs (Ansible, Helm values, manifests)\n\n3. **Testing**:\n   - Quarterly disaster recovery drills\n   - Monthly upgrade testing in staging\n   - Chaos engineering (simulate node/network failures)\n\n4. **Documentation**:\n   - Keep runbook updated\n   - Document all manual interventions\n   - Maintain version matrix of all components\n\n## Emergency Contacts\n\n- **On-call Engineer**: [Pager Duty/OpsGenie details]\n- **Storage Team**: [Ceph/Storage specialists]\n- **Network Team**: [Network/Security team]\n- **Platform Team**: [K8s/Rancher/ArgoCD specialists]\n- **Vendor Support**: [If applicable]\n\n## Quick Reference: Common Fix Commands\n\n```bash\n# Restart kubelet\nsystemctl restart kubelet\n\n# Restart containerd\nsystemctl restart containerd\n\n# Renew kubeadm certificates\nkubeadm certs renew all\n\n# Reset etcd OK)\nkubeadm reset\n\n# cordon and drain node\nkubectl cordon <node>\nkubectl drain <node> --ignore-daemonsets --delete-emptydir-data\n\n# uncordon node\nkubectl uncordon <node>\n\n# Check pod restarts in last hour\nkubectl get pods -A --field-selector=status.phase=Running \\\n  -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.status.containerStatuses[*].restartCount}{\"\\n\"}{end}' \\\n  | sort -k2 -nr | head -10\n\n# Watch node status\nwatch -n 5 \"kubectl get nodes\"\n\n# Watch pod status in namespace\nwatch -n 5 \"kubectl get pods -n <namespace>\"\n\n# Tail all pods in namespace\nstern -n <namespace> .\n```\n\n## When to Escalate\n\nEscalate to senior/storage/network team if:\n- Multiple etcd members failed simultaneously\n- Storage cluster showing data loss symptoms\n- Network partition affecting >50% of cluster\n- Certificate authority compromised\n- Security breach suspected\n- Application data corruption detected\n\n---\n*Last Updated: $(date)*\n*Version: 1.0*\n*Environment: Air-gapped Kubernetes with KubeSpray*\n