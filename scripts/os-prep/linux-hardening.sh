#!/usr/bin/env bash
#
# linux-hardening.sh - Production-grade OS hardening for Ubuntu 22.04
#
# Hardens Ubuntu 22.04 for Kubernetes deployment in air-gapped environments.
# Follows CIS Benchmark Level 1 with Kubernetes-specific tuning.
#
# Usage:
#   sudo ./linux-hardening.sh [OPTIONS]
#
# Options:
#   -h, --help          Show this help message
#   -d, --dry-run       Show what would be done without making changes
#   -t, --target HOST   Run remotely on specified SSH target
#   -u, --user USER     Deploy user (default: deploy)
#   -v, --verbose       Enable verbose output
#   -l, --log FILE      Log file path (default: /var/log/os-hardening.log)
#   --skip-containerd   Skip containerd installation
#   --skip-chrony       Skip chrony configuration
#   --skip-audit        Skip auditd configuration
#
# Exit Codes:
#   0 - Success
#   1 - Error
#   2 - Invalid arguments
#
# Idempotent: Safe to re-run. Checks existing state before making changes.
#
# Examples:
#   # Local execution
#   sudo ./linux-hardening.sh
#
#   # Dry-run first
#   sudo ./linux-hardening.sh --dry-run
#
#   # Remote execution
#   sudo ./linux-hardening.sh --target k8s-worker-01
#
#   # Custom user, verbose
#   sudo ./linux-hardening.sh --user deploy --verbose
#
set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"
readonly OS_REQUIREMENT="22.04"

# Defaults
LOG_FILE="/var/log/os-hardening.log"
DEPLOY_USER="deploy"
DRY_RUN=false
VERBOSE=false
TARGET_HOST=""
SKIP_CONTAINERD=false
SKIP_CHRONY=false
SKIP_AUDIT=false

# Internal infrastructure (customize these)
NTP_SERVERS=("ntp1.internal.lan" "ntp2.internal.lan")
DNS_SERVERS=("10.0.0.2" "10.0.0.3")
DNS_SEARCH_DOMAINS=("internal.lan" "cluster.local")
NEXUS_HOST="nexus.internal.lan:5000"
HARBOR_HOST="harbor.internal.lan"
INTERNAL_DNS_DOMAIN="internal.lan"

# Containerd configuration
CONTAINERD_REGISTRY_MIRRORS=(
    "https://${NEXUS_HOST}"
    "https://${HARBOR_HOST}"
)
K8S_PAUSE_IMAGE="registry.internal.lan/google_containers/pause:3.9"

# Kernel modules to load
KERNEL_MODULES=(
    "br_netfilter"
    "overlay"
    "ip_vs"
    "ip_vs_rr"
    "ip_vs_wrr"
    "ip_vs_sh"
    "nf_conntrack"
)

# Sysctl parameters for Kubernetes
declare -A SYSCTL_PARAMS=(
    ["net.ipv4.ip_forward"]="1"
    ["net.ipv6.conf.all.forwarding"]="1"
    ["net.bridge.bridge-nf-call-iptables"]="1"
    ["net.bridge.bridge-nf-call-ip6tables"]="1"
    ["net.bridge.bridge-nf-call-arptables"]="1"
    ["net.netfilter.nf_conntrack_max"]="131072"
    ["net.core.somaxconn"]="32768"
    ["net.core.netdev_max_backlog"]="1000"
    ["net.ipv4.tcp_max_syn_backlog"]="8096"
    ["net.ipv4.conf.all.rp_filter"]="1"
    ["net.ipv4.conf.default.rp_filter"]="1"
    ["net.ipv6.conf.all.disable_ipv6"]="1"
    ["net.ipv6.conf.default.disable_ipv6"]="1"
    ["vm.overcommit_memory"]="1"
    ["vm.panic_on_oom"]="0"
    ["kernel.panic"]="10"
    ["kernel.panic_on_oops"]="1"
    ["fs.file-max"]="2097152"
    ["fs.inotify.max_user_watches"]="524288"
    ["fs.inotify.max_user_instances"]="8192"
    ["net.ipv4.neigh.default.gc_thresh1"]="128"
    ["net.ipv4.neigh.default.gc_thresh2"]="512"
    ["net.ipv4.neigh.default.gc_thresh3"]="1024"
)

