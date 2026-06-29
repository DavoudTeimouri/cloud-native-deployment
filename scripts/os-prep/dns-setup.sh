#!/usr/bin/env bash
#
# dns-setup.sh - DNS Configuration for Air-Gapped Environments
#
# Configures DNS resolution for Kubernetes nodes in air-gapped environments.
# Sets up resolv.conf, static host entries for bootstrapping, and verifies
# DNS resolution.
#
# Usage:
#   sudo ./dns-setup.sh [OPTIONS]
#
# Options:
#   -h, --help              Show this help message
#   -d, --dry-run           Show what would be done without making changes
#   -n, --nameserver IP     DNS nameserver (can specify multiple)
#   --search DOMAIN         Search domain (can specify multiple)
#   --hosts-file FILE       Path to additional hosts file for bootstrapping
#   --domain DOMAIN         Internal domain (default: internal.lan)
#   --cluster-domain        K8s cluster domain (default: cluster.local)
#   --disable-resolved      Disable systemd-resolved
#   --verify-only           Only verify DNS resolution
#   -v, --verbose           Enable verbose output
#   -l, --log FILE          Log file path
#
# Exit Codes:
#   0 - Success
#   1 - Error
#
# Examples:
#   # Basic DNS setup
#   sudo ./dns-setup.sh -n 10.0.0.2 -n 10.0.0.3 --search internal.lan
#
#   # With bootstrap hosts
dns-setup.sh -n 10.0.0.2 --hosts-file /etc/k8s-hosts
#
#   # Verify only
#   sudo ./dns-setup.sh --verify-only
#
set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"

# Defaults
LOG_FILE="/var/log/dns-setup.log"
DRY_RUN=false
VERBOSE=false
VERIFY_ONLY=false
DISABLE_RESOLVED=false
INTERNAL_DOMAIN="internal.lan"
CLUSTER_DOMAIN="cluster.local"
HOSTS_FILE=""
NAMESERVERS=()
SEARCH_DOMAINS=()

# Default nameservers
DEFAULT_NAMESERVERS=("10.0.0.2" "10.0.0.3")
DEFAULT_SEARCH_DOMAINS=("internal.lan" "cluster.local")

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

    echo "${log_line}" >> "${LOG_FILE}" 2>/dev/null || true

    case "${level}" in
        ERROR)   echo -e "\033[31m${log_line}\033[0m" >&2 ;;
        WARN)    echo -e "\033[33m${log_line}\033[0m" >&2 ;;
        INFO)    echo "${log_line}" ;;
        DEBUG)   [[ "${VERBOSE}" == true ]] && echo -e "\033[36m${log_line}\033[0m" ;;
        SUCCESS) echo -e "\\033[32m${log_line}\\033[0m" ;;
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

check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "This script must be run as root"
    fi
}

setup_logging() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    touch "${LOG_FILE}"
    chmod 640 "${LOG_FILE}"
    log_info "=== DNS Setup Script v${SCRIPT_VERSION} started ==="
}

