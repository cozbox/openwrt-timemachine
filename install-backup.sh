#!/bin/sh
#
# OpenWrt Backup Manager Installation Script
# Installs dependencies and sets up the backup-manager.sh tool
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
echo "OpenWrt Backup Manager Installation"
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

PACKAGES="git whiptail openssh-client openssh-keygen"

for pkg in $PACKAGES; do
    print_info "Installing $pkg..."
    if opkg install "$pkg" 2>/dev/null || opkg list-installed | grep -q "^$pkg "; then
        print_success "$pkg installed"
    else
        print_warning "$pkg may already be installed or failed to install"
    fi
done

# Download backup-manager.sh
INSTALL_DIR="/root"
SCRIPT_URL="https://raw.githubusercontent.com/niyisurvey/gitwrt/main/backup-manager.sh"

print_info "Downloading backup-manager.sh to $INSTALL_DIR..."

if [ -f "$INSTALL_DIR/backup-manager.sh" ]; then
    print_warning "backup-manager.sh already exists, backing up..."
    mv "$INSTALL_DIR/backup-manager.sh" "$INSTALL_DIR/backup-manager.sh.backup.$(date +%s)"
fi

# Try to download from GitHub, fallback to local copy if available
if command -v curl >/dev/null 2>&1; then
    if curl -f -L -o "$INSTALL_DIR/backup-manager.sh" "$SCRIPT_URL" 2>/dev/null; then
        print_success "Downloaded backup-manager.sh from GitHub"
    elif [ -f "./backup-manager.sh" ]; then
        print_warning "Download failed, using local copy..."
        cp "./backup-manager.sh" "$INSTALL_DIR/backup-manager.sh"
        print_success "Copied local backup-manager.sh"
    else
        print_error "Failed to download backup-manager.sh and no local copy found"
        exit 1
    fi
elif command -v wget >/dev/null 2>&1; then
    if wget -O "$INSTALL_DIR/backup-manager.sh" "$SCRIPT_URL" 2>/dev/null; then
        print_success "Downloaded backup-manager.sh from GitHub"
    elif [ -f "./backup-manager.sh" ]; then
        print_warning "Download failed, using local copy..."
        cp "./backup-manager.sh" "$INSTALL_DIR/backup-manager.sh"
        print_success "Copied local backup-manager.sh"
    else
        print_error "Failed to download backup-manager.sh and no local copy found"
        exit 1
    fi
elif [ -f "./backup-manager.sh" ]; then
    print_info "No download tool available, using local copy..."
    cp "./backup-manager.sh" "$INSTALL_DIR/backup-manager.sh"
    print_success "Copied local backup-manager.sh"
else
    print_error "No download tool (curl/wget) available and no local copy found"
    exit 1
fi

# Make executable
chmod +x "$INSTALL_DIR/backup-manager.sh"
print_success "Made backup-manager.sh executable"

# Create symbolic link for easy access
if [ -L /usr/bin/backup ]; then
    rm /usr/bin/backup
fi

ln -s "$INSTALL_DIR/backup-manager.sh" /usr/bin/backup
print_success "Created alias: backup"

echo ""
echo "======================================="
print_success "Installation complete!"
echo "======================================="
echo ""
echo "You can now run the Backup Manager using:"
echo "  backup"
echo "  or"
echo "  $INSTALL_DIR/backup-manager.sh"
echo ""
print_info "Starting Backup Manager for first-time setup..."
echo ""

# Run the script
exec "$INSTALL_DIR/backup-manager.sh"
