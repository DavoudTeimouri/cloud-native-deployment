# Kubernetes Cheat Sheet

> Quick reference for daily cluster operations

---

## Cluster Management

| Action | Command |
|--------|---------|
| List nodes | `kubectl get nodes -o wide` |
| Node details | `kubectl describe node <node>` |
| Node labels | `kubectl get nodes --show-labels` |
| Add label | `kubectl label node <node> key=value` |
| Remove label | `kubectl label node <node> key-` |
| Cordon (mark unschedulable) | `kubectl cordon <node>` |
| Uncordon (mark schedulable) | `kubectl uncordon <node>` |
| Drain (evict pods) | `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` |
| Taint node | `kubectl taint node <node> key=value:NoSchedule` |
| Remove taint | `kubectl taint node <node> key-` |
| Node resources | `kubectl top node` |
| Cluster info | `kubectl cluster-info` |
| Cluster version | `kubectl version --short` |
| API resources | `kubectl api-resources` |
| API versions | `kubectl api-versions` |

---

## Workload Management

### Pods

| Action | Command |
|--------|---------|
| List pods | `kubectl get pods -n <ns> -o wide` |
| All pods | `kubectl get pods --all-namespaces` |
| Pod details | `kubectl describe pod <pod> -n <ns>` |
| Pod logs | `kubectl logs <pod> -n <ns>` |
| Previous logs | `kubectl logs <pod> -n <ns> --previous` |
| Multi-container logs | `kubectl logs <pod> -n <ns> -c <container>` |
| Stream logs | `kubectl logs <pod> -n <ns> -f` |
| Execute command | `kubectl exec -it <pod> -n <ns> -- /bin/sh` |
| Delete pod | `kubectl delete pod <pod> -n <ns>` |
| Pod YAML | `kubectl get pod <pod> -n <ns> -o yaml` |
| Pod IPs | `kubectl get pods -n <ns> -o custom-columns=NAME:.metadata.name,IP:.status.podIP` |

### Deployments

| Action | Command |
|--------|---------|
| List deployments | `kubectl get deployments -n <ns>` |
| Deployment details | `kubectl describe deployment <dep> -n <ns>` |
| Scale | `kubectl scale deployment <dep> -n <ns> --replicas=3` |
| Rollout status | `kubectl rollout status deployment/<dep> -n <ns>` |
| Rollout history | `kubectl rollout history deployment/<dep> -n <ns>` |
| Rollback | `kubectl rollout undo deployment/<dep> -n <ns>` |
| Rollback to revision | `kubectl rollout undo deployment/<dep> -n <ns> --to-revision=2` |
| Restart | `kubectl rollout restart deployment/<dep> -n <ns>` |
| Update image | `kubectl set image deployment/<dep> <container>=<image>:<tag> -n <ns>` |
| Pause rollout | `kubectl rollout pause deployment/<dep> -n <ns>` |
| Resume rollout | `kubectl rollout resume deployment/<dep> -n <ns>` |

### StatefulSets

| Action | Command |
|--------|---------|
| List | `kubectl get statefulsets -n <ns>` |
| Scale | `kubectl scale statefulset <sts> -n <ns> --replicas=3` |
| Update image | `kubectl set image statefulset/<sts> <container>=<image>:<tag> -n <ns>` |
| Rollout status | `kubectl rollout status statefulset/<sts> -n <ns>` |

### DaemonSets

| Action | Command |
|--------|---------|
| List | `kubectl get daemonsets --all-namespaces` |
| Details | `kubectl describe ds <ds> -n <ns>` |
| Update image | `kubectl set image ds/<ds> <container>=<image>:<tag> -n <ns>` |

### Jobs & CronJobs

| Action | Command |
|--------|---------|
| List jobs | `kubectl get jobs -n <ns>` |
| Create job from cronjob | `kubectl create job --from=cronjob/<cj> <job-name> -n <ns>` |
| List cronjobs | `kubectl get cronjobs -n <ns>` |
| Suspend cronjob | `kubectl patch cronjob <cj> -n <ns> -p '{"spec":{"suspend":true}}'` |
| Trigger manually | `kubectl create job --from=cronjob/<cj> manual-trigger -n <ns>` |

---

## Networking

### Services

| Action | Command |
|--------|---------|
| List services | `kubectl get svc -n <ns> -o wide` |
| Service details | `kubectl describe svc <svc> -n <ns>` |
| Endpoints | `kubectl get endpoints <svc> -n <ns>` |
| Port forward | `kubectl port-forward svc/<svc> 8080:80 -n <ns>` |

### Ingress

| Action | Command |
|--------|---------|
| List ingress | `kubectl get ingress -n <ns>` |
| Ingress details | `kubectl describe ingress <ing> -n <ns>` |

### Network Policies

| Action | Command |
|--------|---------|
| List policies | `kubectl get networkpolicies -n <ns>` |
| Policy details | `kubectl describe networkpolicy <pol> -n <ns>` |
| All policies | `kubectl get networkpolicies --all-namespaces` |

### Port Forwarding

| Action | Command |
|--------|---------|
| Pod port forward | `kubectl port-forward <pod> 8080:80 -n <ns>` |
| Service port forward | `kubectl port-forward svc/<svc> 8080:80 -n <ns>` |
| Local to remote | `kubectl port-forward <pod> 8080:8080 -n <ns>` |
| Listen on all interfaces | `kubectl port-forward --address 0.0.0.0 <pod> 8080:80 -n <ns>` |

---

## Storage

