# OpenWrt Git Manager

A comprehensive shell script for managing git repositories on OpenWrt routers with an intuitive whiptail-based menu interface. Designed specifically for OpenWrt users who may not be familiar with git command-line operations.

## Features

- 🔑 **Automated SSH Key Setup** - Automatically generates SSH keys and guides you through GitHub setup
- 📁 **Repository Finder** - Automatically discovers git repositories on your system
- 📊 **Status View** - Easy-to-read repository status, branch info, and remote details
- ⬇️ **Pull/Push** - Simple pull and push operations with clear error messages
- 💾 **Commit Workflow** - Interactive file staging and commit with diff preview
- 🌿 **Branch Management** - List, switch, and create branches with ease
- 📦 **Clone Repositories** - Clone new repositories from GitHub
- 📜 **Commit Log** - View recent commit history

## Requirements

- OpenWrt router (tested on 24.10.2 aarch64)
- Internet connection for initial setup
- GitHub account

## Installation

### Quick Install (Recommended)

Run this one-liner on your OpenWrt router:

```sh
wget -O - https://raw.githubusercontent.com/niyisurvey/gitwrt/main/install.sh | sh
```

Or with curl:

```sh
curl -L https://raw.githubusercontent.com/niyisurvey/gitwrt/main/install.sh | sh
```

### Manual Installation

1. **Install dependencies:**

```sh
opkg update
opkg install git whiptail openssh-client openssh-keygen curl
```

2. **Download the script:**

```sh
cd /root
wget https://raw.githubusercontent.com/niyisurvey/gitwrt/main/git-manager.sh
chmod +x git-manager.sh
```

3. **Create a symbolic link (optional):**

```sh
ln -s /root/git-manager.sh /usr/bin/git-manager
```

## Usage

### First Run

When you run the script for the first time, it will:

1. Check for an SSH key at `~/.ssh/id_ed25519`
2. Create one if it doesn't exist
3. Display your public key
4. Guide you to add it to GitHub at https://github.com/settings/ssh/new
5. Test the GitHub SSH connection
6. Ask for your GitHub username
7. Set up the default repositories directory (default: `/root/repos/`)

### Running the Script

Simply run:

```sh
git-manager
```

Or:

```sh
/root/git-manager.sh
```

### Main Menu Options

1. **Select repository (Repo finder)** - Scans `/root/` and `/root/repos/` for git repositories
2. **View status** - Shows current branch, remote URL, and repository status
3. **Pull from remote** - Fetches and merges changes from the remote repository
4. **Push to remote** - Pushes your local commits to the remote repository
5. **Commit changes** - Interactive workflow:
   - View diff of changed files
   - Select files to stage
   - Enter commit message
   - Execute commit
6. **Branch management** - List, switch, or create branches
7. **Clone new repository** - Clone a new repository from GitHub
8. **View commit log** - See the last 20 commits
9. **Show diff** - View changes in working directory
0. **Exit** - Exit the application

## Configuration

Configuration is stored in `~/.gitmanager.conf` with the following settings:

- `GITHUB_USERNAME` - Your GitHub username
- `REPOS_DIR` - Directory where repositories are stored

You can manually edit this file or delete it to run the first-time setup again.

## Tips for OpenWrt Users

### Network Considerations

- Ensure your router has internet access before running operations that require network (pull, push, clone)
- The script checks GitHub connectivity during first-run setup

### Storage Considerations

- Git repositories can take up significant space
- Consider using an external USB drive mounted at `/mnt/` for repositories if internal storage is limited
- You can change the `REPOS_DIR` in the config file

### Existing Repositories

If you already have a git repository (like the example at `/root/openwrt-config`), the script will automatically discover it when you use the "Repo finder" option.

## Troubleshooting

### "Missing required tools" error

Install the missing packages:

```sh
opkg update
opkg install git whiptail openssh-client openssh-keygen
```

### SSH connection to GitHub fails

1. Ensure your SSH key is added to GitHub
2. Check that your router can reach github.com:

```sh
ping -c 3 github.com
ssh -T git@github.com
```

### "No repositories found"

The script searches `/root/` and the configured repos directory. If you have repositories elsewhere, you can:

1. Move them to `/root/repos/`
2. Create symbolic links in `/root/repos/`
3. Modify the `find_repos()` function in the script to search additional directories

### Permission errors

Ensure the script is executable:

```sh
chmod +x /root/git-manager.sh
```

## Advanced Usage

### Running git commands directly

While this tool simplifies git operations, you can always run git commands directly:

```sh
cd /root/openwrt-config
git status
git log --oneline
```

### Customizing the script

The script is designed to be easily customizable. Edit `/root/git-manager.sh` to:

- Add custom search directories in `find_repos()`
- Modify colors in the color definitions section
- Add new menu options in `main_menu()`

## Compatibility

- **Shell:** OpenWrt's ash shell (POSIX-compliant, no bash-specific syntax)
- **Interface:** whiptail (newt-based text UI)
- **Git:** Uses `--no-pager` flag to prevent interactive pagers
- **Tested on:** OpenWrt 24.10.2 (aarch64)

## Contributing

This tool is designed for OpenWrt routers. If you have improvements or find bugs, please submit issues or pull requests to the GitHub repository.

## License

This project is open source. Feel free to use, modify, and distribute.

## Author

Created for the OpenWrt community to simplify git repository management on routers.
