#!/bin/bash
#
# FPP uninstall script: logs out, removes Tailscale entirely, and deletes the
# plugin's config and log.
#

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
LOG_ECHO=1

log "=== Uninstalling Tailscale plugin ==="

kill_pending_up

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

log "Removing plugin configuration and logs..."
rm -f "$CONFIG_FILE" "$CONFIG_FILE.tmp" "$LOG_FILE" "$OLD_LOG_FILE"

echo "=== Tailscale plugin uninstalled ==="
exit 0