| Action | Command |
|--------|---------|
| List PVs | `kubectl get pv` |
| List PVCs | `kubectl get pvc -n <ns>` |
| PVC details | `kubectl describe pvc <pvc> -n <ns>` |
| List StorageClasses | `kubectl get sc` |
| SC details | `kubectl describe sc <sc>` |
| Default SC | `kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'` |
| Set default SC | `kubectl patch sc <sc> -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'` |
| Expand PVC | `kubectl patch pvc <pvc> -n <ns> -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'` |
| Delete PVC | `kubectl delete pvc <pvc> -n <ns>` |

---

## Debugging

| Action | Command |
|--------|---------|
| Pod events | `kubectl get events -n <ns> --field-selector involvedObject.name=<pod>` |
| All events | `kubectl get events --all-namespaces --sort-by='.lastTimestamp'` |
| Resource usage | `kubectl top pods -n <ns> --sort-by=memory` |
| Node usage | `kubectl top nodes` |
| Pod with node | `kubectl get pods -n <ns> -o wide` |
| Debug pod (busybox) | `kubectl run debug --image=busybox -it --rm -- /bin/sh` |
| Debug with network tools | `kubectl run debug --image=nicolaka/netshoot -it --rm -- /bin/sh` |
| Copy files to pod | `kubectl cp <local-path> <pod>:<pod-path> -n <ns>` |
| Copy files from pod | `kubectl cp <pod>:<pod-path> <local-path> -n <ns>` |
| Ephemeral debug container | `kubectl debug -it <pod> -n <ns> --image=busybox --target=<container>` |
| Resource quotas | `kubectl get resourcequotas -n <ns>` |
| Limit ranges | `kubectl get limitranges -n <ns>` |

---

## RBAC

| Action | Command |
|--------|---------|
| List roles | `kubectl get roles -n <ns>` |
| List role bindings | `kubectl get rolebindings -n <ns>` |
| List cluster roles | `kubectl get clusterroles` |
| List cluster role bindings | `kubectl get clusterrolebindings` |
| Check access | `kubectl auth can-i create deployments -n <ns>` |
| Check as user | `kubectl auth can-i create deployments --as=<user> -n <ns>` |
| Check as serviceaccount | `kubectl auth can-i create deployments --as=system:serviceaccount:<ns>:<sa> -n <ns>` |
| Create role | `kubectl create role <role> -n <ns> --verb=get,list --resource=pods` |
| Create rolebinding | `kubectl create rolebinding <rb> -n <ns> --role=<role> --user=<user>` |
| Create clusterrolebinding | `kubectl create clusterrolebinding <crb> --clusterrole=cluster-admin --user=<user>` |
| Service account token | `kubectl create token <sa> -n <ns>` |

---

## Configuration

### ConfigMaps

| Action | Command |
|--------|---------|
| List | `kubectl get configmaps -n <ns>` |
| Get | `kubectl get configmap <cm> -n <ns> -o yaml` |
| Create from file | `kubectl create configmap <cm> --from-file=<file> -n <ns>` |
| Create from literal | `kubectl create configmap <cm> --from-literal=key=value -n <ns>` |
| Create from env file | `kubectl create configmap <cm> --from-env-file=.env -n <ns>` |

### Secrets

| Action | Command |
|--------|---------|
| List | `kubectl get secrets -n <ns>` |
| Get | `kubectl get secret <secret> -n <ns> -o yaml` |
| Create generic | `kubectl create secret generic <secret> --from-literal=key=value -n <ns>` |
| Create TLS | `kubectl create secret tls <secret> --cert=tls.crt --key=tls.key -n <ns>` |
| Create docker-registry | `kubectl create secret docker-registry <secret> --docker-server=<reg> --docker-username=<user> --docker-password=<pass> -n <ns>` |
| Decode secret | `kubectl get secret <secret> -n <ns> -o jsonpath='{.data.key}' \| base64 -d` |

---

## Context & Multi-Cluster

| Action | Command |
|--------|---------|
| Current context | `kubectl config current-context` |
| List contexts | `kubectl config get-contexts` |
| Switch context | `kubectl config use-context <context>` |
| Set namespace | `kubectl config set-context --current --namespace=<ns>` |
| View kubeconfig | `kubectl config view` |
| Merge kubeconfigs | `KUBECONFIG=~/.kube/config:~/.kube/config2 kubectl config view --flatten > ~/.kube/merged` |

---

## Useful One-Liners

```bash
# Get all resources in namespace
kubectl get all -n <ns>

# Get pods with their labels
kubectl get pods -n <ns> --show-labels

# Get pods matching label
kubectl get pods -n <ns> -l app=nginx

# Get pods NOT matching label
kubectl get pods -n <ns> -l 'app!=nginx'

# Watch pod status
kubectl get pods -n <ns> -w

# Get pods sorted by restart count
kubectl get pods -n <ns> --sort-by='.status.containerStatuses[0].restartCount'

# Get pods on specific node
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=<node>

# Delete all pods in namespace (force)
kubectl delete pods --all -n <ns> --grace-period=0 --force

# Get resource usage per container
kubectl top pods -n <ns> --containers

# Export resource to YAML
kubectl get deployment <dep> -n <ns> -o yaml --export > deployment.yaml

# Apply with prune (remove orphaned resources)
kubectl apply -f manifests/ --prune -l app=myapp

# Diff before applying
kubectl diff -f manifests/

# Get cluster events in last hour
kubectl get events --all-namespaces --field-selector type=Warning --sort-by='.lastTimestamp'
```
