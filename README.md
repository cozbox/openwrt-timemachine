# OpenWrt Backup Manager

**Never lose your router settings again!**

A simple backup tool for OpenWrt routers that automatically saves your settings online. No technical knowledge required - just answer a few questions and you're protected.

## What It Does

- 💾 **Automatic Backups** - Saves your router settings daily, weekly, or monthly
- ☁️ **Online Storage** - Keeps backups safe on GitHub (free, private account)
- ⏮️ **Easy Restore** - Go back to any previous backup with one click
- 📱 **Plain English** - No confusing technical terms
- 🔒 **Secure** - Uses encrypted connections, settings stay private
- 📦 **Package Recovery** - Remembers and reinstalls your packages after a reset

## Who Is This For?

- You've never used git (and don't need to know what it is)
- You want to protect your router settings from being lost
- You want automatic backups you don't have to think about
- You might need to restore settings after a factory reset

## Requirements

- OpenWrt router
- Internet connection
- Free GitHub account (we'll show you how to sign up)

## Installation

### Quick Install (One Command)

Run this on your OpenWrt router:

```sh
wget -O - https://raw.githubusercontent.com/niyisurvey/gitwrt/main/install-backup.sh | sh
```

Or with curl:

```sh
curl -L https://raw.githubusercontent.com/niyisurvey/gitwrt/main/install-backup.sh | sh
```

That's it! The installer will:
1. Install everything needed
2. Download the backup manager
3. Walk you through a simple setup wizard
4. Create your first backup

### What Gets Installed

The installer will install these packages (if not already installed):
- `git` - For backup storage
- `whiptail` - For the menu interface  
- `openssh-client` - For secure connections
- `openssh-keygen` - For security keys

### Manual Installation

If you prefer to install manually:

```sh
# Install dependencies
opkg update
opkg install git whiptail openssh-client openssh-keygen

# Download and install
cd /root
wget https://raw.githubusercontent.com/niyisurvey/gitwrt/main/backup-manager.sh
chmod +x backup-manager.sh
ln -s /root/backup-manager.sh /usr/bin/backup

# Run it
backup
```

## How To Use

### First Time Setup

When you run `backup` for the first time, it will guide you through:

1. **Welcome** - Explains what the app does
2. **GitHub Account** - Asks if you have one (shows you how to sign up if not)
3. **Username** - Your GitHub username
4. **Security Key** - Creates one automatically
5. **Add Key to GitHub** - Shows you exactly where to paste it
6. **Test Connection** - Makes sure everything works
7. **Router Name** - What do you want to call this router?
8. **Select Files** - Choose what to back up (has smart defaults)
9. **Auto-Backup** - How often? (Daily, weekly, monthly, or manual)
10. **First Backup** - Creates your first backup automatically
11. **Done!** - You're protected!

The whole process takes about 2 minutes.

### Daily Use

After setup, just run:

```sh
backup
```

You'll see a menu with these options:

```
┌─────────────────────────────────────────────┐
│  OpenWrt Backup Manager                     │
├─────────────────────────────────────────────┤
│  Router: Living Room Router                 │
│  Last backup: 2 hours ago                   │
│  Status: ✓ Everything saved                 │
├─────────────────────────────────────────────┤
│                                             │
│  1. Backup Now                              │
│  2. View Changes                            │
│  3. Restore                                 │
│  4. History                                 │
│  5. Compare Backups                         │
│  6. Health Check                            │
│  7. Export Backup                           │
│  8. Settings                                │
│  9. Exit                                    │
│                                             │
└─────────────────────────────────────────────┘
```

### Common Tasks

**Creating a backup:**
1. Run `backup`
2. Select "Backup Now"
3. Review what changed
4. Add a note (optional)
5. Done!

**Restoring settings:**
1. Run `backup`
2. Select "Restore"
3. Pick which backup to restore
4. Confirm
5. Reboot if prompted

**Checking if everything is working:**
1. Run `backup`
2. Select "Health Check"
3. Fix any issues if shown

## What Gets Backed Up?

You can choose what to protect during setup (you can change this later):

- ✅ **Network settings** (recommended) - IP addresses, interfaces, VLANs
- ✅ **Firewall rules** (recommended) - Port forwards, traffic rules
- ✅ **DHCP settings** (recommended) - Static leases, DHCP options
- ✅ **Installed packages** (recommended) - List of all your installed packages
- ⚠️ **WiFi passwords** (optional, WARNING) - Only if you understand the risks
- ⚙️ **System settings** (recommended) - Hostname, time zone, etc.
- 🔧 **Everything** (advanced) - All files in /etc/config/

**Note about WiFi passwords:** These are stored in your PRIVATE GitHub account. Only back these up if you understand that anyone who gets into your GitHub account could see them.

## Disaster Recovery

### If Your Router Gets Factory Reset

1. Install OpenWrt again (if needed)
2. Get internet connection working
3. Run this command:

```sh
wget -O - https://raw.githubusercontent.com/niyisurvey/gitwrt/main/recover.sh | sh
```

The recovery script will:
- Install required tools
- Ask for your GitHub username
- Set up security key (guide you through adding it to GitHub)
- Find your backup
- Restore all your settings
- Offer to reinstall all your packages
- Install the backup manager

Then just reboot and you're back to normal!

## Multiple Routers

You can use the same GitHub account for multiple routers:

- Each router gets its own name
- Each router's backup is stored in a separate folder
- You can switch between routers in Settings

Examples:
- "Main Router" → backs up to `openwrt-backup-main-router`
- "Living Room AP" → backs up to `openwrt-backup-living-room-ap`

## Troubleshooting

### "Can't connect to internet"

- Check that your router has internet access
- Try: `ping github.com`

### "GitHub doesn't recognize this router"

This means your SSH key isn't added to GitHub:

1. Run `backup`
2. Go to Settings
3. Select "Re-setup GitHub connection"
4. Follow the instructions

### "No changes since last backup"

This is normal! It means everything is already backed up. Only changed settings get saved.

### "Couldn't upload to GitHub"

Your settings are still saved locally on the router. Check:

1. Run Health Check to see what's wrong
2. Test your GitHub connection
3. Make sure you added the SSH key to GitHub

### Storage Space Issues

Backups are small (usually < 1MB), but if you're tight on space:

- Don't back up "Everything in /etc/config"
- Just back up the recommended items
- Use Export to save to a USB drive periodically

## How It Works (For The Curious)

The backup manager uses git behind the scenes to store your settings, but you never need to know that. Here's what actually happens:

1. **Backups** - Your settings files are copied to a folder and saved with a timestamp
2. **Online Storage** - Uploaded to GitHub using secure SSH connections
3. **History** - Every backup is kept, so you can go back to any point in time
4. **Restore** - Files are copied back from a backup to your router

All the technical stuff is hidden. You just see plain English like "Backup Now" and "WiFi settings changed".

## Security & Privacy

- ✅ Your GitHub account is **private by default** - only you can see it
- ✅ Connections use **SSH encryption** - nobody can intercept your backups
- ✅ **No passwords** stored in the app - uses SSH keys instead
- ⚠️ If you back up WiFi passwords, they're stored in your GitHub repo
- ⚠️ If someone gets into your GitHub account, they can see your backups

**Recommendation:** Don't back up WiFi passwords unless you really need to.

## Files and Locations

The backup manager stores files in these locations:

- **Backup directory:** `/root/openwrt-backup/`
- **Config file:** `~/.backupmanager/config`
- **SSH key:** `~/.ssh/id_ed25519`
- **Script:** `/root/backup-manager.sh`
- **Command alias:** `/usr/bin/backup` → `/root/backup-manager.sh`

## Compatibility

- **Tested on:** OpenWrt 21.02, 22.03, 23.05, 24.10
- **Shell:** Works in OpenWrt's ash shell (POSIX-compliant)
- **Architecture:** All OpenWrt-supported architectures (ARM, x86, MIPS, etc.)
- **Required space:** ~5MB for software + minimal for backups (< 1MB typically)

## License

This project is open source and free to use. Feel free to modify and share.

## Getting Help

If you run into problems:

1. Run the **Health Check** (option 6 in the menu)
2. Check the **Troubleshooting** section above
3. Open an issue on GitHub with:
   - What you were trying to do
   - What error message you saw
   - Output from Health Check

## Credits

Created for the OpenWrt community to make router configuration backups simple and automatic.

No git knowledge required. No technical knowledge required. Just simple backups that work.
