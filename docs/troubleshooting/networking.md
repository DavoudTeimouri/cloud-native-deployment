# Networking Troubleshooting Guide

> Covers: Calico, MetalLB, NGINX Ingress, HAProxy/keepalived, CoreDNS

---

## 1. Calico Issues

### 1.1 Pod-to-Pod Connectivity Failure

**Symptom:** Pods on different nodes cannot communicate

**Possible Causes:**
- BGP peering down
- Felix agent not running
- IP pool exhausted
- iptables rules blocking
- Network policy blocking

**Diagnostic Commands:**
```bash
# Check Calico pods
kubectl get pods -n kube-system -l k8s-app=calico-node
kubectl logs -n kube-system -l k8s-app=calico-node --tail=50

# Check BGP peer status
calicoctl node status
# or
kubectl exec -n kube-system calico-node-<id> -- calicoctl node status

# Check IP pools
calicoctl get ippool -o wide
kubectl get ippools.crd.projectcalico.org -o yaml

# Check BGP configuration
calicoctl get bgpconfig -o wide
kubectl get bgpconfigurations.crd.projectcalico.org -o yaml

# Check BGP peers
calicoctl get bgppeer -o wide
kubectl get bgppeers.crd.projectcalico.org -o wide

# Test connectivity between pods
kubectl run test1 --image=busybox --restart=Never -it --rm -- ping -c 3 <pod-ip-on-other-node>
```

**Resolution:**
```bash
# Restart Calico on affected node
kubectl delete pod -n kube-system -l k8s-app=calico-node --field-selector spec.nodeName=<node>

# If BGP peering is down, check router config
calicoctl node status
# Verify router ID, AS number, peer IP match

# If IP pool is exhausted, expand it
calicoctl patch ippool default-ipv4-ippool --patch '{"spec": {"cidr": "10.244.0.0/16"}}'

# Check for iptables issues
ssh <node> iptables -L -n -v | grep cali
ssh <node> iptables -t nat -L -n -v | grep cali
```

---

### 1.2 BGP Peering Issues

**Symptom:** `calicoctl node status` shows BGP peer as `not established`

**Diagnostic Commands:**
```bash
# Detailed BGP status
calicoctl node status

# Check bird logs
kubectl exec -n kube-system calico-node-<id> -- cat /var/log/calico/bird/bird.log

# Check BGP peer configuration
calicoctl get bgppeer -o yaml

# Test BGP port connectivity
nc -zv <router-ip> 179
```

**Resolution:**
```bash
# Verify BGP peer config matches router
calicoctl get bgppeer <peer-name> -o yaml
# Check: peerIP, asNumber match router config

# If using node-to-node mesh and it's broken
calicoctl patch bgpconfiguration default --patch '{"spec": {"nodeToNodeMeshEnabled": true}}'

# If using route reflector
calicoctl get bgppeer rr -o yaml
# Ensure route reflector config is correct

# Restart bird on affected node
kubectl exec -n kube-system calico-node-<id> -- kill -HUP $(pgrep bird)
```

---

### 1.3 Network Policy Blocking Traffic

**Symptom:** Traffic denied between pods that should communicate

**Diagnostic Commands:**
```bash
# List all network policies
kubectl get networkpolicies --all-namespaces
calicoctl get networkpolicy --all-namespaces -o wide

# Check Calico profiles and rules
calicoctl get profile -o wide
calicoctl get policy -o wide

# Check if policy is applied to pod
calicoctl get workloadendpoint -o wide | grep <pod-ip>

# Test with policy temporarily removed
kubectl delete networkpolicy <policy> -n <namespace>
# Test connectivity, then re-apply
```

**Resolution:**
```bash
# Review policy for overly restrictive rules
kubectl describe networkpolicy <policy> -n <namespace>

# Add allow rule for required traffic
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-specific
  namespace: <namespace>
spec:
  podSelector:
    matchLabels:
      app: <app>
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: <source-app>
    ports:
    - port: <port>
EOF

# Use Calico's policy ordering (lower order = higher priority)
calicoctl apply -f policy.yaml
```

---

## 2. MetalLB Issues

### 2.1 IP Not Assigned to Service

