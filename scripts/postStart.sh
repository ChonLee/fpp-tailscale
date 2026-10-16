#!/bin/bash
#
# FPP boot hook. FPP runs it as root inside fppd.service's ExecStartPost, which
# blocks fppd startup, so all slow work happens in the background.
#

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"

trim_log

(
    log "=== FPP started, checking Tailscale ==="

    # The curl reinstall and `tailscale up` need the network.
    for _ in $(seq 1 60); do
        ip route show default 2>/dev/null | grep -q . && break
        sleep 1
    done

    ensure_installed || exit 1
    ensure_tailscaled || exit 1

    if cfg_true auto_connect; then
        log "Auto-connect enabled"
        /bin/bash "$PLUGIN_DIR/scripts/ts-ctl.sh" up
    else
        log "Auto-connect disabled"
    fi
) < /dev/null >> "$LOG_FILE" 2>&1 &

exit 0
