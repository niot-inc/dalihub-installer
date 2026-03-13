#!/bin/bash
#
# Tailscale Uninstaller for DALIHub Remote Access
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
cat << "EOF"
    ____  ___    __    ____  __  __      __
   / __ \/   |  / /   /  _/ / / / /_  __/ /_
  / / / / /| | / /    / /  / /_/ / / / / __ \
 / /_/ / ___ |/ /____/ /  / __  / /_/ / /_/ /
/_____/_/  |_/_____/___/ /_/ /_/\__,_/_.___/

EOF
echo -e "${NC}"
echo -e "${YELLOW}Tailscale Uninstaller${NC}"
echo ""
echo "This will:"
echo "  - Disconnect from Tailscale network"
echo "  - Stop and disable Tailscale service"
echo "  - Remove Tailscale package"
echo ""
read -p "Continue? [y/N] " -n 1 -r < /dev/tty
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

# Disconnect from Tailscale
echo -e "${GREEN}[1/3]${NC} Disconnecting from Tailscale..."
if command -v tailscale &> /dev/null; then
    tailscale down 2>/dev/null || true
    tailscale logout 2>/dev/null || true
fi
echo "  Done"

# Stop service
echo -e "${GREEN}[2/3]${NC} Stopping Tailscale service..."
systemctl stop tailscaled 2>/dev/null || true
systemctl disable tailscaled 2>/dev/null || true
echo "  Done"

# Remove package
echo ""
read -p "$(echo -e "${GREEN}[3/3]${NC}") Remove Tailscale package? [Y/n] " -n 1 -r < /dev/tty
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    # Detect package manager and remove
    if command -v apt-get &> /dev/null; then
        apt-get remove -y tailscale 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        # Remove Tailscale repo
        rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg
        rm -f /etc/apt/sources.list.d/tailscale.list
    elif command -v yum &> /dev/null; then
        yum remove -y tailscale 2>/dev/null || true
        rm -f /etc/yum.repos.d/tailscale.repo
    elif command -v dnf &> /dev/null; then
        dnf remove -y tailscale 2>/dev/null || true
        rm -f /etc/yum.repos.d/tailscale.repo
    else
        echo -e "${YELLOW}  Could not detect package manager. Please remove tailscale manually.${NC}"
    fi
    echo "  Package removed"
else
    echo "  Keeping package"
fi

# Clean up state
rm -rf /var/lib/tailscale 2>/dev/null || true

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Tailscale uninstalled${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "  The device has been removed from your Tailscale network."
echo "  You can also remove it from the admin console:"
echo "  https://login.tailscale.com/admin/machines"
echo ""
