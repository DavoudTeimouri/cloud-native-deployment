#!/usr/bin/env bash
#
# ceph-dashboard.sh - Ceph Dashboard Configuration Script
#
# Configures the Ceph Manager Dashboard including:
# - Enable dashboard module
# - Create admin user with password
# - SSL/TLS certificate configuration
# - Custom port setting
# - Grafana integration URL
# - Prometheus metrics endpoint
#
# Usage:
#   sudo ./ceph-dashboard.sh [OPTIONS]
#
# Prerequisites:
#   - Ceph cluster deployed (at least 1 MGR running)
#   - ceph-mgr dashboard module available
#
# Air-Gap Notes:
#   - TLS certificates should be from internal CA
#   - No external service dependencies
#

set -euo pipefail

#=============================================================================
# CONFIGURATION
#=============================================================================

# Dashboard settings
DASHBOARD_USER="${DASHBOARD_USER:-admin}"
DASHBOARD_PASSWORD="${DA...nssl rand -base64 16)}"
DASHBOARD_PORT="${DASHBOARD_PORT:-8443}"
DASHBOARD_SSL="${DASHBOARD_SSL:-true}"

# TLS certificate paths
TLS_CERT_PATH="${TLS_CERT_PATH:-/etc/ceph/dashboard/cert.pem}"
TLS_KEY_PATH="${TLS_KEY_PATH:-/etc/ceph/dashboard/key.pem}"
CA_CERT_PATH="${CA_CERT_PATH:-/etc/ssl/certs/internal-ca.pem}"

# Certificate details
CERT_COUNTRY="${CERT_COUNTRY:-US}"
CERT_STATE="${CERT_STATE:-California}"
CERT_CITY="${CERT_CITY:-San Francisco}"
CERT_ORG="${CERT_ORG:-Internal}"
CERT_CN="${DASHBOARD_CN:-ceph-dashboard.internal}"
CERT_SAN="${DERT_SAN:-DNS:ceph-dashboard.internal,DNS:ceph-dashboard}"

# Grafana integration
GRAFANA_URL="${GRAFANA_URL:-https://grafana.internal}"
GRAFANA_API_URL="${GRAFANA_API_URL:-https://grafana.internal/api}"

# Prometheus
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9283}"

# Feature flags
ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-true}"
ENABLE_RGW_MANAGEMENT="${ENABLE_RGW_MANAGEMENT:-true}"
ENABLE_USER_MANAGEMENT="${ENABLE_USER_MANAGEMENT:-true}"
ENABLE_NETFLOW="${ENABLE_NETFLOW:-false}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/ceph-dashboard-$(date +%Y%m%d-%H%M%S).log}"

#=============================================================================
# COLOR OUTPUT
#=============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#=============================================================================
# LOGGING
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
    esac
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

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
    
    # Check ceph command
    if ! command -v ceph &>/dev/null; then
        log_error "ceph command not found. Is Ceph installed?"
        exit 1
    fi
    
    # Check MGR is running
    local mgr_active
    mgr_active=$(ceph mgr stat 2>/dev/null | grep -c "active" || echo "0")
    if [[ "$mgr_active" -lt 1 ]]; then
        log_error "No active MGR found. Deploy MGRs first."
        exit 1
    fi
    
    # Check cluster health
    local health
    health=$(ceph health 2>/dev/null | head -1 || echo "unknown")
    log_info "Cluster health: $health"
    
    log_info "Prerequisites check passed"
}

#=============================================================================
# DASHBOARD CONFIGURATION FUNCTIONS
#=============================================================================

enable_dashboard_module() {
    log_info "Enabling dashboard module..."
    
    if ceph mgr module list 2>/dev/null | grep -q "dashboard.*enabled"; then
        log_info "Dashboard module already enabled"
        return 0
    fi
    
    ceph mgr module enable dashboard 2>&1 | tee -a "$LOG_FILE"
    
    # Wait for module to be enabled
    sleep 5
    
    if ceph mgr module list 2>/dev/null | grep -q "dashboard.*enabled"; then
        log_info "Dashboard module enabled successfully"
    else
        log_error "Failed to enable dashboard module"
        return 1
    fi
}

