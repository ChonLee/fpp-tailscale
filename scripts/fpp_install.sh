#!/bin/bash
#
# FPP install script for the Tailscale plugin. FPP 10 also re-runs this after
# every plugin update, so a re-run must be quick and change nothing.
#
# It installs Tailscale but doesn't start it: nothing connects to Tailscale
# until the user clicks Connect (or turns on auto-connect).
#

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
LOG_ECHO=1

mkdir -p "$LOG_DIR"

redact_old_logs
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
id fpp >/dev/null 2>&1 && chown fpp:fpp "$LOG_FILE"

log "=== Installing Tailscale plugin ==="

# On a first install (no config yet), note whether Tailscale was already here,
# so uninstalling the plugin leaves it alone. Later runs are plugin updates.
if [ ! -f "$CONFIG_FILE" ] && ts_installed; then
    mkdir -p "$DATA_DIR"
    touch "$PREINSTALLED_MARKER"
    save_preinstalled
    id fpp >/dev/null 2>&1 && chown -R fpp:fpp "$DATA_DIR"
    log "Tailscale was already installed. Uninstalling the plugin will leave it installed and put back what the plugin changed."
fi

if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<EOF
auto_connect = "false"
accept_routes = "false"
hostname = "$(ts_hostname)"
EOF
    log "Created default configuration (hostname: $(ts_hostname))"
fi
# The web UI (running as fpp) must be able to rewrite the config.
chmod 644 "$CONFIG_FILE"
id fpp >/dev/null 2>&1 && chown fpp:fpp "$CONFIG_FILE"

migrate_apt_source
ensure_installed || exit 1

log "Tailscale $(tailscale version 2>/dev/null | head -n1) is installed"
log "=== Install complete. Open Content Setup -> Tailscale VPN to connect ==="
exit 0
