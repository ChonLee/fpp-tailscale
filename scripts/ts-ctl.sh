#!/bin/bash
#
# Every privileged Tailscale action the plugin takes goes through here.
# Run as root (the web UI calls it with `sudo -n /bin/bash ts-ctl.sh <cmd>`).
#
#   up      Start `tailscale up` with the plugin's settings in the background
#           and return immediately. If a login is needed, tailscaled holds the
#           auth URL; callers read it from `tailscale status --json`.
#   down    Disconnect.
#   reauth  Log out, then `up` again to get a fresh login URL.
#

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
. "$(dirname "$SELF")/common.sh"

# Runs detached (see start_up). `tailscale up` blocks until login completes,
# so it's capped. Subnet routes are only turned on afterwards: the routes the
# tailnet advertises aren't known until we're connected, and one that covers
# this FPP's own LAN would cut it off from its local network.
up_worker() {
    local -a args=(up --reset "--hostname=$(ts_hostname)")
    log "Running: tailscale ${args[*]}"
    timeout --foreground 600 tailscale "${args[@]}" || return

    cfg_true accept_routes || return 0
    local conflicts
    if conflicts=$(php "$PLUGIN_DIR/lan-routes.php"); then
        log "Running: tailscale set --accept-routes"
        tailscale set --accept-routes
    else
        log "WARNING: not accepting subnet routes, because accepting them would cut this FPP off from its local network:"
        log "$conflicts"
    fi
}

start_up() {
    ensure_tailscaled || exit 1
    kill_pending_up
    setsid /bin/bash "$SELF" _up-worker >> "$LOG_FILE" 2>&1 < /dev/null &
    echo $! > "$UP_PIDFILE"
}

case "$1" in
    up)
        start_up
        ;;
    down)
        kill_pending_up
        log "Running: tailscale down"
        timeout 15 tailscale down >> "$LOG_FILE" 2>&1
        ;;
    reauth)
        kill_pending_up
        log "Running: tailscale logout"
        timeout 15 tailscale logout >> "$LOG_FILE" 2>&1
        start_up
        ;;
    _up-worker)
        up_worker
        # Only clear the pidfile if a newer `up` hasn't replaced it.
        [ "$(cat "$UP_PIDFILE" 2>/dev/null)" = "$$" ] && rm -f "$UP_PIDFILE"
        ;;
    *)
        echo "usage: $0 up|down|reauth" >&2
        exit 2
        ;;
esac