# Packages to remove
REMOVE_PACKAGES=(
    "snapd"
    "accountsservice"
    "avahi-daemon"
    "cups"
    "cups-bsd"
    "cups-client"
    "wireshark"
    "tcpdump"
    "nmap"
    "zenmap"
)

# ==============================================================================
# LOGGING
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_line="[${timestamp}] [${level}] ${message}"

    # Write to log file
    echo "${log_line}" >> "${LOG_FILE}" 2>/

    # Write to stdout/stderr based on level
    case "${level}" in
        ERROR)
            echo -e "\033[31m${log_line}\033[0m" >&2
            ;;
        WARN)
            echo -e "\033[33m${log_line}\033[0m" >&2
            ;;
        INFO)
            echo "${log_line}"
            ;;
        DEBUG)
            if [[ "${VERBOSE}" == true ]]; then
                echo -e "\033[36m${log_line}\033[0m"
            fi
            ;;
        SUCCESS)
            echo -e "\033[32m${log_line}\033[0m"
            ;;
    esac
}

log_info()    { log "INFO" "$@"; }
log_warn()    { log "WARN" "$@"; }
log_error()   { log "ERROR" "$@"; }
log_debug()   { log "DEBUG" "$@"; }
log_success() { log "SUCCESS" "$@"; }

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

die() {
    log_error "$@"
    exit 1
}

run_or_dry() {
    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would execute: $*"
        return 0
    else
        log_debug "Executing: $@"
        eval "$@"
    fi
}

run_remote() {
    local host="$1"
    shift
    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would execute on ${host}: $*"
        return 0
    else
        log_debug "Executing on ${host}: $*"
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${host}" "$@"
    fi
}

check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "This script must be run as root (current UIDu))"
    fi
}

check_os_version() {
    if -f /etc/os-release ]]; then
        die "Cannot determine OS version: /etc/os-release not found"
    fi

    source /etc/os-release
    if [[ "${VERSION_ID}" != "${OS_REQUIREMENT}" ]]; then
        die "This script requires Ubuntu ${OS_REQUIREMENT} (detected: ${VERSION_ID})"
    fi
    log_info "OS version verified: Ubuntu ${VERSION_ID}"
}

check_command() {
    command -v "$1" &>/dev/null
}

backup_file() {
    local file="$1"
    if [[ -f "${file}" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d%H%M%S)"
        run_or_dry "cp ${file} ${backup}"
        log_debug "Backed up ${file} to ${backup}"
    fi
}

# ==============================================================================
# PARSING ARGUMENTS
# ==============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -t|--target)
                TARGET_HOST="$2"
                shift 2
                ;;
            -u|--user)
                DEPLOY_USER="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -l|--log)
                LOG_FILE="$2"
                shift 2
                ;;
            --skip-containerd)
                SKIP_CONTAINERD=true
                shift
                ;;
            --skip-chrony)
                SKIP_CHRONY=true
                shift
                ;;
            --skip-audit)
                SKIP_AUDIT=true
                shift
                ;;
            *)
                die "Unknown option: $1 (use --help for usage)"
                ;;
        esac
    done
}

