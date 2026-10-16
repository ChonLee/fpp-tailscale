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

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"

start_up() {
    ensure_tailscaled || exit 1
    kill_pending_up

    local -a args=(up --reset "--hostname=$(ts_hostname)")
    cfg_true accept_routes && args+=(--accept-routes)

    log "Running: tailscale ${args[*]}"
    # `tailscale up` blocks until login completes; cap it so it can't linger.
    setsid timeout 600 tailscale "${args[@]}" >> "$LOG_FILE" 2>&1 < /dev/null &
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
    *)
        echo "usage: $0 up|down|reauth" >&2
        exit 2
        ;;
esac
