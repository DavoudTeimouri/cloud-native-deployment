#!/usr/bin/env bash
#
# deploy-ceph.sh - Bare-Metal Ceph Deployment Script (cephadm-based)
#
# This script automates the deployment of a Ceph Reef cluster using cephadm
# on Ubuntu 22.04 nodes in an air-gapped environment.
#
# Usage:
#   sudo ./deploy-ceph.sh [OPTIONS]
#
# Prerequisites:
#   - All nodes running Ubuntu 22.04 LTS
#   - SSH key-based authentication configured
#   - NTP synchronized across all nodes
#   - DNS resolution working (forward and reverse)
#   - Nexus apt repository configured for Ceph packages
#   - All Ceph packages installed on all nodes
#
# Air-Gap Notes:
#   - All packages must be available from internal Nexus repository
#   - No internet access required during deployment
#   - Container images must be pre-loaded or available from Harbor
#

set -euo pipefail

#=============================================================================
# CONFIGURATION VARIABLES
# Modify these for your environment
#=============================================================================

# Ceph version (Reef)
CEPH_VERSION="${CEPH_VERSION:-18.2.1}"

# Node definitions
MON_NODES="${MON_NODES:-mon01 mon02 mon03 mon04 mon05}"
OSD_NODES="${OSD_NODES:-osd01 osd02 osd03 osd04 osd05}"
MGR_NODES="${MGR_NODES:-mon01 mon02}"

# Network configuration
PUBLIC_NETWORK="${PUBLIC_NETWORK:-10.1.1.0/24}"
CLUSTER_NETWORK="${CLUSTER_NETWORK:-10.1.2.0/24}"
MON_IP="${MON_IP:-10.1.1.11}"  # First MON node IP

# OSD configuration
OSD_DEVICES="${OSD_DEVICES:-/dev/sdb /dev/sdc /dev/sdd}"
WAL_DEVICE="${WAL_DEVICE:-/dev/nvme0n1}"
OSD_ENCRYPTED="${OSD_ENCRYPTED:-true}"

# Pool configuration
CEPHFS_PG_NUM="${CEPHFS_PG_NUM:-2048}"
CEPHFS_METADATA_PG_NUM="${CEPHFS_METADATA_PG_NUM:-64}"
RBD_PG_NUM="${RBD_PG_NUM:-512}"
POOL_SIZE="${POOL_SIZE:-3}"
POOL_MIN_SIZE="${POOL_MIN_SIZE:-2}"

# Dashboard
DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD:-$(openssl rand -base64 16)}"
DASHBOARD_PORT="${DASHBOARD_PORT:-8443}"

# RGW configuration
RGW_REALM="${RGW_REALM:-myrealm}"
RGW_ZONEGROUP="${RGW_ZONEGROUP:-myzone}"
RGW_ZONE="${RGW_ZONE:-myzone}"
RGW_PLACEMENT="${RGW_PLACEMENT:-2 mon01 mon02}"

# CSI user
CSI_CEPHFS_USER="${CSI_CEPHFS_USER:-csi-cephfs}"
CSI_RBD_USER="${CSI_RBD_USER:-csi-rbd}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/ceph-deploy-$(date +%Y%m%d-%H%M%S).log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Air-gap configuration
NEXUS_REPO="${NEXUS_REPO:-https://nexus.internal/repository/ceph-reef}"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-harbor.internal}"

# CRUSH map
CRUSH_RACK_PREFIX="${CRUSH_RACK_PREFIX:-rack}"

