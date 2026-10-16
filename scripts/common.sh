#!/bin/bash
#
# Shared helpers for the fpp-tailscale scripts. Source this file; don't run it.
#

# FPP 8+ runs boot hooks via system(), which may not have sbin on PATH.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="/home/fpp/media/config/plugin.fpp-tailscale"
LOG_DIR="/home/fpp/media/logs"
LOG_FILE="$LOG_DIR/fpp-tailscale.log"
OLD_LOG_FILE="/var/log/fpp-tailscale.log"
UP_PIDFILE="/run/fpp-tailscale-up.pid"
TS_STATE_DIR="/var/lib/tailscale"
TS_SOCKET="/var/run/tailscale/tailscaled.sock"

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

# Set LOG_ECHO=1 to also print log lines to stdout (shown in FPP's plugin
# install/uninstall output).
log() {
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo "$line" >> "$LOG_FILE" 2>/dev/null
    [ -n "$LOG_ECHO" ] && echo "$line"
    return 0
}

# Keep the log from growing forever (it lives on the SD card). Truncate in place
# so a manually started tailscaled appending to it keeps working.
trim_log() {
    [ -f "$LOG_FILE" ] || return 0
    local size
    size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt 524288 ]; then
        tail -n 1000 "$LOG_FILE" > "$LOG_FILE.tmp" && cat "$LOG_FILE.tmp" > "$LOG_FILE"
        rm -f "$LOG_FILE.tmp"
    fi
}

# cfg KEY [DEFAULT] - read a value from the plugin's INI config.
cfg() {
    local v=""
    if [ -f "$CONFIG_FILE" ]; then
        v=$(awk -v k="$1" '
            /^[ \t]*[;#]/ { next }
            {
                i = index($0, "="); if (i == 0) next
                key = substr($0, 1, i - 1); gsub(/^[ \t]+|[ \t]+$/, "", key)
                if (key != k) next
                val = substr($0, i + 1); gsub(/^[ \t"]+|[ \t"\r]+$/, "", val)
                print val; exit
            }' "$CONFIG_FILE")
    fi
    echo "${v:-$2}"
}

# cfg_true KEY - succeed if the config value is truthy.
cfg_true() {
    case "$(cfg "$1" false)" in
        true|TRUE|True|1|on|ON|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# Hostname to register with Tailscale: config value, else the system hostname.
ts_hostname() {
    local h
    h=$(cfg hostname "")
    [ -z "$h" ] && h=$(tr -d '[:space:]' < /etc/hostname 2>/dev/null)
    [ -z "$h" ] && h=$(hostname 2>/dev/null)
    # Docker gives the container ID as the hostname; that's useless in a tailnet.
    if [ -z "$h" ] || echo "$h" | grep -qE '^[0-9a-f]{12,}$'; then
        h="fpp-player"
    fi
    echo "$h"
}

# Install Tailscale if it's missing (first install, or an FPPOS upgrade wiped it).
ensure_installed() {
    if command -v tailscale >/dev/null 2>&1 && command -v tailscaled >/dev/null 2>&1; then
        return 0
    fi
    log "Tailscale not found, installing from tailscale.com..."
    local script
    script=$(mktemp) || return 1
    if curl -fsSL --retry 3 -o "$script" https://tailscale.com/install.sh \
        && $SUDO sh "$script" >> "$LOG_FILE" 2>&1; then
        rm -f "$script"
        log "Tailscale installed: $(tailscale version 2>/dev/null | head -n1)"
        return 0
    fi
    rm -f "$script"
    log "ERROR: failed to install Tailscale"
    return 1
}

# Succeeds once tailscaled answers on its socket.
ts_ready() {
    tailscale status --json 2>/dev/null | grep -q '"BackendState"'
}

# wait_ready SECONDS
wait_ready() {
    for _ in $(seq 1 "${1:-10}"); do
        ts_ready && return 0
        sleep 1
    done
    return 1
}

start_tailscaled_manually() {
    if pgrep -x tailscaled >/dev/null && wait_ready 10; then
        return 0
    fi
    $SUDO mkdir -p "$TS_STATE_DIR" "$(dirname "$TS_SOCKET")"
    local mode pid
    local -a extra
    for mode in tun userspace; do
        extra=()
        [ "$mode" = userspace ] && extra=(--tun=userspace-networking)
        log "Starting tailscaled manually ($mode networking)..."
        $SUDO setsid nohup tailscaled "${extra[@]}" \
            --state="$TS_STATE_DIR/tailscaled.state" \
            --socket="$TS_SOCKET" >> "$LOG_FILE" 2>&1 < /dev/null &
        pid=$!
        for _ in $(seq 1 10); do
            if ts_ready; then
                log "tailscaled running ($mode networking)"
                return 0
            fi
            # Stop waiting if it already exited (e.g. no /dev/net/tun).
            kill -0 "$pid" 2>/dev/null || break
            sleep 1
        done
        $SUDO pkill -x tailscaled 2>/dev/null
        sleep 1
    done
    log "ERROR: could not start tailscaled"
    return 1
}

# Make sure tailscaled is running. Doesn't touch a daemon that's already up.
ensure_tailscaled() {
    ts_ready && return 0
    if [ -d /run/systemd/system ]; then
        log "Starting tailscaled via systemd..."
        $SUDO systemctl enable --now tailscaled >> "$LOG_FILE" 2>&1
        if wait_ready 10; then
            log "tailscaled running (systemd)"
            return 0
        fi
        log "systemd could not start tailscaled, trying a manual start..."
    fi
    start_tailscaled_manually
}

# Stop a background `tailscale up` still waiting on a login, if any.
kill_pending_up() {
    [ -f "$UP_PIDFILE" ] || return 0
    local pid
    pid=$(cat "$UP_PIDFILE" 2>/dev/null)
    # Only kill it if the PID still belongs to our `tailscale up` (PIDs get reused).
    if [ -n "$pid" ] && ps -p "$pid" -o args= 2>/dev/null | grep -q 'tailscale up'; then
        $SUDO kill "$pid" 2>/dev/null
    fi
    $SUDO rm -f "$UP_PIDFILE"
}
