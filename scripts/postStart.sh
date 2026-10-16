#!/bin/bash
#
# FPP boot hook. FPP runs it as root inside fppd.service's ExecStartPost, which
# blocks fppd startup, so all slow work happens in the background.
#

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"

(
    log "=== FPP started, checking Tailscale ==="
    migrate_apt_source

    # Without auto-connect, leave Tailscale alone: if it was connected before,
    # its own service brings that back.
    if ! cfg_true auto_connect; then
        log "Auto-connect disabled"
        exit 0
    fi
    log "Auto-connect enabled"

    # Reinstalling (after an FPP OS update removed Tailscale) and
    # `tailscale up` need the network.
    for _ in $(seq 1 60); do
        ip route show default 2>/dev/null | grep -q . && break
        sleep 1
    done

    ensure_installed || exit 1
    /bin/bash "$PLUGIN_DIR/scripts/ts-ctl.sh" up
) < /dev/null >> "$LOG_FILE" 2>&1 &

exit 0