show_help() {
    cat << 'EOF'
linux-hardening.sh - OS Hardening for Ubuntu 22.04 Kubernetes Nodes

Usage: sudo ./linux-hardening.sh [OPTIONS]

Options:
  -h, --help          Show this help message
  -d, --dry-run       Show what would be done without making changes
  -t, --target HOST   Run remotely on specified SSH target
  -u, --user USER     Deploy user (default: deploy)
  -v, --verbose       Enable verbose output
  -l, --log FILE      Log file path (default: /var/log/os-hardening.log)
  --skip-containerd   Skip containerd installation
  --skip-chrony       Skip chrony configuration
  --skip-audit        Skip auditd configuration

Examples:
  sudo ./linux-hardening.sh
  sudo ./linux-hardening.sh --dry-run
  sudo ./linux-hardening.sh --target k8s-worker-01
  sudo ./linux-hardening.sh --user deploy --verbose
EOF
}

# ==============================================================================
# HARDENING FUNCTIONS
# ==============================================================================

setup_logging() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    touch "${LOG_FILE}"
    chmod 640 "${LOG_FILE}"
    log_info "=== OS Hardening Script v${SCRIPT_VERSION} started ==="
    log_info "Dry-run mode: ${DRY_RUN}"
    log_info "Target: ${TARGET_HOST:-localhost}"
}

configure_sysctl() {
    log_info "Configuring kernel parameters (sysctl)..."

    local sysctl_file="/etc/sysctl.d/99-kubernetes-hardening.conf"
    backup_file "${sysctl_file}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would write sysctl parameters to ${sysctl_file}"
        for param in "${!SYSCTL_PARAMS[@]}"; do
            log_debug "[DRY-RUN] ${param} = ${SYSCTL_PARAMS[$param]}"
        done
        return 0
    fi

    cat > "${sysctl_file}" << 'HEADER'
# Kubernetes OS Hardening - Kernel Parameters
# Generated by linux-hardening.sh
# CIS Benchmark Level 1 + Kubernetes-specific tuning

HEADER

    for param in $(echo "${!SYSCTL_PARAMS[@]}" | tr ' ' '\n' | sort); do
        local value="${SYSCTL_PARAMS[$param]}"
        echo "${param} = ${value}" >> "${sysctl_file}"
        log_debug "Set ${param} = ${value}"
    done

    # Apply sysctl settings
    if sysctl --system &>/dev/null; then
        log_success "Sysctl parameters applied successfully"
    else
        log_error "Failed to apply sysctl parameters"
        return 1
    fi
}

disable_swap() {
    log_info "Disabling swap..."

    # Check current swap status
    if [[ "$(free -m | awk '/^Swap:/ {print $2}')" == "0" ]]; then
        log_info "Swap is already disabled"
        return 0
    fi

    run_or_dry "swapoff -a"

    # Remove swap from fstab
    if grep -q 'swap' /etc/fstab 2>/dev/null; then
        backup_file "/etc/fstab"
        run_or_dry "sed -i '/\s*swap\s*/d' /etc/fstab"
        log_info "Removed swap entries from /etc/fstab"
    fi

    # Verify
    if [[ "${DRY_RUN}" == false ]]; then
        local swap_total
        swap_total="$(free -m | awk '/^Swap:/ {print $2}')"
        if [[ "${swap_total}" == "0" ]]; then
            log_success "Swap disabled successfully"
        else
            log_warn "Swap may still be active (total: ${swap_total}MB)"
        fi
    fi
}

load_kernel_modules() {
    log_info "Loading kernel modules..."

    local modules_file="/etc/modules-load.d/kubernetes-hardening.conf"
    backup_file "${modules_file}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would write kernel modules to ${modules_file}"
        for module in "${KERNEL_MODULES[@]}"; do
            log_debug "[DRY-RUN] Module: ${module}"
        done
        return 0
    fi

    # Write modules file
    cat > "${modules_file}" << 'HEADER'
# Kubernetes Required Kernel Modules
# Generated by linux-hardening.sh

HEADER

    for module in "${KERNEL_MODULES[@]}"; do
        echo "${module}" >> "${modules_file}"
        # Load module immediately
        if lsmod 2>/dev/null | grep -q "^${module}"; then
            if modprobe "${module}" 2>/dev/null; then
                log_debug "Loaded module: ${module}"
            else
                log_warn "Failed to load module: ${module} (may not be available)"
            fi
        else
            log_debug "Module already loaded: ${module}"
        fi
    done

    log_success "Kernel modules configured"
}

