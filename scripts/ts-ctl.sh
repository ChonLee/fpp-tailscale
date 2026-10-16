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
# so it's capped. Only the settings the plugin manages (device name, subnet
# routes) change; anything else set with the tailscale CLI, such as Tailscale
# SSH or an exit node, is kept.
up_worker() {
    local host
    host=$(ts_hostname)
    if ts_logged_in; then
        # A bare `tailscale up` reconnects without changing any setting.
        log "Running: tailscale set --hostname=$host --accept-routes=false"
        tailscale set "--hostname=$host" --accept-routes=false || return
        log "Running: tailscale up"
        timeout --foreground 600 tailscale up || return
    else
        login_up "$host" || return
    fi
    apply_routes
}

# login_up HOSTNAME - sign in. Without --reset, `tailscale up` refuses to run
# while settings made outside the plugin differ from their defaults, and prints
# the command that keeps them. Run that instead, falling back to --reset only
# if it can't be passed on safely.
login_up() {
    local out line rc
    local -a args=(up "--hostname=$1" --accept-routes=false) keep
    out=$(mktemp) || return
    log "Running: tailscale ${args[*]}"
    timeout --foreground 600 tailscale "${args[@]}" 2>&1 | tee "$out"
    rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ] && grep -q 'requires mentioning all' "$out"; then
        line=$(sed -n 's/^[[:space:]]*tailscale up //p' "$out" | head -n 1)
        read -r -a keep <<< "$line"
        if [ "${#keep[@]}" -gt 0 ] && plain_flags "${keep[@]}"; then
            log "Keeping Tailscale settings made outside the plugin. Running: tailscale up ${keep[*]}"
            timeout --foreground 600 tailscale up "${keep[@]}"
        else
            log "WARNING: resetting Tailscale settings made outside the plugin. Running: tailscale ${args[*]} --reset"
            timeout --foreground 600 tailscale "${args[@]}" --reset
        fi
        rc=$?
    fi
    rm -f "$out"
    return "$rc"
}

# Succeeds if every argument is a bare --flag or --flag=value. Tailscale quotes
# unusual values for a shell, and those can't be passed on as-is.
plain_flags() {
    local a
    for a in "$@"; do
        [[ "$a" =~ ^--[a-z0-9-]+(=[A-Za-z0-9:.,/@_+-]*)?$ ]] || return 1
    done
}

# Subnet routes are only turned on once connected: the routes the tailnet
# advertises aren't known until then, and one that covers this FPP's own LAN
# would cut it off from its local network.
apply_routes() {
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
