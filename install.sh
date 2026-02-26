#!/bin/bash
#
# DALIHub Installer
#
# One-line installation:
#   curl -sSL https://raw.githubusercontent.com/niot-inc/dalihub-installer/main/install.sh | sudo bash
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
INSTALL_DIR="${DALIHUB_INSTALL_DIR:-/opt/dalihub}"
REPO_RAW_URL="https://raw.githubusercontent.com/niot-inc/dalihub-installer/main"

# Flags
REBOOT_REQUIRED=false
IS_RASPBERRY_PI=false
SKIP_UART=false
SKIP_DOCKER=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-uart) SKIP_UART=true; shift ;;
        --skip-docker) SKIP_DOCKER=true; shift ;;
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --skip-uart      Skip UART setup (for non-Pi or manual setup)"
            echo "  --skip-docker    Skip Docker installation"
            echo "  --install-dir    Installation directory (default: /opt/dalihub)"
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
    echo -e "${BLUE}DALI Lighting Control System - Installer${NC}"
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

# Generate random string for tokens
generate_token() {
    head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32
}

# Detect system timezone
detect_timezone() {
    # Try timedatectl first (systemd)
    if command -v timedatectl &> /dev/null; then
        TZ=$(timedatectl show --property=Timezone --value 2>/dev/null)
        if [ -n "$TZ" ]; then
            echo "$TZ"
            return
        fi
    fi

    # Try /etc/timezone (Debian-based)
    if [ -f /etc/timezone ]; then
        cat /etc/timezone
        return
    fi

    # Try /etc/localtime symlink
    if [ -L /etc/localtime ]; then
        readlink /etc/localtime | sed 's|.*/zoneinfo/||'
        return
    fi

    # Default to UTC
    echo "UTC"
}

# ============================================================================
# Check Functions
# ============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Please run: sudo bash install.sh"
        exit 1
    fi
}

detect_platform() {
    log_info "Detecting platform..."

    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        log_step "OS: $PRETTY_NAME"
    else
        log_error "Cannot detect OS"
        exit 1
    fi

    # Check if Raspberry Pi
    if [ -f /proc/device-tree/model ]; then
        MODEL=$(tr -d '\0' < /proc/device-tree/model)
        if [[ "$MODEL" == *"Raspberry Pi"* ]]; then
            IS_RASPBERRY_PI=true
            log_step "Hardware: $MODEL"
        fi
    fi

    # Check architecture
    ARCH=$(uname -m)
    log_step "Architecture: $ARCH"

    # Detect timezone
    SYSTEM_TZ=$(detect_timezone)
    log_step "Timezone: $SYSTEM_TZ"
}

# ============================================================================
# Docker Installation
# ============================================================================

install_docker() {
    if [ "$SKIP_DOCKER" = true ]; then
        log_warn "Skipping Docker installation (--skip-docker)"
        return
    fi

    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | cut -d ' ' -f3 | cut -d ',' -f1)
        log_step "Docker already installed: v$DOCKER_VERSION"
    else
        log_info "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        log_step "Docker installed"
    fi

    # Add user to docker group
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        if ! groups "$SUDO_USER" | grep -q docker; then
            usermod -aG docker "$SUDO_USER"
            log_step "Added $SUDO_USER to docker group"
        fi
    fi

    # Enable and start Docker
    systemctl enable docker
    systemctl start docker

    # Check Docker Compose
    if docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version --short)
        log_step "Docker Compose available: v$COMPOSE_VERSION"
    else
        log_info "Installing Docker Compose plugin..."
        apt-get update -qq
        apt-get install -y -qq docker-compose-plugin
        log_step "Docker Compose installed"
    fi
}

# ============================================================================
# UART Setup (Raspberry Pi)
# ============================================================================

setup_uart() {
    if [ "$SKIP_UART" = true ]; then
        log_warn "Skipping UART setup (--skip-uart)"
        return
    fi

    if [ "$IS_RASPBERRY_PI" != true ]; then
        log_warn "Not a Raspberry Pi, skipping UART setup"
        return
    fi

    log_info "Configuring UART for DALI HAT..."

    # Find config.txt
    CFG_FILE=""
    if [ -f /boot/firmware/config.txt ]; then
        CFG_FILE="/boot/firmware/config.txt"
    elif [ -f /boot/config.txt ]; then
        CFG_FILE="/boot/config.txt"
    else
        log_error "config.txt not found!"
        return
    fi

    # Backup config.txt
    cp "$CFG_FILE" "${CFG_FILE}.backup.$(date +%Y%m%d-%H%M%S)"

    # Enable UART
    if grep -q "^enable_uart" "$CFG_FILE"; then
        sed -i 's/^enable_uart=.*/enable_uart=1/' "$CFG_FILE"
    else
        echo "enable_uart=1" >> "$CFG_FILE"
    fi

    # Disable Bluetooth (to free up UART)
    if ! grep -q "^dtoverlay=disable-bt" "$CFG_FILE"; then
        echo "dtoverlay=disable-bt" >> "$CFG_FILE"
    fi

    # Disable Bluetooth services
    systemctl stop hciuart 2>/dev/null || true
    systemctl disable hciuart 2>/dev/null || true
    systemctl stop bluetooth 2>/dev/null || true
    systemctl disable bluetooth 2>/dev/null || true

    # Disable serial console getty
    systemctl stop serial-getty@ttyAMA0.service 2>/dev/null || true
    systemctl disable serial-getty@ttyAMA0.service 2>/dev/null || true
    systemctl stop serial-getty@ttyS0.service 2>/dev/null || true
    systemctl disable serial-getty@ttyS0.service 2>/dev/null || true

    # Remove console from cmdline.txt
    CMDLINE_FILE=""
    if [ -f /boot/firmware/cmdline.txt ]; then
        CMDLINE_FILE="/boot/firmware/cmdline.txt"
    elif [ -f /boot/cmdline.txt ]; then
        CMDLINE_FILE="/boot/cmdline.txt"
    fi

    if [ -n "$CMDLINE_FILE" ]; then
        cp "$CMDLINE_FILE" "${CMDLINE_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
        sed -i 's/console=serial0,[0-9]* //g' "$CMDLINE_FILE"
        sed -i 's/console=ttyAMA0,[0-9]* //g' "$CMDLINE_FILE"
        sed -i 's/console=ttyS0,[0-9]* //g' "$CMDLINE_FILE"
    fi

    log_step "UART configured for DALI HAT"
    REBOOT_REQUIRED=true
}

