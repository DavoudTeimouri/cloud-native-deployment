# Kubernetes Cheat Sheet

## Cluster Management
```bash
# Get nodes
kubectl get nodes
kubectl get nodes -o wide
kubectl describe node <node-name>

# Cordon/uncordon (mark unschedulable/schedulable)
kubectl cordon <node-name>
kubectl uncordon <node-name>

# Drain node for maintenance
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Node resource usage
kubectl top nodes
kubectl top nodes --use-proxy-bytes
```

## Namespace Management
```bash
# Get namespaces
kubectl get ns
kubectl describe ns <namespace>

# Create namespace
kubectl create namespace <name>
kubectl create -f namespace.yaml

# Set default namespace
kubectl config set-context --current --namespace=<name>
```

## Workload Management
### Pods
```bash
# Get pods
kubectl get pods
kubectl get pods -A
kubectl get pods -o wide
kubectl get pods -l app=myapp
kubectl describe pod <pod-name>

# Get pod logs
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container-name>
kubectl logs <pod-name> --previous
kubectl logs -f <pod-name>  # Follow

# Execute into pod
kubectl exec -it <pod-name> -- /bin/sh
kubectl exec -it <pod-name> -c <container> -- /bin/sh

# Copy files to/from pod
kubectl cp <local-file> <pod-name>:<remote-path>
kubectl cp <pod-name>:<remote-path> <local-file>

# Port forward
kubectl port-forward <pod-name> <local-port>:<remote-port>
```

### Deployments
```bash
# Get deployments
kubectl get deploy
kubectl get deploy -o wide
kubectl describe deploy <deploy-name>

# Scale deployment
kubectl scale deploy <deploy-name> --replicas=5
kubectl scale deploy <deploy-name> --replicas=0

# Rollout management
kubectl rollout status deploy/<deploy-name>
kubectl rollout history deploy/<deploy-name>
kubectl rollout undo deploy/<deploy-name>
kubectl rollout pause deploy/<deploy-name>
kubectl rollout resume deploy/<deploy-name>

# Edit deployment
kubectl edit deploy <deploy-name>
```

### Services
```bash
# Get services
kubectl get svc
kubectl get svc -o wide
kubectl describe svc <svc-name>

# Expose deployment as service
kubectl expose deploy <deploy-name> --port=80 --target-port=8080
kubectl expose deploy <deploy-name> --type=LoadBalancer --port=443 --target-port=8443
```

### Ingress
```bash
# Get ingress
kubectl get ingress
kubectl describe ingress <ingress-name>

# Test ingress
curl -H "Host: foo.example.com" http://<ingress-ip>/
```

## Storage
```bash
# Get persistent volumes
kubectl get pv
kubectl get pvc
kubectl describe pvc <pvc-name>

# Get storage classes
kubectl get storageclass
```

## Configuration & Secrets
```bash
# Get configmaps and secrets
kubectl get cm
kubectl get secret
kubectl describe secret <secret-name>

# Create secret from literal
kubectl create secret generic <secret-name> --from-literal=key1=val1 --from-literal=key2=val2

# Create secret from file
kubectl create secret generic <secret-name> --from-file=./path/to/file

# Edit secret
kubectl edit secret <secret-name>
```

## Labels and Selectors
```bash
# Label resources
kubectl label pods <pod-name> env=production
kubectl label nodes <node-name> zone=us-east-1a
kubectl label --overwrite pods <pod-name> status=debug

# Select resources by label
kubectl get pods -l env=production,release=stable
kubectl get pods -l 'env in (production,staging)'
kubectl get pods -l 'environment notin (dev)'
```

## Resource Management
```bash
# Describe resource usage
kubectl top pod
kubectl top pod --containers
kubectl top node

# Set resource limits via patch
kubectl patch pod <pod-name> -p '{"spec":{"containers":[{"name":"<container-name>","resources":{"limits":{"cpu":"500m","memory":"512Mi"}}}]}}'

# Create limit range
kubectl create -f limit-range.yaml
```

## DaemonSets & StatefulSets & Jobs
```bash
# DaemonSet
kubectl get ds
kubectl describe ds <ds-name>

# StatefulSet
kubectl get sts
kubectl describe sts <sts-name>
kubectl scale sts <sts-name> --replicas=3

# Job/CronJob
kubectl get job
kubectl get cronjob
kubectl create job --from=cronjob/<cronjob-name> <job-name>
```

## Context & Configuration
```bash
# Context management
kubectl config get-contexts
kubectl config use-context <context-name>
kubectl config current-context

# View config
kubectl config view
kubectl config view --minify

# Set namespace for context
kubectl config set-context --current --namespace=<namespace>
```

## Debugging
```bash
# Debug DNS
kubectl run -it --rm --image=alpine:3.18 dnsutils -- nslookup kubernetes.default.svc.cluster.local

# Debug connectivity
kubectl run -it --rm --image=alpine:3.18 netutils -- sh
# Inside container: wget, curl, nc, telnet, ping, traceroute, dig

# Describe events
kubectl get events --sort-by='.metadata.timestamp'
kubectl get events --field-selector involvedObject.name=<pod-name>

# API resources
kubectl api-resources
kubectl api-versions
```

## kubectl Tips & Tricks
```bash
# Output formats
kubectl get pods -o wide
kubectl get pods -o json
kubectl get pods -o yaml
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase

# Watch changes
kubectl get pods -w
kubectl get nodes -w

# Label output
kubectl get pods --show-labels
kubectl get nodes --show-labels

# Template output
kubectl get pods -o go-template='{{range .items}}{{.metadata.name}} {{.status.phase}}{{"\n"}}{{end}}'

# Explain resource fields
kubectl explain pod.spec.containers
kubectl explain deployment.spec.strategy
```

## Common One-liners
```bash
# Restart all pods in deployment
kubectl rollout restart deploy/<deploy-name>

# Delete all completed jobs
kubectl delete job --field-selector=status.successful=1

# Delete all evicted pods
kubectl delete pods --field-selector=status.phase=Failed

# Get all images running in cluster
kubectl get pods -o jsonpath="{.items[*].spec.containers[*].image}" | tr -s '[[:space:]]' '\n' | sort | uniq -c

# Count resources by namespace
kubectl get all --all-namespaces

# Apply multiple files
kubectl apply -f ./k8s/
```

## Environment Variables & Arguments
```bash
# Set env var in deployment
kubectl set env deploy/<deploy-name> KEY=value

# Set args/command
kubectl patch deploy <deploy-name> -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container-name>","args":["--flag","value"]}]}}}}'
```

## Rollback & History
```bash
# View rollout history
kubectl rollout history deploy/<deploy-name>
kubectl rollout history deploy/<deploy-name> --revision=2

# Undo to specific revision
kubectl rollout undo deploy/<deploy-name> --to-revision=2
```