disable_ufw() {
    log_info "Disabling UFW (Calico manages firewall rules)..."

    if check_command ufw; then
        run_or_dry "ufw disable"
        run_or_dry "systemctl stop ufw 2>/dev/null || true"
        run_or_dry "systemctl disable ufw 2>/dev/null || true"
        log_success "UFW disabled"
    else
        log_info "UFW not installed, skipping"
    fi
}

disable_unused_services() {
    log_info "Disabling unused services..."

    local services=(
        "accounts-daemon"
        "ModemManager"
        "bluetooth"
        "avahi-daemon"
    )

    for service in "${services[@]}"; do
        if systemctl list-unit-files "${service}.service" &>/dev/null; then
            run_or_dry "systemctl stop ${service} 2>/dev/null || true"
            run_or_dry "systemctl disable ${service} 2>/dev/null || true"
            log_debug "Disabled service: ${service}"
        else
            log_debug "Service not found: ${service} (skipping)"
        fi
    done

    log_success "Unused services disabled"
}

harden_ssh() {
    log_info "Hardening SSH configuration..."

    local sshd_config="/etc/ssh/sshd_config"
    backup_file "${sshd_config}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would harden SSH configuration"
        return 0
    fi

    # Create hardened sshd_config
    cat > "${sshd_config}" << SSHD_EOF
# SSH Server Configuration - Hardened for Kubernetes
# Generated by linux-hardening.sh
# CIS Benchmark Level 1 compliant

# Protocol
Protocol 2

# Authentication
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey

# Ciphers and MACs (CIS compliant)
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Connection limits
MaxAuthTries 3
MaxSessions 4
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# Logging
LogLevel VERBOSE
SyslogFacility AUTH

# Restrict users
AllowUsers ${DEPLOY_USER}

# Disable forwarding features
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
GatewayPorts no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
Compression no
ClientAliveCountMax 2
UsePAM yes
SSHD_EOF

    # Validate SSH config
    if sshd -t 2>/dev/null; then
        run_or_dry "systemctl restart sshd"
        log_success "SSH hardened and restarted"
    else
        log_error "SSH configuration validation failed - restoring backup"
        if [[ -f "${sshd_config}.backup."* ]]; then
            cp "${sshd_config}.backup."* "${sshd_config}"
        fi
        return 1
    fi
}

create_deploy_user() {
    log_info "Setting up deploy user: ${DEPLOY_USER}..."

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would create/configure user: ${DEPLOY_USER}"
        return 0
    fi

    # Create user if not exists
    if ! id "${DEPLOY_USER}" &>/dev/null; then
        useradd -m -s /bin/bash -c "Ansible Deploy User" "${DEPLOY_USER}"
        log_info "Created user: ${DEPLOY_USER}"
    else
        log_info "User ${DEPLOY_USER} already exists"
    fi

    # Add to required groups
    usermod -aG sudo,adm,systemd-journal "${DEPLOY_USER}" 2>/dev/null || true

    # Configure sudo (passwordless for automation)
    local sudoers_file="/etc/sudoers.d/${DEPLOY_USER}"
    if [[ ! -f "${sudoers_file}" ]]; then
        echo "${DEPLOY_USER} ALL=(ALL) NOPASSWD:ALL" > "${sudoers_file}"
        chmod 440 "${sudoers_file}"
        log_info "Configured passwordless sudo for ${DEPLOY_USER}"
    fi

    # Setup SSH directory
    local ssh_dir="/home/${DEPLOY_USER}/.ssh"
    if [[ ! -d "${ssh_dir}" ]]; then
        mkdir -p "${ssh_dir}"
        chmod 700 "${ssh_dir}"
        touch "${ssh_dir}/authorized_keys"
        chmod 600 "${ssh_dir}/authorized_keys"
        chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${ssh_dir}"
        log_info "Created SSH directory for ${DEPLOY_USER}"
    fi

    log_success "Deploy user configured"
}