#=============================================================================
# COLOR OUTPUT
#=============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#=============================================================================
# LOGGING FUNCTIONS
#=============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
    
    case "$level" in
        INFO)    echo -e "${GREEN}[INFO]${NC} ${message}" ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC} ${message}" ;;
        ERROR)   echo -e "${RED}[ERROR]${NC} ${message}" ;;
        DEBUG)   [[ "$LOG_LEVEL" == "DEBUG" ]] && echo -e "${BLUE}[DEBUG]${NC} ${message}" ;;
    esac
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { log "DEBUG" "$@"; }

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local required_commands=("cephadm" "ceph-common" "ceph" "ssh" "ping" "dig")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            log_error "Install Ceph packages from Nexus: $NEXUS_REPO"
            exit 1
        fi
    done
    
    # Check SSH agent
    if ! ssh-add -l &>/dev/null; then
        log_warn "No SSH agent keys found. Ensure SSH keys are configured."
    fi
    
    # Check NTP synchronization
    if command -v chronyc &>/dev/null; then
        local tracking
        tracking=$(chronyc tracking 2>/dev/null | grep "System time" || true)
        if [[ -n "$tracking" ]]; then
            log_info "NTP status: $tracking"
        fi
    fi
    
    log_info "Prerequisites check passed"
}

wait_for_healthy() {
    local timeout="${1:-300}"
    local interval="${2:-10}"
    local elapsed=0
    
    log_info "Waiting for cluster to become healthy (timeout: ${timeout}s)..."
    
    while [[ $elapsed -lt $timeout ]]; do
        local health
        health=$(ceph -s --format json 2>/dev/null | jq -r '.health.status' 2>/dev/null || echo "unknown")
        
        if [[ "$health" == "HEALTH_OK" ]]; then
            log_info "Cluster is healthy!"
            return 0
        fi
        
        log_info "Cluster health: $health (waiting... ${elapsed}/${timeout}s)"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    log_error "Timeout waiting for cluster health"
    return 1
}

ssh_cmd() {
    local node="$1"
    shift
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$node" "$@"
}

ssh_cmd_parallel() {
    local results=()
    local pids=()
    
    for node in $MON_NODES $OSD_NODES; do
        (
            ssh_cmd "$node" "$@" > "/tmp/ssh-${node}-$$.log" 2>&1
        ) &
        pids+=("$!:$node")
    done
    
    for pid_node in "${pids[@]}"; do
        local pid="${pid_node%%:*}"
        local node="${pid_node##*:}"
        wait "$pid" || log_warn "Command failed on $node"
        log_debug "Output from $node: $(cat /tmp/ssh-${node}-$$.log)"
        rm -f "/tmp/ssh-${node}-$$.log"
    done
}

#=============================================================================
# DEPLOYMENT PHASES
#=============================================================================

phase1_bootstrap() {
    log_info "========================================="
    log_info "PHASE 1: Bootstrap first MON node"
    log_info "========================================="
    
    local first_mon
    first_mon=$(echo "$MON_NODES" | awk '{print $1}')
    
    log_info "Bootstrapping Ceph cluster on $first_mon (IP: $MON_IP)"
    
    # Check if already bootstrapped
    if [[ -f /etc/ceph/ceph.conf ]] && [[ -f /etc/ceph/ceph.client.admin.keyring ]]; then
        log_warn "Ceph appears to be already bootstrapped. Skipping bootstrap."
        return 0
    fi
    
    # Bootstrap
    cephadm bootstrap \
        --mon-ip "$MON_IP" \
        --cluster-network "$CLUSTER_NETWORK" \
        --allow-fqdn-hostname \
        --dashboard-password-noupdate \
        --output-keyring /etc/ceph/ceph.client.admin.keyring \
        --output-config /etc/ceph/ceph.conf \
        --initial-dashboard-password "$DASHBOARD_PASSWORD" \
        --ssh-private-key /root/.ssh/id_ed25519 \
        --ssh-public-key /root/.ssh/id_ed25519.pub \
        2>&1 | tee -a "$LOG_FILE"
    
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "Bootstrap failed!"
        exit 1
    fi
    
    log_info "Bootstrap completed successfully"
    log_info "Dashboard password: $DASHBOARD_PASSWORD"
    
    # Verify
    ceph -s
    ceph health detail
}

