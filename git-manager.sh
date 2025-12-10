#!/bin/sh
#
# OpenWrt Git Manager
# A whiptail-based git repository management tool for OpenWrt routers
# Compatible with ash shell (no bash-specific syntax)
#

set -e

# Configuration
CONFIG_FILE="$HOME/.gitmanager.conf"
DEFAULT_REPOS_DIR="/root/repos"
SSH_KEY_PATH="$HOME/.ssh/id_ed25519"

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Current repository path (selected by user)
CURRENT_REPO=""

# Function to print colored messages
print_success() {
    printf "${GREEN}✓ %s${NC}\n" "$1"
}

print_error() {
    printf "${RED}✗ %s${NC}\n" "$1"
}

print_warning() {
    printf "${YELLOW}⚠ %s${NC}\n" "$1"
}

# Safely change to a directory
safe_cd() {
    if [ -z "$1" ]; then
        whiptail --title "Error" --msgbox "No directory specified." 8 60
        return 1
    fi
    
    if ! cd "$1" 2>/dev/null; then
        whiptail --title "Error" --msgbox "Failed to access directory: $1" 8 60
        return 1
    fi
    return 0
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
        missing="ssh $missing"
    fi
    
    if [ -n "$missing" ]; then
        echo "Missing required tools: $missing"
        echo "Please install them using: opkg install $missing"
        exit 1
    fi
}

# Load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        GITHUB_USERNAME=""
        REPOS_DIR="$DEFAULT_REPOS_DIR"
    fi
}

# Save configuration
save_config() {
    cat > "$CONFIG_FILE" << EOF
GITHUB_USERNAME="$GITHUB_USERNAME"
REPOS_DIR="$REPOS_DIR"
EOF
    print_success "Configuration saved to $CONFIG_FILE"
}

