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
#   autoupdate-on / autoupdate-off
#           Turn Tailscale's automatic updates on or off.
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
        timeout --foreground 600 tailscale up 2>&1 | redact
        [ "${PIPESTATUS[0]}" -eq 0 ] || return
    else
        login_up "$host" || return
    fi
    apply_routes
}

# login_up HOSTNAME - sign in. Without --reset, `tailscale up` refuses to run
# while settings made outside the plugin differ from their defaults, and prints
# the command that keeps them. Run that instead (each argument passed as is, no
# shell); if it can't be read, stop with an error rather than reset them.
login_up() {
    local out line rc flags
    local -a args=(up "--hostname=$1" --accept-routes=false) keep
    out=$(mktemp) || return
    log "Running: tailscale ${args[*]}"
    timeout --foreground 600 tailscale "${args[@]}" 2>&1 | redact | tee "$out"
    rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ] && grep -q 'requires mentioning all' "$out"; then
        line=$(sed -n 's/^[[:space:]]*tailscale up //p' "$out" | head -n 1)
        if flags=$(split_flags "$line"); then
            mapfile -t keep <<< "$flags"
            log "Keeping Tailscale settings made outside the plugin. Running: tailscale up ${keep[*]}"
            timeout --foreground 600 tailscale up "${keep[@]}" 2>&1 | redact
            rc=${PIPESTATUS[0]}
        else
            # Never fall back to --reset: that would drop those settings.
            log "ERROR: not signing in. Tailscale has settings made outside the plugin that must be repeated to sign in, and the plugin couldn't read them. To keep them, run once from a shell: tailscale up $line"
            log "To drop them instead, run: tailscale up --reset"
            rc=1
        fi
    fi
    rm -f "$out"
    return "$rc"
}

# Subnet routes are only turned on once connected: the routes the tailnet
# advertises aren't known until then, and one that covers this FPP's own LAN
# would cut it off from its local network.
# Fails closed: routes stay off unless the check ran and found no overlap.
apply_routes() {
    cfg_true accept_routes || return 0
    local out rc
    out=$(php "$PLUGIN_DIR/lan-routes.php")
    rc=$?
    case "$rc" in
        0)
            log "Running: tailscale set --accept-routes"
            tailscale set --accept-routes
            ;;
        1)
            log "WARNING: not accepting subnet routes, because accepting them would cut this FPP off from its local network:"
            log "$out"
            ;;
        *)
            log "WARNING: not accepting subnet routes, because the plugin couldn't check they're safe: ${out:-lan-routes.php failed}"
            ;;
    esac
}

start_up() {
    ensure_tailscaled || exit 1
    kill_pending_up
    setsid /bin/bash "$SELF" _up-worker >> "$LOG_FILE" 2>&1 < /dev/null 9>&- &
    echo $! > "$UP_PIDFILE"
}

# One lifecycle action at a time. Two Connects at once (or auto-connect at boot
# and a click) could otherwise each start a worker and leave one that
# Disconnect doesn't know about. Processes that outlive this script (the worker,
# a manually started tailscaled) close fd 9, so they don't keep the lock.
lock_actions() {
    exec 9> /run/fpp-tailscale.lock || exit 1
    if ! flock -w 60 9; then
        echo "Another Tailscale action is still running. Try again in a moment."
        exit 1
    fi
}

case "$1" in
    up|down|reauth|autoupdate-on|autoupdate-off) lock_actions ;;
esac

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
    autoupdate-on|autoupdate-off)
        flag=--auto-update
        [ "$1" = autoupdate-off ] && flag=--auto-update=false
        log "Running: tailscale set $flag"
        out=$(timeout 15 tailscale set "$flag" 2>&1)
        rc=$?
        [ -n "$out" ] && log "$out"
        echo "$out"
        exit "$rc"
        ;;
    _up-worker)
        up_worker
        # Only clear the pidfile if a newer `up` hasn't replaced it.
        [ "$(cat "$UP_PIDFILE" 2>/dev/null)" = "$$" ] && rm -f "$UP_PIDFILE"
        ;;
    *)
        echo "usage: $0 up|down|reauth|autoupdate-on|autoupdate-off" >&2
        exit 2
        ;;
esac