phase2_add_mons() {
    log_info "========================================="
    log_info "PHASE 2: Add remaining MON nodes"
    log_info "========================================="
    
    local first_mon
    first_mon=$(echo "$MON_NODES" | awk '{print $1}')
    local remaining_mons
    remaining_mons=$(echo "$MON_NODES" | cut -d' ' -f2-)
    
    # Copy SSH keys to remaining MONs
    for mon in $remaining_mons; do
        log_info "Copying SSH key to $mon"
        ssh-copy-id -f -i /etc/ceph/ceph.pub "$mon" 2>/dev/null || true
    done
    
    # Add hosts
    for mon in $remaining_mons; do
        log_info "Adding host: $mon"
        local mon_ip
        mon_ip=$(dig +short "$mon" | head -1)
        ceph orch host add "$mon" "$mon_ip" 2>/dev/null || log_warn "Host $mon may already exist"
    done
    
    # Deploy MONs
    local mon_count
    mon_count=$(echo "$MON_NODES" | wc -w)
    ceph orch apply mon --unmanaged 2>/dev/null || true
    ceph orch apply mon "$mon_count" 2>&1 | tee -a "$LOG_FILE"
    
    # Wait for quorum
    log_info "Waiting for MON quorum..."
    local timeout=300
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local quorum
        quorum=$(ceph mon stat 2>/dev/null | grep -c "mon\." || echo "0")
        if [[ "$quorum" -ge "$mon_count" ]]; then
            log_info "All $mon_count MONs are in quorum"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    # Verify
    ceph mon stat
    ceph quorum_status
    
    log_info "MON deployment complete"
}

phase3_deploy_mgrs() {
    log_info "========================================="
    log_info "PHASE 3: Deploy MGR daemons"
    log_info "========================================="
    
    local mgr_count
    mgr_count=$(echo "$MGR_NODES" | wc -w)
    
    ceph orch apply mgr --placement="$mgr_count $MGR_NODES" 2>&1 | tee -a "$LOG_FILE"
    
    # Wait for active MGR
    sleep 10
    ceph mgr stat
    
    # Enable modules
    ceph mgr module enable dashboard 2>/dev/null || true
    ceph mgr module enable prometheus 2>/dev/null || true
    ceph mgr module enable balancer 2>/dev/null || true
    
    log_info "MGR deployment complete"
}

phase4_add_osd_hosts() {
    log_info "========================================="
    log_info "PHASE 4: Add OSD hosts"
    log_info "========================================="
    
    for osd in $OSD_NODES; do
        log_info "Adding OSD host: $osd"
        local osd_ip
        osd_ip=$(dig +short "$osd" | head -1)
        
        # Copy SSH key
        ssh-copy-id -f -i /etc/ceph/ceph.pub "$osd" 2>/dev/null || true
        
        # Add host with cluster network
        local cluster_ip
        cluster_ip=$(ssh_cmd "$osd" "hostname -I | awk '{print \$2}'" 2>/dev/null || echo "")
        if [[ -n "$cluster_ip" ]]; then
            ceph orch host add "$osd" "$osd_ip" "$cluster_ip" 2>/dev/null || log_warn "Host $osd may already exist"
        else
            ceph orch host add "$osd" "$osd_ip" 2>/dev/null || log_warn "Host $osd may already exist"
        fi
    done
    
    # Verify hosts
    ceph orch host ls
    
    log_info "OSD hosts added"
}

phase5_deploy_osds() {
    log_info "========================================="
    log_info "PHASE 5: Deploy OSDs with BlueStore"
    log_info "========================================="
    
    # Create OSD service specification
    local osd_spec="/tmp/ceph-osd-spec.yaml"
    cat > "$osd_spec" <<OSDSPEC
service_type: osd
service_id: all-ossd
placement:
  host_pattern: 'osd*'
spec:
  data_devices:
    all: true
  db_devices:
    paths:
      - ${WAL_DEVICE}
  encrypted: ${OSD_ENCRYPTED}
OSDSPEC
    
    log_info "Applying OSD specification..."
    ceph orch apply -i "$osd_spec" 2>&1 | tee -a "$LOG_FILE"
    
    # Wait for OSDs
    log_info "Waiting for OSDs to be deployed..."
    local total_osd_nodes
    total_osd_nodes=$(echo "$OSD_NODES" | wc -w)
    local expected_osds=$((total_osd_nodes * $(echo "$OSD_DEVICES" | wc -w)))
    
    local timeout=600
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local osd_count
        osd_count=$(ceph osd stat 2>/dev/null | grep -oP '\d+(?= osds)' || echo "0")
        if [[ "$osd_count" -ge "$expected_osds" ]]; then
            log_info "All $osd_count OSDs are up"
            break
        fi
        log_info "OSDs: $osd_count / $expected_osds (waiting...)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    # Verify
    ceph osd tree
    ceph osd df
    
    log_info "OSD deployment complete"
}