# First-run setup
first_run_setup() {
    # Check if SSH key exists
    if [ ! -f "$SSH_KEY_PATH" ]; then
        whiptail --title "First-Run Setup" --msgbox "No SSH key found. We'll create one now." 8 60
        
        mkdir -p "$HOME/.ssh"
        ssh-keygen -t ed25519 -N "" -f "$SSH_KEY_PATH" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            print_success "SSH key created at $SSH_KEY_PATH"
        else
            whiptail --title "Error" --msgbox "Failed to create SSH key." 8 60
            exit 1
        fi
        
        # Show public key
        local pubkey=$(cat "$SSH_KEY_PATH.pub")
        whiptail --title "SSH Public Key" --msgbox "Your SSH public key:\n\n$pubkey\n\nPlease add this key to GitHub at:\nhttps://github.com/settings/ssh/new\n\nPress OK when you've added the key." 20 78
        
        # Test GitHub connection
        whiptail --title "Testing Connection" --msgbox "Now testing connection to GitHub..." 8 60
        
        local test_output=$(ssh -T git@github.com 2>&1 || true)
        
        if echo "$test_output" | grep -q "successfully authenticated"; then
            whiptail --title "Success" --msgbox "GitHub SSH connection successful!\n\n$test_output" 12 78
        else
            whiptail --title "Warning" --msgbox "GitHub SSH test result:\n\n$test_output\n\nYou may need to add the key to GitHub." 15 78
        fi
    fi
    
    # Get GitHub username
    if [ -z "$GITHUB_USERNAME" ]; then
        GITHUB_USERNAME=$(whiptail --title "GitHub Username" --inputbox "Enter your GitHub username:" 8 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            GITHUB_USERNAME="user"
        fi
    fi
    
    # Get repos directory
    local input_dir=$(whiptail --title "Repositories Directory" --inputbox "Enter the directory for storing repositories:" 8 60 "$REPOS_DIR" 3>&1 1>&2 2>&3)
    if [ $? -eq 0 ] && [ -n "$input_dir" ]; then
        REPOS_DIR="$input_dir"
    fi
    
    # Create repos directory if it doesn't exist
    mkdir -p "$REPOS_DIR"
    
    save_config
    
    whiptail --title "Setup Complete" --msgbox "First-run setup completed!\n\nGitHub Username: $GITHUB_USERNAME\nRepos Directory: $REPOS_DIR" 10 60
}

# Find git repositories
find_repos() {
    local repos=""
    local count=0
    
    # Search in /root/ and REPOS_DIR
    for search_dir in /root "$REPOS_DIR"; do
        if [ -d "$search_dir" ]; then
            # Find directories containing .git
            for dir in $(find "$search_dir" -maxdepth 3 -type d -name ".git" 2>/dev/null); do
                local repo_path=$(dirname "$dir")
                repos="$repos$repo_path OFF "
                count=$((count + 1))
            done
        fi
    done
    
    if [ $count -eq 0 ]; then
        whiptail --title "No Repositories" --msgbox "No git repositories found in /root or $REPOS_DIR" 8 60
        return 1
    fi
    
    local selected=$(whiptail --title "Select Repository" --radiolist "Choose a repository:" 20 78 10 $repos 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$selected" ]; then
        CURRENT_REPO="$selected"
        return 0
    else
        return 1
    fi
}

# Show repository status
show_status() {
    if [ -z "$CURRENT_REPO" ]; then
        whiptail --title "Error" --msgbox "No repository selected." 8 60
        return
    fi
    
    safe_cd "$CURRENT_REPO" || return
    
    local branch=$(git --no-pager branch --show-current 2>/dev/null || echo "unknown")
    local remote=$(git --no-pager config --get remote.origin.url 2>/dev/null || echo "No remote configured")
    local status=$(git --no-pager status -sb 2>&1)
    
    local message="Repository: $CURRENT_REPO\n\nCurrent Branch: $branch\nRemote URL: $remote\n\nStatus:\n$status"
    
    whiptail --title "Repository Status" --msgbox "$message" 20 78
}

# Pull from remote
do_pull() {
    if [ -z "$CURRENT_REPO" ]; then
        whiptail --title "Error" --msgbox "No repository selected." 8 60
        return
    fi
    
    safe_cd "$CURRENT_REPO" || return
    
    # Check if remote exists
    if ! git --no-pager config --get remote.origin.url >/dev/null 2>&1; then
        whiptail --title "Error" --msgbox "No remote 'origin' configured for this repository." 8 60
        return
    fi
    
    local output=$(git --no-pager pull origin $(git --no-pager branch --show-current) 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        whiptail --title "Pull Successful" --msgbox "$output" 15 78
        print_success "Pull completed successfully"
    else
        whiptail --title "Pull Failed" --msgbox "Pull failed with error:\n\n$output" 15 78
        print_error "Pull failed"
    fi
}

# Push to remote
do_push() {
    if [ -z "$CURRENT_REPO" ]; then
        whiptail --title "Error" --msgbox "No repository selected." 8 60
        return
    fi
    
    safe_cd "$CURRENT_REPO" || return
    
    # Check if remote exists
    if ! git --no-pager config --get remote.origin.url >/dev/null 2>&1; then
        whiptail --title "Error" --msgbox "No remote 'origin' configured for this repository." 8 60
        return
    fi
    
    local output=$(git --no-pager push origin $(git --no-pager branch --show-current) 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        whiptail --title "Push Successful" --msgbox "$output" 15 78
        print_success "Push completed successfully"
    else
        whiptail --title "Push Failed" --msgbox "Push failed with error:\n\n$output" 15 78
        print_error "Push failed"
    fi
}

# Show git diff
show_diff() {
    if [ -z "$CURRENT_REPO" ]; then
        whiptail --title "Error" --msgbox "No repository selected." 8 60
        return
    fi
    
    safe_cd "$CURRENT_REPO" || return
    
    local diff_output=$(git --no-pager diff 2>&1)
    
    if [ -z "$diff_output" ]; then
        whiptail --title "No Changes" --msgbox "No unstaged changes found." 8 60
    else
        whiptail --title "Git Diff" --msgbox "$diff_output" 30 100 --scrolltext
    fi
}

# Interactive file staging
stage_files() {
    if [ -z "$CURRENT_REPO" ]; then
        whiptail --title "Error" --msgbox "No repository selected." 8 60
        return 1
    fi
    
    safe_cd "$CURRENT_REPO" || return
    
    # Get list of modified/untracked files
    local files=$(git --no-pager status --short 2>/dev/null | awk '{print $2}')
    
    if [ -z "$files" ]; then
        whiptail --title "No Changes" --msgbox "No changes to stage." 8 60
        return 1
    fi
    
    # Build checklist options
    local checklist_items=""
    for file in $files; do
        local status=$(git --no-pager status --short "$file" | awk '{print $1}')
        checklist_items="$checklist_items$file $status OFF "
    done
    
    local selected=$(whiptail --title "Stage Files" --checklist "Select files to stage (use SPACE to select):" 20 78 10 $checklist_items 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    if [ -z "$selected" ]; then
        whiptail --title "No Files Selected" --msgbox "No files were selected for staging." 8 60
        return 1
    fi
    
    # Remove quotes and add files
    selected=$(echo "$selected" | tr -d '"')
    for file in $selected; do
        git add "$file"
        print_success "Staged: $file"
    done
    
    return 0
}

# Commit workflow
do_commit() {
    if [ -z "$CURRENT_REPO" ]; then
        whiptail --title "Error" --msgbox "No repository selected." 8 60
        return
    fi
    
    safe_cd "$CURRENT_REPO" || return
    
    # Show diff first
    show_diff
    
    # Stage files
    if ! stage_files; then
        return
    fi
    
    # Get commit message
    local commit_msg=$(whiptail --title "Commit Message" --inputbox "Enter commit message:" 10 60 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ] || [ -z "$commit_msg" ]; then
        whiptail --title "Cancelled" --msgbox "Commit cancelled - no message provided." 8 60
        return
    fi
    
    # Execute commit
    local output=$(git --no-pager commit -m "$commit_msg" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        whiptail --title "Commit Successful" --msgbox "$output" 15 78
        print_success "Commit completed successfully"
    else
        whiptail --title "Commit Failed" --msgbox "Commit failed with error:\n\n$output" 15 78
        print_error "Commit failed"
    fi
}

# Branch management
manage_branches() {
    if [ -z "$CURRENT_REPO" ]; then
        whiptail --title "Error" --msgbox "No repository selected." 8 60
        return
    fi
    
    safe_cd "$CURRENT_REPO" || return
    
    local choice=$(whiptail --title "Branch Management" --menu "Choose an option:" 15 60 4 \
        "1" "List branches" \
        "2" "Switch branch" \
        "3" "Create new branch" \
        "4" "Back to main menu" \
        3>&1 1>&2 2>&3)
    
    case "$choice" in
        1)
            local branches=$(git --no-pager branch -a 2>&1)
            whiptail --title "Branches" --msgbox "$branches" 20 78
            ;;
        2)
            # Get list of local branches
            local branches=$(git --no-pager branch | sed 's/^[* ]*//')
            local branch_list=""
            for branch in $branches; do
                branch_list="$branch_list$branch $branch "
            done
            
            if [ -z "$branch_list" ]; then
                whiptail --title "No Branches" --msgbox "No branches found." 8 60
                return
            fi
            
            local selected=$(whiptail --title "Switch Branch" --menu "Select branch to switch to:" 20 78 10 $branch_list 3>&1 1>&2 2>&3)
            
            if [ $? -eq 0 ] && [ -n "$selected" ]; then
                local output=$(git --no-pager checkout "$selected" 2>&1)
                local exit_code=$?
                
                if [ $exit_code -eq 0 ]; then
                    whiptail --title "Success" --msgbox "Switched to branch: $selected\n\n$output" 12 78
                    print_success "Switched to branch: $selected"
                else
                    whiptail --title "Error" --msgbox "Failed to switch branch:\n\n$output" 12 78
                    print_error "Branch switch failed"
                fi
            fi
            ;;
        3)
            local new_branch=$(whiptail --title "Create Branch" --inputbox "Enter new branch name:" 8 60 3>&1 1>&2 2>&3)
            
            if [ $? -eq 0 ] && [ -n "$new_branch" ]; then
                local output=$(git --no-pager checkout -b "$new_branch" 2>&1)
                local exit_code=$?
                
                if [ $exit_code -eq 0 ]; then
                    whiptail --title "Success" --msgbox "Created and switched to branch: $new_branch\n\n$output" 12 78
                    print_success "Created branch: $new_branch"
                else
                    whiptail --title "Error" --msgbox "Failed to create branch:\n\n$output" 12 78
                    print_error "Branch creation failed"
                fi
            fi
            ;;
    esac
}

# Clone new repository
clone_repo() {
    local repo_url=$(whiptail --title "Clone Repository" --inputbox "Enter GitHub repository URL (e.g., git@github.com:user/repo.git):" 10 78 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ] || [ -z "$repo_url" ]; then
        return
    fi
    
    # Ensure repos directory exists
    mkdir -p "$REPOS_DIR"
    
    safe_cd "$REPOS_DIR" || return
    
    local output=$(git clone "$repo_url" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        whiptail --title "Clone Successful" --msgbox "Repository cloned successfully to $REPOS_DIR\n\n$output" 15 78
        print_success "Clone completed successfully"
    else
        whiptail --title "Clone Failed" --msgbox "Clone failed with error:\n\n$output" 15 78
        print_error "Clone failed"
    fi
}

# View commit log
view_log() {
    if [ -z "$CURRENT_REPO" ]; then
        whiptail --title "Error" --msgbox "No repository selected." 8 60
        return
    fi
    
    safe_cd "$CURRENT_REPO" || return
    
    local log_output=$(git --no-pager log --oneline -20 2>&1)
    
    if [ $? -eq 0 ]; then
        whiptail --title "Commit Log (Last 20)" --msgbox "$log_output" 25 100 --scrolltext
    else
        whiptail --title "Error" --msgbox "Failed to retrieve commit log:\n\n$log_output" 12 78
    fi
}

# Main menu
main_menu() {
    while true; do
        local repo_info=""
        if [ -n "$CURRENT_REPO" ]; then
            repo_info="Current: $CURRENT_REPO"
        else
            repo_info="No repository selected"
        fi
        
        local choice=$(whiptail --title "OpenWrt Git Manager - $repo_info" --menu "Choose an option:" 22 78 14 \
            "1" "Select repository (Repo finder)" \
            "2" "View status" \
            "3" "Pull from remote" \
            "4" "Push to remote" \
            "5" "Commit changes" \
            "6" "Branch management" \
            "7" "Clone new repository" \
            "8" "View commit log" \
            "9" "Show diff" \
            "0" "Exit" \
            3>&1 1>&2 2>&3)
        
        local exit_status=$?
        
        if [ $exit_status -ne 0 ]; then
            break
        fi
        
        case "$choice" in
            1)
                find_repos
                ;;
            2)
                show_status
                ;;
            3)
                do_pull
                ;;
            4)
                do_push
                ;;
            5)
                do_commit
                ;;
            6)
                manage_branches
                ;;
            7)
                clone_repo
                ;;
            8)
                view_log
                ;;
            9)
                show_diff
                ;;
            0)
                break
                ;;
            *)
                whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                ;;
        esac
    done
}

# Main execution
main() {
    check_requirements
    load_config
    
    # Run first-time setup if needed
    if [ ! -f "$CONFIG_FILE" ]; then
        first_run_setup
    fi
    
    main_menu
    
    print_success "Thank you for using OpenWrt Git Manager!"
}

main "$@"
