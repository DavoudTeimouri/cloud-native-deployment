#!/usr/bin/env bash
#
# ntp-setup.sh - NTP Configuration for Air-Gapped Environments
#
# Installs and configures chrony for time synchronization in air-gapped
# environments. Supports local NTP servers, GPS receivers, and can
# configure the node as an NTP server for other cluster nodes.
#
# Usage:
#   sudo ./ntp-setup.sh [OPTIONS]
#
# Options:
#   -h, --help              Show this help message
#   -d, --dry-run           Show what would be done without making changes
#   -s, --server HOST       NTP server hostname/IP (can specify multiple)
#   --as-server             Configure this node as an NTP server
#   --allow-net CIDR        Allowed client network (default: 10.0.0.0/8)
#   --gps                   primary time source (via PPS)
#   --stratum N             Local stratum if no upstream (default: 10)
#   -v, --verbose           Enable verbose output
#   -l, --log FILE          Log file path
#   --verify-only           Only verify current NTP sync status
#
# Exit Codes:
#   0 - Success
#   1 - Error
#
# Examples:
#   # Configure as NTP client
#   sudo ./ntp-setup.sh -s ntp1.internal.lan -s ntp2.internal.lan
#
#   # Configure as NTP server (first node with GPS)
#   sudo ./ntp-setup.sh --as-server --gps --allow-net 10.0.0.0/8
#
#   # Configure as NTP server (syncing from other NTP server)
#   sudo ./ntp-setup.sh --as-server -s ntp1.internal.lan --allow-net 10.0.0.0/8
#
#   # Verify only
#   sudo ./ntp-setup.sh --verify-only
#
set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"

# Defaults
LOG_FILE="/var/log/ntp-setup.log"
DRY_RUN=false
VERBOSE=false
AS_SERVER=false
USE_GPS=false
NTP_SERVERS=()
ALLOW_NETWORK="10.0.0.0/8"
LOCAL_STRATUM=10
VERIFY_ONLY=false