phase6_create_pools() {
    log_info "========================================="
    log_info "PHASE 6: Create storage pools"
    log_info "========================================="
    
    # CephFS metadata pool
    log_info "Creating CephFS metadata pool..."
    ceph osd pool create cephfs_metadata "$CEPHFS_METADATA_PG_NUM" "$CEPHFS_METADATA_PG_NUM" replicated 2>/dev/null || \
        log_warn "Pool cephfs_metadata may already exist"
    ceph osd pool set cephfs_metadata size "$POOL_SIZE"
    ceph osd pool set cephfs_metadata min_size "$POOL_MIN_SIZE"
    ceph osd pool application enable cephfs_metadata cephfs 2>/dev/null || true
    
    # CephFS data pool
    log_info "Creating CephFS data pool..."
    ceph osd pool create cephfs_data "$CEPHFS_PG_NUM" "$CEPHFS_PG_NUM" replicated 2>/dev/null || \
        log_warn "Pool cephfs_data may already exist"
    ceph osd pool set cephfs_data size "$POOL_SIZE"
    ceph osd pool set cephfs_data min_size "$POOL_MIN_SIZE"
    ceph osd pool application enable cephfs_data cephfs 2>/dev/null || true
    
    # RBD pool
    log_info "Creating RBD pool..."
    ceph osd pool create k8s-rbd "$RBD_PG_NUM" "$RBD_PG_NUM" replicated 2>/dev/null || \
        log_warn "Pool k8s-rbd may already exist"
    ceph osd pool set k8s-rbd size "$POOL_SIZE"
    ceph osd pool set k8s-rbd min_size "$POOL_MIN_SIZE"
    ceph osd pool application enable k8s-rbd rbd 2>/dev/null || true
    rbd pool init k8s-rbd 2>/dev/null || true
    
    # Verify pools
    ceph osd pool ls detail
    ceph osd pool stats
    
    log_info "Pool creation complete"
}

phase7_create_cephfs() {
    log_info "========================================="
    log_info "PHASE 7: Create CephFS"
    log_info "========================================="
    
    # Check if CephFS already exists
    if ceph fs ls 2>/dev/null | grep -q "cephfs"; then
        log_warn "CephFS already exists. Skipping creation."
        return 0
    fi
    
    # Deploy MDS
    local mds_count=2
    ceph orch apply mds cephfs --placement="$mds_count $MGR_NODES" 2>&1 | tee -a "$LOG_FILE"
    
    # Wait for MDS
    sleep 15
    
    # Create filesystem
    ceph fs new cephfs cephfs_metadata cephfs_data 2>&1 | tee -a "$LOG_FILE"
    
    # Verify
    ceph fs status cephfs
    ceph mds stat
    
    log_info "CephFS creation complete"
}

phase8_deploy_rgw() {
    log_info "========================================="
    log_info "PHASE 8: Deploy RGW"
    log_info "========================================="
    
    # Deploy RGW
    ceph orch apply rgw "$RGW_REALM" "$RGW_ZONE" --placement="$RGW_PLACEMENT" 2>&1 | tee -a "$LOG_FILE"
    
    # Configure RGW
    ceph config set client.rgw."${RGW_REALM}.${RGW_ZONE}" rgw_frontends "civetweb port=8080" 2>/dev/null || true
    
    # Wait for RGW
    sleep 10
    
    # Verify
    ceph orch ps --daemon_type rgw
    
    log_info "RGW deployment complete"
}

