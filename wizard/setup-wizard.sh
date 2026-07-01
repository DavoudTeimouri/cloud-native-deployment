#!/bin/bash
# ============================================================================
# Cloud-Native Deployment Wizard
# Interactive configuration generator for air-gapped K8s clusters
# ============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="$PROJECT_ROOT/templates"
GENERATED_DIR="$PROJECT_ROOT/generated"
WIZARD_CONFIG="$GENERATED_DIR/wizard-config.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize
mkdir -p "$GENERATED_DIR"
mkdir -p "$TEMPLATE_DIR"

# Header
print_header() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║         CLOUD-NATIVE DEPLOYMENT WIZARD                                 ║"
    echo "║   Configure IPs and topology for your air-gapped Kubernetes cluster     ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Input validation
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if (( octet < 0 || octet > 255 )); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

validate_hostname() {
    local host=$1
    if [[ $host =~ ^[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9]$ ]] && [[ ${#host} -le 63 ]]; then
        return 0
    fi
    return 1
}

# Prompt functions
prompt_input() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local validate_func="$4"
    
    while true; do
        if [[ -n "$default" ]]; then
            read -rp "$prompt [$default]: " input
            input=${input:-$default}
        else
            read -rp "$prompt: " input
        fi
        
        if [[ -n "$validate_func" ]] && ! $validate_func "$input"; then
            echo -e "${RED}Invalid input. Please try again.${NC}"
            continue
        fi
        
        eval "$varname=\"\$input\""
        break
    done
}

prompt_yes_no() {
    local prompt="$1"
    local default="$2"  # y/n
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -rp "$prompt [Y/n]: " input
            input=${input:-y}
        else
            read -rp "$prompt [y/N]: " input
            input=${input:-n}
        fi
        
        case "$input" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo -e "${RED}Please answer y or n.${NC}" ;;
        esac
    done
}

prompt_number() {
    local prompt="$1"
    local default="$2"
    local min="$3"
    local max="$4"
    local varname="$5"
    
    while true; do
        if [[ -n "$default" ]]; then
            read -rp "$prompt [$default]: " input
            input=${input:-$default}
        else
            read -rp "$prompt: " input
        fi
        
        if ! [[ "$input" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Please enter a number.${NC}"
            continue
        fi
        
        if [[ -n "$min" && "$input" -lt "$min" ]] || [[ -n "$max" && "$input" -gt "$max" ]]; then
            echo -e "${RED}Please enter a number between $min and $max.${NC}"
            continue
        fi
        
        eval "$varname=\"\$input\""
        break
    done
}

prompt_ip_range() {
    local prompt="$1"
    local base_ip="$2"
    local count="$3"
    local varname="$4"
    
    IFS='.' read -r -a octets <<< "$base_ip"
    local base="${octets[0]}.${octets[1]}.${octets[2]}"
    local start=${octets[3]}
    
    echo -e "${YELLOW}Please provide $count IP(s) starting from $base.$start${NC}"
    echo -e "(Enter starting IP, or leave blank for $base.$start)"
    
    prompt_input "Starting IP" "$base.$start" START_IP validate_ip
    
    IFS='.' read -r -a start_octets <<< "$START_IP"
    local start_num=${start_octets[3]}
    
    declare -g -a "$varname"
    eval "$varname=()"
    
    for ((i=0; i<count; i++)); do
        ip="${start_octets[0]}.${start_octets[1]}.${start_octets[2]}.$((start_num + i))"
        eval "$varname+=(\"$ip\")"
    done
}

# Main wizard
main() {
    print_header
    
    echo -e "${YELLOW}=== CLUSTER TOPOLOGY ===${NC}"
    
    # Cluster identification
    prompt_input "Cluster name" "mgmt-cluster" CLUSTER_NAME
    prompt_input "Domain suffix" "internal" DOMAIN_SUFFIX
    
    echo ""
    echo -e "${YELLOW}=== MASTER NODES (ETCD & CONTROL PLANE) ===${NC}"
    prompt_number "Number of master nodes" "3" "1" "7" MASTER_COUNT
    prompt_ip_range "Master node IPs" "10.1.1.10" "$MASTER_COUNT" MASTER_IPS
    
    echo ""
    echo -e "${YELLOW}=== WORKER NODES ===${NC}"
    prompt_number "Number of worker nodes" "3" "1" "50" WORKER_COUNT
    prompt_ip_range "Worker node IPs" "10.1.2.10" "$WORKER_COUNT" WORKER_IPS
    
    echo ""
    echo -e "${YELLOW}=== EXTERNAL LOAD BALANCERS (HAProxy + keepalived) ===${NC}"
    prompt_number "Number of LB nodes" "2" "1" "4" LB_COUNT
    prompt_ip_range "Load Balancer IPs" "10.1.0.10" "$LB_COUNT" LB_IPS
    
    echo ""
    echo -e "${YELLOW}=== CEPH MONITOR NODES ===${NC}"
    prompt_number "Number of Ceph MON nodes" "3" "1" "7" MON_COUNT
    prompt_ip_range "Ceph Monitor IPs" "10.1.3.10" "$MON_COUNT" MON_IPS
    
    echo ""
    echo -e "${YELLOW}=== CEPH OSD NODES ===${NC}"
    prompt_number "Number of Ceph OSD nodes" "3" "1" "20" OSD_COUNT
    prompt_ip_range "Ceph OSD IPs" "10.1.4.10" "$OSD_COUNT" OSD_IPS
    
    echo ""
    echo -e "${YELLOW}=== OPERATIONS SERVERS ===${NC}"
    prompt_input "Linux Ops server IP" "10.1.0.50" OPS_LINUX_IP validate_ip
    prompt_input "Windows Ops server IP" "10.1.0.51" OPS_WINDOWS_IP validate_ip
    
    echo ""
    echo -e "${YELLOW}=== NETWORK CONFIGURATION ===${NC}"
    prompt_input "Kubernetes Service CIDR" "10.96.0.0/12" SERVICE_CIDR
    prompt_input "Kubernetes Pod CIDR" "10.244.0.0/16" POD_CIDR
    prompt_input "MetalLB IP Pool Start (App cluster only)" "10.2.0.200" METALLB_START validate_ip
    prompt_input "MetalLB IP Pool End (App cluster only)" "10.2.0.250" METALLB_END validate_ip
    
    echo ""
    echo -e "${YELLOW}=== STORAGE CONFIGURATION ===${NC}"
    prompt_input "CephFS Storage Class name" "cephfs" CEPHFS_SC
    prompt_input "RBD Storage Class name" "rbd" RBD_SC
    
    echo ""
    echo -e "${YELLOW}=== REGISTRY CONFIGURATION ===${NC}"
    prompt_input "Harbor registry URL" "harbor.internal" HARBOR_URL
    prompt_input "Nexus repository URL" "nexus.internal:8081" NEXUS_URL
    prompt_input "Default Python index URL" "http://$NEXUS_URL/repository/pypi-group/simple" PIP_INDEX
    
    echo ""
    echo -e "${YELLOW}=== VERSIONS (optional - leave blank for latest) ===${NC}"
    prompt_input "Kubernetes version" "" K8S_VERSION
    prompt_input "Ceph version" "" CEPH_VERSION
    prompt_input "KubeSpray version" "" KUBESPRAY_VERSION
    
    echo ""
    echo -e "${GREEN}Configuration collected! Generating files...${NC}"
    
    # Save config for reference
    cat > "$WIZARD_CONFIG" << EOF
# Wizard-generated configuration
CLUSTER_NAME: "$CLUSTER_NAME"
DOMAIN_SUFFIX: "$DOMAIN_SUFFIX"
MASTER_COUNT: $MASTER_COUNT
WORKER_COUNT: $WORKER_COUNT
LB_COUNT: $LB_COUNT
MON_COUNT: $MON_COUNT
OSD_COUNT: $OSD_COUNT
OPS_LINUX_IP: "$OPS_LINUX_IP"
OPS_WINDOWS_IP: "$OPS_WINDOWS_IP"
SERVICE_CIDR: "$SERVICE_CIDR"
POD_CIDR: "$POD_CIDR"
METALLB_START: "$METALLB_START"
METALLB_END: "$METALLB_END"
CEPHFS_SC: "$CEPHFS_SC"
RBD_SC: "$RBD_SC"
HARBOR_URL: "$HARBOR_URL"
NEXUS_URL: "$NEXUS_URL"
PIP_INDEX: "$PIP_INDEX"
K8S_VERSION: "${K8S_VERSION:-latest}"
CEPH_VERSION: "${CEPH_VERSION:-latest}"
KUBESPRAY_VERSION: "${KUBESPRAY_VERSION:-latest}"
EOF
    
    # Generate all files
    generate_inventory
    generate_group_vars
    generate_scripts
    generate_docs
    
    echo -e "${GREEN}Generation complete! Files saved to: $GENERATED_DIR${NC}"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Review generated files in $GENERATED_DIR"
    echo "  2. Copy inventory to ansible/inventory/<cluster-name>/"
    echo "  3. Run OS preparation scripts"
    echo "  4. Deploy with KubeSpray"
}

# ============================================================================
# TEMPLATE GENERATION FUNCTIONS
# ============================================================================

generate_inventory() {
    echo "Generating inventory file..."
    
    local template="$TEMPLATE_DIR/inventory-hosts.yml.j2"
    local output="$GENERATED_DIR/inventory/$CLUSTER_NAME/hosts.yml"
    
    mkdir -p "$(dirname "$output")"
    
    # If template doesn't exist, create it from default
    if [[ ! -f "$template" ]]; then
        create_default_inventory_template "$template"
    fi
    
    # Render template
    envsubst < "$template" > "$output"
    
    echo "  → $output"
}

create_default_inventory_template() {
    local template="$1"
    mkdir -p "$(dirname "$template")"
    
    cat > "$template" << 'EOF'
all:
  hosts:
    # Master Nodes
{% for i in range(master_count) %}
    master-{{ loop.index }}:
      ansible_host: {{ master_ips[i] }}
      ip: {{ master_ips[i] }}
      access_ip: {{ master_ips[i] }}
{% endfor %}
    
    # Worker Nodes
{% for i in range(worker_count) %}
    worker-{{ loop.index }}:
      ansible_host: {{ worker_ips[i] }}
      ip: {{ worker_ips[i] }}
      access_ip: {{ worker_ips[i] }}
{% endfor %}
    
    # Load Balancers
{% for i in range(lb_count) %}
    lb-{{ loop.index }}:
      ansible_host: {{ lb_ips[i] }}
      ip: {{ lb_ips[i] }}
      access_ip: {{ lb_ips[i] }}
{% endfor %}
    
    # Ceph Monitors
{% for i in range(mon_count) %}
    ceph-mon-{{ loop.index }}:
      ansible_host: {{ mon_ips[i] }}
      ip: {{ mon_ips[i] }}
      access_ip: {{ mon_ips[i] }}
{% endfor %}
    
    # Ceph OSDs
{% for i in range(osd_count) %}
    ceph-osd-{{ loop.index }}:
      ansible_host: {{ osd_ips[i] }}
      ip: {{ osd_ips[i] }}
      access_ip: {{ osd_ips[i] }}
{% endfor %}
    
    # Ops Servers
    ops-linux:
      ansible_host: {{ ops_linux_ip }}
      ip: {{ ops_linux_ip }}
      access_ip: {{ ops_linux_ip }}
    ops-windows:
      ansible_host: {{ ops_windows_ip }}
      ip: {{ ops_windows_ip }}
      access_ip: {{ ops_windows_ip }}

  children:
    kube_control_plane:
      hosts:
{% for i in range(master_count) %}
        master-{{ loop.index }}:
{% endfor %}
    
    etcd:
      hosts:
{% for i in range(master_count) %}
        etcd-{{ loop.index }}:
{% endfor %}
    
    kube_node:
      hosts:
{% for i in range(worker_count) %}
        worker-{{ loop.index }}:
{% endfor %}
    
    balancer:
      hosts:
{% for i in range(lb_count) %}
        lb-{{ loop.index }}:
{% endfor %}
    
    ceph_mon:
      hosts:
{% for i in range(mon_count) %}
        ceph-mon-{{ loop.index }}:
{% endfor %}
    
    ceph_osd:
      hosts:
{% for i in range(osd_count) %}
        ceph-osd-{{ loop.index }}:
{% endfor %}
EOF
}

generate_group_vars() {
    echo "Generating group variables..."
    
    local template="$TEMPLATE_DIR/group-vars-k8s-cluster.yml.j2"
    local output="$GENERATED_DIR/inventory/$CLUSTER_NAME/group_vars/k8s_cluster.yml"
    
    mkdir -p "$(dirname "$output")"
    
    if [[ ! -f "$template" ]]; then
        create_default_k8s_template "$template"
    fi
    
    # Export variables for envsubst
    export KUBERNETES_VERSION="${K8S_VERSION:-v1.31.4}"
    export CLUSTER_NAME="$CLUSTER_NAME"
    export SERVICE_CIDR="$SERVICE_CIDR"
    export POD_CIDR="$POD_CIDR"
    export HARBOR_URL="$HARBOR_URL"
    export NEXUS_URL="$NEXUS_URL"
    export CEPHFS_SC="$CEPHFS_SC"
    export RBD_SC="$RBD_SC"
    
    envsubst < "$template" > "$output"
    echo "  → $output"
}

create_default_k8s_template() {
    local template="$1"
    mkdir -p "$(dirname "$template")"
    
    cat > "$template" << 'EOF'
# Kubernetes Cluster Configuration
# Generated by Cloud-Native Deployment Wizard

kube_version: "{{ lookup('env', 'KUBERNETES_VERSION') | default('v1.31.4', true) }}"
cluster_name: "{{ lookup('env', 'CLUSTER_NAME') }}"

container_manager: containerd
kube_network_plugin: calico

# Calico Configuration
calico_iptables_backend: "Auto"
calico_ipip_mode: "Always"
calico_vxlan_mode: "Never"
calico_ip_autodetection_method: "interface=eth0"
calico_node_liveness_check_enabled: true

# Network Configuration
kube_pods_subnet: "{{ lookup('env', 'POD_CIDR') }}"
kube_service_addresses: "{{ lookup('env', 'SERVICE_CIDR') }}"
kube_network_node_prefix: 24

# Load Balancer (External HAProxy)
loadbalancer_apiserver:
  address: {{ lb_ips[0] }}  # First LB as primary VIP
  port: 6443

# etcd Configuration
etcd_deployment_type: host
etcd_data_dir: /var/lib/etcd

# API Server
kube_apiserver_enable_admission_plugins:
  - NodeRestriction
  - PodSecurity
  - ResourceQuota
  - ServiceAccount
  - DefaultStorageClass
  - DefaultTolerationSeconds
  - MutatingAdmissionWebhook
  - ValidatingAdmissionWebhook
  - Priority
  - NamespaceLifecycle
  - LimitRanger

# Audit Logging
kubernetes_audit: true
audit_log_path: "/var/log/kubernetes/audit.log"
audit_log_maxage: 30
audit_log_maxbackups: 10
audit_log_maxsize: 200

# Encryption at Rest
kube_encrypt_secret_data: true

# Air-Gap Configuration
registry_host: "{{ lookup('env', 'HARBOR_URL') | split(':')[0] }}"
registry_port: "{{ lookup('env', 'HARBOR_URL') | split(':')[1] | default('443', true) }}"
registry_protocol: "https"

kube_image_repo: "{{ lookup('env', 'HARBOR_URL') }}/k8s"
etcd_image_repo: "{{ lookup('env', 'HARBOR_URL') }}/k8s/etcd"
calico_image_repo: "{{ lookup('env', 'HARBOR_URL') }}/calico"
coredns_image_repo: "{{ lookup('env', 'HARBOR_URL') }}/k8s/coredns"
dnsautoscaler_image_repo: "{{ lookup('env', 'HARBOR_URL') }}/k8s/cluster-proportional-autoscaler"
metrics_server_image_repo: "{{ lookup('env', 'HARBOR_URL') }}/k8s/metrics-server"
nginx_image_repo: "{{ lookup('env', 'HARBOR_URL') }}/k8s/nginx"

containerd_registries:
  "{{ lookup('env', 'HARBOR_URL') }}":
    endpoints:
      - "https://{{ lookup('env', 'HARBOR_URL') }}"

containerd_insecure_registries:
  - "{{ lookup('env', 'HARBOR_URL') }}"

download_run_once: false
download_localhost: false

# Security
kube_security_context: true

# Node Labels
node_labels:
{% for i in range(worker_count) %}
    worker-{{ loop.index }}:
      node-role.kubernetes.io/worker: "true"
{% endfor %}

# Certificates
kube_cert_group: kube-cert-api
auto_renew_certificates: true

# Additional sysctl
additional_sysctl:
  - { name: 'net.core.somaxconn', value: '65535' }
  - { name: 'net.ipv4.tcp_max_syn_backlog', value: '65535' }
  - { name: 'vm.max_map_count', value: '262144' }

# Kubelet
kubelet_config_extra_args:
  maxPods: 110
  eventRecordQPS: 50
  eventBurst: 100
  kubeAPIQPS: 50
  kubeAPIBurst: 100
  serializeImagePulls: false

# Kube-proxy
kube_proxy_mode: iptables

# DNS
enable_nodelocaldns: true
nodelocaldns_ip: 169.254.25.10

# Metrics Server
metrics_server_enabled: true

# Upstream DNS
upstream_dns_servers:
  - 10.0.0.1
  - 10.0.0.2

searchdomains:
  - {{ cluster_name }}.{{ domain_suffix }}
  - {{ domain_suffix }}
EOF
}

generate_scripts() {
    echo "Generating customized scripts..."
    
    # OS preparation script with custom IPs/NTP/DNS
    local ostemplate="$TEMPLATE_DIR/os-prep/linux-hardening.sh.j2"
    local osoutput="$GENERATED_DIR/scripts/os-prep/linux-hardening.sh"
    
    mkdir -p "$(dirname "$osoutput")"
    
    if [[ ! -f "$ostemplate" ]]; then
        create_os_template "$ostemplate"
    fi
    
    # Export variables
    export NTP_SERVERS="10.0.0.1 10.0.0.2"
    export DNS_SERVERS="10.0.0.1 10.0.0.2"
    export SEARCH_DOMAINS="${CLUSTER_NAME}.${DOMAIN_SUFFIX} ${DOMAIN_SUFFIX}"
    
    envsubst < "$ostemplate" > "$osoutput"
    chmod +x "$osoutput"
    echo "  → $osoutput"
    
    # Generate KubeSpray wrapper script
    local kstemplate="$TEMPLATE_DIR/kubespray-deploy.sh.j2"
    local ksoutput="$GENERATED_DIR/scripts/kubespray-deploy.sh"
    
    mkdir -p "$(dirname "$ksoutput")"
    
    if [[ ! -f "$kstemplate" ]]; then
        create_kubespray_template "$kstemplate"
    fi
    
    envsubst < "$kstemplate" > "$ksoutput"
    chmod +x "$ksoutput"
    echo "  → $ksoutput"
}

create_os_template() {
    local template="$1"
    mkdir -p "$(dirname "$template")"
    
    cat > "$template" << 'EOF'
#!/bin/bash
# OS Preparation Script - Generated by Wizard
# Customized for: {{ cluster_name }}
# NTP Servers: {{ env.NTP_SERVERS }}
# DNS Servers: {{ env.DNS_SERVERS }}
# Search Domains: {{ env.SEARCH_DOMAINS }}

set -euo pipefail

# Variables from wizard
NTP_SERVERS=(${NTP_SERVERS[@]})
DNS_SERVERS=(${DNS_SERVERS[@]})
SEARCH_DOMAINS=(${SEARCH_DOMAINS[@]})

# ... rest of script uses these arrays ...
# (Full script would use these variables in configuration sections)
EOF
}

create_kubespray_template() {
    local template="$1"
    mkdir -p "$(dirname "$template")"
    
    cat > "$template" << 'EOF'
#!/bin/bash
# KubeSpray Deployment Wrapper - Generated by Wizard

set -euo pipefail

CLUSTER_NAME="{{ cluster_name }}"
INVENTORY_DIR="generated/inventory/$CLUSTER_NAME"
KUBESPRAY_PATH="../kubespray"  # Adjust as needed

echo "Deploying cluster: $CLUSTER_NAME"
echo "Using inventory: $INVENTORY_DIR"

# Pre-flight checks
ansible -i "$INVENTORY_DIR/hosts.yml" all -m ping

# Run deployment
ansible-playbook -i "$INVENTORY_DIR/hosts.yml" "$KUBESPRAY_PATH/cluster.yml"

echo "Deployment complete!"
echo "Kubeconfig available at: ~/.kube/config"
EOF
}

generate_docs() {
    echo "Generating customized documentation..."
    
    # Generate network diagram with actual IPs
    local netdiag="$TEMPLATE_DIR/docs/architecture/network-diagram.md.j2"
    local netout="$GENERATED_DIR/docs/architecture/network-diagram.md"
    
    mkdir -p "$(dirname "$netout")"
    
    if [[ ! -f "$netdiag" ]]; then
        create_network_diagram_template "$netdiag"
    fi
    
    envsubst < "$netdiag" > "$netout"
    echo "  → $netout"
    
    # Generate repository list with actual URLs
    local rasch="$TEMPLATE_DIR/docs/prerequisites/repository-list.md.j2"
    local rasout="$GENERATED_DIR/docs/prerequisites/repository-list.md"
    
    mkdir -p "$(dirname "$rasout")"
    
    if [[ ! -f "$rasch" ]]; then
        create_repo_template "$rasch"
    fi
    
    envsubst < "$rasch" > "$rasout"
    echo "  → $rasout"
}

create_network_diagram_template() {
    local template="$1"
    mkdir -p "$(dirname "$template")"
    
    cat > "$template" << 'EOF'
# Network Diagram - Customized for {{ cluster_name }}

```
IP ADDRESSING SCHEME
===================

# Management Cluster
Master Nodes:
{% for ip in master_ips %}- {{ ip }}{% endfor %}

Worker Nodes:
{% for ip in worker_ips %}- {{ ip }}{% endfor %}

Load Balancers (HAProxy + keepalived):
{% for ip in lb_ips %}- {{ ip }} (VIP: {{ lb_ips[0] }} for API){% endfor %}

Ceph Monitor Nodes:
{% for ip in mon_ips %}- {{ ip }}{% endfor %}

Ceph OSD Nodes:
{% for ip in osd_ips %}- {{ ip }}{% endfor %}

Ops Servers:
- Linux: {{ ops_linux_ip }}
- Windows: {{ ops_windows_ip }}

Networks:
- Node Network: 10.1.0.0/16
- Service CIDR: {{ service_cidr }}
- Pod CIDR: {{ pod_cidr }}
- MetalLB Pool: {{ metallb_start }}-{{ metallb_end }} (Application cluster only)
```

EOF
}

create_repo_template() {
    local template="$1"
    mkdir -p "$(dirname "$template")"
    
    cat > "$template" << 'EOF'
# Repository and Registry List - Customized

## Container Registries
- Harbor: https://{{ harbor_url }}/
  - Projects: k8s-images, ceph-images, monitoring-images, platform-images, os-images

## Package Repositories (Nexus)
- APT (Ubuntu 22.04): http://{{ nexus_url }}/repository/apt-ubuntu-hosted/
  - Components: main, universe, restricted, multiverse
- PyPI: {{ pip_index }}
- Helm (raw): http://{{ nexus_url }}/repository/helm-hosted/
- YUM/Ceph: http://{{ nexus_url }}/repository/yum-hosted-ceph/

## Git Repositories
- GitLab: http://gitlab.internal/
  - Infrastructure: k8s-manifests, helm-values, ansible-playbooks, scripts
  - Applications: [your-projects]

EOF
}

# Execute main function
main "$@"
EOF