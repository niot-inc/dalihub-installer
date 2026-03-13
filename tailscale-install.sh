#!/bin/bash
#
# Tailscale Installer for DALIHub Remote Access
#
# One-line installation:
#   curl -sSL https://raw.githubusercontent.com/niot-inc/dalihub-installer/main/tailscale-install.sh | sudo bash -s -- --auth-key 'tskey-auth-xxxxx'
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
AUTH_KEY=""
TAILSCALE_TAGS="tag:dalihub"
TAILSCALE_HOSTNAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --auth-key) AUTH_KEY="$2"; shift 2 ;;
        --tags) TAILSCALE_TAGS="$2"; shift 2 ;;
        --hostname) TAILSCALE_HOSTNAME="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --auth-key KEY       Tailscale auth key (required)"
            echo "  --tags TAGS          Tailscale ACL tags (default: tag:dalihub)"
            echo "  --hostname NAME      Tailscale hostname (default: dalihub-<hardware-id>)"
            exit 0
            ;;
        *) shift ;;
    esac
done

# ============================================================================
# Helper Functions
# ============================================================================

print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
    ____  ___    __    ____  __  __      __
   / __ \/   |  / /   /  _/ / / / /_  __/ /_
  / / / / /| | / /    / /  / /_/ / / / / __ \
 / /_/ / ___ |/ /____/ /  / __  / /_/ / /_/ /
/_____/_/  |_/_____/___/ /_/ /_/\__,_/_.___/

EOF
    echo -e "${NC}"
    echo -e "${BLUE}Tailscale Remote Access - Installer${NC}"
    echo ""
}

log_step() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# ============================================================================
# Check Functions
# ============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Please run: sudo bash tailscale-install.sh --auth-key 'YOUR_KEY'"
        exit 1
    fi
}

check_auth_key() {
    if [ -z "$AUTH_KEY" ]; then
        log_error "Auth key is required"
        echo ""
        echo "Usage: sudo bash tailscale-install.sh --auth-key 'tskey-auth-xxxxx'"
        echo ""
        echo "Get your auth key from: https://login.tailscale.com/admin/settings/keys"
        exit 1
    fi
}

# Generate hardware ID (matches DALIHub HardwareIdService logic)
# - Raspberry Pi: SHA256(CPU Serial) → first 16 chars uppercase
# - Other Linux:  SHA256(hostname:MAC) → first 16 chars uppercase
detect_hostname() {
    if [ -n "$TAILSCALE_HOSTNAME" ]; then
        log_step "Hostname: $TAILSCALE_HOSTNAME (user-specified)"
        return
    fi

    local combined=""

    # Try Raspberry Pi CPU Serial from /proc/cpuinfo
    if [ -f /proc/cpuinfo ]; then
        local cpu_serial
        cpu_serial=$(grep -i 'Serial' /proc/cpuinfo | awk -F': ' '{print $2}' | tr -d '[:space:]')
        if [ -n "$cpu_serial" ]; then
            combined="$cpu_serial"
            log_info "Using CPU Serial for hardware ID"
        fi
    fi

    # Fallback: hostname + MAC address
    if [ -z "$combined" ]; then
        local sys_hostname
        sys_hostname=$(hostname)
        local mac_address=""

        # Find primary MAC address (priority: eth0, en0, wlan0, enp0s3, ens33)
        for iface in eth0 en0 wlan0 enp0s3 ens33; do
            if [ -f "/sys/class/net/${iface}/address" ]; then
                mac_address=$(cat "/sys/class/net/${iface}/address")
                if [ "$mac_address" != "00:00:00:00:00:00" ]; then
                    break
                fi
                mac_address=""
            fi
        done

        # Fallback: any non-lo interface
        if [ -z "$mac_address" ]; then
            for iface_path in /sys/class/net/*/address; do
                local iface_name
                iface_name=$(basename "$(dirname "$iface_path")")
                [ "$iface_name" = "lo" ] && continue
                mac_address=$(cat "$iface_path")
                if [ "$mac_address" != "00:00:00:00:00:00" ]; then
                    break
                fi
                mac_address=""
            done
        fi

        combined="${sys_hostname}:${mac_address:-unknown-mac}"
        log_info "Using hostname + MAC for hardware ID"
    fi

    # SHA256 hash → first 16 chars → uppercase (matches HardwareIdService)
    local hw_id
    hw_id=$(printf '%s' "$combined" | sha256sum | head -c 16 | tr '[:lower:]' '[:upper:]')

    TAILSCALE_HOSTNAME="dalihub-${hw_id}"
    log_step "Hostname: $TAILSCALE_HOSTNAME (hardware ID)"
}

# ============================================================================
# Tailscale Installation
# ============================================================================

install_tailscale() {
    if command -v tailscale &> /dev/null; then
        TAILSCALE_VERSION=$(tailscale version | head -1)
        log_step "Tailscale already installed: $TAILSCALE_VERSION"
    else
        log_info "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
        log_step "Tailscale installed"
    fi

    # Enable and start tailscaled
    systemctl enable tailscaled
    systemctl start tailscaled
    log_step "Tailscale service started"
}

connect_tailscale() {
    log_info "Connecting to Tailscale network..."

    tailscale up \
        --auth-key="${AUTH_KEY}?ephemeral=false&preauthorized=true" \
        --advertise-tags="${TAILSCALE_TAGS}" \
        --hostname="${TAILSCALE_HOSTNAME}" \
        --ssh

    log_step "Connected to Tailscale network"
}

# ============================================================================
# Completion
# ============================================================================

print_completion() {
    # Get Tailscale IP
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "<pending>")
    HOSTNAME=$(tailscale status --self --json 2>/dev/null | grep -o '"DNSName":"[^"]*"' | head -1 | cut -d'"' -f4 || hostname)

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Tailscale installation complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Tailscale IP:  $TAILSCALE_IP"
    echo "  Hostname:      $HOSTNAME"
    echo "  Tags:          $TAILSCALE_TAGS"
    echo ""
    echo "  Commands:"
    echo "    tailscale status       # Check connection"
    echo "    tailscale ip           # Show Tailscale IP"
    echo ""
    echo -e "  ${CYAN}Admin Console:${NC} https://login.tailscale.com/admin/machines"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_banner
    check_root
    check_auth_key
    detect_hostname
    install_tailscale
    connect_tailscale
    print_completion
}

main "$@"