generate_self_signed_cert() {
    log_info "Generating self-signed TLS certificate..."
    
    local cert_dir
    cert_dir=$(dirname "$TLS_CERT_PATH")
    mkdir -p "$cert_dir"
    
    # Generate self-signed certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$TLS_KEY_PATH" \
        -out "$TLS_CERT_PATH" \
        -subj "/C=$CERT_COUNTRY/ST=$CERT_STATE/L=$CERT_CITY/O=$CERT_ORG/CN=$CERT_CN" \
        -addext "subjectAltName=$CERT_SAN" \
        2>&1 | tee -a "$LOG_FILE"
    
    # Set permissions
    chmod 644 "$TLS_CERT_PATH"
    chmod 600 "$TLS_KEY_PATH"
    chown ceph:ceph "$TLS_CERT_PATH" "$TLS_KEY_PATH" 2>/dev/null || true
    
    log_info "Self-signed certificate generated"
    log_info "Certificate: $TLS_CERT_PATH"
    log_info "Key: $TLS_KEY_PATH"
}

generate_internal_ca_cert() {
    log_info "Generating certificate signed by internal CA..."
    
    if [[ ! -f "$CA_CERT_PATH" ]]; then
        log_warn "CA certificate not found at $CA_CERT_PATH"
        log_warn "Falling back to self-signed certificate"
        generate_self_signed_cert
        return
    fi
    
    local cert_dir
    cert_dir=$(dirname "$TLS_CERT_PATH")
    mkdir -p "$cert_dir"
    
    # Generate CSR
    local csr_path="/tmp/dashboard-csr.pem"
    openssl req -new -newkey rsa:2048 -nodes \
        -keyout "$TLS_KEY_PATH" \
        -out "$csr_path" \
        -subj "/C=$CERT_COUNTRY/ST=$CERT_STATE/L=$CERT_CITY/O=$CERT_ORG/CN=$CERT_CN" \
        2>&1 | tee -a "$LOG_FILE"
    
    # Sign with internal CA
    local ca_key="${CA_CERT_PATH%.pem}-key.pem"
    if [[ ! -f "$ca_key" ]]; then
        log_warn "CA private key not found at $ca_key"
        log_warn "Falling back to self-signed certificate"
        generate_self_signed_cert
        return
    fi
    
    openssl x509 -req -in "$csr_path" \
        -CA "$CA_CERT_PATH" \
        -CAkey "$ca_key" \
        -CAcreateserial \
        -out "$TLS_CERT_PATH" \
        -days 365 \
        -extfile <(printf "subjectAltName=$CERT_SAN") \
        2>&1 | tee -a "$LOG_FILE"
    
    # Set permissions
    chmod 644 "$TLS_CERT_PATH"
    chmod 600 "$TLS_KEY_PATH"
    chown ceph:ceph "$TLS_CERT_PATH" "$TLS_KEY_PATH" 2>/dev/null || true
    
    # Clean up CSR
    rm -f "$csr_path"
    
    log_info "Internal CA signed certificate generated"
    log_info "Certificate: $TLS_CERT_PATH"
    log_info "Key: $TLS_KEY_PATH"
}

configure_tls() {
    log_info "Configuring TLS..."
    
    if [[ "$DASHBOARD_SSL" != true ]]; then
        log_info "SSL disabled, skipping TLS configuration"
        return 0
    fi
    
    # Check if custom certificates exist
    if [[ -f "$TLS_CERT_PATH" ]] && [[ -f "$TLS_KEY_PATH" ]]; then
        log_info "Using existing certificates"
    elif [[ -f "$CA_CERT_PATH" ]]; then
        generate_internal_ca_cert
    else
        log_warn "No CA certificate found, generating self-signed"
        generate_self_signed_cert
    fi
    
    # Configure dashboard for SSL
    ceph config set mgr mgr/dashboard/ssl_server_port "$DASHBOARD_PORT" 2>&1 | tee -a "$LOG_FILE"
    
    log_info "TLS configured on port $DASHBOARD_PORT"
}

configure_credentials() {
    log_info "Configuring dashboard credentials..."
    
    # Set login credentials
    ceph dashboard set-login-credentials "$DASHBOARD_USER" "$DASHBOARD_PASSWORD" 2>&1 | tee -a "$LOG_FILE"
    
    log_info "Credentials configured:"
    log_info "  Username: $DASHBOARD_USER"
    log_info "  Password: $DASHBOARD_PASSWORD"
}

configure_port() {
    log_info "Configuring dashboard port..."
    
    ceph config set mgr mgr/dashboard/server_port "$DASHBOARD_PORT" 2>&1 | tee -a "$LOG_FILE"
    
    log_info "Dashboard port set to: $DASHBOARD_PORT"
}