# Default NTP servers if none specified
DEFAULT_NTP_SERVERS=("ntp1.internal.lan" "ntp2.internal.lan")

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
        SUCCESS) echo -e "\033[32m${log_line}\033[0m" ;;
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
    log_info "=== NTP Setup Script v${SCRIPT_VERSION} started ==="
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
            -s|--server)
                NTP_SERVERS+=("$2")
                shift 2
                ;;
            --as-server)
                AS_SERVER=true
                shift
                ;;
            --allow-net)
                ALLOW_NETWORK="$2"
                shift 2
                ;;
            --gps)
                USE_GPS=true
                shift
                ;;
            --stratum)
                LOCAL_STRATUM="$2"
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
            --verify-only)
                VERIFY_ONLY=true
                shift
                ;;
            *)
                die "Unknown option: $1 (use --help for usage)"
                ;;
        esac
    done

    # Use default NTP servers if none specified and not using GPS/server mode
    if [[ ${#NTP_SERVERS[@]} -eq 0 && "${VERIFY_ONLY}" == false && "${USE_GPS}" == false ]]; then
        NTP_SERVERS=("${DEFAULT_NTP_SERVERS[@]}")
    fi
}

show_help() {
    cat << 'EOF'
ntp-setup.sh - NTP Configuration for Air-Gapped Environments

Usage: sudo ./ntp-setup.sh [OPTIONS]

Options:
  -h, --help              Show this help message
  -d, --dry-run           Show what would be done without making changes
  -s, --server HOST       NTP server hostname/IP (can specify multiple)
  --as-server             Configure this node as an NTP server
  --allow-net CIDR        Allowed client network (default: 10.0.0.0/8)
  --gps                   Use GPS as primary time source (via PPS)
  --stratum N             Local stratum if no upstream (default: 10)
  -v, --verbose           Enable verbose output
  -l, --log FILE          Log file path
  --verify-only           Only verify current NTP sync status

Examples:
  sudo ./ntp-setup.sh -s ntp1.internal.lan -s ntp2.internal.lan
  sudo ./ntp-setup.sh --as-server --gps --allow-net 10.0.0.0/8
  sudo ./ntp-setup.sh --as-server -s ntp1.internal.lan --allow-net 10.0.0.0/8
  sudo ./ntp-setup.sh --verify-only
EOF
}

# ==============================================================================
# NTP FUNCTIONS
# ==============================================================================

install_chrony() {
    log_info "Installing chrony..."

    if check_command chronyc; then
        log_info "chrony already installed"
        return 0
    fi

    run_or_dry "apt-get update -qq"
    run_or_dry "apt-get install -y chrony"

    if [[ "${DRY_RUN}" == false ]] && ! check_command chronyc; then
        die "Failed to install chrony"
    fi

    log_success "chrony installed"
}

configure_chrony_client() {
    log_info "Configuring chrony as NTP client..."

    local chrony_conf="/etc/chrony/chrony.conf"
    backup_file "${chrony_conf}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would configure chrony as client"
        return 0
    fi

    cat > "${chrony_conf}" << CHRONY_HEADER
# Chrony Configuration - NTP Client
# Generated by ntp-setup.sh
# Air-Gap Environment

CHRONY_HEADER

    # Add NTP servers
    for ntp in "${NTP_SERVERS[@]}"; do
        if [[ "${ntp}" == "${NTP_SERVERS[0]}" ]]; then
            echo "server ${ntp} iburst prefer" >> "${chrony_conf}"
        else
            echo "server ${ntp} iburst" >> "${chrony_conf}"
        fi
    done

    cat >> "${chrony_conf}" << CHRONY_FOOTER

# Fallback to local clock
local stratum ${LOCAL_STRATUM}

# Drift file
driftfile /var/lib/chrony/chrony.drift

# Logging
logdir /var/log/chrony
log measurements statistics tracking

# Kernel RTC sync
rtcsync

# Step threshold
makestep 1.0 3

# Minimum sources
minsources 1
CHRONY_FOOTER

    log_success "Chrony client configuration written"
}

configure_chrony_server() {
    log_info "Configuring chrony as NTP server..."

    local chrony_conf="/etc/chrony/chrony.conf"
    backup_file "${chrony_conf}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would configure chrony as server"
        return 0
    fi

    cat > "${chrony_conf}" << CHRONY_HEADER
# Chrony Configuration - NTP Server
# Generated by ntp-setup.sh
# Air-Gap Environment - This node serves time to cluster

CHRONY_HEADER

    # If GPS, add refclock
    if [[ "${USE_GPS}" == true ]]; then
        cat >> "${chrony_conf}" << 'GPS_CONFIG'
# GPS Reference Clock
refclock PPS /dev/pps0 poll 3 trust
refclock SHM 0 offset 0.0 delay 0.1 refid GPS trust

GPS_CONFIG
        log_info "GPS reference clock configured"
    fi

    # Add upstream NTP servers if specified
    if [[ ${#NTP_SERVERS[@]} -gt 0 ]]; then
        for ntp in "${NTP_SERVERS[@]}"; do
            if [[ "${ntp}" == "${NTP_SERVERS[0]}" ]]; then
                echo "server ${ntp} iburst prefer" >> "${chrony_conf}"
            else
                echo "server ${ntp} iburst" >> "${chrony_conf}"
            fi
        done
        echo "" >> "${chrony_conf}"
    fi

    cat >> "${chrony_conf}" << CHRONY_SERVER

# Serve time to internal network
allow ${ALLOW_NETWORK}

# Serve time even if not synchronized
local stratum ${LOCAL_STRATUM}

# Drift file
driftfile /var/lib/chrony/chrony.drift

# Logging
logdir /var/log/chrony
log measurements statistics tracking

# Kernel RTC sync
rtcsync

# Step threshold
makestep 1.0 3

# Minimum sources
minsources 1

# Bind
bindaddress 0.0.0.0

# NTS (disable in air-gap)
nts disable
CHRONY_SERVER

    log_success "Chrony server configuration written"
}

start_chrony() {
    log_info "Starting chrony service..."

    run_or_dry "systemctl enable chrony"
    run_or_dry "systemctl restart chrony"

    if [[ "${DRY_RUN}" == false ]]; then
        sleep 3
        if systemctl is-active chrony &>/dev/null; then
            log_success "Chrony is running"
        else
            log_error "Chrony failed to start"
            return 1
        fi
    fi
}

verify_ntp_sync() {
    log_info "Verifying NTP synchronization..."

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would verify NTP sync"
        return 0
    fi

    if ! check_command chronyc; then
        log_error "chronyc not available"
        return 1
    fi

    # Wait for initial sync
    log_info "Waiting for initial sync (up to 30 seconds)..."
    local attempts=0
    while [[ ${attempts} -lt 6 ]]; do
        local tracking
        tracking="$(chronyc tracking 2>/dev/null || true)"
        if echo "${tracking}" | grep -q "Leap status.*Normal"; then
            log_success "NTP synchronized successfully"
            break
        fi
        sleep 5
        ((attempts++))
    done

    # Display status
    echo ""
    echo "=== NTP Status ==="
    chronyc tracking 2>/dev/null || true
    echo ""
    echo "=== NTP Sources ==="
    chronyc sources -v 2>/dev/null || true
    echo ""

    # Check sync status
    local leap_status="$(chronyc tracking 2>/dev/null | grep "Leap status" | awk -F: '{print $2}' | xargs)"
    if [[ "${leap_status}" == "Normal" ]]; then
        log_success "NTP sync verified - Leap status: ${leap_status}"
        return 0
    else
        log_warn "NTP sync status: ${leap_status} (may still be synchronizing)"
        return 1
    fi
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
# MAIN
# ==============================================================================

main() {
    parse_args "$@"
    check_root
    setup_logging

    log_info "NTP Setup Script v${SCRIPT_VERSION}"
    log_info "Mode: $(if [[ "${AS_SERVER}" == true ]]; then echo "Server"; else echo "Client"; fi)"
    log_info "Dry-run: ${DRY_RUN}"

    # Verify-only mode
    if [[ "${VERIFY_ONLY}" == true ]]; then
        verify_ntp_sync
        exit $?
    fi

    # Install chrony
    install_chrony

    # Configure based on mode
    if [[ "${AS_SERVER}" == true ]]; then
        configure_chrony_server
    else
        configure_chrony_client
    fi

    # Start and verify
    start_chrony
    verify_ntp_sync

    log_info "=== NTP Setup completed ==="
    log_info "Log file: ${LOG_FILE}"
}

main "$@"