phase9_tune_crush() {
    log_info "========================================="
    log_info "PHASE 9: CRUSH map tuning"
    log_info "========================================="
    
    # Create CRUSH hierarchy
    local mon_array=($MON_NODES)
    local osd_array=($OSD_NODES)
    
    # Create racks
    local rack_a="${CRUSH_RACK_PREFIX}-a"
    local rack_b="${CRUSH_RACK_PREFIX}-b"
    local rack_c="${CRUSH_RACK_PREFIX}-c"
    
    ceph osd crush add-bucket "$rack_a" rack 2>/dev/null || true
    ceph osd crush add-bucket "$rack_b" rack 2>/dev/null || true
    ceph osd crush add-bucket "$rack_c" rack 2>/dev/null || true
    
    # Distribute OSDs across racks
    for i in "${!osd_array[@]}"; do
        local osd="${osd_array[$i]}"
        local rack
        case $((i % 3)) in
            0) rack="$rack_a" ;;
            1) rack="$rack_b" ;;
            2) rack="$rack_c" ;;
        esac
        ceph osd crush move "$osd" rack="$rack" 2>/dev/null || true
    done
    
    # Create rack-aware CRUSH rule
    ceph osd crush rule create-replicated rack-aware default rack 2>/dev/null || true
    
    # Apply to pools
    for pool in cephfs_metadata cephfs_data k8s-rbd; do
        ceph osd pool set "$pool" crush_rule rack-aware 2>/dev/null || true
    done
    
    # Verify
    ceph osd crush tree
    
    log_info "CRUSH map tuning complete"
}

phase10_configure_dashboard() {
    log_info "========================================="
    log_info "PHASE 10: Configure Dashboard"
    log_info "========================================="
    
    # Enable dashboard
    ceph mgr module enable dashboard 2>/dev/null || true
    
    # Create self-signed cert
    ceph dashboard create-self-signed-cert 2>/dev/null || true
    
    # Set port
    ceph config set mgr mgr/dashboard/server_port "$DASHBOARD_PORT" 2>/dev/null || true
    
    # Set credentials
    ceph dashboard set-login-credentials admin "$DASHBOARD_PASSWORD" 2>/dev/null || true
    
    # Restart
    ceph mgr restart 2>/dev/null || true
    
    log_info "Dashboard configured at https://${MON_IP}:${DASHBOARD_PORT}"
    log_info "Username: admin"
    log_info "Password: $DASHBOARD_PASSWORD"
    
    log_info "Dashboard configuration complete"
}

phase11_create_csi_user() {
    log_info "========================================="
    log_info "PHASE 11: Create K8s CSI user"
    log_info "========================================="
    
    # Create CephFS CSI user
    log_info "Creating CephFS CSI user: $CSI_CEPHFS_USER"
    ceph auth get-or-create client."$CSI_CEPHFS_USER" \
        mon 'allow r, allow command "osd blacklist"' \
        osd 'allow rw pool=cephfs_metadata, allow rw pool=cephfs_data' \
        mds 'allow rw, allow' \
        mgr 'allow r' \
        2>/dev/null || log_warn "CSI CephFS user may already exist"
    
    # Create RBD CSI user
    log_info "Creating RBD CSI user: $CSI_RBD_USER"
    ceph auth get-or-create client."$CSI_RBD_USER" \
        mon 'allow r, allow command "osd blacklist"' \
        osd 'allow rw pool=k8s-rbd' \
        mgr 'allow r' \
        2>/dev/null || log_warn "CSI RBD user may already exist"
    
    # Export keys
    local cephfs_key
    cephfs_key=$(ceph auth get-key client."$CSI_CEPHFS_USER" 2>/dev/null || echo "")
    local rbd_key
    rbd_key=$(ceph auth get-key client."$CSI_RBD_USER" 2>/dev/null || echo "")
    local fsid
    fsid=$(ceph fsid 2>/dev/null || echo "")
    
    # Generate CSI config
    local csi_config="/etc/ceph/csi-config.yaml"
    cat > "$csi_config" <<CISOCONFIG
---
ceph_cluster:
  fsid: "${fsid}"
  monitors:
$(for mon in $MON_NODES; do
    local mon_ip
    mon_ip=$(dig +short "$mon" | head -1)
    echo "    - ${mon_ip}:6789"
done)

csi_cephfs:
  user: ${CSI_CEPHFS_USER}
  key: ${cephfs_key}

csi_rbd:
  user: ${CSI_RBD_USER}
  key: ${rbd_key}
CISOCONFIG
    
    log_info "CSI config written to $csi_config"
    log_info "CephFS CSI Key: $cephfs_key"
    log_info "RBD CSI Key: $rbd_key"
    log_info "Cluster FSID: $fsid"
    
    log_info "CSI user creation complete"
}

