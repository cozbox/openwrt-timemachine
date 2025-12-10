#!/bin/sh
#
# OpenWrt Backup Manager
# A user-friendly backup tool for OpenWrt routers
# NO GIT TERMINOLOGY - designed for users who have never heard of git
#

# Configuration
CONFIG_DIR="$HOME/.backupmanager"
CONFIG_FILE="$CONFIG_DIR/config"
BACKUP_DIR="/root/openwrt-backup"
SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
CRON_FILE="/etc/crontabs/root"

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Current router name (loaded from config)
ROUTER_NAME=""
GITHUB_USERNAME=""
BACKUP_SCHEDULE="never"
BACKUP_FILES=""

# Print colored messages
print_success() {
    printf "${GREEN}✓ %s${NC}\n" "$1"
}

print_error() {
    printf "${RED}✗ %s${NC}\n" "$1"
}

print_warning() {
    printf "${YELLOW}⚠ %s${NC}\n" "$1"
}

# Check if required tools are installed
check_requirements() {
    local missing=""
    
    if ! command -v git >/dev/null 2>&1; then
        missing="git $missing"
    fi
    
    if ! command -v whiptail >/dev/null 2>&1; then
        missing="whiptail $missing"
    fi
    
    if ! command -v ssh >/dev/null 2>&1; then
        missing="openssh-client $missing"
    fi
    
    if ! command -v ssh-keygen >/dev/null 2>&1; then
        missing="openssh-keygen $missing"
    fi
    
    if [ -n "$missing" ]; then
        echo "Missing required tools: $missing"
        echo "Please install them using: opkg update && opkg install $missing"
        exit 1
    fi
}

# Load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    fi
}

# Save configuration
save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
ROUTER_NAME="$ROUTER_NAME"
GITHUB_USERNAME="$GITHUB_USERNAME"
BACKUP_SCHEDULE="$BACKUP_SCHEDULE"
BACKUP_FILES="$BACKUP_FILES"
EOF
}

# Translate file paths to plain English
file_to_description() {
    local file="$1"
    case "$file" in
        /etc/config/network) echo "Network settings" ;;
        /etc/config/wireless) echo "WiFi settings" ;;
        /etc/config/firewall) echo "Firewall rules" ;;
        /etc/config/dhcp) echo "DHCP settings" ;;
        /etc/config/system) echo "System settings" ;;
        /etc/config/dropbear) echo "SSH settings" ;;
        /etc/config/uhttpd) echo "Web interface settings" ;;
        *) echo "$file" ;;
    esac
}

# Check if file contains sensitive data
is_sensitive_file() {
    local file="$1"
    case "$file" in
        /etc/config/wireless) return 0 ;;
        /etc/shadow) return 0 ;;
        /etc/dropbear/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Translate git errors to plain English
translate_error() {
    local error="$1"
    
    if echo "$error" | grep -qi "could not resolve hostname"; then
        echo "Can't connect to internet. Check your connection."
    elif echo "$error" | grep -qi "permission denied.*publickey"; then
        echo "GitHub doesn't recognize this router. Let's fix that."
    elif echo "$error" | grep -qi "repository not found"; then
        echo "Your online backup doesn't exist yet."
    elif echo "$error" | grep -qi "merge conflict"; then
        echo "The online backup and this router have different changes."
    elif echo "$error" | grep -qi "nothing to commit"; then
        echo "Nothing has changed since your last backup!"
    else
        echo "$error"
    fi
}

# Setup wizard - Step 1: Welcome
setup_welcome() {
    whiptail --title "Welcome to OpenWrt Backup Manager" --msgbox "\
This app will help you protect your router settings.

What it does:
• Saves your router settings automatically
• Keeps them safe online (on GitHub)
• Lets you restore if something goes wrong
• No technical knowledge needed!

Let's get you set up in a few simple steps." 16 70
}

# Setup wizard - Step 2: GitHub account check
setup_github_check() {
    if whiptail --title "GitHub Account" --yesno "\
Do you have a GitHub account?

GitHub is a free service that will store your backups online safely.

If you don't have one, we'll show you how to sign up." 12 70; then
        return 0
    else
        whiptail --title "Create GitHub Account" --msgbox "\
Please visit this link to create a free GitHub account:

https://github.com/signup

It only takes a minute. Press OK when you're done." 12 70
        return 0
    fi
}

