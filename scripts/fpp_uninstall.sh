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
    # tailscaled's own cache; the package purge doesn't remove it.
    $SUDO rm -rf /var/cache/tailscale

    if command -v apt-get >/dev/null 2>&1; then
        log "Removing the Tailscale package and its apt source..."
        $SUDO apt-get purge -y tailscale >> "$LOG_FILE" 2>&1
        if dpkg -s tailscale-archive-keyring >/dev/null 2>&1; then
            $SUDO apt-get purge -y tailscale-archive-keyring >> "$LOG_FILE" 2>&1
        fi
        $SUDO rm -f "$APT_LIST" "$APT_KEYRING" "$APT_PIN" "$LEGACY_APT_KEYRING"
        # apt's cached copies of that source's package lists, and the
        # downloaded package.
        $SUDO rm -f /var/lib/apt/lists/pkgs.tailscale.com_* \
            /var/cache/apt/archives/tailscale_*.deb /var/cache/apt/archives/tailscale-archive-keyring_*.deb
    fi

    # FPP's own network settings for tailscale0, if any were saved on its
    # Network page, deleted through FPP's API (FPP 10+); FPP drops the matching
    # systemd-networkd file the next time it sets up the network. Older FPP
    # has no such API, and the leftover file is harmless there, since
    # systemd-networkd doesn't manage tailscale0.
    curl -fsS -m 10 -X DELETE "http://localhost/api/network/interface/tailscale0" >/dev/null 2>&1 || true
fi

log "Removing plugin configuration and logs..."
rm -f "$CONFIG_FILE" "$CONFIG_FILE.tmp" "$LOG_FILE"
rm -rf "$DATA_DIR"

echo "=== Tailscale plugin uninstalled ==="
exit 0