phase12_performance_tuning() {
    log_info "========================================="
    log_info "PHASE 12: Performance tuning"
    log_info "========================================="
    
    # BlueStore cache
    ceph config set osd bluestore_cache_size_ssd 4294967296 2>/dev/null || true
    ceph config set osd bluestore_cache_size_hbd 1073741824 2>/dev/null || true
    ceph config set osd bluestore_cache_meta_ratio 0.5 2>/dev/null || true
    ceph config set osd bluestore_cache_kv_ratio 0.3 2>/dev/null || true
    
    # OSD settings
    ceph config set osd osd_op_threads 8 2>/dev/null || true
    ceph config set osd osd_recovery_max_active 3 2>/dev/null || true
    ceph config set osd osd_recovery_sleep 0.5 2>/dev/null || true
    ceph config set osd osd_max_backfills 2 2>/dev/null || true
    
    # Scrubbing
    ceph config set osd osd_scrub_begin_hour 22 2>/dev/null || true
    ceph config set osd osd_scrub_end_hour 6 2>/dev/null || true
    ceph config set osd osd_scrub_sleep 0.1 2>/dev/null || true
    
    # PG autoscaler
    ceph config set global osd_pg_autoscale_mode on 2>/dev/null || true
    
    log_info "Performance tuning complete"
}

phase13_health_check() {
    log_info "========================================="
    log_info "PHASE 13: Health verification"
    log_info "========================================="
    
    echo ""
    echo "========================================="
    echo "DEPLOYMENT SUMMARY"
    echo "========================================="
    echo ""
    
    echo "--- Cluster Status ---"
    ceph -s
    
    echo ""
    echo "--- MON Status ---"
    ceph mon stat
    
    echo ""
    echo "--- MGR Status ---"
    ceph mgr stat
    
    echo ""
    echo "--- OSD Status ---"
    ceph osd stat
    ceph osd tree
    
    echo ""
    echo "--- Pool Status ---"
    ceph osd pool stats
    
    echo ""
    echo "--- CephFS Status ---"
    ceph fs status cephfs 2>/dev/null || echo "CephFS not available"
    
    echo ""
    echo "--- RGW Status ---"
    ceph orch ps --daemon_type rgw 2>/dev/null || echo "RGW not available"
    
    echo ""
    echo "--- CSI Config ---"
    if [[ -f /etc/ceph/csi-config.yaml ]]; then
        echo "CSI config available at: /etc/ceph/csi-config.yaml"
    fi
    
    echo ""
    echo "--- Dashboard ---"
    echo "URL: https://${MON_IP}:${DASHBOARD_PORT}"
    echo "Username: admin"
    echo "Password: $DASHBOARD_PASSWORD"
    
    echo ""
    echo "========================================="
    echo "Deployment log: $LOG_FILE"
    echo "========================================="
    
    # Final health check
    local health
    health=$(ceph -s --format json 2>/dev/null | jq -r '.health.status' 2>/dev/null || echo "unknown")
    
    if [[ "$health" == "HEALTH_OK" ]]; then
        log_info "✓ Cluster is HEALTHY"
        return 0
    else
        log_warn "Cluster health: $health"
        ceph health detail
        return 1
    fi
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --mon-nodes "node1 node2 ..."    MON nodes (default: $MON_NODES)
  --osd-nodes "node1 node2 ..."    OSD nodes (default: $OSD_NODES)
  --osd-devices "dev1 dev2 ..."    OSD data devices (default: $OSD_DEVICES)
  --wal-device device             WAL/DB device (default: $WAL_DEVICE)
  --public-network CIDR           Public network (default: $PUBLIC_NETWORK)
  --cluster-network CIDR          Cluster network (default: $CLUSTER_NETWORK)
  --mon-ip IP                     First MON IP (default: $MON_IP)
  --dashboard-password PASS       Dashboard password (auto-generated if not set)
  --skip-osd                      Skip OSD deployment
  --skip-cephfs                   Skip CephFS creation
  --skip-rgw                      Skip RGW deployment
  --skip-csi                      Skip CSI user creation
  --phase PHASE                   Run only specific phase (1-13)
  --help                          Show this help

Examples:
  # Full deployment with defaults
  sudo ./deploy-ceph.sh

  # Custom node list
  sudo ./deploy-ceph.sh --mon-nodes "m1 m2 m3 m4 m5" --osd-nodes "s1 s2 s3 s4 s5"

  # Run only OSD deployment
  sudo ./deploy-ceph.sh --phase 5

  # Skip RGW and CephFS
  sudo ./deploy-ceph.sh --skip-rgw --skip-cephfs
EOF
}