**Symptom:** Service of type `LoadBalancer` stuck in `<pending>` for EXTERNAL-IP

**Diagnostic Commands:**
```bash
# Check service status
kubectl get svc <service> -n <namespace>
kubectl describe svc <service> -n <namespace>

# Check MetalLB controller logs
kubectl logs -n metallb-system -l app=metallb,component=controller --tail=50

# Check MetalLB speaker logs
kubectl logs -n metallb-system -l app=metallb,component=speaker --tail=50

# Check IP address pool
kubectl get ipaddresspool -n metallb-system -o yaml
kubectl get l2advertisement -n metallb-system -o yaml
```

**Resolution:**
```bash
# Verify address pool has available IPs
kubectl get ipaddresspool -n metallb-system -o yaml
# Check that the pool range is correct and not exhausted

# Check if L2 Advertisement is configured
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF

# For BGP mode, check BGP peer
kubectl get bgppeers -n metallb-system -o yaml
# Verify peer ASN and IP match router config

# Restart MetalLB
kubectl rollout restart deployment controller -n metallb-system
kubectl rollout restart daemonset speaker -n metallb-system
```

---

### 2.2 ARP Issues (Layer2 Mode)

**Symptom:** External clients cannot reach LoadBalancer IP

**Diagnostic Commands:**
```bash
# Check ARP tables on client machines
arp -a | grep <loadbalancer-ip>

# Check which node is announcing
kubectl logs -n metallb-system -l app=metallb,component=speaker | grep <loadbalancer-ip>

# Check ARP on nodes
ssh <node> ip neigh | grep <loadbalancer-ip>
ssh <node> arping -c 3 <loadbalancer-ip>
```

**Resolution:**
```bash
# Ensure speaker is running on the correct node
kubectl get pods -n metallb-system -l app=metallb,component=speaker -o wide

# Check for ARP conflicts on network
# Ensure no other device has the same IP

# Verify the service has externalTrafficPolicy
kubectl get svc <service> -n <namespace> -o jsonpath='{.spec.externalTrafficPolicy}'
# Cluster: traffic goes through any node (may need hairpin)
# Local: traffic only to local pods (preserves source IP)
```

---

### 2.3 BGP Session Not Established (BGP Mode)

**Diagnostic Commands:**
```bash
# Check speaker logs for BGP errors
kubectl logs -n metallb-system -l app=metallb,component=speaker | grep -i bgp

# Check BGP peer config
kubectl get bgppeers -n metallb-system -o yaml

# Test BGP connectivity
nc -zv <router-ip> 179
```

**Resolution:**
```bash
# Verify BGP peer configuration
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: router-peer
  namespace: metallb-system
spec:
  myASN: 64512
  peerASN: 64513
  peerAddress: 10.0.0.1
  routerID: 10.0.0.2
EOF

# Check router accepts BGP from node IPs
# Verify no firewall blocking TCP/179
```

---

## 3. NGINX Ingress Issues

### 3.1 502 Bad Gateway

**Symptom:** Ingress returns 502 when accessing backend service

**Possible Causes:**
- Backend pods not running
- Backend service endpoints empty
- Readiness probe failing
- Backend port mismatch

**Diagnostic Commands:**
```bash
# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100

# Check backend service endpoints
kubectl get endpoints <service> -n <namespace>
kubectl describe svc <service> -n <namespace>

# Check backend pods
kubectl get pods -n <namespace> -l <selector>
kubectl describe pod <backend-pod> -n <namespace>

# Check ingress configuration
kubectl describe ingress <ingress> -n <namespace>

# Test backend directly
kubectl exec -it <test-pod> -n <namespace> -- wget -qO- http://<service>:<port>
```

**Resolution:**
```bash
# Fix backend service selector
kubectl get svc <service> -n <namespace> -o jsonpath='{.spec.selector}'
kubectl get pods -n <namespace> --show-labels

# Fix backend port in ingress
kubectl edit ingress <ingress> -n <namespace>
# Ensure servicePort matches container port

# Check for backend timeouts
kubectl annotate ingress <ingress> -n <namespace> \
  nginx.ingress.kubernetes.io/proxy-connect-timeout="10" \
  nginx.ingress.kubernetes.io/proxy-read-timeout="60"
```

---

