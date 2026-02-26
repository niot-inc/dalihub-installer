#!/bin/bash
#
# DALIHub Uninstaller
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="${DALIHUB_INSTALL_DIR:-/opt/dalihub}"

echo -e "${CYAN}"
cat << "EOF"
    ____  ___    __    ____  __  __      __
   / __ \/   |  / /   /  _/ / / / /_  __/ /_
  / / / / /| | / /    / /  / /_/ / / / / __ \
 / /_/ / ___ |/ /____/ /  / __  / /_/ / /_/ /
/_____/_/  |_/_____/___/ /_/ /_/\__,_/_.___/

EOF
echo -e "${NC}"
echo -e "${YELLOW}Uninstaller${NC}"
echo ""
echo "This will:"
echo "  - Stop and remove all DALIHub containers"
echo "  - Optionally remove data and configuration"
echo "  - Optionally reset UART settings"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

echo ""

# Stop containers
echo -e "${GREEN}[1/4]${NC} Stopping containers..."
if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    cd "$INSTALL_DIR"
    docker compose down --remove-orphans 2>/dev/null || true
fi
echo "  Done"

# Remove data
echo ""
echo -e "${GREEN}[2/4]${NC} Data removal options:"
echo "  1) Keep all data (config, logs, etc.)"
echo "  2) Remove everything except config"
echo "  3) Remove everything"
read -p "  Choose [1-3]: " -n 1 -r
echo

case $REPLY in
    2)
        rm -rf "$INSTALL_DIR/data"
        rm -rf "$INSTALL_DIR/logs"
        rm -rf "$INSTALL_DIR/mosquitto/data"
        rm -rf "$INSTALL_DIR/mosquitto/log"
        rm -f "$INSTALL_DIR/docker-compose.yml"
        echo "  Removed data, kept config"
        ;;
    3)
        rm -rf "$INSTALL_DIR"
        echo "  Removed $INSTALL_DIR"
        ;;
    *)
        echo "  Keeping all data"
        ;;
esac

# Remove Docker images (optional)
echo ""
read -p "$(echo -e "${GREEN}[3/4]${NC}") Remove Docker images? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker rmi ghcr.io/niot-inc/dalihub 2>/dev/null || true
    docker rmi eclipse-mosquitto:2.1.2-alpine 2>/dev/null || true
    docker rmi containrrr/watchtower 2>/dev/null || true
    echo "  Images removed"
else
    echo "  Keeping images"
fi

# Reset UART
echo ""
read -p "$(echo -e "${GREEN}[4/4]${NC}") Reset UART settings (re-enable Bluetooth)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Find config.txt
    CFG_FILE=""
    if [ -f /boot/firmware/config.txt ]; then
        CFG_FILE="/boot/firmware/config.txt"
    elif [ -f /boot/config.txt ]; then
        CFG_FILE="/boot/config.txt"
    fi

    if [ -n "$CFG_FILE" ]; then
        # Look for backup
        LATEST_BACKUP=$(ls -t "${CFG_FILE}.backup."* 2>/dev/null | head -1 || true)
        if [ -n "$LATEST_BACKUP" ]; then
            read -p "  Restore from backup ($LATEST_BACKUP)? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cp "$LATEST_BACKUP" "$CFG_FILE"
                echo "  Restored config.txt"
            fi
        else
            sed -i '/^enable_uart=1$/d' "$CFG_FILE" 2>/dev/null || true
            sed -i '/^dtoverlay=disable-bt$/d' "$CFG_FILE" 2>/dev/null || true
            echo "  Removed UART settings"
        fi
    fi

    # Re-enable services
    systemctl enable hciuart 2>/dev/null || true
    systemctl enable bluetooth 2>/dev/null || true
    systemctl enable serial-getty@ttyAMA0.service 2>/dev/null || true

    echo ""
    echo -e "${YELLOW}  Reboot required to apply UART changes${NC}"
else
    echo "  Keeping UART settings"
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  DALIHub uninstalled${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
