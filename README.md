# FPP Tailscale Plugin

Manage a Tailscale VPN connection from the Falcon Player (FPP) web interface, for secure remote access to your show controller.

Works on FPP 7.x through 10.x.

## Features

- **Web login**: click Connect and open the login link. The page notices when you're done.
- **Auto-connect** when FPP starts
- **Subnet routes**: optionally accept routes advertised on your tailnet
- **Custom device name**, or use the system hostname
- **Live status**: Tailscale IP, hostname and MagicDNS name
- **Force re-authenticate** for devices that were removed or expired in the admin console
- **Log viewer** for the plugin's recent activity

## Installation

### From FPP Plugin Manager

1. Open the FPP web interface.
2. Go to **Content Setup** → **Plugin Manager**.
3. Paste this into the plugin URL box and click **Get Plugin Info**:
   `https://raw.githubusercontent.com/ChonLee/fpp-tailscale/main/pluginInfo.json`
4. Click **Install**.

The install script downloads Tailscale from tailscale.com, so the FPP device needs internet access.

### Manual Installation

```bash
cd /home/fpp/media/plugins
git clone https://github.com/ChonLee/fpp-tailscale.git
sudo fpp-tailscale/scripts/fpp_install.sh
```

## Usage

### First-time setup

1. Open **Content Setup** → **Tailscale VPN**.
2. Click **Connect**. A login link appears within a few seconds.
3. Open the link and sign in to your Tailscale account.
4. The page switches to **Connected** by itself and shows the device's Tailscale IP.

If your tailnet requires device approval, the page shows **Waiting for approval** until an admin approves the device in the Tailscale admin console.

### Auto-connect

With **Auto-connect when FPP starts** checked, the plugin runs `tailscale up` every time FPP starts. This happens in the background, so it doesn't slow FPP's startup.

With it unchecked, the plugin doesn't force a connection. Tailscale itself still remembers whether it was connected or disconnected, and restores that state on boot.

### Subnet routes and device name

These settings save as soon as you change them. If Tailscale is connected, the change applies right away. Leave the device name blank to use the system hostname.

### Re-authenticating

If the device was removed or its key expired in the Tailscale admin console, click **Force re-authenticate**. This logs the device out and gives you a new login link.

## Configuration

Settings are stored in `/home/fpp/media/config/plugin.fpp-tailscale`:

```ini
auto_connect = "true"
accept_routes = "false"
hostname = "my-fpp-display"
```

## Troubleshooting

- **Plugin log:** `/home/fpp/media/logs/plugin-fpp-tailscale.log`. It's also shown at the bottom of the plugin page. It's trimmed automatically when it grows past 512KB.
- **Daemon log:** `sudo journalctl -u tailscaled -n 50`
- **Page won't load:** `sudo tail /var/log/apache2/error.log`
- **After an FPP OS upgrade:** if the upgrade removed Tailscale, the plugin reinstalls it the next time FPP starts.

## Uninstallation

Delete the plugin from **Content Setup** → **Plugin Manager**. This logs the device out of Tailscale, removes the Tailscale package and its apt source, and deletes the plugin's config and log.

If you're connected to the FPP device through Tailscale, you'll lose that connection.

## Development

```
fpp-tailscale/
├── scripts/
│   ├── common.sh          # Shared helpers: config, logging, install/start tailscaled
│   ├── ts-ctl.sh          # Privileged actions: up / down / reauth (run via sudo)
│   ├── postStart.sh       # FPP boot hook (backgrounds its work)
│   ├── fpp_install.sh     # Install; FPP 10 re-runs it on every plugin update
│   └── fpp_uninstall.sh   # Uninstall
├── api-handler.php        # JSON API used by the page
├── tailscale.php          # UI (an HTML fragment inside FPP's page)
├── menu.inc               # Adds the page to FPP's Content Setup menu
└── pluginInfo.json        # Plugin metadata and FPP version → branch mapping
```

Compatibility rules (checked against FPP source at 7.0, 8.0, 9.5 and 10.2):

- **PHP 7.4 syntax only.** FPP 7 runs PHP 7.4.
- **jQuery calls must work in both 3.7 and 4.0.** FPP 10 ships jQuery 4.
- **Bootstrap 5.3 classes** plus FPP's `buttons` class.
- **Scripts use LF line endings** and are committed executable: `git update-index --chmod=+x scripts/*.sh`.
- **`postStart.sh` must return immediately.** It runs inside fppd's startup.

## Credits

- Built for [Falcon Player (FPP)](https://github.com/FalconChristmas/fpp)
- Uses [Tailscale](https://tailscale.com/) for VPN connectivity
- Created by [ChonLee](https://github.com/ChonLee)

## Support

- **Issues**: [GitHub Issues](https://github.com/ChonLee/fpp-tailscale/issues)
- **FPP Forums**: [FPP Community](https://falconchristmas.com)