configure_security_limits() {
    log_info "Configuring security limits..."

    local limits_file="/etc/security/limits.d/99-kubernetes-hardening.conf"
    backup_file "${limits_file}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would write security limits to ${limits_file}"
        return 0
    fi

    cat > "${limits_file}" << LIMITS_EOF
# Security Limits for Kubernetes
# Generated by linux-hardening.sh

# File descriptors
*               soft    nofile          1048576
*               hard    nofile          1048576

# Processes
*               soft    nproc           65535
*               hard    nproc           65535

# Root
root            soft    nofile          1048576
root            hard    nofile          1048576
root            soft    nproc           unlimited
root            hard    nproc           unlimited

# Deploy user
${DEPLOY_USER}  soft    nofile          65536
${DEPLOY_USER}  hard    nofile          65536
${DEPLOY_USER}  soft    nproc           65536
${DEPLOY_USER}  hard    nproc           65536
LIMITS_EOF

    log_success "Security limits configured"
}

configure_chrony() {
    if [[ "${SKIP_CHRONY}" == true ]]; then
        log_info "Skipping chrony configuration (--skip-chrony)"
        return 0
    fi

    log_info "Configuring chrony for air-gap NTP..."

    local chrony_conf="/etc/chrony/chrony.conf"
    backup_file "${chrony_conf}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would configure chrony with air-gap settings"
        return 0
    fi

    # Install chrony
    if ! check_command chronyc; then
        apt-get install -y chrony 2>/dev/null || log_warn "chrony install failed (may be pre-installed)"
    fi

    # Build chrony config
    cat > "${chrony_conf}" << CHRONY_EOF
# Chrony Configuration - Air-Gap Environment
# Generated by linux-hardening.sh
# No internet NTP servers - using internal sources only

CHRONY_EOF

    # Add NTP servers
    for ntp in "${NTP_SERVERS[@]}"; do
        if [[ "${ntp}" == "${NTP_SERVERS[0]}" ]]; then
            echo "server ${ntp} iburst prefer" >> "${chrony_conf}"
        else
            echo "server ${ntp} iburst" >> "${chrony_conf}"
        fi
    done

    cat >> "${chrony_conf}" << CHRONY_EOF2

# Fallback to local clock if NTP servers unreachable
local stratum 10

# Drift file
driftfile /var/lib/chrony/chrony.drift

# Logging
logdir /var/log/chrony
log measurements statistics tracking

# Kernel RTC sync
rtcsync

# Step threshold: 1 second in first 3 updates
makestep 1.0 3

# Minimum sources required
minsources 1

# Bind to all interfaces
bindaddress 0.0.0.0

# Allow NTP queries from internal network
allow 10.0.0.0/8
allow 172.16.0.0/12
allow 192.168.0.0/16
CHRONY_EOF2

    # Enable and start chrony
    systemctl enable chrony 2>/dev/null || true
    systemctl restart chrony 2>/dev/null || true

    # Verify
    sleep 2
    if systemctl is-active chrony &>/dev/null; then
        log_success "Chrony configured and running"
        if check_command chronyc; then
            chronyc tracking 2>/dev/null | head -5 | while read -r line; do
                log_debug "  ${line}"
            done
        fi
    else
        log_warn "Chrony may not be running (check with: systemctl status chrony)"
    fi
}

