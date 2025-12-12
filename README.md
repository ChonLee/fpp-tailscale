# FPP Tailscale Plugin

Manage Tailscale VPN connections directly from your Falcon Player (FPP) web interface for secure remote access to your display controller.

## Features

- 🔐 **Easy Authentication** - One-click authentication with Tailscale
- 🔄 **Auto-Connect** - Automatically connect to Tailscale on system boot
- 🌐 **Subnet Routes** - Accept subnet routes from your Tailscale network
- ⚙️ **Custom Hostname** - Set custom hostname or use system hostname
- 📊 **Real-time Status** - View connection status and Tailscale IP
- 🔄 **Force Re-authenticate** - Re-authenticate when device is revoked
- 📝 **Logs** - View recent Tailscale logs

## Installation

### From FPP Plugin Manager

1. Open FPP web interface
2. Go to **Content Setup** → **Plugin Manager**
3. Click **Install Plugin** tab
4. Enter repository URL: `https://github.com/ChonLee/fpp-tailscale`
5. Click **Install**

### Manual Installation

```bash
cd /home/fpp/media/plugins
git clone https://github.com/ChonLee/fpp-tailscale.git
cd fpp-tailscale
sudo bash scripts/fpp_install.sh
```

## Usage

### First Time Setup

1. Navigate to **Content Setup** → **Tailscale VPN** in FPP menu
2. Wait for the page to load
3. Click **🔑 Authenticate** button
4. A new tab will open with Tailscale login
5. Sign in with your Tailscale account
6. Return to FPP and click **Refresh Status**
7. You should now be connected!

### Auto-Connect on Boot

1. Check **Auto-connect on boot** checkbox
2. Settings save automatically
3. FPP will now connect to Tailscale every time it starts

### Accept Subnet Routes

1. Check **Accept subnet routes** checkbox
2. Settings save automatically
3. Your FPP device can now access other devices on your Tailscale network

### Custom Hostname

- The plugin automatically uses your system hostname
- Click **Use System Hostname** to sync with system
- Or enter a custom hostname manually

### Re-authenticating

If your device is revoked from the Tailscale admin console:

1. Click **🔄 Force Re-authenticate** button
2. Confirm the prompt
3. Authenticate in the new tab
4. Return and refresh

## Configuration

Configuration is stored in: `/home/fpp/media/config/plugin.fpp-tailscale`

Example:
```ini
; Tailscale Plugin Configuration
auto_connect = true
accept_routes = false
hostname = my-fpp-display
```

## Requirements

- FPP 7.0 or later
- Internet connection for initial Tailscale installation
- Tailscale account (free)

## Troubleshooting

### Plugin pages won't load
Check Apache error log:
```bash
sudo tail -f /var/log/apache2/error.log
```

### Daemon not starting
Check logs:
```bash
sudo journalctl -u tailscaled -n 50
```

Or view in plugin:
1. Navigate to plugin page
2. Scroll to **Recent Logs** section

### Settings won't save
Ensure config directory is writable:
```bash
sudo chmod 777 /home/fpp/media/config
```

### Device shows disconnected after reboot
Enable **Auto-connect on boot** in settings

## Uninstallation

### From Plugin Manager
1. Go to **Content Setup** → **Plugin Manager**
2. Find **Tailscale VPN**
3. Click **Delete**
4. Tailscale will be completely removed

### Manual Uninstall
```bash
cd /home/fpp/media/plugins/fpp-tailscale
sudo bash scripts/fpp_uninstall.sh
sudo rm -rf /home/fpp/media/plugins/fpp-tailscale
```

## Development

### File Structure
```
fpp-tailscale/
├── api/
│   └── endpoints.php       # FPP API integration (required)
├── scripts/
│   ├── fpp_install.sh     # Installation script
│   ├── fpp_start.sh       # Startup script (runs on boot)
│   └── fpp_uninstall.sh   # Uninstallation script
├── api-handler.php        # Plugin API endpoints
├── tailscale.php          # Main UI page
├── menu.inc               # FPP menu integration
├── pluginInfo.json        # Plugin metadata
├── .gitattributes         # Git configuration (LF line endings)
└── README.md
```

### Key Files

- **api/endpoints.php** - Required by FPP's core API system
- **api-handler.php** - Custom plugin API for web UI
- **menu.inc** - Adds plugin to FPP's Content Setup menu
- **tailscale.php** - Main plugin interface

### Making Changes

When developing, ensure:
1. Scripts use LF line endings (not CRLF)
2. Scripts are executable in git: `git update-index --chmod=+x scripts/*.sh`
3. Test complete install/uninstall cycle

## Credits

- Built for [Falcon Player (FPP)](https://github.com/FalconChristmas/fpp)
- Uses [Tailscale](https://tailscale.com/) for VPN connectivity
- Created by [ChonLee](https://github.com/ChonLee)

## License

This project is open source. Feel free to use and modify as needed.

## Support

- **Issues**: [GitHub Issues](https://github.com/ChonLee/fpp-tailscale/issues)
- **FPP Forums**: [FPP Community](https://falconchristmas.com)

## Changelog

### v1.0.0 (Initial Release)
- ✅ Tailscale installation and management
- ✅ Web-based authentication
- ✅ Auto-connect on boot
- ✅ Subnet route acceptance
- ✅ Custom hostname support
- ✅ Real-time status monitoring
- ✅ Log viewing
- ✅ Force re-authentication for revoked devices