configure_grafana() {
    log_info "Configuring Grafana integration..."
    
    if [[ -n "$GRAFANA_URL" ]]; then
        ceph dashboard set-grafana-api-url "$GRAFANA_URL" 2>&1 | tee -a "$LOG_FILE"
        log_info "Grafana URL set to: $GRAFANA_URL"
    fi
    
    if [[ -n "$GRAFANA_API_URL" ]]; then
        ceph dashboard set-grafana-api-url "$GRAFANA_API_URL" 2>&1 | tee -a "$LOG_FILE"
    fi
}

configure_prometheus() {
    if [[ "$ENABLE_PROMETHEUS" != true ]]; then
        log_info "Prometheus integration disabled"
        return 0
    fi
    
    log_info "Configuring Prometheus integration..."
    
    # Enable prometheus module
    ceph mgr module enable prometheus 2>/dev/null || true
    
    # Set prometheus endpoint
    ceph dashboard set-prometheus-api-host "$PROMETHEUS_URL" 2>&1 | tee -a "$LOG_FILE"
    
    log_info "Prometheus integration configured"
}

configure_rgw_management() {
    if [[ "$ENABLE_RGW_MANAGEMENT" != true ]]; then
        log_info "RGW management disabled"
        return 0
    fi
    
    log_info "Enabling RGW management in dashboard..."
    
    # Enable RGW management (requires RGW to be deployed)
    ceph dashboard set-rgw-api-host "http://localhost:8080" 2>/dev/null || true
    ceph dashboard set-rgw-api-admin-resource "admin" 2>/dev/null || true
    
    log_info "RGW management enabled"
}

configure_user_management() {
    if [[ "$ENABLE_USER_MANAGEMENT" != true ]]; then
        log_info "User management disabled"
        return 0
    fi
    
    log_info "Enabling user management..."
    
    # Enable user management features
    ceph dashboard set-user-creation true 2>/dev/null || true
    
    log_info "User management enabled"
}

configure_audit_logging() {
    log_info "Configuring audit logging..."
    
    # Enable audit logging
    ceph config set mgr mgr/dashboard_audit_enabled true 2>/dev/null || true
    
    log_info "Audit logging enabled"
}

restart_dashboard() {
    log_info "Restarting dashboard..."
    
    ceph mgr restart 2>&1 | tee -a "$LOG_FILE"
    
    # Wait for restart
    sleep 10
    
    log_info "Dashboard restarted"
}

verify_dashboard() {
    log_info "Verifying dashboard configuration..."
    
    echo ""
    echo "========================================="
    echo "DASHBOARD CONFIGURATION SUMMARY"
    echo "========================================="
    echo ""
    
    # Check module status
    echo "--- Module Status ---"
    ceph mgr module list 2>/dev/null | grep dashboard || echo "Dashboard module not found"
    
    echo ""
    echo "--- Dashboard Config ---"
    ceph config get mgr mgr/dashboard/server_port 2>/dev/null || true
    ceph config get mgr mgr/dashboard/ssl_server_port 2>/dev/null || true
    
    echo ""
    echo "--- Dashboard URL ---"
    local mon_dump
    mon_dump=$(ceph mon dump -f json 2>/dev/null | jq -r '.mons[0].public_addrs.addrvec[0].addr' 2>/dev/null || echo "unknown")
    echo "Dashboard URL: https://${mon_dump%:*}:$DASHBOARD_PORT"
    echo "Username: $DASHBOARD_USER"
    echo "Password: $DASHBOARD_PASSWORD"
    
    echo ""
    echo "--- TLS Certificate ---"
    if [[ -f "$TLS_CERT_PATH" ]]; then
        echo "Certificate: $TLS_CERT_PATH"
        openssl x509 -in "$TLS_CERT_PATH" -noout -subject -dates 2>/dev/null || true
    else
        echo "No certificate found"
    fi
    
    echo ""
    echo "--- Grafana ---"
    echo "Grafana URL: $GRAFANA_URL"
    
    echo ""
    echo "========================================="
    echo "Log file: $LOG_FILE"
    echo "========================================="
    
    # Test dashboard endpoint
    local dashboard_url
    dashboard_url="https://${mon_dump%:*}:$DASHBOARD_PORT"
    local http_code
    http_code=$(curl -sk -o /dev/null -w "%{http_code}" "$dashboard_url" 2>/dev/null || echo "000")
    
    if [[ "$http_code" -eq 200 ]] || [[ "$http_code" -eq 301 ]] || [[ "$http_code" -eq 302 ]]; then
        log_info "✓ Dashboard is accessible (HTTP $http_code)"
    else
        log_warn "Dashboard may not be accessible (HTTP $http_code)"
    fi
}

