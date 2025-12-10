#!/bin/sh
#
# OpenWrt Backup Recovery Script
# Minimal disaster recovery for factory reset routers
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

print_info() {
    printf "→ %s\n" "$1"
}

echo "======================================="
echo "OpenWrt Backup Recovery"
echo "======================================="
echo ""
echo "This script helps you restore your router"
echo "after a factory reset or on a new router."
echo ""

# Check if running on OpenWrt
if [ ! -f /etc/openwrt_release ]; then
    print_error "This script is designed for OpenWrt routers"
    exit 1
fi

# Install dependencies
print_info "Installing required tools..."
if opkg update >/dev/null 2>&1; then
    print_success "Package list updated"
else
    print_error "Failed to update package list. Check your internet connection."
    exit 1
fi

for pkg in git openssh-client openssh-keygen; do
    if opkg install "$pkg" >/dev/null 2>&1 || opkg list-installed | grep -q "^$pkg "; then
        print_success "$pkg installed"
    else
        print_error "Failed to install $pkg"
        exit 1
    fi
done

# Get GitHub username
echo ""
print_info "Enter your GitHub username:"
read -r GITHUB_USERNAME

if [ -z "$GITHUB_USERNAME" ]; then
    print_error "GitHub username is required"
    exit 1
fi

# Set up SSH key
SSH_KEY_PATH="$HOME/.ssh/id_ed25519"

if [ ! -f "$SSH_KEY_PATH" ]; then
    print_info "Creating security key..."
    mkdir -p "$HOME/.ssh"
    
    if ssh-keygen -t ed25519 -N "" -f "$SSH_KEY_PATH" -C "openwrt-recovery" >/dev/null 2>&1; then
        print_success "Security key created"
    else
        print_error "Failed to create security key"
        exit 1
    fi
    
    echo ""
    echo "======================================="
    echo "Add this key to GitHub:"
    echo "======================================="
    cat "$SSH_KEY_PATH.pub"
    echo ""
    echo "1. Go to: https://github.com/settings/ssh/new"
    echo "2. Paste the key above"
    echo "3. Click 'Add SSH key'"
    echo ""
    echo "Press ENTER when done..."
    read -r dummy
else
    print_info "Using existing security key"
fi

# Test GitHub connection
print_info "Testing connection to GitHub..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    print_success "Connected to GitHub!"
else
    print_error "Can't connect to GitHub. Make sure you added the SSH key."
    exit 1
fi

# Try to find backup repositories
print_info "Looking for your backup repositories..."

BACKUP_DIR="/root/openwrt-backup"

# Try common repository names
REPO_NAMES="openwrt-backup openwrt-backup-main-router openwrt-backup-living-room-router"

FOUND_REPO=""
for repo_name in $REPO_NAMES; do
    repo_url="git@github.com:$GITHUB_USERNAME/$repo_name.git"
    
    if git ls-remote "$repo_url" >/dev/null 2>&1; then
        FOUND_REPO="$repo_url"
        print_success "Found backup: $repo_name"
        
        # Ask if this is the right one
        echo ""
        print_info "Is this the backup you want to restore? (y/n)"
        read -r answer
        
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            break
        else
            FOUND_REPO=""
        fi
    fi
done

# If no repo found, ask for manual input
if [ -z "$FOUND_REPO" ]; then
    echo ""
    print_info "Couldn't auto-detect your backup."
    print_info "Enter your backup repository name (e.g., openwrt-backup):"
    read -r repo_name
    
    if [ -z "$repo_name" ]; then
        print_error "Repository name is required"
        exit 1
    fi
    
    FOUND_REPO="git@github.com:$GITHUB_USERNAME/$repo_name.git"
fi

# Clone the repository
print_info "Downloading your backup..."

if [ -d "$BACKUP_DIR" ]; then
    print_info "Backup directory exists, backing up..."
    mv "$BACKUP_DIR" "$BACKUP_DIR.old.$(date +%s)"
fi

if git clone "$FOUND_REPO" "$BACKUP_DIR" >/dev/null 2>&1; then
    print_success "Backup downloaded!"
else
    print_error "Failed to download backup from: $FOUND_REPO"
    exit 1
fi

# Restore configuration files
print_info "Restoring settings..."

if [ -d "$BACKUP_DIR/etc/config" ]; then
    cp -r "$BACKUP_DIR/etc/config/"* /etc/config/ 2>/dev/null || true
    print_success "Settings restored"
else
    print_error "No settings found in backup"
fi

# Check for package list
if [ -f "$BACKUP_DIR/package-list.txt" ]; then
    echo ""
    print_info "Found package list with $(wc -l < "$BACKUP_DIR/package-list.txt") packages"
    print_info "Do you want to reinstall these packages? (y/n)"
    read -r answer
    
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        print_info "Installing packages..."
        
        while read -r package; do
            pkg_name=$(echo "$package" | awk '{print $1}')
            
            if opkg install "$pkg_name" >/dev/null 2>&1; then
                print_success "Installed: $pkg_name"
            else
                print_info "Skipped: $pkg_name (already installed or not available)"
            fi
        done < "$BACKUP_DIR/package-list.txt"
        
        print_success "Package installation complete"
    fi
fi

# Install backup manager
print_info "Installing Backup Manager..."

SCRIPT_URL="https://raw.githubusercontent.com/niyisurvey/gitwrt/main/backup-manager.sh"

if command -v curl >/dev/null 2>&1; then
    curl -f -L -o /root/backup-manager.sh "$SCRIPT_URL" >/dev/null 2>&1 || true
elif command -v wget >/dev/null 2>&1; then
    wget -O /root/backup-manager.sh "$SCRIPT_URL" >/dev/null 2>&1 || true
fi

if [ -f /root/backup-manager.sh ]; then
    chmod +x /root/backup-manager.sh
    ln -sf /root/backup-manager.sh /usr/bin/backup
    print_success "Backup Manager installed"
fi

echo ""
echo "======================================="
print_success "Recovery Complete!"
echo "======================================="
echo ""
echo "Your router settings have been restored."
echo ""
echo "Important:"
echo "• You should reboot your router now"
echo "• Run 'backup' to access the Backup Manager"
echo "• Your backup is located at: $BACKUP_DIR"
echo ""
print_info "Reboot now? (y/n)"
read -r answer

if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    print_info "Rebooting..."
    reboot
fi