# Setup wizard - Step 3: Get GitHub username
setup_github_username() {
    local username=$(whiptail --title "GitHub Username" --inputbox "\
What's your GitHub username?

(This is what you use to log in to GitHub)" 10 70 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$username" ]; then
        GITHUB_USERNAME="$username"
        return 0
    else
        return 1
    fi
}

# Setup wizard - Step 4: Auto-create SSH key
setup_ssh_key() {
    if [ -f "$SSH_KEY_PATH" ]; then
        whiptail --title "SSH Key Found" --msgbox "\
Found existing SSH key. We'll use that." 8 70
        return 0
    fi
    
    whiptail --title "Creating Security Key" --msgbox "\
Creating a security key for your router...

This lets GitHub recognize this router safely." 10 70
    
    mkdir -p "$HOME/.ssh"
    
    if ssh-keygen -t ed25519 -N "" -f "$SSH_KEY_PATH" -C "openwrt-backup-$ROUTER_NAME" >/dev/null 2>&1; then
        print_success "Security key created"
        return 0
    else
        whiptail --title "Error" --msgbox "Failed to create security key." 8 70
        return 1
    fi
}

# Setup wizard - Step 5: Show public key and instructions
setup_show_key() {
    local pubkey=$(cat "$SSH_KEY_PATH.pub")
    
    whiptail --title "Add Security Key to GitHub" --msgbox "\
Now we need to tell GitHub about this router.

1. Copy this key:

$pubkey

2. Click this link: https://github.com/settings/ssh/new

3. Give it a name like 'My Router'
4. Paste the key
5. Click 'Add SSH key'

Press OK when you've done this." 20 78
}

# Setup wizard - Step 6: Test connection
setup_test_connection() {
    whiptail --title "Testing Connection" --infobox "Testing connection to GitHub..." 5 50
    sleep 1
    
    local test_output=$(ssh -T git@github.com 2>&1 || true)
    
    if echo "$test_output" | grep -q "successfully authenticated"; then
        whiptail --title "Success!" --msgbox "\
✓ Connected to GitHub successfully!

Your router can now save backups online." 10 70
        return 0
    else
        if whiptail --title "Connection Failed" --yesno "\
Couldn't connect to GitHub.

This usually means you didn't add the key yet.

Want to try again?" 12 70; then
            return 1
        else
            whiptail --title "Skip for Now" --msgbox "\
OK, you can set this up later from Settings.

Note: You won't be able to save backups online until this is fixed." 10 70
            return 0
        fi
    fi
}

# Setup wizard - Step 7: Router name
setup_router_name() {
    local name=$(whiptail --title "Name Your Router" --inputbox "\
What do you want to call this router?

Examples:
• Living Room Router
• Main Router
• Garage AP

This helps you identify it if you have multiple routers." 14 70 "Main Router" 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$name" ]; then
        ROUTER_NAME="$name"
        return 0
    else
        ROUTER_NAME="Main Router"
        return 0
    fi
}