# Parse arguments
RUN_ALL=true
RUN_PHASE=""
SKIP_OSD=false
SKIP_CEPHFS=false
SKIP_RGW=false
SKIP_CSI=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --mon-nodes) MON_NODES="$2"; shift 2 ;;
        --osd-nodes) OSD_NODES="$2"; shift 2 ;;
        --osd-devices) OSD_DEVICES="$2"; shift 2 ;;
        --wal-device) WAL_DEVICE="$2"; shift 2 ;;
        --public-network) PUBLIC_NETWORK="$2"; shift 2 ;;
        --cluster-network) CLUSTER_NETWORK="$2"; shift 2 ;;
        --mon-ip) MON_IP="$2"; shift 2 ;;
        --dashboard-password) DASHBOARD_PASSWORD="$2"; shift 2 ;;
        --skip-osd) SKIP_OSD=true; shift ;;
        --skip-cephfs) SKIP_CEPHFS=true; shift ;;
        --skip-rgw) SKIP_RGW=true; shift ;;
        --skip-csi) SKIP_CSI=true; shift ;;
        --phase) RUN_PHASE="$2"; RUN_ALL=false; shift 2 ;;
        --help) usage; exit 0 ;;
        *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Main
main() {
    check_root
    
    log_info "Starting Ceph deployment (version: $CEPH_VERSION)"
    log_info "Log file: $LOG_FILE"
    log_info "Air-gap mode: Nexus=$NEXUS_REPO, Harbor=$HARBOR_REGISTRY"
    
    if [[ -n "$RUN_PHASE" ]]; then
        # Run specific phase
        case "$RUN_PHASE" in
            1) check_prerequisites; phase1_bootstrap ;;
            2) phase2_add_mons ;;
            3) phase3_deploy_mgrs ;;
            4) phase4_add_osd_hosts ;;
            5) phase5_deploy_osds ;;
            6) phase6_create_pools ;;
            7) phase7_create_cephfs ;;
            8) phase8_deploy_rgw ;;
            9) phase9_tune_crush ;;
            10) phase10_configure_dashboard ;;
            11) phase11_create_csi_user ;;
            12) phase12_performance_tuning ;;
            13) phase13_health_check ;;
            *) log_error "Invalid phase: $RUN_PHASE"; exit 1 ;;
        esac
    else
        # Run all phases
        check_prerequisites
        phase1_bootstrap
        phase2_add_mons
        phase3_deploy_mgrs
        phase4_add_osd_hosts
        
        if [[ "$SKIP_OSD" != true ]]; then
            phase5_deploy_osds
        fi
        
        phase6_create_pools
        
        if [[ "$SKIP_CEPHFS" != true ]]; then
            phase7_create_cephfs
        fi
        
        if [[ "$SKIP_RGW" != true ]]; then
            phase8_deploy_rgw
        fi
        
        phase9_tune_crush
        phase10_configure_dashboard
        
        if [[ "$SKIP_CSI" != true ]]; then
            phase11_create_csi_user
        fi
        
        phase12_performance_tuning
        phase13_health_check
    fi
    
    log_info "Deployment script completed"
}

# Run main
main "$@"
