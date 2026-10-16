#!/bin/bash
#
# FPP uninstall script: logs out, removes Tailscale entirely, and deletes the
# plugin's config and log. If Tailscale was installed before the plugin, it's
# left as it is.
#

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
LOG_ECHO=1

log "=== Uninstalling Tailscale plugin ==="

kill_pending_up

if [ -f "$PREINSTALLED_MARKER" ]; then
    # Tailscale was here before the plugin: leave it installed and signed in.
    log "Tailscale was installed before this plugin, so it's left in place."
else
    if command -v tailscale >/dev/null 2>&1; then
        log "Logging out of Tailscale..."
        timeout 15 $SUDO tailscale down >/dev/null 2>&1
        timeout 15 $SUDO tailscale logout >/dev/null 2>&1
    fi

    log "Stopping tailscaled..."
    if [ -d /run/systemd/system ]; then
        $SUDO systemctl disable --now tailscaled >/dev/null 2>&1
    fi
    $SUDO pkill -x tailscaled 2>/dev/null

    if command -v apt-get >/dev/null 2>&1; then
        log "Removing the Tailscale package..."
        $SUDO apt-get purge -y tailscale >> "$LOG_FILE" 2>&1
        # Apt source and key added by tailscale.com/install.sh
        $SUDO rm -f /etc/apt/sources.list.d/tailscale.list \
            /usr/share/keyrings/tailscale-archive-keyring.gpg
    fi

    # FPP's own network settings for tailscale0, if any were saved on its
    # Network page. FPP deletes the matching systemd-networkd file at its next
    # boot.
    rm -f /home/fpp/media/config/interface.tailscale0
fi

log "Removing plugin configuration and logs..."
rm -f "$CONFIG_FILE" "$CONFIG_FILE.tmp" "$PREINSTALLED_MARKER" "$LOG_FILE" $OLD_LOG_FILES

echo "=== Tailscale plugin uninstalled ==="
exit 0
