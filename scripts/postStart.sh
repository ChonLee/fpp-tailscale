#!/bin/bash
#
# FPP boot hook. FPP runs it as root inside fppd.service's ExecStartPost, which
# blocks fppd startup, so all slow work happens in the background.
#

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"

(
    log "=== FPP started, checking Tailscale ==="
    # In case an update didn't re-run fpp_install.sh. In the background: it
    # can mean reading FPP's rotated logs.
    redact_old_logs
    migrate_apt_source

    # A Tailscale update can replace tailscaled's defaults file, dropping the
    # flag that turns off its log upload. Put it back, unless this is a
    # Tailscale from before the plugin that hasn't been connected through it.
    if ts_installed && { [ ! -f "$PREINSTALLED_MARKER" ] || preinstalled_get connected >/dev/null; } \
        && disable_log_upload && [ -d /run/systemd/system ] && systemctl is-active --quiet tailscaled; then
        log "Restarting tailscaled to apply it..."
        systemctl restart tailscaled
    fi

    # Without auto-connect, leave Tailscale alone: if it was connected before,
    # its own service brings that back. But if the plugin turned on subnet
    # routes, check them once it has reconnected: a route approved while the
    # FPP was off may cover its own network.
    if ! cfg_true auto_connect; then
        log "Auto-connect disabled"
        # An FPP OS upgrade replaces the system, removing Tailscale. If this
        # player was signed in through the plugin, install Tailscale again
        # with that sign-in, so Connect brings back the same device. It isn't
        # started: that waits for Connect (guideline §4.4).
        if ! ts_installed && kept_state_ours; then
            log "Tailscale was removed, probably by an FPP OS upgrade. Installing it again with this player's sign-in; click Connect to reconnect."
            wait_network
            ensure_installed && restore_kept_state
            exit 0
        fi
        if cfg_true accept_routes && ts_installed \
            && { [ ! -f "$PREINSTALLED_MARKER" ] || preinstalled_get connected >/dev/null; }; then
            wait_ready 60
            if [ "$(ts_pref WantRunning)" = true ] && [ "$(ts_pref RouteAll)" = true ]; then
                for _ in $(seq 1 300); do
                    [ "$(ts_backend_state)" = Running ] && break
                    sleep 2
                done
                /bin/bash "$PLUGIN_DIR/scripts/ts-ctl.sh" check-routes
            fi
        fi
        exit 0
    fi
    log "Auto-connect enabled"

    # Reinstalling (after an FPP OS update removed Tailscale) and
    # `tailscale up` need the network.
    wait_network

    ensure_installed || exit 1
    # Tailscale's sign-in from before an OS upgrade or a Reinstall.
    restore_kept_state
    /bin/bash "$PLUGIN_DIR/scripts/ts-ctl.sh" up
) < /dev/null >> "$LOG_FILE" 2>&1 &

exit 0
