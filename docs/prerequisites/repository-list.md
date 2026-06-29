# Repository and Artifact List

## Table of Contents

- [Overview](#overview)
- [Ubuntu 22.04 Apt Repositories](#ubuntu-2204-apt-repositories)
- [Python pip Packages](#python-pip-packages)
- [Container Images](#container-images)
- [Helm Charts](#helm-charts)
- [Ceph Packages](#ceph-packages)
- [Nexus Repository Configuration](#nexus-repository-configuration)
- [Harbor Project Structure](#harbor-project-structure)
- [Complete Image List by Phase](#complete-image-list-by-phase)
- [Complete Chart List by Component](#complete-chart-list-by-component)
- [Raw Binaries and Other Artifacts](#raw-binaries-and-other-artifacts)
- [Air-Gap Transfer Procedure](#air-gap-transfer-procedure)

---

## Overview

This document provides a comprehensive list of all artifacts required for the air-gapped deployment. Every binary, package, image, and chart must be mirrored to the internal Nexus and Harbor infrastructure before deployment begins.

### Artifact Categories

| Category | Count | Storage Location | Format |
|----------|-------|-----------------|--------|
| Ubuntu apt packages | ~2,000 | Nexus (apt hosted) | .deb |
| Python pip packages | ~150 | Nexus (pip hosted) | .whl / .tar.gz |
| Container images | ~120 | Harbor | OCI |
| Helm charts | ~25 | Nexus (helm hosted) | .tgz |
| Ceph apt packages | ~300 | Nexus (apt hosted) | .deb |
| Raw binaries | ~20 | Nexus (raw hosted) | various |
| **Total** | **~2,715** | | |

---

## Ubuntu 22.04 Apt Repositories

### Required apt Packages (Per Node)

#### Base System Packages

| Package | Version | Purpose |
|---------|---------|---------|
| ubuntu-server | 22.04 LTS | Base OS |
| openssh-server | 1:8.9p1-3ubuntu0 | Remote access |
| vim | 2:8.2.3995-1ubuntu2 | Text editor |
| curl | 7.81.0-1ubuntu1 | HTTP client |
| wget | 1.21.2-2ubuntu1 | File download |
| net-tools | 1.60+git20180626 | Network tools |
| iproute2 | 5.15.0-1ubuntu4 | Network configuration |
| iptables | 1.8.7-1ubuntu5 | Firewall |
| htop | 3.0.5-7build2 | Process monitoring |
| tmux | 3.2a-4ubuntu1 | Terminal multiplexer |
| rsync | 3.2.7-0ubuntu0 | File sync |
| jq | 1.6-2.1ubuntu1 | JSON processing |
| gnupg2 | 2.2.27-3ubuntu4 | GPG keys |
| apt-transport-https | 2.4.12 | HTTPS apt |
| ca-certificates | 20230311ubuntu1 | SSL certificates |
| software-properties-common | 0.99.22.9 | PPA management |
| unattended-upgrades | 2ubuntu1 | Auto updates |

#### Kubernetes Node Packages

| Package | Version | Purpose |
|---------|---------|---------|
| containerd.io | $CONTAINERD_VERSION | Container runtime |
| kubelet | $K8S_VERSION-00 | Kubernetes node agent |
| kubeadm | $K8S_VERSION-00 | Cluster bootstrap |
| kubectl | $K8S_VERSION-00 | Kubernetes CLI |
| cri-tools | $CRI_TOOLS_VERSION | CRI testing |

#### Ceph Packages

| Package | Version | Purpose |
|---------|---------|---------|
| ceph-common | $CEPH_VERSION | Ceph CLI tools |
| ceph-mon | $CEPH_VERSION | Ceph monitor |
| ceph-osd | $CEPH_VERSION | Ceph OSD daemon |
| ceph-mds | $CEPH_VERSION | Ceph MDS (CephFS) |
| ceph-mgr | $CEPH_VERSION | Ceph manager |
| ceph-radosgw | $CEPH_VERSION | Ceph RGW (S3) |
| ceph-base | $CEPH_VERSION | Base Ceph libraries |
| ceph-fuse | $CEPH_VERSION | Ceph FUSE mount |
| rados-bench | $CEPH_VERSION | Ceph benchmark |
| python3-rados | $CEPH_VERSION | Python RADOS bindings |
| python3-rbd | $CEPH_VERSION | Python RBD bindings |
| python3-cephfs | $CEPH_VERSION | Python CephFS bindings |
| libcephfs2 | $CEPH_VERSION | CephFS library |
| librbd1 | $CEPH_VERSION | RBD library |
| librados2 | $CEPH_VERSION | RADOS library |
| libcephfs-jni | $CEPH_VERSION | CephFS JNI |

#### HAProxy and keepalived Packages

| Package | Version | Purpose |
|---------|---------|---------|
| haproxy | 2.4.14-1ubuntu1 | Load balancer |
| keepalived | 1:2.2.7-1ubuntu1 | VRRP failover |
| socat | 1.7.4.1-3ubuntu1 | HAProxy socket |

#### Monitoring and Logging Packages

| Package | Version | Purpose |
|---------|---------|---------|
| telegraf | 1.25-1ubuntu1 | Metrics collector |
| collectd | 5.12.0-1ubuntu1 | System statistics |

#### Security Packages

| Package | Version | Purpose |
|---------|---------|---------|
| auditd | 1:3.0.7-1ubuntu1 | Audit framework |
| apparmor | 3.0.4-2ubuntu2 | MAC system |
| apparmor-utils | 3.0.4-2ubuntu2 | AppArmor tools |
| fail2ban | 0.11.2-1ubuntu1 | Intrusion prevention |
| ufw | 0.36.1-8ubuntu1 | Firewall frontend |

#### Utility Packages

| Package | Version | Purpose |
|---------|---------|---------|
| lvm2 | 2.03.11-2ubuntu5 | Logical volume management |
| mdadm | 4.2-3ubuntu1 | RAID management |
| xfsprogs | 5.13.0-1ubuntu1 | XFS filesystem tools |
| e2fsprogs | 1.46.5-2ubuntu1 | ext4 filesystem tools |
| parted | 3.4-2ubuntu1 | Partition management |
| gdisk | 1.0.8-1ubuntu1 | GPT partition tool |
| smartmontools | 7.3-1ubuntu1 | Disk health monitoring |
| nvme-cli | 1.16-3ubuntu1 | NVMe management |
| ethtool | 1:5.16-1ubuntu1 | NIC configuration |
| bridge-utils | 1.7-1ubuntu1 | Bridge configuration |
| tcpdump | 4.99.1-3ubuntu1 | Packet capture |
| nmap | 7.91+dfsg1-1ubuntu1 | Network scanner |
| traceroute | 1:2.1.0-2ubuntu1 | Network diagnostics |
| dnsutils | 1:9.18.18-0ubuntu0 | DNS tools |
| netcat-openbsd | 1.218-4ubuntu1 | Network utility |
| conntrack | 1:1.4.6-2ubuntu1 | Connection tracking |
| ipset | 7.15-1ubuntu1 | IP set management |
| ebtables | 2.0.11-4ubuntu1 | Ethernet bridge firewall |

---

## Python pip Packages

### KubeSpray Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| ansible-core | $ANSIBLE_VERSION | Configuration management |
| ansible | $ANSIBLE_VERSION | Full Ansible |
| jinja2 | 3.1.x | Template engine |
| jmespath | 1.0.x | JSON query |
| netaddr | 0.8.x | Network address |
| pbr | 5.11.x | Python build |
| hvac | 1.1.x | HashiCorp Vault |
| requests | 2.28.x | HTTP library |
| urllib3 | 1.26.x | HTTP client |
| pyyaml | 6.0 | YAML parsing |
| cryptography | 3.4.x | Cryptography |
| packaging | 21.x | Package versioning |
| jsonschema | 4.x | JSON validation |
| bcrypt | 4.x | Password hashing |
| paramiko | 2.x | SSH library |
| scp | 0.14.x | SCP transfer |
| passlib | 1.7.x | Password hashing |
| mergevars | 1.0.x | Variable merging |
| docker | 6.x | Docker SDK |
| docker-compose | 1.29.x | Docker compose |
| openshift | 0.13.x | OpenShift client |
| kubernetes | 26.x | Kubernetes client |
| community.kubernetes | 2.0.x | K8s Ansible collection |
| ansible.netcommon | 5.x | Network modules |
| ansible.posix | 1.x | POSIX modules |
| ansible.utils | 2.x | Ansible utilities |
| community.general | 6.x | General community modules |
| community.docker | 3.x | Docker community modules |

### Ceph Admin Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| ceph-daemon | $CEPH_VERSION | Ceph daemon tool |
| cephadm | $CEPH_VERSION | Ceph administration |

### Additional Tools

| Package | Version | Purpose |
|---------|---------|---------|
| boto3 | 1.26.x | AWS SDK (for S3-compatible) |
| botocore | 1.29.x | AWS core |
| google-api-python-client | 2.x | Google Cloud SDK |
| azure-storage-blob | 12.x | Azure Storage |
| s3cmd | 2.3.x | S3 command line |
| awscli | 1.27.x | AWS CLI |

---

## Container Images

### Base Infrastructure Images

| Image | Tag | Size | Purpose |
|-------|-----|------|---------|
| ubuntu | 22.04 | 77 MB | Base OS image |
| alpine | 3.18 | 7 MB | Lightweight base |
| busybox | 1.36 | 1.2 MB | Debug/init containers |
| nginx | 1.25-alpine | 40 MB | Web server |
| pause | 3.9 | 682 KB | Pod sandbox |

### Kubernetes System Images (Phase 6/9)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| kube-apiserver | $K8S_VERSION | k8s.gcr.io | API server |
| kube-controller-manager | $K8S_VERSION | k8s.gcr.io | Controller manager |
| kube-scheduler | $K8S_VERSION | k8s.gcr.io | Scheduler |
| kube-proxy | $K8S_VERSION | k8s.gcr.io | Network proxy |
| etcd | $ETCD_VERSION | k8s.gcr.io | Distributed storage |
| coredns | $COREDNS_VERSION | k8s.gcr.io | DNS |
| pause | 3.9 | k8s.gcr.io | Pod sandbox |

### Calico Images (Phase 6/9)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| calico/cni | $CALICO_VERSION | docker.io | CNI plugin |
| calico/node | $CALICO_VERSION | docker.io | Calico node |
| calico/kube-controllers | $CALICO_VERSION | docker.io | K8s controllers |
| calico/typha | $CALICO_VERSION | docker.io | Typha daemon |
| calico/pod2daemon-flexvol | $CALICO_VERSION | docker.io | FlexVolume driver |
| calico/apiserver | $CALICO_VERSION | docker.io | Calico API server |
| calico/ctl | $CALICO_VERSION | docker.io | Calico CLI |

### containerd Images

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| containerd | $CONTAINERD_VERSION | docker.io | Container runtime |
| containerd/config | $CONTAINERD_VERSION | docker.io | containerd config |

### MetalLB Images (Phase 10)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| metallb/controller | $METALLB_VERSION | quay.io | MetalLB controller |
| metallb/speaker | $METALLB_VERSION | quay.io | MetalLB speaker |
| metallb/frr | $METALLB_VERSION | quay.io | FRR routing (BGP mode) |

### NGINX Ingress Images (Phase 10)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| ingress-nginx/controller | $NGINX_INGRESS_VERSION | registry.k8s.io | Ingress controller |
| ingress-nginx/kube-webhook-certgen | $CERTGEN_VERSION | registry.k8s.io | Webhook cert gen |
| ingress-nginx/opentelemetry | latest | registry.k8s.io | OpenTelemetry |

### cert-manager Images (Phase 7/10)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| cert-manager-controller | $CERTMANAGER_VERSION | quay.io | cert-manager controller |
| cert-manager-cainjector | $CERTMANAGER_VERSION | quay.io | CA injector |
| cert-manager-webhook | $CERTMANAGER_VERSION | quay.io | Webhook |
| cert-manager-acmesolver | $CERTMANAGER_VERSION | quay.io | ACME solver |
| cert-manager-ctl | $CERTMANAGER_VERSION | quay.io | CLI |

### Rancher Images (Phase 7)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| rancher/rancher | $RANCHER_VERSION | docker.io | Rancher server |
| rancher/rancher-agent | $RANCHER_VERSION | docker.io | Rancher agent |
| rancher/machine | $RANCHER_VERSION | docker.io | Rancher machine |
| rancher/fleet | $RANCHER_VERSION | docker.io | Fleet manager |
| rancher/fleet-agent | $RANCHER_VERSION | docker.io | Fleet agent |
| rancher/rancher-webhook | $RANCHER_VERSION | docker.io | Webhook |
| rancher/shell | $RANCHER_VERSION | docker.io | Shell utility |
| rancher/system-upgrade-controller | latest | docker.io | System upgrade |
| rancher/kubectl | latest | docker.io | kubectl |
| rancher/mirrored-calico-cni | $CALICO_VERSION | docker.io | Calico CNI mirror |
| rancher/mirrored-calico-node | $CALICO_VERSION | docker.io | Calico node mirror |
| rancher/mirrored-calico-kube-controllers | $CALICO_VERSION | docker.io | Calico controllers mirror |
| rancher/mirrored-coredns | $COREDNS_VERSION | docker.io | CoreDNS mirror |
| rancher/mirrored-pause | 3.9 | docker.io | Pause mirror |
| rancher/mirrored-ingress-nginx-controller | $NGINX_INGRESS_VERSION | docker.io | Ingress mirror |
| rancher/mirrored-cert-manager-controller | $CERTMANAGER_VERSION | docker.io | cert-manager mirror |
| rancher/mirrored-metrics-server | $METRICS_SERVER_VERSION | docker.io | Metrics server mirror |
| rancher/mirrored-calico-typha | $CALICO_VERSION | docker.io | Typha mirror |
| rancher/mirrored-calico-apiserver | $CALICO_VERSION | docker.io | Calico API mirror |
| rancher/mirrored-calico-flexvol | $CALICO_VERSION | docker.io | Flexvol mirror |
| rancher/mirrored-coredns-coredns | $COREDNS_VERSION | docker.io | CoreDNS mirror |
| rancher/mirrored-pause | 3.9 | docker.io | Pause mirror |
| rancher/mirrored-core-downloads | latest | docker.io | Core downloads |
| rancher/suc-image | latest | docker.io | SUC image |

### ArgoCD Images (Phase 7)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| argocd | $ARGOCD_VERSION | quay.io | ArgoCD server |
| argoproj/argocd | $ARGOCD_VERSION | quay.io | ArgoCD |
| argoproj/argo-cd | $ARGOCD_VERSION | quay.io | ArgoCD (alt) |
| redis | 7.0-alpine | docker.io | Redis cache |
| redis-exporter | 1.50 | docker.io | Redis metrics |
| dexidp/dex | $DEX_VERSION | ghcr.io | Dex identity |
| argocd-notifications | $ARGOCD_VERSION | quay.io | Notifications |
| argocd-image-updater | $IMAGE_UPDATER_VERSION | quay.io | Image updater |
| argocd-applicationset | $ARGOCD_VERSION | quay.io | ApplicationSet |
| argocd-repo-server | $ARGOCD_VERSION | quay.io | Repo server |

### Prometheus Stack Images (Phase 7)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| prom/prometheus | $PROMETHEUS_VERSION | docker.io | Prometheus server |
| prom/alertmanager | $ALERTMANAGER_VERSION | docker.io | Alertmanager |
| prom/pushgateway | $PUSHGATEWAY_VERSION | docker.io | Pushgateway |
| prom/node-exporter | $NODE_EXPORTER_VERSION | docker.io | Node exporter |
| grafana/grafana | $GRAFANA_VERSION | docker.io | Grafana |
| grafana/loki | $LOKI_VERSION | docker.io | Loki |
| grafana/promtail | $PROMTAIL_VERSION | docker.io | Promtail |
| grafana/mimir | $MIMIR_VERSION | docker.io | Mimir |
| grafana/tempo | $TEMPO_VERSION | docker.io | Tempo |
| grafana/agent | $GRAFANA_AGENT_VERSION | docker.io | Grafana Agent |
| brancz/prometheus-example-app | latest | docker.io | Example app |
| quay.io/brancz/prometheus-example-app | latest | quay.io | Example app |
| quay.io/brancz/prometheus-operator | $PROMETHEUS_OPERATOR_VERSION | quay.io | Prometheus operator |
| quay.io/brancz/prometheus-adapter | $PROMETHEUS_ADAPTER_VERSION | quay.io | Prometheus adapter |
| jimmidyson/configmap-reload | latest | docker.io | Configmap reload |
| quay.io/coreos/kube-state-metrics | $KUBESTATEMETRICS_VERSION | quay.io | K8s state metrics |
| quay.io/coreos/prometheus-config-reloader | $PROMETHEUS_OPERATOR_VERSION | quay.io | Config reloader |
| quay.io/coreos/prometheus-operator | $PROMETHEUS_OPERATOR_VERSION | quay.io | Operator |
| k8s.gcr.io/kube-state-metrics/kube-state-metrics | $KUBESTATEMETRICS_VERSION | k8s.gcr.io | K8s state metrics |
| k8s.gcr.io/ingress-nginx/kube-webhook-certgen | $CERTGEN_VERSION | k8s.gcr.io | Webhook certgen |
| registry.k8s.io/kube-state-metrics/kube-state-metrics | $KUBESTATEMETRICS_VERSION | registry.k8s.io | K8s state metrics |
| registry.k8s.io/ingress-nginx/kube-webhook-certgen | $CERTGEN_VERSION | registry.k8s.io | Webhook certgen |

### Loki Stack Images (Phase 7)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| grafana/loki | $LOKI_VERSION | docker.io | Loki |
| grafana/promtail | $PROMTAIL_VERSION | docker.io | Promtail |
| grafana/logcli | $LOKI_VERSION | docker.io | Log CLI |
| minio/minio | latest | docker.io | Minio (S3-compatible) |
| minio/mc | latest | docker.io | Minio client |

### Velero Images (Phase 13)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| velero/velero | $VELERO_VERSION | docker.io | Velero server |
| velero/velero-plugin-for-aws | $VELERO_VERSION | docker.io | AWS plugin |
| velero/velero-plugin-for-microsoft-azure | $VELERO_VERSION | docker.io | Azure plugin |
| velero/velero-plugin-for-gcp | $VELERO_VERSION | docker.io | GCP plugin |
| velero/velero-plugin-for-csi | $VELERO_VERSION | docker.io | CSI plugin |
| velero/velero-restic-restore-helper | $VELERO_VERSION | docker.io | Restic helper |
| velero/velero-restore-helper | $VELERO_VERSION | docker.io | Restore helper |
| restic/restic | $RESTIC_VERSION | docker.io | Restic backup |
| kopia/kopia | $KOPIA_VERSION | docker.io | Kopia backup |

### Gatekeeper Images (Phase 12)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| openpolicyagent/gatekeeper | $GATEKEEPER_VERSION | docker.io | Gatekeeper |
| openpolicyagent/gatekeeper-crds | $GATEKEEPER_VERSION | docker.io | CRDs |
| openpolicyagent/gatekeeper-operator | $GATEKEEPER_VERSION | docker.io | Operator |
| openpolicyagent/opa | $OPA_VERSION | docker.io | OPA |
| openpolicyagent/kube-mgmt | $KUBEMGMT_VERSION | docker.io | Kube mgmt |

### Ceph Images (Phase 4/8)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| ceph/ceph | $CEPH_VERSION | docker.io | Ceph base |
| ceph/ceph-grafana | $CEPH_VERSION | docker.io | Ceph Grafana |
| cephcsi/cephcsi | $CEPH_CSI_VERSION | quay.io | Ceph CSI |
| cephcsi/csi-provisioner | $CSI_PROVISIONER_VERSION | k8s.gcr.io | CSI provisioner |
| cephcsi/csi-resizer | $CSI_RESIZER_VERSION | k8s.gcr.io | CSI resizer |
| cephcsi/csi-snapshotter | $CSI_SNAPSHOTTER_VERSION | k8s.gcr.io | CSI snapshotter |
| cephcsi/csi-attacher | $CSI_ATTACHER_VERSION | k8s.gcr.io | CSI attacher |
| cephcsi/csi-node-driver-registrar | $CSI_NODE_DRIVER_VERSION | k8s.gcr.io | Node driver |
| rook/rook-ceph | $ROOK_VERSION | docker.io | Rook operator |
| rook/rook-ceph-tools | $ROOK_VERSION | docker.io | Rook tools |
| rook/rook-ceph-operator | $ROOK_VERSION | docker.io | Rook operator |
| ceph/ceph | $CEPH_VERSION | docker.io | Ceph daemon |
| ceph/ceph-radosgw | $CEPH_VERSION | docker.io | Ceph RGW |

### Rook-Ceph Images (Phase 4/8)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| rook/rook-ceph | $ROOK_VERSION | docker.io | Rook operator |
| rook/rook-ceph-tools | $ROOK_VERSION | docker.io | Rook tools |
| ceph/ceph | $CEPH_VERSION | docker.io | Ceph daemon |
| ceph/ceph-mgr-dashboard | $CEPH_VERSION | docker.io | Ceph dashboard |
| ceph/ceph-exporter | $CEPH_VERSION | docker.io | Ceph exporter |
| csiaddons/k8s-sidecar | $CSIADDONS_VERSION | k8s.gcr.io | CSI addons sidecar |
| csiaddons/volumereplication-operator | $CSIADDONS_VERSION | k8s.gcr.io | Volume replication |

### Harbor Images (Phase 1)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| goharbor/harbor-core | $HARBOR_VERSION | docker.io | Harbor core |
| goharbor/harbor-portal | $HARBOR_VERSION | docker.io | Harbor portal |
| goharbor/harbor-jobservice | $HARBOR_VERSION | docker.io | Job service |
| goharbor/harbor-registryctl | $HARBOR_VERSION | docker.io | Registry control |
| goharbor/harbor-db | $HARBOR_VERSION | docker.io | Harbor DB |
| goharbor/harbor-redis | $HARBOR_VERSION | docker.io | Harbor Redis |
| goharbor/harbor-exporter | $HARBOR_VERSION | docker.io | Harbor exporter |
| goharbor/harbor-registry | $HARBOR_VERSION | docker.io | Registry |
| goharbor/harbor-trivy-adapter | $HARBOR_VERSION | docker.io | Trivy adapter |
| goharbor/harbor-chartmuseum | $HARBOR_VERSION | docker.io | Chart museum |
| goharbor/harbor-notary-server | $HARBOR_VERSION | docker.io | Notary server |
| goharbor/harbor-notary-signer | $HARBOR_VERSION | docker.io | Notary signer |
| goharbor/harbor-nginx | $HARBOR_VERSION | docker.io | Harbor nginx |
| goharbor/harbor-preheat | $HARBOR_VERSION | docker.io | Preheat |
| goharbor/harbor-registryctl | $HARBOR_VERSION | docker.io | Registryctl |
| goharbor/prepare | $HARBOR_VERSION | docker.io | Prepare |
| goharbor/redis-photon | 5.0 | docker.io | Redis |
| goharbor/postgres-photon | 14 | docker.io | PostgreSQL |
| goharbor/harbor-scanner-trivy | $TRIVY_VERSION | docker.io | Trivy scanner |
| goharbor/harbor-scanner-adapter | $TRIVY_VERSION | docker.io | Scanner adapter |

### Nexus Images (Phase 1)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| sonatype/nexus3 | $NEXUS_VERSION | docker.io | Nexus repository |
| sonatype/nexus3 | $NEXUS_VERSION | docker.io | Nexus (alt tag) |
| busybox | 1.36 | docker.io | Init container |

### Metrics Server Images (Phase 7/10)

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| metrics-server/metrics-server | $METRICS_SERVER_VERSION | k8s.gcr.io | Metrics server |
| registry.k8s.io/metrics-server/metrics-server | $METRICS_SERVER_VERSION | registry.k8s.io | Metrics server |

### Kube-State-Metrics Images

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| k8s.gcr.io/kube-state-metrics/kube-state-metrics | $KUBESTATEMETRICS_VERSION | k8s.gcr.io | K8s state metrics |
| registry.k8s.io/kube-state-metrics/kube-state-metrics | $KUBESTATEMETRICS_VERSION | registry.k8s.io | K8s state metrics |

### CSI Sidecar Images

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| k8s.gcr.io/sig-storage/csi-provisioner | $CSI_PROVISIONER_VERSION | k8s.gcr.io | CSI provisioner |
| k8s.gcr.io/sig-storage/csi-resizer | $CSI_RESIZER_VERSION | k8s.gcr.io | CSI resizer |
| k8s.gcr.io/sig-storage/csi-snapshotter | $CSI_SNAPSHOTTER_VERSION | k8s.gcr.io | CSI snapshotter |
| k8s.gcr.io/sig-storage/csi-attacher | $CSI_ATTACHER_VERSION | k8s.gcr.io | CSI attacher |
| k8s.gcr.io/sig-storage/csi-node-driver-registrar | $CSI_NODE_DRIVER_VERSION | k8s.gcr.io | Node driver registrar |
| k8s.gcr.io/sig-storage/snapshot-controller | $CSI_SNAPSHOTTER_VERSION | k8s.gcr.io | Snapshot controller |
| k8s.gcr.io/sig-storage/livenessprobe | $CSI_LIVENESSPROBE_VERSION | k8s.gcr.io | Liveness probe |
| k8s.gcr.io/sig-storage/csi-addons-replicator | $CSIADDONS_VERSION | k8s.gcr.io | CSI replication |
| k8s.gcr.io/sig-storage/csi-addons-controller | $CSIADDONS_VERSION | k8s.gcr.io | CSI addons controller |

### Additional Utility Images

| Image | Tag | Registry | Purpose |
|-------|-----|----------|---------|
| jupyterhub/k8s-image-awaiter | latest | docker.io | Image awaiter |
| kubernetesui/dashboard | $K8S_DASHBOARD_VERSION | docker.io | K8s dashboard |
| kubernetesui/metrics-scraper | latest | docker.io | Metrics scraper |
| bash | 5.2 | docker.io | Debug tool |
| nicolaka/netshoot | latest | docker.io | Network debug |
| alpine/curl | latest | docker.io | Curl debug |
| alpine/helm | $HELM_VERSION | docker.io | Helm debug |
| bitnami/kubectl | $K8S_VERSION | docker.io | kubectl debug |
| alpine/k8s:1.27 | latest | docker.io | K8s tools |

---

## Helm Charts

### Core Platform Charts

| Chart | Version | Repository | Purpose |
|-------|---------|------------|---------|
| rancher | $RANCHER_VERSION | https://releases.rancher.com/server-charts/stable | Multi-cluster management |
| argo-cd | $ARGOCD_VERSION | https://argoproj.github.io/argo-helm | GitOps CD |
| cert-manager | $CERTMANAGER_VERSION | https://charts.jetstack.io | TLS certificates |
| gatekeeper | $GATEKEEPER_VERSION | https://open-policy-agent.github.io/gatekeeper/charts | Policy enforcement |
| ingress-nginx | $NGINX_INGRESS_VERSION | https://kubernetes.github.io/ingress-nginx | Ingress controller |
| metallb | $METALLB_VERSION | https://metallb.github.io/metallb | Bare-metal LB |
| metrics-server | $METRICS_SERVER_VERSION | https://kubernetes-sigs.github.io/metrics-server | Metrics API |

### Monitoring Charts

| Chart | Version | Repository | Purpose |
|-------|---------|------------|---------|
| kube-prometheus-stack | $PROMETHEUS_STACK_VERSION | https://prometheus-community.github.io/helm-charts | Full monitoring |
| prometheus | $PROMETHEUS_CHART_VERSION | https://prometheus-community.github.io/helm-charts | Prometheus |
| grafana | $GRAFANA_CHART_VERSION | https://grafana.github.io/helm-charts | Grafana |
| loki-stack | $LOKI_STACK_VERSION | https://grafana.github.io/helm-charts | Loki + Promtail |
| loki | $LOKI_CHART_VERSION | https://grafana.github.io/helm-charts | Loki |
| promtail | $PROMTAIL_CHART_VERSION | https://grafana.github.io/helm-charts | Promtail |
| alertmanager | $ALERTMANAGER_CHART_VERSION | https://prometheus-community.github.io/helm-charts | Alertmanager |
| prometheus-operator | $PROMETHEUS_OPERATOR_VERSION | https://prometheus-community.github.io/helm-charts | Operator |
| prometheus-adapter | $PROMETHEUS_ADAPTER_VERSION | https://prometheus-community.github.io/helm-charts | Custom metrics |
| node-exporter | $NODE_EXPORTER_CHART_VERSION | https://prometheus-community.github.io/helm-charts | Node metrics |
| kube-state-metrics | $KUBESTATEMETRICS_CHART_VERSION | https://prometheus-community.github.io/helm-charts | K8s metrics |

### Storage Charts

| Chart | Version | Repository | Purpose |
|-------|---------|------------|---------|
| rook-ceph | $ROOK_VERSION | https://charts.rook.io/release | Ceph operator |
| rook-ceph-cluster | $ROOK_VERSION | https://charts.rook.io/release | Ceph cluster |
| ceph-csi-rbd | $CEPH_CSI_CHART_VERSION | https://ceph.github.io/charts | RBD CSI |
| ceph-csi-cephfs | $CEPH_CSI_CHART_VERSION | https://ceph.github.io/charts | CephFS CSI |
| ceph-provisioner | $CEPH_PROVISIONER_VERSION | https://charts.helm.sh/stable | Ceph provisioner |
| nfs-server-provisioner | $NFS_PROVISIONER_VERSION | https://charts.helm.sh/stable | NFS provisioner |
| nfs-subdir-external-provisioner | $NFS_SUBDIR_VERSION | https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner | NFS subdir |

### Backup Charts

| Chart | Version | Repository | Purpose |
|-------|---------|------------|---------|
| velero | $VELERO_CHART_VERSION | https://vmware-tanzu.github.io/helm-charts | Backup/restore |
| restic | $RESTIC_CHART_VERSION | https://charts.helm.sh/stable | Restic backup |

### Security Charts

| Chart | Version | Repository | Purpose |
|-------|---------|------------|---------|
| falco | $FALCO_VERSION | https://falcosecurity.github.io/charts | Runtime security |
| trivy-operator | $TRIVY_OPERATOR_VERSION | https://aquasecurity.github.io/trivy-operator | Vulnerability scanning |
| opa-kube-manager | $OPA_VERSION | https://open-policy-agent.github.io/opa-helm-charts | OPA manager |
| secrets-store-csi-driver | $SECRETS_STORE_VERSION | https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts | Secrets management |

### Networking Charts

| Chart | Version | Repository | Purpose |
|-------|---------|------------|---------|
| calico | $CALICO_CHART_VERSION | https://docs.tigera.io/calico/charts | Calico CNI |
| calico-operator | $CALICO_CHART_VERSION | https://docs.tigera.io/calico/charts | Calico operator |

### Additional Charts

| Chart | Version | Repository | Purpose |
|-------|---------|------------|---------|
| external-dns | $EXTERNALDNS_VERSION | https://kubernetes-sigs.github.io/external-dns | External DNS |
| cluster-autoscaler | $CLUSTER_AUTOSCALER_VERSION | https://kubernetes.github.io/autoscaler | Auto-scaling |
| kubernetes-dashboard | $K8S_DASHBOARD_VERSION | https://kubernetes.github.io/dashboard | Web dashboard |
| harbor | $HARBOR_CHART_VERSION | https://goharbor.io/helm-chart | Container registry |
| nexus-repository-manager | $NEXUS_CHART_VERSION | https://oteemo.github.io/charts | Nexus |
| keycloak | $KEYCLOAK_VERSION | https://charts.bitnami.com/bitnami | Identity provider |
| redis | $REDIS_VERSION | https://charts.bitnami.com/bitnami | Redis cache |
| postgresql | $POSTGRESQL_VERSION | https://charts.bitnami.com/bitnami | PostgreSQL |
| minio | $MINIO_VERSION | https://charts.bitnami.com/bitnami | S3-compatible storage |

---

## Ceph Packages

### Ceph Reef (v18) Apt Packages

| Package | Description |
|---------|-------------|
| ceph | Ceph base |
| ceph-common | Ceph common files |
| ceph-mds | Ceph MDS daemon |
| ceph-mgr | Ceph manager daemon |
| ceph-mgr-cephadm | Ceph manager cephadm |
| ceph-mgr-dashboard | Ceph manager dashboard |
| ceph-mgr-diskprediction-local | Disk prediction |
| ceph-mgr-k8sevents | K8s events |
| ceph-mgr-modules-core | Core modules |
| ceph-mgr-rook | Rook integration |
| ceph-mon | Ceph monitor daemon |
| ceph-osd | Ceph OSD daemon |
| ceph-radosgw | Ceph RADOS gateway |
| ceph-base | Base libraries |
| ceph-fuse | Ceph FUSE client |
| ceph-immutable-object-cache | Immutable cache |
| ceph-volume | Volume utility |
| cephadm | Ceph administration |
| cephfs-top | CephFS top |
| radosgw | RADOS gateway |
| librados2 | RADOS library |
| libradosstriper1 | RADOS striper |
| librbd1 | RBD library |
| libcephfs2 | CephFS library |
| libcephfs-jni | CephFS JNI |
| python3-rados | Python RADOS |
| python3-rbd | Python RBD |
| python3-cephfs | Python CephFS |
| python3-crush | Python crush |
| libjemalloc2 | jemalloc |
| libleveldb1d | LevelDB |
| liblttng-ust0 | LTTng |
| libbabeltrace1 | Babeltrace |

### Ceph Quincy (v17) Apt Packages

Same as Reef with version-specific differences.

---

## Nexus Repository Configuration

### Repository Definitions

```json
{
  "apt": [
    {
      "name": "ubuntu-22.04",
      "format": "apt",
      "type": "hosted",
      "url": "https://nexus.corp.internal/repository/ubuntu-22.04",
      "distribution": "jammy",
      "components": ["main", "universe", "restricted", "multiverse"],
      "architectures": ["amd64"],
      "signing": {
        "key": "<apt-signing-key>"
      }
    },
    {
      "name": "ubuntu-22.04-security",
      "format": "apt",
      "type": "hosted",
      "url": "https://nexus.corp.internal/repository/ubuntu-22.04-security",
      "distribution": "jammy",
      "components": ["main", "universe", "restricted", "multiverse"],
      "architectures": ["amd64"]
    },
    {
      "name": "ceph-reef",
      "format": "apt",
      "type": "hosted",
      "url": "https://nexus.corp.internal/repository/ceph-reef",
      "distribution": "jammy",
      "components": ["main"],
      "architectures": ["amd64"]
    },
    {
      "name": "ceph-quincy",
      "format": "apt",
      "type": "hosted",
      "url": "https://nexus.corp.internal/repository/ceph-quincy",
      "distribution": "jammy",
      "components": ["main"],
      "architectures": ["amd64"]
    }
  ],
  "docker": [
    {
      "name": "docker-hosted",
      "format": "docker",
      "type": "hosted",
      "url": "https://nexus.corp.internal/repository/docker-hosted",
      "v1WritePolicy": "AllowOnce",
      "httpPort": 8082,
      "httpsPort": 8083
    },
    {
      "name": "k8s-gcr",
      "format": "docker",
      "type": "proxy",
      "url": "https://k8s.gcr.io",
      "remoteUrl": "https://k8s.gcr.io",
      "blobCount": 10000
    },
    {
      "name": "quay-io",
      "format": "docker",
      "type": "proxy",
      "url": "https://quay.io",
      "remoteUrl": "https://quay.io",
      "blobCount": 10000
    },
    {
      "name": "docker-hub",
      "format": "docker",
      "type": "proxy",
      "url": "https://registry-1.docker.io",
      "remoteUrl": "https://registry-1.docker.io",
      "blobCount": 10000
    },
    {
      "name": "ghcr-io",
      "format": "docker",
      "type": "proxy",
      "url": "https://ghcr.io",
      "remoteUrl": "https://ghcr.io",
      "blobCount": 10000
    },
    {
      "name": "registry-k8s-io",
      "format": "docker",
      "type": "proxy",
      "url": "https://registry.k8s.io",
      "remoteUrl": "https://registry.k8s.io",
      "blobCount": 10000
    }
  ],
  "helm": [
    {
      "name": "helm-charts",
      "format": "helm",
      "type": "hosted",
      "url": "https://nexus.corp.internal/repository/helm-charts"
    },
    {
      "name": "helm-proxy",
      "format": "helm",
      "type": "proxy",
      "url": "https://charts.helm.sh/stable",
      "remoteUrl": "https://charts.helm.sh/stable"
    }
  ],
  "pypi": [
    {
      "name": "pypi-hosted",
      "format": "pypi",
      "type": "hosted",
      "url": "https://nexus.corp.internal/repository/pypi-hosted"
    },
    {
      "name": "pypi-proxy",
      "format": "pypi",
      "type": "proxy",
      "url": "https://pypi.org",
      "remoteUrl": "https://pypi.org"
    }
  ],
  "raw": [
    {
      "name": "raw-hosted",
      "format": "raw",
      "type": "hosted",
      "url": "https://nexus.corp.internal/repository/raw-hosted"
    },
    {
      "name": "kubespray-binaries",
      "format": "raw",
      "type": "hosted",
      "url": "https://nexus.corp.internal/repository/kubespray-binaries"
    }
  ],
  "yum": [
    {
      "name": "yum-hosted",
      "format": "yum",
      "type": "hosted",
      "url": "https://nexus.corp.internal/repository/yum-hosted"
    }
  ]
}
```

### Nexus Configuration on K8s Nodes

```bash
# /etc/apt/sources.list.d/nexus.list (on each node)
deb [signed-by=/usr/share/keyrings/nexus.gpg] https://nexus.corp.internal/repository/ubuntu-22.04/ jammy main universe restricted multiverse
deb [signed-by=/usr/share/keyrings/nexus.gpg] https://nexus.corp.internal/repository/ubuntu-22.04-security/ jammy main universe restricted multiverse
deb [signed-by=/usr/share/keyrings/nexus.gpg] https://nexus.corp.internal/repository/ceph-reef/ jammy main
```

```toml
# /etc/containerd/config.toml (air-gap registry config)
[plugins."io.containerd.grpc.v1.cri".registry]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
    endpoint = ["https://nexus.corp.internal:8083"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs."docker.io".tls]
    insecure_skip_verify = false
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."k8s.gcr.io"]
    endpoint = ["https://nexus.corp.internal:8083"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs."k8s.gcr.io".tls]
    insecure_skip_verify = false
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]
    endpoint = ["https://nexus.corp.internal:8083"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io"]
    endpoint = ["https://nexus.corp.internal:8083"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."ghcr.io"]
    endpoint = ["https://nexus.corp.internal:8083"]
```

---

## Harbor Project Structure

### Projects and Repositories

| Project | Visibility | Repositories | Purpose |
|---------|-----------|-------------|---------|
| k8s | Private | 50+ | Kubernetes system images |
| ceph | Private | 15+ | Ceph storage images |
| platform | Private | 30+ | Platform tool images |
| system | Private | 20+ | OS-level tools, debugging |
| charts | Private | 15+ | Helm chart mirror |
| library | Public | 10+ | Base images (if needed) |

### Harbor Robot Accounts

| Account | Scope | Permissions |
|---------|-------|------------|
| kubespray-deploy | k8s/*, ceph/*, platform/* | pull, push, delete |
| monitoring-bot | platform/prometheus/*, platform/grafana/* | pull |
| backup-bot | system/* | pull |
| admin-service | * | pull, push, delete, read |

### Harbor Replication Rules

| Source | Destination | Trigger | Filter |
|--------|-------------|---------|--------|
| Docker Hub | Harbor/k8s | Manual | k8s.gcr.io/**/* |
| quay.io | Harbor/ceph | Manual | ceph/ceph, rook/rook-ceph |
| quay.io | Harbor/platform | Manual | quay.io/coreos/*, quay.io/jetstack/* |
| gcr.io | Harbor/k8s | Manual | gcr.io/**/* |
| registry.k8s.io | Harbor/k8s | Manual | registry.k8s.io/**/* |

---

## Complete Image List by Phase

### Phase 1: Air-Gap Infrastructure

| Image | Tag | Registry | Size |
|-------|-----|----------|------|
| sonatype/nexus3 | $NEXUS_VERSION | docker.io | 600 MB |
| goharbor/harbor-core | $HARBOR_VERSION | docker.io | 100 MB |
| goharbor/harbor-portal | $HARBOR_VERSION | docker.io | 50 MB |
| goharbor/harbor-jobservice | $HARBOR_VERSION | docker.io | 80 MB |
| goharbor/harbor-registryctl | $HARBOR_VERSION | docker.io | 30 MB |
| goharbor/harbor-db | $HARBOR_VERSION | docker.io | 100 MB |
| goharbor/harbor-redis | $HARBOR_VERSION | docker.io | 50 MB |
| goharbor/harbor-exporter | $HARBOR_VERSION | docker.io | 30 MB |
| goharbor/harbor-registry | $HARBOR_VERSION | docker.io | 30 MB |
| goharbor/harbor-trivy-adapter | $HARBOR_VERSION | docker.io | 100 MB |
| goharbor/harbor-chartmuseum | $HARBOR_VERSION | docker.io | 30 MB |
| goharbor/harbor-notary-server | $HARBOR_VERSION | docker.io | 50 MB |
| goharbor/harbor-notary-signer | $HARBOR_VERSION | docker.io | 50 MB |
| goharbor/harbor-nginx | $HARBOR_VERSION | docker.io | 50 MB |
| goharbor/harbor-preheat | $HARBOR_VERSION | docker.io | 30 MB |
| goharbor/prepare | $HARBOR_VERSION | docker.io | 30 MB |
| goharbor/redis-photon | 5.0 | docker.io | 50 MB |
| goharbor/postgres-photon | 14 | docker.io | 100 MB |
| goharbor/harbor-scanner-trivy | $TRIVY_VERSION | docker.io | 100 MB |
| goharbor/harbor-scanner-adapter | $TRIVY_VERSION | docker.io | 50 MB |
| minio/minio | latest | docker.io | 100 MB |
| minio/mc | latest | docker.io | 30 MB |

### Phase 4/8: Ceph Storage

| Image | Tag | Registry | Size |
|-------|-----|----------|------|
| ceph/ceph | $CEPH_VERSION | docker.io | 500 MB |
| ceph/ceph-grafana | $CEPH_VERSION | docker.io | 100 MB |
| cephcsi/cephcsi | $CEPH_CSI_VERSION | quay.io | 200 MB |
| cephcsi/csi-provisioner | $CSI_PROVISIONER_VERSION | k8s.gcr.io | 50 MB |
| cephcsi/csi-resizer | $CSI_RESIZER_VERSION | k8s.gcr.io | 50 MB |
| cephcsi/csi-snapshotter | $CSI_SNAPSHOTTER_VERSION | k8s.gcr.io | 50 MB |
| cephcsi/csi-attacher | $CSI_ATTACHER_VERSION | k8s.gcr.io | 50 MB |
| cephcsi/csi-node-driver-registrar | $CSI_NODE_DRIVER_VERSION | k8s.gcr.io | 30 MB |
| rook/rook-ceph | $ROOK_VERSION | docker.io | 300 MB |
| rook/rook-ceph-tools | $ROOK_VERSION | docker.io | 300 MB |
| rook/rook-ceph-operator | $ROOK_VERSION | docker.io | 300 MB |
| ceph/ceph-mgr-dashboard | $CEPH_VERSION | docker.io | 500 MB |
| ceph/ceph-exporter | $CEPH_VERSION | docker.io | 100 MB |
| csiaddons/k8s-sidecar | $CSIADDONS_VERSION | k8s.gcr.io | 50 MB |
| csiaddons/volumereplication-operator | $CSIADDONS_VERSION | k8s.gcr.io | 50 MB |

### Phase 6/9: Kubernetes Core

| Image | Tag | Registry | Size |
|-------|-----|----------|------|
| kube-apiserver | $K8S_VERSION | k8s.gcr.io | 120 MB |
| kube-controller-manager | $K8S_VERSION | k8s.gcr.io | 120 MB |
| kube-scheduler | $K8S_VERSION | k8s.gcr.io | 50 MB |
| kube-proxy | $K8S_VERSION | k8s.gcr.io | 70 MB |
| etcd | $ETCD_VERSION | k8s.gcr.io | 100 MB |
| coredns | $COREDNS_VERSION | k8s.gcr.io | 50 MB |
| pause | 3.9 | k8s.gcr.io | 682 KB |
| calico/cni | $CALICO_VERSION | docker.io | 100 MB |
| calico/node | $CALICO_VERSION | docker.io | 200 MB |
| calico/kube-controllers | $CALICO_VERSION | docker.io | 50 MB |
| calico/typha | $CALICO_VERSION | docker.io | 50 MB |
| calico/pod2daemon-flexvol | $CALICO_VERSION | docker.io | 30 MB |
| calico/apiserver | $CALICO_VERSION | docker.io | 50 MB |
| calico/ctl | $CALICO_VERSION | docker.io | 50 MB |
| metrics-server/metrics-server | $METRICS_SERVER_VERSION | k8s.gcr.io | 50 MB |
| k8s.gcr.io/kube-state-metrics/kube-state-metrics | $KUBESTATEMETRICS_VERSION | k8s.gcr.io | 50 MB |

### Phase 7: Management Services

| Image | Tag | Registry | Size |
|-------|-----|----------|------|
| rancher/rancher | $RANCHER_VERSION | docker.io | 500 MB |
| rancher/rancher-agent | $RANCHER_VERSION | docker.io | 100 MB |
| rancher/machine | $RANCHER_VERSION | docker.io | 100 MB |
| rancher/fleet | $RANCHER_VERSION | docker.io | 100 MB |
| rancher/fleet-agent | $RANCHER_VERSION | docker.io | 100 MB |
| rancher/rancher-webhook | $RANCHER_VERSION | docker.io | 50 MB |
| rancher/shell | $RANCHER_VERSION | docker.io | 50 MB |
| rancher/system-upgrade-controller | latest | docker.io | 50 MB |
| argocd | $ARGOCD_VERSION | quay.io | 200 MB |
| argoproj/argocd | $ARGOCD_VERSION | quay.io | 200 MB |
| redis | 7.0-alpine | docker.io | 30 MB |
| dexidp/dex | $DEX_VERSION | ghcr.io | 100 MB |
| cert-manager-controller | $CERTMANAGER_VERSION | quay.io | 50 MB |
| cert-manager-cainjector | $CERTMANAGER_VERSION | quay.io | 50 MB |
| cert-manager-webhook | $CERTMANAGER_VERSION | quay.io | 50 MB |
| cert-manager-acmesolver | $CERTMANAGER_VERSION | quay.io | 30 MB |
| openpolicyagent/gatekeeper | $GATEKEEPER_VERSION | docker.io | 100 MB |
| prom/prometheus | $PROMETHEUS_VERSION | docker.io | 200 MB |
| prom/alertmanager | $ALERTMANAGER_VERSION | docker.io | 100 MB |
| prom/pushgateway | $PUSHGATEWAY_VERSION | docker.io | 50 MB |
| prom/node-exporter | $NODE_EXPORTER_VERSION | docker.io | 30 MB |
| grafana/grafana | $GRAFANA_VERSION | docker.io | 200 MB |
| grafana/loki | $LOKI_VERSION | docker.io | 100 MB |
| grafana/promtail | $PROMTAIL_VERSION | docker.io | 50 MB |
| grafana/mimir | $MIMIR_VERSION | docker.io | 100 MB |
| grafana/tempo | $TEMPO_VERSION | docker.io | 100 MB |
| grafana/agent | $GRAFANA_AGENT_VERSION | docker.io | 100 MB |
| brancz/prometheus-example-app | latest | docker.io | 30 MB |
| quay.io/brancz/prometheus-operator | $PROMETHEUS_OPERATOR_VERSION | quay.io | 50 MB |
| jimmidyson/configmap-reload | latest | docker.io | 20 MB |
| quay.io/coreos/kube-state-metrics | $KUBESTATEMETRICS_VERSION | quay.io | 50 MB |
| quay.io/coreos/prometheus-config-reloader | $PROMETHEUS_OPERATOR_VERSION | quay.io | 30 MB |
| quay.io/coreos/prometheus-operator | $PROMETHEUS_OPERATOR_VERSION | quay.io | 50 MB |
| ingress-nginx/controller | $NGINX_INGRESS_VERSION | registry.k8s.io | 100 MB |
| ingress-nginx/kube-webhook-certgen | $CERTGEN_VERSION | registry.k8s.io | 30 MB |

### Phase 10: Application Services

| Image | Tag | Registry | Size |
|-------|-----|----------|------|
| metallb/controller | $METALLB_VERSION | quay.io | 50 MB |
| metallb/speaker | $METALLB_VERSION | quay.io | 50 MB |
| metallb/frr | $METALLB_VERSION | quay.io | 100 MB |
| ingress-nginx/controller | $NGINX_INGRESS_VERSION | registry.k8s.io | 100 MB |
| ingress-nginx/kube-webhook-certgen | $CERTGEN_VERSION | registry.k8s.io | 30 MB |
| cert-manager-controller | $CERTMANAGER_VERSION | quay.io | 50 MB |
| cert-manager-cainjector | $CERTMANAGER_VERSION | quay.io | 50 MB |
| cert-manager-webhook | $CERTMANAGER_VERSION | quay.io | 50 MB |
| openpolicyagent/gatekeeper | $GATEKEEPER_VERSION | docker.io | 100 MB |

### Phase 13: Backup

| Image | Tag | Registry | Size |
|-------|-----|----------|------|
| velero/velero | $VELERO_VERSION | docker.io | 200 MB |
| velero/velero-plugin-for-aws | $VELERO_VERSION | docker.io | 50 MB |
| velero/velero-plugin-for-csi | $VELERO_VERSION | docker.io | 50 MB |
| velero/velero-restore-helper | $VELERO_VERSION | docker.io | 50 MB |
| restic/restic | $RESTIC_VERSION | docker.io | 50 MB |
| kopia/kopia | $KOPIA_VERSION | docker.io | 100 MB |

---

## Complete Chart List by Component

### Monitoring Stack

| Chart | Version | Repository URL |
|-------|---------|---------------|
| kube-prometheus-stack | $PROMETHEUS_STACK_VERSION | https://prometheus-community.github.io/helm-charts |
| prometheus | $PROMETHEUS_CHART_VERSION | https://prometheus-community.github.io/helm-charts |
| grafana | $GRAFANA_CHART_VERSION | https://grafana.github.io/helm-charts |
| loki-stack | $LOKI_STACK_VERSION | https://grafana.github.io/helm-charts |
| loki | $LOKI_CHART_VERSION | https://grafana.github.io/helm-charts |
| promtail | $PROMTAIL_CHART_VERSION | https://grafana.github.io/helm-charts |
| alertmanager | $ALERTMANAGER_CHART_VERSION | https://prometheus-community.github.io/helm-charts |
| prometheus-operator | $PROMETHEUS_OPERATOR_VERSION | https://prometheus-community.github.io/helm-charts |
| prometheus-adapter | $PROMETHEUS_ADAPTER_VERSION | https://prometheus-community.github.io/helm-charts |
| node-exporter | $NODE_EXPORTER_CHART_VERSION | https://prometheus-community.github.io/helm-charts |
| kube-state-metrics | $KUBESTATEMETRICS_CHART_VERSION | https://prometheus-community.github.io/helm-charts |

### Storage Stack

| Chart | Version | Repository URL |
|-------|---------|---------------|
| rook-ceph | $ROOK_VERSION | https://charts.rook.io/release |
| rook-ceph-cluster | $ROOK_VERSION | https://charts.rook.io/release |
| ceph-csi-rbd | $CEPH_CSI_CHART_VERSION | https://ceph.github.io/charts |
| ceph-csi-cephfs | $CEPH_CSI_CHART_VERSION | https://ceph.github.io/charts |
| nfs-subdir-external-provisioner | $NFS_SUBDIR_VERSION | https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner |

### Security Stack

| Chart | Version | Repository URL |
|-------|---------|---------------|
| cert-manager | $CERTMANAGER_VERSION | https://charts.jetstack.io |
| gatekeeper | $GATEKEEPER_VERSION | https://open-policy-agent.github.io/gatekeeper/charts |
| falco | $FALCO_VERSION | https://falcosecurity.github.io/charts |
| trivy-operator | $TRIVY_OPERATOR_VERSION | https://aquasecurity.github.io/trivy-operator |
| secrets-store-csi-driver | $SECRETS_STORE_VERSION | https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts |

### Networking Stack

| Chart | Version | Repository URL |
|-------|---------|---------------|
| ingress-nginx | $NGINX_INGRESS_VERSION | https://kubernetes.github.io/ingress-nginx |
| metallb | $METALLB_VERSION | https://metallb.github.io/metallb |
| calico | $CALICO_CHART_VERSION | https://docs.tigera.io/calico/charts |
| external-dns | $EXTERNALDNS_VERSION | https://kubernetes-sigs.github.io/external-dns |

### Platform Stack

| Chart | Version | Repository URL |
|-------|---------|---------------|
| rancher | $RANCHER_VERSION | https://releases.rancher.com/server-charts/stable |
| argo-cd | $ARGOCD_VERSION | https://argoproj.github.io/argo-helm |
| metrics-server | $METRICS_SERVER_VERSION | https://kubernetes-sigs.github.io/metrics-server |
| kubernetes-dashboard | $K8S_DASHBOARD_VERSION | https://kubernetes.github.io/dashboard |
| harbor | $HARBOR_CHART_VERSION | https://goharbor.io/helm-chart |
| nexus-repository-manager | $NEXUS_CHART_VERSION | https://oteemo.github.io/charts |
| keycloak | $KEYCLOAK_VERSION | https://charts.bitnami.com/bitnami |

### Backup Stack

| Chart | Version | Repository URL |
|-------|---------|---------------|
| velero | $VELERO_CHART_VERSION | https://vmware-tanzu.github.io/helm-charts |

### Infrastructure Stack

| Chart | Version | Repository URL |
|-------|---------|---------------|
| redis | $REDIS_VERSION | https://charts.bitnami.com/bitnami |
| postgresql | $POSTGRESQL_VERSION | https://charts.bitnami.com/bitnami |
| minio | $MINIO_VERSION | https://charts.bitnami.com/bitnami |

---

## Raw Binaries and Other Artifacts

### KubeSpray Binaries

| Artifact | Version | Source | Purpose |
|----------|---------|--------|---------|
| kubespray | $KUBESPRAY_VERSION | GitHub | Deployment automation |
| kubeadm | $K8S_VERSION | apt | Cluster bootstrap |
| kubectl | $K8S_VERSION | apt | CLI |
| kubelet | $K8S_VERSION | apt | Node agent |
| etcdctl | $ETCD_VERSION | apt | etcd management |
| crictl | $CRI_TOOLS_VERSION | apt | CRI tools |
| runc | $RUNC_VERSION | apt | Container runtime |
| cni-plugins | $CNI_PLUGINS_VERSION | apt | CNI binaries |
| containerd | $CONTAINERD_VERSION | apt | Container runtime |
| cri-tools | $CRI_TOOLS_VERSION | apt | CRI testing |
| helm | $HELM_VERSION | GitHub | Package manager |
| ansible | $ANSIBLE_VERSION | pip | Config management |

### Additional Binaries

| Artifact | Version | Source | Purpose |
|----------|---------|--------|---------|
| rke2 | $RKE2_VERSION | GitHub | Lightweight K8s (alternative) |
| calicoctl | $CALICO_VERSION | GitHub | Calico CLI |
| rook-ceph | $ROOK_VERSION | GitHub | Rook CLI |
| ceph-common | $CEPH_VERSION | apt | Ceph CLI |
| s3cmd | 2.3.x | pip | S3 management |
| rclone | $RCLONE_VERSION | GitHub | File sync |
| velero | $VELERO_VERSION | GitHub | Backup CLI |
| argocd | $ARGOCD_VERSION | GitHub | ArgoCD CLI |
| trivy | $TRIVY_VERSION | GitHub | Vulnerability scanner |
| cosign | $COSIGN_VERSION | GitHub | Image signing |
| skopeo | $SKOPEO_VERSION | GitHub | Image copy |
| crane | $CRANE_VERSION | GitHub | Crane CLI |

### OS ISOs

| Artifact | Version | Purpose |
|----------|---------|---------|
| ubuntu-22.04-live-server-amd64.iso | 22.04 LTS | Server OS installation |
| ubuntu-22.04-desktop-amd64.iso | 22.04 LTS | Desktop OS (ops) |

---

## Air-Gap Transfer Procedure

### Step 1: Prepare External Workstation

```bash
# On internet-connected workstation
# Install required tools
pip install skopeo
apt install -y jq

# Create transfer directory
mkdir -p /mnt/airgap/{images,charts,packages,binaries}
```

### Step 2: Sync Container Images

```bash
# Sync images using skopeo
# Example: sync all k8s.gcr.io images
skopeo sync --src docker --dest dir \
  --scoped \
  k8s.gcr.io \
  /mnt/airgap/images/k8s

# Sync quay.io images
skopeo sync --src docker --dest dir \
  --scoped \
  quay.io \
  /mnt/airgap/images/quay

# Sync docker.io images
skopeo sync --src docker --dest dir \
  --scoped \
  docker.io \
  /mnt/airgap/images/docker
```

### Step 3: Sync Helm Charts

```bash
# Add repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add jetstack https://charts.jetstack.io
helm repo add rook https://charts.rook.io/release
helm repo add rancher https://releases.rancher.com/server-charts/stable
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add metallb https://metallb.github.io/metallb
helm repo update

# Download charts
mkdir -p /mnt/airgap/charts
cd /mnt/airgap/charts
helm pull prometheus-community/kube-prometheus-stack
helm pull grafana/grafana
helm pull grafana/loki-stack
helm pull jetstack/cert-manager
helm pull rook/rook-ceph
helm pull rancher/rancher
helm pull argo/argo-cd
helm pull ingress-nginx/ingress-nginx
helm pull metallb/metallb
```

### Step 4: Sync Apt Packages

```bash
# Create apt mirror
apt-mirror /etc/apt/mirror.list
# or use debootstrap

# Copy to transfer media
cp -r /var/spool/apt-mirror /mnt/airgap/packages/apt
```

### Step 5: Sync pip Packages

```bash
# Download pip packages
pip download -r requirements.txt \
  --dest /mnt/airgap/packages/pip \
  --platform manylinux2014_x86_64 \
  --python-version 3.10 \
  --only-binary=:all:
```

### Step 6: Transfer to Air-Gap Environment

```bash
# Mount transfer media
mount /dev/sdb1 /mnt/transfer

# Copy artifacts
cp -r /mnt/airgap/* /mnt/transfer/

# Verify checksums
cd /mnt/transfer
find . -type f -exec sha256sum {} \; > checksums.sha256
```

### Step 7: Import to Nexus and Harbor

```bash
# Import images to Harbor
skopeo sync --src dir --dest docker \
  --dest-tls-verify=false \
  /mnt/transfer/images/k8s \
  harbor.corp.internal/k8s

# Upload charts to Nexus
curl -u admin:password \
  https://nexus.corp.internal/repository/helm-charts/ \
  --upload-file chart.tgz

# Import apt packages
# (Nexus handles this via UI or API)
```

### Step 8: Verify Integrity

```bash
# Verify image count
echo "Expected images: 120"
echo "Actual images: $(ls /mnt/transfer/images/ | wc -l)"

# Verify chart count
echo "Expected charts: 25"
echo "Actual charts: $(ls /mnt/transfer/charts/*.tgz | wc -l)"

# Verify checksums
cd /mnt/transfer
sha256sum -c checksums.sha256
```

---

## Version Variables Reference

| Variable | Recommended Value | Description |
|----------|------------------|-------------|
| $K8S_VERSION | 1.28.x | Kubernetes version |
| $KUBESPRAY_VERSION | 2.24.x | KubeSpray version |
| $CEPH_VERSION | 18.2.x (Reef) | Ceph version |
| $CALICO_VERSION | 3.26.x | Calico CNI version |
| $CONTAINERD_VERSION | 1.7.x | containerd version |
| $ETCD_VERSION | 3.5.x | etcd version |
| $HELM_VERSION | 3.13.x | Helm version |
| $ANSIBLE_VERSION | 2.15.x | Ansible version |
| $RANCHER_VERSION | 2.8.x | Rancher version |
| $ARGOCD_VERSION | 2.9.x | ArgoCD version |
| $CERTMANAGER_VERSION | 1.13.x | cert-manager version |
| $GATEKEEPER_VERSION | 3.13.x | Gatekeeper version |
| $PROMETHEUS_VERSION | 2.47.x | Prometheus version |
| $GRAFANA_VERSION | 10.1.x | Grafana version |
| $LOKI_VERSION | 2.9.x | Loki version |
| $NGINX_INGRESS_VERSION | 4.8.x | NGINX Ingress version |
| $METALLB_VERSION | 0.14.x | MetalLB version |
| $VELERO_VERSION | 1.12.x | Velero version |
| $ROOK_VERSION | 1.12.x | Rook version |
| $HARBOR_VERSION | 2.9.x | Harbor version |
| $NEXUS_VERSION | 3.62.x | Nexus version |
| $ROOK_VERSION | 1.12.x | Rook version |
| $CSI_PROVISIONER_VERSION | 3.6.x | CSI provisioner |
| $CSI_RESIZER_VERSION | 1.9.x | CSI resizer |
| $CSI_SNAPSHOTTER_VERSION | 6.3.x | CSI snapshotter |
| $CSI_ATTACHER_VERSION | 4.4.x | CSI attacher |
| $CSI_NODE_DRIVER_VERSION | 2.9.x | CSI node driver |
| $CEPH_CSI_VERSION | 3.10.x | Ceph CSI |
| $METRICS_SERVER_VERSION | 0.6.x | Metrics Server |
| $KUBESTATEMETRICS_VERSION | 2.10.x | Kube State Metrics |
| $NODE_EXPORTER_VERSION | 1.6.x | Node Exporter |
| $ALERTMANAGER_VERSION | 0.26.x | Alertmanager |
| $PUSHGATEWAY_VERSION | 1.6.x | Pushgateway |
| $PROMTAIL_VERSION | 2.9.x | Promtail |
| $DEX_VERSION | 2.37.x | Dex |
| $TRIVY_VERSION | 0.47.x | Trivy |
| $RCLONE_VERSION | 1.62.x | Rclone |
| $RESTIC_VERSION | 0.16.x | Restic |
| $KOPIA_VERSION | 0.14.x | Kopia |
| $FALCO_VERSION | 3.2.x | Falco |
| $TRIVY_OPERATOR_VERSION | 0.18.x | Trivy Operator |
| $EXTERNALDNS_VERSION | 1.13.x | External DNS |
| $KEYCLOAK_VERSION | 22.x | Keycloak |
| $REDIS_VERSION | 18.x | Redis (Bitnami) |
| $POSTGRESQL_VERSION | 15.x | PostgreSQL (Bitnami) |
| $MINIO_VERSION | 13.x | Minio (Bitnami) |
| $PROMETHEUS_STACK_VERSION | 51.x | Prometheus Stack chart |
| $PROMETHEUS_OPERATOR_VERSION | 0.68.x | Prometheus Operator |
| $PROMETHEUS_ADAPTER_VERSION | 0.10.x | Prometheus Adapter |
| $LOKI_STACK_VERSION | 2.9.x | Loki Stack chart |
| $NFS_SUBDIR_VERSION | 4.0.x | NFS Subdir Provisioner |
| $SECRETS_STORE_VERSION | 1.4.x | Secrets Store CSI |
| $COSIGN_VERSION | 2.2.x | Cosign |
| $SKOPEO_VERSION | 1.14.x | Skopeo |
| $CRANE_VERSION | 0.19.x | Crane |
| $RUNC_VERSION | 1.1.x | runc |
| $CNI_PLUGINS_VERSION | 1.3.x | CNI plugins |
| $CRI_TOOLS_VERSION | 1.28.x | CRI tools |
| $K8S_DASHBOARD_VERSION | 7.8.x | K8s Dashboard |
| $IMAGE_UPDATER_VERSION | 0.12.x | ArgoCD Image Updater |
| $CSIADDONS_VERSION | 0.7.x | CSI Addons |
| $CSI_LIVENESSPROBE_VERSION | 2.11.x | Liveness Probe |
| $PROMETHEUS_ADAPTER_VERSION | 0.10.x | Prometheus Adapter |