# ============================================================================
# DALIHub Installation
# ============================================================================

create_directories() {
    log_info "Creating installation directory..."

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/config"
    mkdir -p "$INSTALL_DIR/data"
    mkdir -p "$INSTALL_DIR/logs"
    mkdir -p "$INSTALL_DIR/mosquitto/config"
    mkdir -p "$INSTALL_DIR/mosquitto/data"
    mkdir -p "$INSTALL_DIR/mosquitto/log"

    # Set ownership
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        chown -R "$SUDO_USER:$SUDO_USER" "$INSTALL_DIR"
    fi

    log_step "Created $INSTALL_DIR"
}

create_env_file() {
    log_info "Generating configuration..."

    cd "$INSTALL_DIR"

    # Skip if .env already exists (upgrade scenario)
    if [ -f .env ]; then
        log_warn ".env already exists, keeping existing configuration"
        return
    fi

    # Generate Watchtower API token
    WATCHTOWER_TOKEN=$(generate_token)

    # Create minimal .env file
    cat > .env << EOF
# DALIHub Configuration
# Generated by installer on $(date)

# Timezone (auto-detected from system)
TZ=${SYSTEM_TZ}

# Watchtower API token (auto-generated, do not change)
WATCHTOWER_TOKEN=${WATCHTOWER_TOKEN}
EOF

    log_step "Generated .env configuration"
}

download_files() {
    log_info "Downloading configuration files..."

    cd "$INSTALL_DIR"

    # Download docker-compose.yml
    curl -fsSL "$REPO_RAW_URL/docker-compose.yml" -o docker-compose.yml
    log_step "Downloaded docker-compose.yml"

    # Download mosquitto config
    curl -fsSL "$REPO_RAW_URL/mosquitto/config/mosquitto.conf" -o mosquitto/config/mosquitto.conf
    log_step "Downloaded mosquitto.conf"

    # Set ownership
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        chown -R "$SUDO_USER:$SUDO_USER" "$INSTALL_DIR"
    fi
}

setup_mosquitto() {
    log_info "Setting up MQTT broker..."

    cd "$INSTALL_DIR"

    # Fixed credentials (dalihub/dalihub)
    MQTT_USER="dalihub"
    MQTT_PASS="dalihub"

    # Generate password file using mosquitto container
    docker run --rm \
        -v "$INSTALL_DIR/mosquitto/config:/mosquitto/config" \
        eclipse-mosquitto:2.1.2-alpine \
        mosquitto_passwd -b -c /mosquitto/config/passwd "$MQTT_USER" "$MQTT_PASS"

    # Set ownership for mosquitto user (UID 1883 in container)
    chown -R 1883:1883 "$INSTALL_DIR/mosquitto"

    log_step "MQTT credentials configured ($MQTT_USER/$MQTT_PASS)"
}

start_dalihub() {
    log_info "Starting DALIHub..."

    cd "$INSTALL_DIR"

    # Pull images
    docker compose pull

    # Start all services
    docker compose up -d

    log_step "DALIHub started"
}

# ============================================================================
# Completion
# ============================================================================

print_completion() {
    # Get IP address
    IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$IP_ADDR" ]; then
        IP_ADDR="<your-ip>"
    fi

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  DALIHub installation complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Installation: $INSTALL_DIR"
    echo ""
    echo -e "  ${CYAN}Web UI:${NC}  http://${IP_ADDR}:3000"
    echo -e "  ${CYAN}MQTT:${NC}    mqtt://${IP_ADDR}:1883"
    echo "           Username: dalihub"
    echo "           Password: dalihub"
    echo ""
    echo "  Commands:"
    echo "    cd $INSTALL_DIR"
    echo "    docker compose logs -f       # View logs"
    echo "    docker compose restart       # Restart"
    echo ""
    echo -e "  ${CYAN}Updates:${NC} Managed via Web UI (Settings > Updates)"
    echo ""

    if [ "$REBOOT_REQUIRED" = true ]; then
        echo -e "${YELLOW}  ⚠ REBOOT REQUIRED to enable UART for DALI HAT!${NC}"
        echo ""
        read -p "  Reboot now? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Rebooting..."
            reboot
        else
            echo ""
            echo "  Run 'sudo reboot' when ready."
        fi
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_banner
    check_root
    detect_platform
    install_docker
    setup_uart
    create_directories
    create_env_file
    download_files
    setup_mosquitto
    start_dalihub
    print_completion
}

main "$@"
