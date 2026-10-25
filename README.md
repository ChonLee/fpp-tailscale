# FPP Tailscale Plugin

Manage a Tailscale VPN connection from the Falcon Player (FPP) web interface, for secure remote access to your show controller.

Works on FPP 7.x through 10.x.

## Features

- **Web login**: click Connect and open the login link. The page notices when you're done.
- **Auto-connect** when FPP starts
- **Subnet routes**: optionally accept routes advertised on your tailnet
- **Custom device name**, or use the system hostname
- **Live status**: Tailscale IP, hostname, MagicDNS name, and the tailnet and account it's signed in to
- **Force re-authenticate** for devices that were removed or expired in the admin console
- **Automatic Tailscale updates**, optional
- **Keeps your own Tailscale settings**: things you set with the `tailscale` command, such as Tailscale SSH or an exit node, survive connects and reboots
- **Log viewer** for the plugin's recent activity

## Installation

### From FPP Plugin Manager

1. Open the FPP web interface.
2. Go to **Content Setup** → **Plugin Manager**.
3. Paste this into the plugin URL box and click **Get Plugin Info**:
   `https://raw.githubusercontent.com/ChonLee/fpp-tailscale/main/pluginInfo.json`
4. Click **Install**.

The install script installs Tailscale from Tailscale's own apt source, pkgs.tailscale.com, so the FPP device needs internet access. The plugin adds that source with Tailscale's signing key (shipped in `apt/`), and pins it so it can only supply the `tailscale` package. Tailscale stays stopped until you click **Connect**.

### Manual Installation

```bash
cd /home/fpp/media/plugins
git clone https://github.com/ChonLee/fpp-tailscale.git
sudo fpp-tailscale/scripts/fpp_install.sh
```

## Usage

### First-time setup

1. Open **Content Setup** → **Tailscale VPN**.
2. Click **Connect**. This starts Tailscale, and a login link appears within a few seconds.
3. Open the link and sign in to your Tailscale account.
4. The page switches to **Connected** by itself. It shows the device's Tailscale IP, and the tailnet and account it joined. Check that they're yours: anyone who can open the plugin page while the login link is showing could use the link first.

If your tailnet requires device approval, the page shows **Waiting for approval** until an admin approves the device in the Tailscale admin console.

Once you've clicked Connect, Tailscale's service (`tailscaled`) starts at every boot and keeps running while FPP is stopped, until you uninstall the plugin. **Disconnect** leaves the service running but disconnected. It isn't stopped with FPP, so restarting FPP remotely doesn't cut off the person who restarted it.

### Who can reach FPP over Tailscale