configure_dns() {
    log_info "Configuring DNS..."

    local resolv_conf="/etc/resolv.conf"
    backup_file "${resolv_conf}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would configure DNS servers: ${DNS_SERVERS[*]}"
        return 0
    fi

    # Unset immutable flag if present
    chattr -i "${resolv_conf}" 2>/dev/null || true

    # Disable systemd-resolved if it's managing resolv.conf
    if systemctl is-active systemd-resolved &>/dev/null; then
        log_info "Disabling systemd-resolved to manage resolv.conf directly"
        run_or_dry "systemctl stop systemd-resolved 2>/dev/null || true"
        run_or_dry "systemctl disable systemd-resolved 2>/dev/null || true"
    fi

    # Build resolv.conf
    {
        echo "# DNS Configuration - Air-Gap Environment"
        echo "# Generated by linux-hardening.sh"
        echo "#"
        for dns in "${DNS_SERVERS[@]}"; do
            echo "nameserver ${dns}"
        done
        if [[ ${#DNS_SEARCH_DOMAINS[@]} -gt 0 ]]; then
            echo "search ${DNS_SEARCH_DOMAINS[*]}"
        fi
        echo "options timeout:2 attempts:3 rotate"
    } > "${resolv_conf}"

    # Make immutable to prevent overwrite
    chattr +i "${resolv_conf}" 2>/dev/null || log_warn "Could not set immutable on ${resolv_conf}"

    log_success "DNS configured"
}

install_containerd() {
    if [[ "${SKIP_CONTAINERD}" == true ]]; then
        log_info "Skipping containerd installation (--skip-containerd)"
        return 0
    fi

    log_info "Installing and configuring containerd..."

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would install containerd with Nexus/Harbor mirrors"
        return 0
    fi

    # Install containerd if not present
    if ! check_command containerd; then
        apt-get update -qq 2>/dev/null || log_warn "apt-get update failed"
        apt-get install -y containerd 2>/dev/null || {
            log_error "Failed to install containerd. Ensure packages are available in Nexus."
            return 1
        }
    fi

    # Create containerd config directory
    mkdir -p /etc/containerd

    # Generate default config and modify
    local config_file="/etc/containerd/config.toml"
    backup_file "${config_file}"

    containerd config default > "${config_file}" 2>/dev/null || true

    # Configure registry mirrors
    cat > "${config_file}" << CONTAINERD_EOF
# Containerd Configuration - Air-Gap Environment
# Generated by linux-hardening.sh

version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "${K8S_PAUSE_IMAGE}"

    [plugins."io.containerd.grpc.v1.cri".registry]
CONTAINERD_EOF

    # Add registry mirrors
    for mirror in "${CONTAINERD_REGISTRY_MIRRORS[@]}"; do
        local host
        host="$(echo "${mirror}" | sed 's|https\?://||')"
        cat >> "${config_file}" << MIRROR_EOF
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${host}"]
        endpoint = ["${mirror}"]
      [plugins."io.containerd.grpc.v1.cri".registry.configs."${host}".tls]
        insecure_skip_verify = false
MIRROR_EOF
    done

    # Add containerd runtime config
    cat >> "${config_file}" << 'CONTAINERD_EOF2'

    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true

[plugins."io.containerd.grpc.v1.cri".cni]
  bin_dir = "/opt/cni/bin"
  conf_dir = "/etc/cni/net.d"
CONTAINERD_EOF2

    # Restart containerd
    systemctl restart containerd 2>/dev/null || true
    systemctl enable containerd 2>/dev/null || true

    if systemctl is-active containerd &>/dev/null; then
        log_success "Containerd installed and running"
    else
        log_warn "Containerd may not be running (check with: systemctl status containerd)"
    fi
}

configure_apparmor() {
    log_info "Checking AppArmor status..."

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would ensure AppArmor is enabled and enforcing"
        return 0
    fi

    if check_command aa-status; then
        if aa-status --enabled 2>/dev/null; then
            log_success "AppArmor is enabled"
            # Set profiles to enforce mode
            aa-enforce /etc/apparmor.d/* 2>/dev/null || true
            log_info "AppArmor profiles set to enforce mode"
        else
            log_warn "AppArmor is not enabled - enabling..."
            systemctl enable apparmor 2>/dev/null || true
            systemctl start apparmor 2>/dev/null || true
        fi
    else
        log_warn "AppArmor tools not found - installing..."
        apt-get install -y apparmor apparmor-utils 2>/dev/null || true
        systemctl enable apparmor 2>/dev/null || true
        systemctl start apparmor 2>/dev/null || true
    fi
}

configure_auditd() {
    if [[ "${SKIP_AUDIT}" == true ]]; then
        log_info "Skipping auditd configuration (--skip-audit)"
        return 0
    fi

    log_info "Configuring auditd..."

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would configure auditd with Kubernetes rules"
        return 0
    fi

    # Install auditd
    if ! check_command auditctl; then
        apt-get install -y auditd audispd-plugins 2>/dev/null || {
            log_warn "Failed to install auditd"
            return 1
        }
    fi

    # Create audit rules
    local audit_rules="/etc/audit/rules.d/kubernetes-hardening.rules"
    backup_file "${audit_rules}"

    cat > "${audit_rules}" << 'AUDIT_EOF'
# Kubernetes Audit Rules
# Generated by linux-hardening.sh

# Delete all existing rules
-D

# Buffer size
-b 8192

# Failure mode (0=silent, 1=printk, 2=panic)
-f 1

# Monitor Kubernetes binaries
-w /usr/bin/kubeadm -p wa -k kubernetes
-w /usr/bin/kubelet -p wa -k kubernetes
-w /usr/bin/kubectl -p wa -k kubernetes
-w /usr/bin/containerd -p wa -k containerd
-w /usr/bin/ctr -p wa -k containerd
-w /usr/bin/calico -p wa -k calico

# Monitor config files
-w /etc/kubernetes/ -p wa -k kubernetes-config
-w /etc/containerd/ -p wa -k containerd-config
-w /etc/cni/ -p wa -k cni-config
-w /etc/calico/ -p wa -k calico-config

# Monitor authentication files
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Monitor mount operations (CSI)
-w /bin/mount -p x -k mounts
-w /bin/umount -p x -k mounts
-w /bin/mount -p x -k mounts

# Monitor privileged operations
-a always,exit -F arch=b64 -S setuid -S setgid -S setreuid -S setregid -k privilege_escalation
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k root_commands

# Monitor network configuration
-w /etc/hosts -p wa -k hosts
-w /etc/resolv.conf -p wa -k dns-config
-w /etc/network/ -p wa -k network-config

# Monitor kernel module loading
-w /sbin/insmod -p x -k kernel_modules
-w /sbin/rmmod -p x -k kernel_modules
-w /sbin/modprobe -p x -k kernel_modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k kernel_modules

# Make configuration immutable (requires reboot to change)
-e 2
AUDIT_EOF

    # Restart auditd
    systemctl restart auditd 2>/dev/null || true
    systemctl enable auditd 2>/dev/null || true

    if systemctl is-active auditd &>/dev/null; then
        log_success "Auditd configured and running"
    else
        log_warn "Auditd may not be running (check with: systemctl status auditd)"
    fi
}

remove_unnecessary_packages() {
    log_info "Removing unnecessary packages..."

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would remove packages: ${REMOVE_PACKAGES[*]}"
        return 0
    fi

    for pkg in "${REMOVE_PACKAGES[@]}"; do
        if dpkg -l "${pkg}" 2>/dev/null | grep -q "^ii"; then
            apt-get remove -y --purge "${pkg}" 2>/dev/null || log_warn "Could not remove ${pkg}"
            log_debug "Removed package: ${pkg}"
        else
            log_debug "Package not installed: ${pkg} (skipping)"
        fi
    done

    # Clean up
    apt-get autoremove -y 2>/dev/null || true
    apt-get autoclean -y 2>/dev/null || true

    log_success "Unnecessary packages removed"
}

verify_hardening() {
    log_info "Running verification checks..."

    local checks_passed=0
    local checks_failed=0

    # Check swap
    local swap_total
    swap_total="$(free -m | awk '/^Swap:/ {print $2}')"
    if [[ "${swap_total}" == "0" ]]; then
        log_success "[PASS] Swap is disabled"
        ((checks_passed++))
    else
        log_error "[FAIL] Swap is still enabled (${swap_total}MB)"
        ((checks_failed++))
    fi

    # Check sysctl
    local ip_forward
    ip_forward="$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)"
    if [[ "${ip_forward}" == "1" ]]; then
        log_success "[PASS] IP forwarding enabled"
        ((checks_passed++))
    else
        log_error "[FAIL] IP forwarding not enabled"
        ((checks_failed++))
    fi

    # Check bridge-nf-call
    local bridge_nf
    bridge_nf="$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo 0)"
    if [[ "${bridge_nf}" == "1" ]]; then
        log_success "[PASS] Bridge-nf-call-iptables enabled"
        ((checks_passed++))
    else
        log_error "[FAIL] Bridge-nf-call-iptables not enabled"
        ((checks_failed++))
    fi

    # Check kernel modules
    for module in "${KERNEL_MODULES[@]}"; do
        if lsmod 2>/dev/null | grep -q "^${module}"; then
            log_success "[PASS] Module loaded: ${module}"
            ((checks_passed++))
        else
            log_error "[FAIL] Module not loaded: ${module}"
            ((checks_failed++))
        fi
    done

    # Check SSH
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
        log_success "[PASS] SSH root login disabled"
        ((checks_passed++))
    else
        log_error "[FAIL] SSH root login not disabled"
        ((checks_failed++))
    fi

    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
        log_success "[PASS] SSH password auth disabled"
        ((checks_passed++))
    else
        log_error "[FAIL] SSH password auth not disabled"
        ((checks_failed++))
    fi

    # Check deploy user
    if id "${DEPLOY_USER}" &>/dev/null; then
        log_success "[PASS] Deploy user exists: ${DEPLOY_USER}"
        ((checks_passed++))
    else
        log_error "[FAIL] Deploy user missing: ${DEPLOY_USER}"
        ((checks_failed++))
    fi

    # Check services
    if systemctl is-active chrony &>/dev/null; then
        log_success "[PASS] Chrony is running"
        ((checks_passed++))
    else
        log_warn "[WARN] Chrony may not be running"
        ((checks_failed++))
    fi

    if systemctl is-active containerd &>/dev/null; then
        log_success "[PASS] Containerd is running"
        ((checks_passed++))
    else
        log_warn "[WARN] Containerd may not be running"
        ((checks_failed++))
    fi

    log_info "Verification complete: ${checks_passed} passed, ${checks_failed} failed"

    if [[ ${checks_failed} -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    parse_args "$@"

    # If target host specified, run remotely
    if [[ -n "${TARGET_HOST}" ]]; then
        log_info "Running remotely on ${TARGET_HOST}"
        # Copy script to remote and execute
        local remote_script="/tmp/${SCRIPT_NAME}"
        scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$0" "${TARGET_HOST}:${remote_script}" 2>/dev/null
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${TARGET_HOST}" "chmod +x ${remote_script} && sudo ${remote_script} $*"
        exit $?
    fi

    # Local execution
    check_root
    check_os_version
    setup_logging

    log_info "Starting OS hardening for Ubuntu ${OS_REQUIREMENT}"
    log_info "Script version: ${SCRIPT_VERSION}"

    # Execute hardening steps
    configure_sysctl
    disable_swap
    load_kernel_modules
    disable_ufw
    disable_unused_services
    harden_ssh
    create_deploy_user
    configure_security_limits
    configure_chrony
    configure_dns
    install_containerd
    configure_apparmor
    configure_auditd
    remove_unnecessary_packages

    # Verification
    verify_hardening

    log_info "=== OS Hardening Script completed ==="
    log_info "Log file: ${LOG_FILE}"
    log_info "A system reboot is recommended to apply all changes."
}

# Run main
main "$@"