### 3.2 503 Service Unavailable

**Symptom:** Ingress returns 503

**Diagnostic Commands:**
```bash
# Check if any endpoints exist
kubectl get endpoints <service> -n <namespace>

# Check for canary/weight issues
kubectl get ingress <ingress> -n <namespace> -o yaml | grep -A 10 canary

# Check ingress controller config
kubectl get configmap -n ingress-nginx ingress-nginx-controller -o yaml
```

**Resolution:**
```bash
# Ensure at least one backend pod is ready
kubectl scale deployment <deployment> -n <namespace> --replicas=1

# Check for pre-stop hooks causing delays
kubectl get pod <pod> -n <namespace> -o jsonpath='{.spec.containers[0].lifecycle}'
```

---

### 3.3 TLS/SSL Issues

**Symptom:** Browser shows certificate warnings, TLS handshake failures

**Diagnostic Commands:**
```bash
# Check TLS secret
kubectl get secret <tls-secret> -n <namespace> -o yaml
kubectl describe secret <tls-secret> -n <namespace>

# Test TLS connection
openssl s_client -connect example.com:443 -servername example.com
curl -vI https://example.com

# Check cert-manager certificate status
kubectl get certificate -n <namespace>
kubectl describe certificate <cert> -n <namespace>
kubectl get certificaterequest -n <namespace>
kubectl describe challenge -n <namespace>
```

**Resolution:**
```bash
# Check if cert-manager is issuing certificates
kubectl get orders.acme.cert-manager.io -n <namespace>
kubectl describe order <order> -n <namespace>

# Check for rate limiting (Let's Encrypt)
kubectl logs -n cert-manager -l app=cert-manager --tail=100 | grep -i "rate\|limit"

# Manually create TLS secret if needed
kubectl create secret tls <secret-name> \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  -n <namespace>
```

---

### 3.4 Config Reload Failures

**Symptom:** Ingress changes not taking effect

**Diagnostic Commands:**
```bash
# Check controller logs for reload errors
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx | grep -i "reload\|error\|config"

# Check generated nginx config
kubectl exec -n ingress-nginx <ingress-pod> -- cat /etc/nginx/nginx.conf | head -100

# Check for syntax errors in annotations
kubectl describe ingress <ingress> -n <namespace> | grep -A 5 "Annotations"
```

**Resolution:**
```bash
# Restart ingress controller
kubectl rollout restart deployment -n ingress-nginx ingress-nginx-controller

# Fix annotation errors
kubectl edit ingress <ingress> -n <namespace>
```

---

## 4. HAProxy / keepalived Issues

### 4.1 VIP Not Failing Over

**Symptom:** Virtual IP stays on failed master, no failover

**Diagnostic Commands:**
```bash
# Check keepalived status
systemctl status keepalived
journalctl -u keepalived --since "10 minutes ago" --no-pager

# Check VIP assignment
ip addr show <interface> | grep <vip>

# Check keepalived configuration
cat /etc/keepalived/keepalived.conf

# Check VRRP communication
tcpdump -i <interface> vrrp -nn
```

**Resolution:**
```bash
# Restart keepalived
systemctl restart keepalived

# Check firewall (VRRP uses IP protocol 112)
iptables -L -n | grep 112
# Allow VRRP
iptables -I INPUT -p vrrp -j ACCEPT

# Check priority settings in keepalived.conf
# Ensure MASTER has higher priority than BACKUP

# Verify virtual_router_id matches between nodes
grep virtual_router_id /etc/keepalived/keepalived.conf
```

---

### 4.2 HAProxy Backend Down

**Symptom:** HAProxy shows backend servers as DOWN

**Diagnostic Commands:**
```bash
# Check HAProxy stats
echo "show stat" | socat stdio /var/run/haproxy.sock | cut -d, -f1,2,18

# Check HAProxy logs
journalctl -u haproxy --since "10 minutes ago" --no-pager

# Check backend connectivity
curl -v http://<backend-ip>:<port>/health

# Check HAProxy config
haproxy -c -f /etc/haproxy/haproxy.cfg
```

