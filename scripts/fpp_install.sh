#!/bin/bash
#
# FPP install script for the Tailscale plugin. FPP 10 also re-runs this after
# every plugin update, so a re-run must be quick and change nothing.
#

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
LOG_ECHO=1

mkdir -p "$LOG_DIR"

migrate_old_logs
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
id fpp >/dev/null 2>&1 && chown fpp:fpp "$LOG_FILE"

log "=== Installing Tailscale plugin ==="

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

ensure_installed || exit 1
ensure_tailscaled || exit 1

log "Tailscale $(tailscale version 2>/dev/null | head -n1) is running"
log "=== Install complete. Open Content Setup -> Tailscale VPN to connect ==="
exit 0