backup_file() {
    local file="$1"
    if [[ -f "${file}" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d%H%M%S)"
        run_or_dry "cp ${file} ${backup}"
        log_debug "Backed up ${file} to ${backup}"
    fi
}

check_command() {
    command -v "$1" &>/dev/null
}

# ==============================================================================
# ARGUMENT PARSING
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
            -n|--nameserver)
                NAMESERVERS+=("$2")
                shift 2
                ;;
            --search)
                SEARCH_DOMAINS+=("$2")
                shift 2
                ;;
            --hosts-file)
                HOSTS_FILE="$2"
                shift 2
                ;;
            --domain)
                INTERNAL_DOMAIN="$2"
                shift 2
                ;;
            --cluster-domain)
                CLUSTER_DOMAIN="$2"
                shift 2
                ;;
            --disable-resolved)
                DISABLE_RESOLVED=true
                shift
                ;;
            --verify-only)
                VERIFY_ONLY=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -l|--log)
                LOG_FILE="$2"
                shift 2
                ;;
            *)
                die "Unknown option: $1 (use --help for usage)"
                ;;
        esac
    done

    # Use defaults if not specified
    if [[ ${#NAMESERVERS[@]} -eq 0 && "${VERIFY_ONLY}" == false ]]; then
        NAMESERVERS=("${DEFAULT_NAMESERVERS[@]}")
    fi
    if [[ ${#SEARCH_DOMAINS[@]} -eq 0 && "${VERIFY_ONLY}" == false ]]; then
        SEARCH_DOMAINS=("${DEFAULT_SEARCH_DOMAINS[@]}")
    fi
}

show_help() {
    cat << 'EOF'
dns-setup.sh - DNS Configuration for Air-Gapped Environments

Usage: sudo ./dns-setup.sh [OPTIONS]

Options:
  -h, --help              Show this help message
  -d, --dry-run           Show what would be done without making changes
  -n, --nameserver IP     DNS nameserver (can specify multiple)
  --search DOMAIN         Search domain (can specify multiple)
  --hosts-file FILE       Path to additional hosts file for bootstrapping
  --domain DOMAIN         Internal domain (default: internal.lan)
  --cluster-domain        K8s cluster domain (default: cluster.local)
  --disable-resolved      Disable systemd-resolved
  --verify-only           Only verify DNS resolution
  -v, --verbose           Enable verbose output
  -l, --log FILE          Log file path

Examples:
  sudo ./dns-setup.sh -n 10.0.0.2 -n 10.0.0.3 --search internal.lan
  sudo ./dns-setup.sh -n 10.0.0.2 --hosts-file /etc/k8s-hosts
  sudo ./dns-setup.sh --verify-only
EOF
}

# ==============================================================================
# DNS FUNCTIONS
# ==============================================================================

disable_systemd_resolved() {
    if [[ "${DISABLE_RESOLVED}" == true ]]; then
        log_info "Disabling systemd-resolved..."

        if [[ "${DRY_RUN}" == true ]]; then
            log_info "[DRY-RUN] Would disable systemd-resolved"
            return 0
        fi

        if systemctl is-active systemd-resolved &>/dev/null; then
            systemctl stop systemd-resolved 2>/dev/null || true
            systemctl disable systemd-resolved 2>/dev/null || true
            log_success "systemd-resolved disabled"
        else
            log_info "systemd-resolved is not active"
        fi
    fi
}

configure_resolv_conf() {
    log_info "Configuring /etc/resolv.conf..."

    local resolv_conf="/etc/resolv.conf"
    backup_file "${resolv_conf}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would configure resolv.conf with:"
        log_info "  Nameservers: ${NAMESERVERS[*]}"
        log_info "  Search: ${SEARCH_DOMAINS[*]}"
        return 0
    fi

    # Remove immutable flag if set
    chattr -i "${resolv_conf}" 2>/dev/null || true

    # Build resolv.conf
    {
        echo "# DNS Configuration - Air-Gap Environment"
        echo "# Generated by dns-setup.sh"
        echo "# Internal domain: ${INTERNAL_DOMAIN}"
        echo "# Cluster domain: ${CLUSTER_DOMAIN}"
        echo "#"
        echo "# Nameservers"
        for ns in "${NAMESERVERS[@]}"; do
            echo "nameserver ${ns}"
        done
        echo ""
        if [[ ${#SEARCH_DOMAINS[@]} -gt 0 ]]; then
            echo "search ${SEARCH_DOMAINS[*]}"
        fi
        echo "options timeout:2 attempts:3 rotate"
    } > "${resolv_conf}"

    # Set permissions
    chmod 644 "${resolv_conf}"

    # Make immutable to prevent overwrite by DHCP/network managers
    chattr +i "${resolv_conf}" 2>/dev/null || log_warn "Could not set immutable on ${resolv_conf}"

    log_success "resolv.conf configured"
}

configure_systemd_resolved() {
    if [[ "${DISABLE_RESOLVED}" == true ]]; then
        return 0
    fi

    log_info "Configuring systemd-resolved..."

    local resolved_conf="/etc/systemd/resolved.conf"
    backup_file "${resolved_conf}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would configure systemd-resolved"
        return 0
    fi

    # Build resolved.conf
    local dns_line=""
    for ns in "${NAMESERVERS[@]}"; do
        if [[ -z "${dns_line}" ]]; then
            dns_line="${ns}"
        else
            dns_line="${dns_line} ${ns}"
        fi
    done

    local search_line=""
    for domain in "${SEARCH_DOMAINS[@]}"; do
        if [[ -z "${search_line}" ]]; then
            search_line="${domain}"
        else
            search_line="${search_line} ${domain}"
        fi
    done

    cat > "${resolved_conf}" << RESOLVED_EOF
# systemd-resolved Configuration - Air-Gap Environment
# Generated by dns-setup.sh

[Resolve]
DNS=${dns_line}
Domains=${search_line}
DNSSEC=no
DNSOverTLS=no
Cache=yes
DNSStubListener=yes
RESOLVED_EOF

    # Restart systemd-resolved
    systemctl restart systemd-resolved 2>/dev/null || true
    systemctl enable systemd-resolved 2>/dev/null || true

    log_success "systemd-resolved configured"
}

add_bootstrap_hosts() {
    if [[ -z "${HOSTS_FILE}" ]]; then
        log_info "No bootstrap hosts file specified, skipping"
        return 0
    fi

    if [[ ! -f "${HOSTS_FILE}" ]]; then
        log_warn "Bootstrap hosts file not found: ${HOSTS_FILE}"
        return 0
    fi

    log_info "Adding bootstrap host entries from ${HOSTS_FILE}..."

    local etc_hosts="/etc/hosts"
    backup_file "${etc_hosts}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would append hosts from ${HOSTS_FILE} to /etc/hosts"
        return 0
    fi

    # Add separator and bootstrap entries
    {
        echo ""
        echo "# === Kubernetes Bootstrap Entries ==="
        echo "# Added by dns-setup.sh on $(date)"
        echo "# Remove after DNS is fully operational"
        echo ""
    } >> "${etc_hosts}"

    # Append hosts file (skip comments and empty lines)
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "${line}" =~ ^#.*$ ]] || [[ -z "${line}" ]]; then
            continue
        fi
        echo "${line}" >> "${etc_hosts}"
    done < "${HOSTS_FILE}"

    log_success "Bootstrap hosts added to /etc/hosts"
}

add_default_bootstrap_entries() {
    log_info "Adding default bootstrap entries..."

    local etc_hosts="/etc/hosts"
    backup_file "${etc_hosts}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would add default bootstrap entries"
        return 0
    fi

    # Add common bootstrap entries
    cat >> "${etc_hosts}" << 'HOSTS_EOF'

# === Kubernetes Bootstrap Entries ===
# Added by dns-setup.sh - Remove after DNS is fully operational

# Nameservers
10.0.0.2    ns1.internal.lan ns1
10.0.0.3    ns2.internal.lan ns2

# NTP servers
10.0.0.10   ntp1.internal.lan ntp1
10.0.0.11   ntp2.internal.lan ntp2

# Kubernetes API
10.0.1.10   k8s-api.internal.lan k8s-api

# Masters
10.0.1.11   k8s-master-01.nodes.internal.lan k8s-master-01
10.0.1.12   k8s-master-02.nodes.internal.lan k8s-master-02
10.0.1.13   k8s-master-03.nodes.internal.lan k8s-master-03

# Workers
10.0.1.21   k8s-worker-01.nodes.internal.lan k8s-worker-01
10.0.1.22   k8s-worker-02.nodes.internal.lan k8s-worker-02
10.0.1.23   k8s-worker-03.nodes.internal.lan k8s-worker-03

# Infrastructure
10.0.0.50   harbor.internal.lan harbor
10.0.0.51   nexus.internal.lan nexus
10.0.0.60   rancher.internal.lan rancher
HOSTS_EOF

    log_success "Default bootstrap entries added"
}

verify_dns_resolution() {
    log_info "Verifying DNS resolution..."

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would verify DNS resolution"
        return 0
    fi

    local checks_passed=0
    local checks_failed=0

    # Check resolv.conf exists and has correct content
    if [[ -f /etc/resolv.conf ]] && grep -q "nameserver" /etc/resolv.conf; then
        log_success "[PASS] resolv.conf has nameservers configured"
        ((checks_passed++))
    else
        log_error "[FAIL] resolv.conf missing or has no nameservers"
        ((checks_failed++))
    fi

    # Test DNS resolution using available tools
    local dns_tool=""
    if check_command dig; then
        dns_tool="dig"
    elif check_command nslookup; then
        dns_tool="nslookup"
    elif check_command host; then
        dns_tool="host"
    elif check_command getent; then
        dns_tool="getent"
    fi

    if [[ -z "${dns_tool}" ]]; then
        log_warn "No DNS tools available for verification (dig, nslookup, host, getent)"
        return 1
    fi

    log_info "Using ${dns_tool} for DNS verification"

    # Test resolution of internal hosts
    local test_hosts=(
        "ns1.${INTERNAL_DOMAIN}"
        "ntp1.${INTERNAL_DOMAIN}"
        "harbor.${INTERNAL_DOMAIN}"
    )

    for host in "${test_hosts[@]}"; do
        local resolved=false
        local result=""
        case "${dns_tool}" in
            dig)
                result="$(dig +short "${host}" "@${NAMESERVERS[0]}" 2>/dev/null || true)"
                if [[ -n "${result}" ]]; then
                    resolved=true
                fi
                ;;
            nslookup)
                result="$(nslookup "${host}" "${NAMESERVERS[0]}" 2>&1 || true)"
                if echo "${result}" | grep -q "Address"; then
                    resolved=true
                fi
                ;;
            host)
                result="$(host "${host}" "${NAMESERVERS[0]}" 2>&1 || true)"
                if echo "${result}" | grep -q "has address"; then
                    resolved=true
                fi
                ;;
            getent)
                result="$(getent hosts "${host}" 2>&1 || true)"
                if [[ -n "${result}" ]]; then
                    resolved=true
                fi
                ;;
        esac

        if [[ "${resolved}" == true ]]; then
            log_success "[PASS] Resolved: ${host}"
            ((checks_passed++))
        else
            log_warn "[WARN] Could not resolve: ${host} (may not exist in DNS)"
            # Don't count as hard failure since hosts may not exist yet
        fi
    done

    # Test localhost resolution
    if getent hosts localhost &>/dev/null; then
        log_success "[PASS] localhost resolves"
        ((checks_passed++))
    else
        log_error "[FAIL] localhost does not resolve"
        ((checks_failed++))
    fi

    # Test reverse DNS (if dig available)
    if [[ "${dns_tool}" == "dig" ]]; then
        local test_reverse
        test_reverse="$(dig +short -x "${NAMESERVERS[0]}" 2>/dev/null || true)"
        if [[ -n "${test_reverse}" ]]; then
            log_success "[PASS] Reverse DNS works: ${NAMESERVERS[0]} -> ${test_reverse}"
            ((checks_passed++))
        else
            log_debug "Reverse DNS not configured (this is OK)"
        fi
    fi

    echo ""
    echo "=== DNS Resolution Summary ==="
    echo "Passed: ${checks_passed}"
    echo "Failed: ${checks_failed}"
    echo ""

    if [[ ${checks_failed} -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    parse_args "$@"
    check_root
    setup_logging

    log_info "DNS Setup Script v${SCRIPT_VERSION}"
    log_info "Domain: ${INTERNAL_DOMAIN}"
    log_info "Cluster domain: ${CLUSTER_DOMAIN}"
    log_info "Dry-run: ${DRY_RUN}"

    # Verify-only mode
    if [[ "${VERIFY_ONLY}" == true ]]; then
        verify_dns_resolution
        exit $?
    fi

    # Disable systemd-resolved if requested
    disable_systemd_resolved

    # Configure DNS
    if [[ "${DISABLE_RESOLVED}" == true ]]; then
        configure_resolv_conf
    else
        configure_systemd_resolved
        # Also write resolv.conf directly as fallback
        configure_resolv_conf
    fi

    # Add bootstrap hosts
    if [[ -n "${HOSTS_FILE}" ]]; then
        add_bootstrap_hosts
    else
        add_default_bootstrap_entries
    fi

    # Verify
    verify_dns_resolution

    log_info "=== DNS Setup completed ==="
    log_info "Log file: ${LOG_FILE}"
    log_info ""
    log_info "NOTE: Bootstrap entries in /etc/hosts should be removed"
    log_info "      after DNS is fully operational."
}

main "$@"