**Resolution:**
```bash
# Restart HAProxy
systemctl restart haproxy

# Check backend health check endpoint
# Ensure /health or configured check endpoint returns 200

# Verify backend IPs in config
grep -A 10 "backend" /etc/haproxy/haproxy.cfg

# Check for maxconn limits
echo "show info" | socat stdio /var/run/haproxy.sock | grep -i max
```

---

## 5. CoreDNS Issues

### 5.1 DNS Resolution Timeout

**Symptom:** Pods cannot resolve any DNS names

**Diagnostic Commands:**
```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# Check CoreDNS service
kubectl get svc -n kube-system kube-dns
kubectl get endpoints -n kube-system kube-dns

# Test DNS from a pod
kubectl run dns-test --image=busybox:1.28 --restart=Never -it --rm -- \
  nslookup kubernetes.default.svc.cluster.local

# Check CoreDNS config
kubectl get configmap coredns -n kube-system -o yaml

# Check node DNS resolution
ssh <node> cat /etc/resolv.conf
```

**Resolution:**
```bash
# Restart CoreDNS
kubectl rollout restart deployment coredns -n kube-system

# Check for CoreDNS crash loop
kubectl logs -n kube-system -l k8s-app=kube-dns --previous

# Fix CoreDNS config
kubectl edit configmap coredns -n kube-system
# Ensure Corefile is valid:
# .:53 {
#     errors
#     health
#     kubernetes cluster.local in-addr.arpa ip6.arpa {
#       pods insecure
#       fallthrough in-addr.arpa ip6.arpa
#     }
#     forward . /etc/resolv.conf
#     cache 30
#     loop
#     reload
#     loadbalance
# }

# Check for conntrack race condition
sysctl net.netfilter.nf_conntrack_udp_timeout=30
```

---

### 5.2 NXDOMAIN for Valid Names

**Diagnostic Commands:**
```bash
# Test specific name
kubectl run test --image=busybox:1.28 --restart=Never -it --rm -- nslookup <service>.<namespace>.svc.cluster.local

# Check if service exists
kubectl get svc -n <namespace>

# Check CoreDNS logs for query
kubectl logs -n kube-system -l k8s-app=kube-dns -f
```

**Resolution:**
```bash
# Verify service name and namespace match
# DNS format: <service>.<namespace>.svc.cluster.local

# Check for headless service issues
kubectl get svc <service> -n <namespace> -o jsonpath='{.spec.clusterIP}'
# If "None", it's headless - use pod hostname instead
```

---

## 6. Tool Reference

### tcpdump
```bash
# Capture traffic on specific interface
tcpdump -i eth0 -nn host <ip> and port <port>

# Capture pod traffic
tcpdump -i calixxx -nn -w /tmp/capture.pcap

# Capture DNS traffic
tcpdump -i any -nn port 53

# Capture BGP traffic
tcpdump -i any -nn port 179

# Read pcap file
tcpdump -r /tmp/capture.pcap -nn
```

### iptables
```bash
# List all rules
iptables -L -n -v --line-numbers

# List NAT rules
iptables -t nat -L -n -v

# List Calico rules
iptables -L -n -v | grep cali

# Check specific chain
iptables -L FORWARD -n -v

# Count packets per rule
iptables -L -n -v | sort -k1 -n -r | head -20
```

### calicoctl
```bash
# Node status
calicoctl node status

# Get resources
calicoctl get ippool -o wide
calicoctl get bgppeer -o wide
calicoctl get networkpolicy --all-namespaces -o wide
calicoctl get felixconfig -o wide

# Apply policy
calicoctl apply -f policy.yaml

# Check BIRD status
calicoctl node bird status
calicoctl node bird bgp peer
```

### nc (netcat)
```bash
# Test TCP connectivity
nc -zv <host> <port>

# Test UDP
nc -zvu <host> <port>

# Port scan range
nc -zv <host> 80-443

# Listen on port
nc -l -p 8080
```

### curl
```bash
# Test HTTP endpoint
curl -v http://<service>:<port>/health

# Test with specific Host header
curl -v -H "Host: example.com" http://<ingress-ip>/

# Test HTTPS with cert info
curl -vI --cacert ca.crt https://example.com

# Test with timeout
curl --connect-timeout 5 --max-time 10 http://<service>/health

# Follow redirects
curl -vL http://<service>
```