# Setup wizard - Step 8: Select files to backup
setup_select_files() {
    local selected=$(whiptail --title "What to Back Up" --checklist "\
Choose what you want to protect:
(Use SPACE to select, ENTER when done)" 20 78 10 \
        "network" "Network settings (recommended)" ON \
        "firewall" "Firewall rules (recommended)" ON \
        "packages" "Installed packages list (recommended)" ON \
        "dhcp" "DHCP settings (recommended)" ON \
        "wireless" "WiFi passwords (WARNING: stored online)" OFF \
        "system" "System settings" ON \
        "all" "Everything in /etc/config/ (advanced)" OFF \
        3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ]; then
        BACKUP_FILES="$selected"
        
        # Show warning if wireless is selected
        if echo "$BACKUP_FILES" | grep -q "wireless"; then
            if ! whiptail --title "⚠️  Warning About WiFi Passwords" --yesno "\
If you back up WiFi passwords:

• They will be stored on GitHub
• Your GitHub account is PRIVATE by default
• Only you can see them (unless you share access)
• If someone gets into your GitHub, they get
  your WiFi password too

Most people choose NOT to back these up.

Do you want to continue backing up WiFi passwords?" 18 70; then
                # Remove wireless from selection
                BACKUP_FILES=$(echo "$BACKUP_FILES" | sed 's/"wireless"//g')
            fi
        fi
        return 0
    else
        # Default selection
        BACKUP_FILES='"network" "firewall" "packages" "dhcp" "system"'
        return 0
    fi
}

# Setup wizard - Step 9: Auto-backup schedule
setup_auto_backup() {
    local schedule=$(whiptail --title "Automatic Backups" --menu "\
How often should your router back up automatically?" 15 70 4 \
        "never" "Never (manual only)" \
        "daily" "Every day" \
        "weekly" "Every week" \
        "monthly" "Every month" \
        3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$schedule" ]; then
        BACKUP_SCHEDULE="$schedule"
    else
        BACKUP_SCHEDULE="never"
    fi
    
    return 0
}

# Setup wizard - Step 10: Create first backup
setup_first_backup() {
    whiptail --title "Creating First Backup" --msgbox "\
Now let's create your first backup!

This will save your current settings." 10 70
    
    # Initialize git repository if needed
    if [ ! -d "$BACKUP_DIR/.git" ]; then
        mkdir -p "$BACKUP_DIR"
        cd "$BACKUP_DIR" || return 1
        
        git --no-pager init >/dev/null 2>&1
        git --no-pager config user.name "$ROUTER_NAME"
        git --no-pager config user.email "$GITHUB_USERNAME@openwrt.backup"
        
        # Create remote if username is set
        if [ -n "$GITHUB_USERNAME" ]; then
            local repo_name="openwrt-backup-$(echo "$ROUTER_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')"
            git --no-pager remote add origin "git@github.com:$GITHUB_USERNAME/$repo_name.git" 2>/dev/null || true
        fi
    fi
    
    # Copy files to backup
    copy_files_to_backup
    
    # Create first backup
    cd "$BACKUP_DIR" || return 1
    git --no-pager add . >/dev/null 2>&1
    
    local commit_output=$(git --no-pager commit -m "Initial backup from $ROUTER_NAME" 2>&1)
    
    if [ $? -eq 0 ]; then
        # Try to push if we have a remote
        if git --no-pager config --get remote.origin.url >/dev/null 2>&1; then
            local push_output=$(git --no-pager push -u origin main 2>&1 || git --no-pager push -u origin master 2>&1 || true)
        fi
        
        whiptail --title "First Backup Created!" --msgbox "\
✓ Your first backup is complete!

Your router settings are now protected." 10 70
        return 0
    else
        whiptail --title "Backup Created Locally" --msgbox "\
✓ Backup created on this router

Note: Couldn't save to GitHub yet. You can set this up later in Settings." 10 70
        return 0
    fi
}

# Copy selected files to backup directory
copy_files_to_backup() {
    mkdir -p "$BACKUP_DIR/etc/config"
    
    # Process each selected file type
    echo "$BACKUP_FILES" | tr ' ' '\n' | while read -r item; do
        item=$(echo "$item" | tr -d '"')
        case "$item" in
            network)
                [ -f /etc/config/network ] && cp /etc/config/network "$BACKUP_DIR/etc/config/"
                ;;
            firewall)
                [ -f /etc/config/firewall ] && cp /etc/config/firewall "$BACKUP_DIR/etc/config/"
                ;;
            dhcp)
                [ -f /etc/config/dhcp ] && cp /etc/config/dhcp "$BACKUP_DIR/etc/config/"
                ;;
            wireless)
                [ -f /etc/config/wireless ] && cp /etc/config/wireless "$BACKUP_DIR/etc/config/"
                ;;
            system)
                [ -f /etc/config/system ] && cp /etc/config/system "$BACKUP_DIR/etc/config/"
                ;;
            all)
                cp -r /etc/config/* "$BACKUP_DIR/etc/config/" 2>/dev/null || true
                ;;
        esac
    done
    
    # Always backup package list if selected
    if echo "$BACKUP_FILES" | grep -q "packages"; then
        opkg list-installed > "$BACKUP_DIR/package-list.txt" 2>/dev/null || true
    fi
}

# Setup wizard - Step 11: Complete
setup_complete() {
    # Set up cron if auto-backup is enabled
    if [ "$BACKUP_SCHEDULE" != "never" ]; then
        setup_cron
    fi
    
    whiptail --title "Setup Complete! 🎉" --msgbox "\
✓ Done! Your router is protected.

You can now:
• Create backups anytime
• Restore old settings
• View what changed
• And more!

Run 'backup' to access the backup manager." 14 70
}

# Set up cron job for auto-backup
setup_cron() {
    local cron_schedule=""
    
    case "$BACKUP_SCHEDULE" in
        daily)
            cron_schedule="0 3 * * *"
            ;;
        weekly)
            cron_schedule="0 3 * * 0"
            ;;
        monthly)
            cron_schedule="0 3 1 * *"
            ;;
        *)
            return
            ;;
    esac
    
    # Remove old backup manager cron jobs
    if [ -f "$CRON_FILE" ]; then
        grep -v "backup-manager.sh" "$CRON_FILE" > "$CRON_FILE.tmp" 2>/dev/null || touch "$CRON_FILE.tmp"
        mv "$CRON_FILE.tmp" "$CRON_FILE"
    fi
    
    # Add new cron job
    echo "$cron_schedule /root/backup-manager.sh --auto-backup >/dev/null 2>&1" >> "$CRON_FILE"
    
    # Restart cron
    /etc/init.d/cron restart >/dev/null 2>&1 || true
}

# Full setup wizard
run_setup_wizard() {
    setup_welcome
    setup_github_check
    
    if ! setup_github_username; then
        return 1
    fi
    
    if ! setup_router_name; then
        return 1
    fi
    
    setup_ssh_key
    setup_show_key
    
    # Loop until connection succeeds or user skips
    while ! setup_test_connection; do
        setup_show_key
    done
    
    setup_select_files
    setup_auto_backup
    
    # Save config before first backup
    save_config
    
    setup_first_backup
    setup_complete
    
    return 0
}

# Get time since last backup
get_last_backup_time() {
    if [ ! -d "$BACKUP_DIR/.git" ]; then
        echo "Never"
        return
    fi
    
    cd "$BACKUP_DIR" || return
    
    local last_commit=$(git --no-pager log -1 --format="%cr" 2>/dev/null || echo "Never")
    echo "$last_commit"
}

# Get backup status
get_backup_status() {
    if [ ! -d "$BACKUP_DIR/.git" ]; then
        echo "⚠️  No backups yet"
        return
    fi
    
    cd "$BACKUP_DIR" || return
    
    # Check if there are uncommitted changes
    if ! git --no-pager diff --quiet 2>/dev/null; then
        echo "⚠️  Changes not saved"
        return
    fi
    
    echo "✓ Everything saved"
}

# Main menu
show_main_menu() {
    local last_backup=$(get_last_backup_time)
    local status=$(get_backup_status)
    
    local choice=$(whiptail --title "OpenWrt Backup Manager" --menu "\
Router: $ROUTER_NAME
Last backup: $last_backup
Status: $status

Choose an option:" 22 70 10 \
        "1" "Backup Now (save current settings)" \
        "2" "View Changes (what's different)" \
        "3" "Restore (go back to old settings)" \
        "4" "History (see all backups)" \
        "5" "Compare Backups (between dates)" \
        "6" "Health Check (is everything working?)" \
        "7" "Export Backup (USB/download)" \
        "8" "Settings" \
        "9" "Exit" \
        3>&1 1>&2 2>&3)
    
    case "$choice" in
        1) backup_now ;;
        2) view_changes ;;
        3) restore_backup ;;
        4) show_history ;;
        5) compare_backups ;;
        6) health_check ;;
        7) export_backup ;;
        8) settings_menu ;;
        9) return 1 ;;
        *) return 0 ;;
    esac
    
    return 0
}

# Backup now
backup_now() {
    if [ ! -d "$BACKUP_DIR/.git" ]; then
        whiptail --title "Error" --msgbox "Backup not initialized. Please run setup first." 8 70
        return
    fi
    
    # Copy current files
    copy_files_to_backup
    
    cd "$BACKUP_DIR" || return
    
    # Check what changed
    local changes=$(git --no-pager status --short 2>/dev/null)
    
    if [ -z "$changes" ]; then
        whiptail --title "No Changes" --msgbox "\
Nothing has changed since your last backup!

Your settings are already saved." 10 70
        return
    fi
    
    # Translate changes to plain English
    local plain_changes=""
    while read -r line; do
        local status=$(echo "$line" | awk '{print $1}')
        local file=$(echo "$line" | awk '{print $2}')
        local description=$(file_to_description "$file")
        
        case "$status" in
            M) plain_changes="$plain_changes✏️ $description changed\n" ;;
            A) plain_changes="$plain_changes➕ $description added\n" ;;
            D) plain_changes="$plain_changes🗑️ $description removed\n" ;;
            *) plain_changes="$plain_changes• $description modified\n" ;;
        esac
    done << EOF
$changes
EOF
    
    # Show what will be backed up
    whiptail --title "What Will Be Saved" --msgbox "\
Changes since last backup:

$plain_changes

These changes will be saved in your backup." 18 70
    
    # Ask for optional note
    local note=$(whiptail --title "Backup Note (Optional)" --inputbox "\
What did you change?

(This helps you remember later. You can leave it blank.)" 12 70 3>&1 1>&2 2>&3)
    
    local commit_msg="Backup from $ROUTER_NAME"
    if [ -n "$note" ]; then
        commit_msg="$commit_msg: $note"
    fi
    
    # Do the backup
    git --no-pager add . >/dev/null 2>&1
    local commit_output=$(git --no-pager commit -m "$commit_msg" 2>&1)
    
    if [ $? -eq 0 ]; then
        # Try to push
        if git --no-pager config --get remote.origin.url >/dev/null 2>&1; then
            whiptail --title "Saving Online" --infobox "Uploading to GitHub..." 5 50
            local push_output=$(git --no-pager push 2>&1)
            
            if [ $? -eq 0 ]; then
                whiptail --title "Backup Complete!" --msgbox "\
✓ Settings saved successfully!
✓ Uploaded to GitHub

Your router is protected." 10 70
            else
                local error_msg=$(translate_error "$push_output")
                whiptail --title "Saved Locally" --msgbox "\
✓ Settings saved on this router
⚠️  Couldn't upload to GitHub

Error: $error_msg

Your backup is still safe on this router." 12 70
            fi
        else
            whiptail --title "Backup Complete!" --msgbox "\
✓ Settings saved successfully!

(Online backup not configured)" 10 70
        fi
    else
        whiptail --title "Backup Failed" --msgbox "\
Failed to save backup.

Error: $commit_output" 10 70
    fi
}

# View changes since last backup
view_changes() {
    if [ ! -d "$BACKUP_DIR/.git" ]; then
        whiptail --title "Error" --msgbox "No backups found. Create a backup first." 8 70
        return
    fi
    
    copy_files_to_backup
    cd "$BACKUP_DIR" || return
    
    local changes=$(git --no-pager status --short 2>/dev/null)
    
    if [ -z "$changes" ]; then
        whiptail --title "No Changes" --msgbox "\
No changes since last backup.

Everything is the same as your last saved settings." 10 70
        return
    fi
    
    # Build plain English description
    local description=""
    while read -r line; do
        local status=$(echo "$line" | awk '{print $1}')
        local file=$(echo "$line" | awk '{print $2}')
        local desc=$(file_to_description "$file")
        
        case "$status" in
            M) description="$description✏️ $desc changed\n" ;;
            A) description="$description➕ $desc added\n" ;;
            D) description="$description🗑️ $desc removed\n" ;;
            *) description="$description• $desc modified\n" ;;
        esac
    done << EOF
$changes
EOF
    
    whiptail --title "What's Different" --msgbox "\
Changes since your last backup:

$description

Use 'Backup Now' to save these changes." 18 70
}

# Show backup history
show_history() {
    if [ ! -d "$BACKUP_DIR/.git" ]; then
        whiptail --title "Error" --msgbox "No backups found." 8 70
        return
    fi
    
    cd "$BACKUP_DIR" || return
    
    local log=$(git --no-pager log --format="%h|%ar|%s" -20 2>/dev/null)
    
    if [ -z "$log" ]; then
        whiptail --title "No History" --msgbox "No backup history found." 8 70
        return
    fi
    
    # Build menu items
    local menu_items=""
    while read -r line; do
        local hash=$(echo "$line" | cut -d'|' -f1)
        local time=$(echo "$line" | cut -d'|' -f2)
        local msg=$(echo "$line" | cut -d'|' -f3)
        menu_items="$menu_items$hash \"$time - $msg\" "
    done << EOF
$log
EOF
    
    local selected=$(whiptail --title "Backup History" --menu "\
All your backups (most recent first):" 20 78 12 $menu_items 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$selected" ]; then
        # Show details of selected backup
        local details=$(git --no-pager show --stat "$selected" 2>/dev/null)
        whiptail --title "Backup Details" --msgbox "$details" 25 100 --scrolltext
    fi
}

# Restore from backup
restore_backup() {
    if [ ! -d "$BACKUP_DIR/.git" ]; then
        whiptail --title "Error" --msgbox "No backups found." 8 70
        return
    fi
    
    cd "$BACKUP_DIR" || return
    
    local log=$(git --no-pager log --format="%h|%ar|%s" -20 2>/dev/null)
    
    if [ -z "$log" ]; then
        whiptail --title "No Backups" --msgbox "No backups available to restore." 8 70
        return
    fi
    
    # Build menu items
    local menu_items=""
    while read -r line; do
        local hash=$(echo "$line" | cut -d'|' -f1)
        local time=$(echo "$line" | cut -d'|' -f2)
        local msg=$(echo "$line" | cut -d'|' -f3)
        menu_items="$menu_items$hash \"$time - $msg\" "
    done << EOF
$log
EOF
    
    local selected=$(whiptail --title "Restore Backup" --menu "\
Which backup do you want to restore?" 20 78 12 $menu_items 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ] || [ -z "$selected" ]; then
        return
    fi
    
    # Show what will change
    local current_head=$(git --no-pager rev-parse HEAD 2>/dev/null)
    local diff_summary=$(git --no-pager diff --stat "$current_head" "$selected" 2>/dev/null)
    
    if ! whiptail --title "Confirm Restore" --yesno "\
Are you sure you want to restore this backup?

This will change your router settings to:
$selected

Changes that will be made:
$diff_summary

This action can be undone by restoring a different backup." 20 78; then
        return
    fi
    
    # Perform restore
    if git --no-pager checkout "$selected" -- . 2>/dev/null; then
        # Copy files back to system
        if [ -d "$BACKUP_DIR/etc/config" ]; then
            cp -r "$BACKUP_DIR/etc/config/"* /etc/config/ 2>/dev/null || true
        fi
        
        whiptail --title "Restore Complete!" --msgbox "\
✓ Settings restored successfully!

You may need to reboot your router for all changes to take effect.

Want to reboot now?" 12 70
        
        if whiptail --title "Reboot?" --yesno "Reboot router now?" 8 50; then
            reboot
        fi
    else
        whiptail --title "Restore Failed" --msgbox "\
Failed to restore backup.

Your current settings are unchanged." 10 70
    fi
}

# Compare two backups
compare_backups() {
    if [ ! -d "$BACKUP_DIR/.git" ]; then
        whiptail --title "Error" --msgbox "No backups found." 8 70
        return
    fi
    
    cd "$BACKUP_DIR" || return
    
    local log=$(git --no-pager log --format="%h|%ar|%s" -20 2>/dev/null)
    
    if [ -z "$log" ]; then
        whiptail --title "No Backups" --msgbox "Not enough backups to compare." 8 70
        return
    fi
    
    # Build menu items
    local menu_items=""
    while read -r line; do
        local hash=$(echo "$line" | cut -d'|' -f1)
        local time=$(echo "$line" | cut -d'|' -f2)
        local msg=$(echo "$line" | cut -d'|' -f3)
        menu_items="$menu_items$hash \"$time - $msg\" "
    done << EOF
$log
EOF
    
    local first=$(whiptail --title "Compare Backups - Select First" --menu "\
Select the first backup:" 20 78 12 $menu_items 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ] || [ -z "$first" ]; then
        return
    fi
    
    local second=$(whiptail --title "Compare Backups - Select Second" --menu "\
Select the second backup:" 20 78 12 $menu_items 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ] || [ -z "$second" ]; then
        return
    fi
    
    # Show differences
    local diff=$(git --no-pager diff --stat "$first" "$second" 2>/dev/null)
    
    if [ -z "$diff" ]; then
        whiptail --title "No Differences" --msgbox "\
These two backups are identical.

No changes between them." 10 70
    else
        whiptail --title "What Changed" --msgbox "\
Differences between the two backups:

$diff" 25 100 --scrolltext
    fi
}

# Health check
health_check() {
    local report=""
    local warnings=0
    
    # Check backup directory
    if [ -d "$BACKUP_DIR/.git" ]; then
        report="$report✓ Backup system initialized\n"
    else
        report="$report✗ Backup system not initialized\n"
        warnings=$((warnings + 1))
    fi
    
    # Check GitHub connection
    if [ -f "$SSH_KEY_PATH" ]; then
        report="$report✓ Security key exists\n"
        
        local test_output=$(ssh -T git@github.com 2>&1 || true)
        if echo "$test_output" | grep -q "successfully authenticated"; then
            report="$report✓ Online backup connected\n"
        else
            report="$report✗ Can't connect to GitHub\n"
            warnings=$((warnings + 1))
        fi
    else
        report="$report✗ No security key found\n"
        warnings=$((warnings + 1))
    fi
    
    # Check last backup time
    local last_backup=$(get_last_backup_time)
    if [ "$last_backup" != "Never" ]; then
        report="$report✓ Last backup: $last_backup\n"
    else
        report="$report⚠️  No backups yet\n"
        warnings=$((warnings + 1))
    fi
    
    # Check if WiFi passwords are backed up
    if echo "$BACKUP_FILES" | grep -q "wireless"; then
        report="$report⚠️  WiFi passwords ARE backed up\n"
    else
        report="$report✓ WiFi passwords are NOT backed up (your choice)\n"
    fi
    
    # Count protected files
    if [ -d "$BACKUP_DIR/etc/config" ]; then
        local file_count=$(find "$BACKUP_DIR/etc/config" -type f | wc -l)
        report="$report✓ $file_count settings files protected\n"
    fi
    
    # Count restore points
    if [ -d "$BACKUP_DIR/.git" ]; then
        cd "$BACKUP_DIR" || return
        local backup_count=$(git --no-pager rev-list --count HEAD 2>/dev/null || echo "0")
        report="$report✓ $backup_count restore points available\n"
    fi
    
    # Check auto-backup
    if [ "$BACKUP_SCHEDULE" != "never" ]; then
        report="$report✓ Auto-backup: $BACKUP_SCHEDULE\n"
    else
        report="$report✓ Auto-backup: Manual only\n"
    fi
    
    whiptail --title "Backup Health" --msgbox "\
$report
" 20 70
    
    if [ $warnings -gt 0 ]; then
        if whiptail --title "Issues Found" --yesno "\
Found $warnings issue(s).

Want to test the connection to GitHub?" 10 70; then
            test_github_connection
        fi
    fi
}

# Test GitHub connection
test_github_connection() {
    whiptail --title "Testing..." --infobox "Testing connection to GitHub..." 5 50
    sleep 1
    
    local test_output=$(ssh -T git@github.com 2>&1 || true)
    
    if echo "$test_output" | grep -q "successfully authenticated"; then
        whiptail --title "Success!" --msgbox "\
✓ Connected to GitHub successfully!

$test_output" 12 78
    else
        local error_msg=$(translate_error "$test_output")
        whiptail --title "Connection Failed" --msgbox "\
✗ Can't connect to GitHub

Error: $error_msg

$test_output

Want to re-setup the connection?" 16 78
        
        if whiptail --title "Re-setup?" --yesno "Re-setup GitHub connection?" 8 50; then
            setup_ssh_key
            setup_show_key
            test_github_connection
        fi
    fi
}

# Export backup
export_backup() {
    local choice=$(whiptail --title "Export Backup" --menu "\
Where do you want to export your backup?" 15 70 4 \
        "1" "USB drive (auto-detect)" \
        "2" "Download via SCP (show instructions)" \
        "3" "Send to another server" \
        "4" "Back" \
        3>&1 1>&2 2>&3)
    
    case "$choice" in
        1) export_to_usb ;;
        2) export_scp_instructions ;;
        3) export_to_server ;;
        4) return ;;
    esac
}

# Export to USB
export_to_usb() {
    # Find mounted USB drives
    local usb_mounts=$(mount | grep -E "sd[a-z][0-9]" | awk '{print $3}')
    
    if [ -z "$usb_mounts" ]; then
        whiptail --title "No USB Found" --msgbox "\
No USB drive detected.

Please plug in a USB drive and try again." 10 70
        return
    fi
    
    # Build menu of USB drives
    local menu_items=""
    local count=1
    for mount_point in $usb_mounts; do
        menu_items="$menu_items$count \"$mount_point\" "
        count=$((count + 1))
    done
    
    local selected=$(whiptail --title "Select USB Drive" --menu "\
Select where to save the backup:" 15 70 5 $menu_items 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ] || [ -z "$selected" ]; then
        return
    fi
    
    # Get the mount point
    local target=$(echo "$usb_mounts" | sed -n "${selected}p")
    
    # Create backup archive
    local archive_name="openwrt-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    if tar -czf "/tmp/$archive_name" -C "$BACKUP_DIR" . 2>/dev/null; then
        if cp "/tmp/$archive_name" "$target/" 2>/dev/null; then
            whiptail --title "Export Complete!" --msgbox "\
✓ Backup exported successfully!

Saved to: $target/$archive_name" 10 70
            rm "/tmp/$archive_name"
        else
            whiptail --title "Export Failed" --msgbox "\
Failed to copy to USB drive.

Check if the drive has enough space." 10 70
            rm "/tmp/$archive_name"
        fi
    else
        whiptail --title "Export Failed" --msgbox "\
Failed to create backup archive." 8 70
    fi
}

# Show SCP download instructions
export_scp_instructions() {
    local archive_name="openwrt-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    if tar -czf "/tmp/$archive_name" -C "$BACKUP_DIR" . 2>/dev/null; then
        local router_ip=$(ip addr show br-lan | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        
        whiptail --title "Download Backup" --msgbox "\
Backup archive created!

From your computer, run this command:

scp root@${router_ip}:/tmp/$archive_name ~/Downloads/

This will download the backup to your Downloads folder.

The file will be deleted from the router when you close this message." 16 78
        
        rm "/tmp/$archive_name"
    else
        whiptail --title "Failed" --msgbox "Failed to create backup archive." 8 70
    fi
}

# Export to another server
export_to_server() {
    local server=$(whiptail --title "Server Address" --inputbox "\
Enter the destination server address:

Format: user@hostname:/path/to/backup/" 12 70 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ] || [ -z "$server" ]; then
        return
    fi
    
    local archive_name="openwrt-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    if tar -czf "/tmp/$archive_name" -C "$BACKUP_DIR" . 2>/dev/null; then
        whiptail --title "Uploading..." --infobox "Uploading backup to server..." 5 50
        
        if scp "/tmp/$archive_name" "$server" 2>/dev/null; then
            whiptail --title "Upload Complete!" --msgbox "\
✓ Backup uploaded successfully!

Sent to: $server" 10 70
        else
            whiptail --title "Upload Failed" --msgbox "\
Failed to upload backup.

Check the server address and your SSH keys." 10 70
        fi
        
        rm "/tmp/$archive_name"
    else
        whiptail --title "Failed" --msgbox "Failed to create backup archive." 8 70
    fi
}

# Settings menu
settings_menu() {
    local choice=$(whiptail --title "Settings" --menu "\
Configure backup manager:" 18 70 8 \
        "1" "Change router name" \
        "2" "Change what's backed up" \
        "3" "Change auto-backup schedule" \
        "4" "Re-setup GitHub connection" \
        "5" "Test GitHub connection" \
        "6" "View configuration" \
        "7" "Back to main menu" \
        3>&1 1>&2 2>&3)
    
    case "$choice" in
        1) settings_change_name ;;
        2) setup_select_files; save_config ;;
        3) setup_auto_backup; save_config; setup_cron ;;
        4) setup_github_username; setup_ssh_key; setup_show_key; setup_test_connection; save_config ;;
        5) test_github_connection ;;
        6) settings_view_config ;;
        7) return ;;
    esac
    
    # Return to settings menu
    settings_menu
}

# Change router name
settings_change_name() {
    local new_name=$(whiptail --title "Change Router Name" --inputbox "\
Current name: $ROUTER_NAME

Enter new name:" 12 70 "$ROUTER_NAME" 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$new_name" ]; then
        ROUTER_NAME="$new_name"
        save_config
        
        # Update git config
        if [ -d "$BACKUP_DIR/.git" ]; then
            cd "$BACKUP_DIR" || return
            git --no-pager config user.name "$ROUTER_NAME" 2>/dev/null
        fi
        
        whiptail --title "Name Updated" --msgbox "\
✓ Router name changed to: $ROUTER_NAME" 8 70
    fi
}

# View configuration
settings_view_config() {
    local config_text="Router Name: $ROUTER_NAME
GitHub Username: $GITHUB_USERNAME
Backup Schedule: $BACKUP_SCHEDULE
Backup Directory: $BACKUP_DIR
Config File: $CONFIG_FILE

Files backed up:
$BACKUP_FILES"
    
    whiptail --title "Current Configuration" --msgbox "$config_text" 18 70
}

# Main execution
main() {
    check_requirements
    load_config
    
    # Handle command-line arguments
    if [ "$1" = "--auto-backup" ]; then
        # Called by cron for auto-backup
        if [ -d "$BACKUP_DIR/.git" ]; then
            copy_files_to_backup
            cd "$BACKUP_DIR" || exit 1
            
            if ! git --no-pager diff --quiet 2>/dev/null; then
                git --no-pager add . >/dev/null 2>&1
                git --no-pager commit -m "Automatic backup from $ROUTER_NAME" >/dev/null 2>&1
                git --no-pager push >/dev/null 2>&1 || true
            fi
        fi
        exit 0
    fi
    
    # Run setup wizard if not configured
    if [ ! -f "$CONFIG_FILE" ] || [ -z "$ROUTER_NAME" ]; then
        run_setup_wizard
    fi
    
    # Main menu loop
    while show_main_menu; do
        :
    done
    
    print_success "Thank you for using OpenWrt Backup Manager!"
}

main "$@"