Every device on your tailnet, and anyone you share this device with, can open FPP's full web interface without logging in, the same as someone on your show network. To limit that, use [Tailscale's access controls](https://tailscale.com/kb/1018/acls), or turn on a UI password in **FPP Settings → UI**.

### Auto-connect

With **Auto-connect when FPP starts** checked, the plugin runs `tailscale up` every time FPP starts. This happens in the background, so it doesn't slow FPP's startup.

With it unchecked, the plugin doesn't force a connection. Tailscale itself still remembers whether it was connected or disconnected, and restores that state on boot.

### Subnet routes and device name

These settings save as soon as you change them. If Tailscale is connected, the change applies right away. Leave the device name blank to use the system hostname.

The plugin won't accept subnet routes when another device shares this FPP's own network, because accepting them would cut the FPP off from its local network. It checks when you turn the setting on and each time the FPP connects. A route that's shared or approved later, while the FPP stays connected, isn't caught: the FPP loses its local connection, including to its controllers, until you turn **Accept subnet routes** off. The plugin page shows a warning when that happens. The two-houses setup below doesn't need subnet routes, so leave the setting off there, especially if both houses use the same network (often 192.168.1.0/24).

The plugin only manages the device name and subnet routes. Anything else you set with the `tailscale` command (Tailscale SSH, an exit node, advertised routes, ...) is left alone when the plugin connects.

### Automatic updates

**Keep Tailscale up to date automatically** turns on Tailscale's own updater, which installs new versions from pkgs.tailscale.com. An update restarts the Tailscale connection for a few seconds; FPP and your show keep running. This is Tailscale's own setting, so the box shows what Tailscale is actually set to, even if it was changed elsewhere.

### Re-authenticating

If the device was removed or its key expired in the Tailscale admin console, click **Force re-authenticate**. This logs the device out and gives you a new login link.

### Syncing two FPPs over Tailscale

Two houses running one show, with a neighbor's house in between? Instead of running a cable or a wireless link across the neighbor's yard, let FPP's MultiSync talk over Tailscale, through each house's own internet connection. FPP normally finds remotes and sends sync packets by multicast, which doesn't cross Tailscale, so the player has to be told where the remote is.

1. Install this plugin on both FPPs and connect them to the same tailnet.
2. On the **player**, open **Status/Control → MultiSync**:
   - Add the remote's Tailscale IP (the 100.x address on its Tailscale VPN page) to **MultiSync Unicast Discovery IPs**.
   - Turn on **Send MultiSync to ALL KNOWN remotes via Unicast**.
3. Also on the player, make sure **Send MultiSync Packets** is on (**FPP Settings → Playback**).
4. On the **remote**, set **FPP Player Mode** to **Remote**. Nothing else is needed: it listens for sync on every network interface, Tailscale included.

After a minute or so the remote shows up in the player's MultiSync list.

- **Timing:** sync packets travel over the internet, so the remote house runs slightly behind the player by however long a packet takes to get there. Between neighbors that's usually a few tens of milliseconds, a frame or two of a typical sequence, which is hard to spot. It's much longer if Tailscale has to relay the connection through its servers. To check, run `tailscale ping <remote's Tailscale IP>` on the player: a reply `via` an IP address is a direct connection, and `via DERP(...)` means it's relayed. The time it shows is the round trip, so the remote lags by about half of it.
- **Copying files:** **Copy files to remotes** uses rsync, so the rsync service must be enabled on the remote. Large media files are slow over a home internet connection.

These steps follow FPP 10.2's MultiSync settings, but haven't been tested end to end yet. Menu names can differ on older FPP versions.

## Configuration

Settings are stored in `/home/fpp/media/config/plugin.fpp-tailscale`:

```ini
auto_connect = "true"
accept_routes = "false"
hostname = "my-fpp-display"
```

## Troubleshooting

- **Plugin log:** `/home/fpp/media/logs/plugin-fpp-tailscale.log`. It's also shown at the bottom of the plugin page. FPP rotates it. Sign-in links are left out of it, because they work like a one-time password until used.
- **Daemon log:** `sudo journalctl -u tailscaled -n 50`
- **Page won't load:** `tail /home/fpp/media/logs/apache2-error.log`
- **After an FPP OS upgrade:** if the upgrade removed Tailscale and auto-connect is on, the plugin reinstalls it the next time FPP starts. Otherwise, reinstall the plugin from the Plugin Manager.

## Uninstallation

Delete the plugin from **Content Setup** → **Plugin Manager**. This logs the device out of Tailscale, removes the Tailscale package and its apt source, signing key and pin, removes any tailscale0 settings saved on FPP's Network page (FPP 10.1 and later), and deletes the plugin's config, data and log. `iptables`, which Tailscale needs, is removed too if it came with the plugin's install, unless something else still uses it.

If Tailscale was already installed before you installed the plugin, uninstalling leaves it installed and signed in, and puts back what the plugin changed: the device name, subnet routes, automatic updates, whether it was connected, tailscaled's flags, and whether its service was enabled and running. The plugin notes those before it first changes them.

**Reinstall** in the Plugin Manager keeps Tailscale running and signed in, and keeps the plugin's settings, on FPP 10.2 and later. On FPP 10.0 and 10.1, a Reinstall removes everything like an uninstall, so you'll need to sign in again. (FPP 7–9 have no Reinstall.)

If you're connected to the FPP device through Tailscale, you'll lose that connection.

## Development

```
fpp-tailscale/
├── scripts/
│   ├── common.sh          # Shared helpers: config, logging, install/start tailscaled
│   ├── ts-ctl.sh          # Privileged actions: up / down / reauth / auto-update (run via sudo)
│   ├── postStart.sh       # FPP boot hook (backgrounds its work)
│   ├── fpp_install.sh     # Install; FPP 10 re-runs it on every plugin update
│   └── fpp_uninstall.sh   # Uninstall
├── apt/
│   └── tailscale-archive-keyring.gpg  # Tailscale's apt signing key (fingerprint 2596 A99E AAB3 3821 893C 0A79 458C A832 957F 5868)
├── api-handler.php        # JSON API used by the page
├── lan-routes.php         # Refuses subnet routes that overlap this FPP's own LAN
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
