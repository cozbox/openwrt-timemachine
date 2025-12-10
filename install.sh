#!/bin/sh
#
# OpenWrt Git Manager Installation Script
# Installs dependencies and sets up the git-manager.sh tool
#

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() {
    printf "${GREEN}✓ %s${NC}\n" "$1"
}

print_error() {
    printf "${RED}✗ %s${NC}\n" "$1"
}

print_warning() {
    printf "${YELLOW}⚠ %s${NC}\n" "$1"
}

print_info() {
    printf "→ %s\n" "$1"
}

echo "======================================="
echo "OpenWrt Git Manager Installation"
echo "======================================="
echo ""

# Check if running on OpenWrt
if [ ! -f /etc/openwrt_release ]; then
    print_warning "This script is designed for OpenWrt, but we'll continue anyway..."
fi

# Update package list
print_info "Updating package list..."
if opkg update; then
    print_success "Package list updated"
else
    print_error "Failed to update package list"
    exit 1
fi

# Install dependencies
print_info "Installing dependencies..."

PACKAGES="git whiptail openssh-client openssh-keygen curl"

for pkg in $PACKAGES; do
    print_info "Installing $pkg..."
    if opkg install "$pkg" 2>/dev/null || opkg list-installed | grep -q "^$pkg "; then
        print_success "$pkg installed"
    else
        print_warning "$pkg may already be installed or failed to install"
    fi
done

# Download git-manager.sh
INSTALL_DIR="/root"
SCRIPT_URL="https://raw.githubusercontent.com/niyisurvey/gitwrt/main/git-manager.sh"

print_info "Downloading git-manager.sh to $INSTALL_DIR..."

if [ -f "$INSTALL_DIR/git-manager.sh" ]; then
    print_warning "git-manager.sh already exists, backing up..."
    mv "$INSTALL_DIR/git-manager.sh" "$INSTALL_DIR/git-manager.sh.backup"
fi

# Try to download from GitHub, fallback to local copy if available
if curl -f -L -o "$INSTALL_DIR/git-manager.sh" "$SCRIPT_URL" 2>/dev/null; then
    print_success "Downloaded git-manager.sh from GitHub"
elif [ -f "./git-manager.sh" ]; then
    print_warning "Download failed, using local copy..."
    cp "./git-manager.sh" "$INSTALL_DIR/git-manager.sh"
    print_success "Copied local git-manager.sh"
else
    print_error "Failed to download git-manager.sh and no local copy found"
    exit 1
fi

# Make executable
chmod +x "$INSTALL_DIR/git-manager.sh"
print_success "Made git-manager.sh executable"

# Create symbolic link for easy access
if [ ! -L /usr/bin/git-manager ]; then
    ln -s "$INSTALL_DIR/git-manager.sh" /usr/bin/git-manager
    print_success "Created symbolic link: /usr/bin/git-manager"
fi

echo ""
echo "======================================="
print_success "Installation complete!"
echo "======================================="
echo ""
echo "You can now run the Git Manager using:"
echo "  git-manager"
echo "  or"
echo "  $INSTALL_DIR/git-manager.sh"
echo ""
print_info "Starting Git Manager for first-time setup..."
echo ""

# Run the script
exec "$INSTALL_DIR/git-manager.sh"