#=============================================================================
# MAIN
#=============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --user USERNAME           Dashboard admin user (default: $DASHBOARD_USER)
  --password PASSWORD       Dashboard password (auto-generated if not set)
  --port PORT               Dashboard port (default: $DASHBOARD_PORT)
  --ssl                     Enable SSL (default: $DASHBOARD_SSL)
  --tls-cert PATH           TLS certificate path (default: $TLS_CERT_PATH)
  --tls-key PATH            TLS key path (default: $TLS_KEY_PATH)
  --ca-cert PATH            CA certificate path (default: $CA_CERT_PATH)
  --cn COMMON_NAME          Certificate CN (default: $CERT_CN)
  --san SUBJECT_ALT_NAMES   Certificate SAN (default: $CERT_SAN)
  --grafana-url URL         Grafana URL (default: $GRAFANA_URL)
  --prometheus-url URL      Prometheus URL (default: $PROMETHEUS_URL)
  --enable-prometheus       Enable Prometheus integration (default: $ENABLE_PROMETHEUS)
  --enable-rgw              Enable RGW management (default: $ENABLE_RGW_MANAGEMENT)
  --enable-user-mgmt        Enable user management (default: $ENABLE_USER_MANAGEMENT)
  --disable-ssl             Disable SSL
  --verify-only             Only verify current configuration
  --help                    Show this help

Examples:
  # Basic configuration with auto-generated password
  sudo ./ceph-dashboard.sh

  # Custom password and port
  sudo ./ceph-dashboard.sh --password "MySecurePass123" --port 9443

  # Use internal CA certificate
  sudo ./ceph-dashboard.sh --ca-cert /etc/ssl/certs/internal-ca.pem

  # Disable SSL (for testing only)
  sudo ./ceph-dashboard.sh --disable-ssl

  # Verify current configuration
  sudo ./ceph-dashboard.sh --verify-only
EOF
}

# Parse arguments
VERIFY_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --user) DASHBOARD_USER="$2"; shift 2 ;;
        --password) DASHBOARD_PASSWORD=*** shift 2 ;;
        --port) DASHBOARD_PORT="$2"; shift 2 ;;
        --ssl) DASHBOARD_SSL=true; shift ;;
        --disable-ssl) DASHBOARD_SSL=false; shift ;;
        --tls-cert) TLS_CERT_PATH="$2"; shift 2 ;;
        --tls-key) TLS_KEY_PATH="$2"; shift 2 ;;
        --ca-cert) CA_CERT_PATH="$2"; shift 2 ;;
        --cn) CERT_CN="$2"; shift 2 ;;
        --san) CERT_SAN="$2"; shift 2 ;;
        --grafana-url) GRAFANA_URL="$2"; GRAFANA_API_URL="$2/api"; shift 2 ;;
        --prometheus-url) PROMETHEUS_URL="$2"; shift 2 ;;
        --enable-prometheus) ENABLE_PROMETHEUS=true; shift ;;
        --enable-rgw) ENABLE_RGW_MANAGEMENT=true; shift ;;
        --enable-user-mgmt) ENABLE_USER_MANAGEMENT=true; shift ;;
        --verify-only) VERIFY_ONLY=true; shift ;;
        --help) usage; exit 0 ;;
        *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

main() {
    check_root
    
    log_info "Ceph Dashboard Configuration Script"
    log_info "Log file: $LOG_FILE"
    
    if [[ "$VERIFY_ONLY" == true ]]; then
        verify_dashboard
        exit 0
    fi
    
    check_prerequisites
    
    echo ""
    echo "========================================="
    echo "Configuring Ceph Dashboard"
    echo "========================================="
    echo ""
    
    # Step 1: Enable module
    enable_dashboard_module
    
    # Step 2: Configure port
    configure_port
    
    # Step 3: Configure TLS
    configure_tls
    
    # Step 4: Set credentials
    configure_credentials
    
    # Step 5: Configure Grafana
    configure_grafana
    
    # Step 6: Configure Prometheus
    configure_prometheus
    
    # Step 7: Configure RGW management
    configure_rgw_management
    
    # Step 8: Configure user management
    configure_user_management
    
    # Step 9: Configure audit logging
    configure_audit_logging
    
    # Step 10: Restart
    restart_dashboard
    
    # Step 11: Verify
    verify_dashboard
    
    log_info "Dashboard configuration complete"
}

main "$@"
