#!/bin/sh
#
# OpenWrt Time Machine Installation Script
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

# Detect and migrate old installations
detect_old_installation() {
    local found=0
    
    # Check for old backup directory
    if [ -d "/root/openwrt-backup" ] && [ ! -d "/root/time-machine" ]; then
        print_info "Found old backup directory at /root/openwrt-backup"
        print_info "Moving to new location /root/time-machine..."
        mv /root/openwrt-backup /root/time-machine
        print_success "Migrated backup directory"
        found=1
    fi
    
    # Check for old config
    if [ -d "$HOME/.backupmanager" ] && [ ! -d "$HOME/.timemachine" ]; then
        print_info "Found old config at ~/.backupmanager"
        print_info "Moving to new location ~/.timemachine..."
        mv "$HOME/.backupmanager" "$HOME/.timemachine"
        print_success "Migrated config directory"
        found=1
    fi
    
    # Return 0 if migrations were found (shell convention: 0 = success)
    # Return 1 if no migrations were found
    test $found -eq 1
}

# Update function
update() {
    echo "======================================="
    echo "OpenWrt Time Machine Update"
    echo "======================================="
    echo ""
    
    INSTALL_DIR="/root"
    SCRIPT_URL="https://raw.githubusercontent.com/cozbox/openwrt-timemachine/main/backup-manager.sh"
    
    print_info "Updating OpenWrt Time Machine..."
    
    # Backup current script
    if [ -f "$INSTALL_DIR/backup-manager.sh" ]; then
        print_info "Backing up current version..."
        cp "$INSTALL_DIR/backup-manager.sh" "$INSTALL_DIR/backup-manager.sh.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Current version backed up"
    fi
    
    # Download new version
    print_info "Downloading latest version..."
    
    if command -v curl >/dev/null 2>&1; then
        if curl -f -L -o "$INSTALL_DIR/backup-manager.sh" "$SCRIPT_URL" 2>/dev/null; then
            print_success "Downloaded latest version from GitHub"
        else
            print_error "Failed to download latest version"
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -O "$INSTALL_DIR/backup-manager.sh" "$SCRIPT_URL" 2>/dev/null; then
            print_success "Downloaded latest version from GitHub"
        else
            print_error "Failed to download latest version"
            exit 1
        fi
    else
        print_error "No download tool (curl/wget) available"
        exit 1
    fi
    
    # Make executable
    chmod +x "$INSTALL_DIR/backup-manager.sh"
    
    echo ""
    echo "======================================="
    print_success "Update complete!"
    echo "======================================="
    echo ""
    
    exit 0
}

# Uninstall function
uninstall() {
    echo "======================================="
    echo "OpenWrt Time Machine Uninstall"
    echo "======================================="
    echo ""
    
    print_info "Uninstalling OpenWrt Time Machine..."
    
    # Remove script
    if [ -f /root/backup-manager.sh ]; then
        rm -f /root/backup-manager.sh
        print_success "Removed backup-manager.sh"
    fi
    
    # Remove symlinks
    if [ -L /usr/bin/timemachine ]; then
        rm -f /usr/bin/timemachine
        print_success "Removed timemachine symlink"
    fi
    
    if [ -L /usr/bin/backup ]; then
        rm -f /usr/bin/backup
        print_success "Removed backup symlink"
    fi
    
    # Remove cron jobs
    if [ -f /etc/crontabs/root ]; then
        if grep -q "backup-manager.sh" /etc/crontabs/root 2>/dev/null; then
            print_info "Removing cron jobs..."
            if grep -v "backup-manager.sh" /etc/crontabs/root > /etc/crontabs/root.tmp; then
                mv /etc/crontabs/root.tmp /etc/crontabs/root
                /etc/init.d/cron restart 2>/dev/null || true
                print_success "Removed cron jobs"
            else
                rm -f /etc/crontabs/root.tmp
                print_warning "Failed to remove cron jobs"
            fi
        fi
    fi
    
    # Ask about config/backup data
    echo ""
    print_warning "Do you want to remove backup data and configuration? (y/n)"
    printf "This will delete: ~/.timemachine, /root/time-machine, ~/.backupmanager, /root/openwrt-backup\n"
    printf "Answer: "
    read answer
    
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        # Remove new locations
        if [ -d "$HOME/.timemachine" ]; then
            rm -rf "$HOME/.timemachine"
            print_success "Removed ~/.timemachine"
        fi
        
        if [ -d /root/time-machine ]; then
            rm -rf /root/time-machine
            print_success "Removed /root/time-machine"
        fi
        
        # Remove old locations
        if [ -d "$HOME/.backupmanager" ]; then
            rm -rf "$HOME/.backupmanager"
            print_success "Removed ~/.backupmanager"
        fi
        
        if [ -d /root/openwrt-backup ]; then
            rm -rf /root/openwrt-backup
            print_success "Removed /root/openwrt-backup"
        fi
    else
        print_info "Keeping backup data and configuration"
    fi
    
    echo ""
    echo "======================================="
    print_success "Uninstall complete!"
    echo "======================================="
    echo ""
    
    exit 0
}

# Show usage
show_usage() {
    echo "OpenWrt Time Machine Installation Script"
    echo ""
    echo "Usage:"
    echo "  $0              Install OpenWrt Time Machine"
    echo "  $0 --update     Update to latest version"
    echo "  $0 --uninstall  Uninstall OpenWrt Time Machine"
    echo "  $0 --help       Show this help message"
    echo ""
    exit 0
}

# Parse command line arguments
if [ $# -gt 0 ]; then
    case "$1" in
        --update)
            update
            ;;
        --uninstall)
            uninstall
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
fi

echo "======================================="
echo "OpenWrt Time Machine Installation"
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

# Detect and migrate old installations
print_info "Checking for old installations..."
if detect_old_installation; then
    echo ""
fi

# Download backup-manager.sh
INSTALL_DIR="/root"
SCRIPT_URL="https://raw.githubusercontent.com/cozbox/openwrt-timemachine/main/backup-manager.sh"

print_info "Downloading backup-manager.sh to $INSTALL_DIR..."

if [ -f "$INSTALL_DIR/backup-manager.sh" ]; then
    print_warning "backup-manager.sh already exists, backing up..."
    mv "$INSTALL_DIR/backup-manager.sh" "$INSTALL_DIR/backup-manager.sh.backup.$(date +%Y%m%d_%H%M%S)"
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
if [ -L /usr/bin/timemachine ]; then
    rm /usr/bin/timemachine
fi

ln -s "$INSTALL_DIR/backup-manager.sh" /usr/bin/timemachine
print_success "Created alias: timemachine"

echo ""
echo "======================================="
print_success "Installation complete!"
echo "======================================="
echo ""
echo "You can now run Time Machine using:"
echo "  timemachine"
echo "  or"
echo "  $INSTALL_DIR/backup-manager.sh"
echo ""
print_info "Starting Time Machine for first-time setup..."
echo ""

# Run the script
exec "$INSTALL_DIR/backup-manager.sh"
