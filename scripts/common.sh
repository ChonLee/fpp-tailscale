#!/bin/bash
#
# Shared helpers for the fpp-tailscale scripts. Source this file; don't run it.
#

# FPP 8+ runs boot hooks via system(), which may not have sbin on PATH.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="/home/fpp/media/config/plugin.fpp-tailscale"
# Present if Tailscale was installed before the plugin was; uninstall then
# leaves Tailscale alone.
PREINSTALLED_MARKER="$CONFIG_FILE.preinstalled"
LOG_DIR="/home/fpp/media/logs"
# FPP's naming for plugin logs: plugin-<repoName>.log
LOG_FILE="$LOG_DIR/plugin-fpp-tailscale.log"
# Where older versions logged.
OLD_LOG_FILES="/var/log/fpp-tailscale.log $LOG_DIR/fpp-tailscale.log"
UP_PIDFILE="/run/fpp-tailscale-up.pid"
TS_DEFAULTS="/etc/default/tailscaled"
# Turns off tailscaled's diagnostic log upload to log.tailscale.com, as declared
# in pluginInfo.json's privacy block.
NO_LOGS_FLAG="--no-logs-no-support"
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

# Move history from older versions' log files into LOG_FILE. The old file is
# only removed once its contents were copied.
migrate_old_logs() {
    local f
    for f in $OLD_LOG_FILES; do
        [ -f "$f" ] || continue
        cat "$f" >> "$LOG_FILE" 2>/dev/null && rm -f "$f"
    done
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
            found || /^[ \t]*[;#]/ { next }
            {
                i = index($0, "="); if (i == 0) next
                key = substr($0, 1, i - 1); gsub(/^[ \t]+|[ \t]+$/, "", key)
                if (key != k) next
                val = substr($0, i + 1); gsub(/^[ \t"]+|[ \t"\r]+$/, "", val)
                print val; found = 1
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

ts_installed() {
    command -v tailscale >/dev/null 2>&1 && command -v tailscaled >/dev/null 2>&1
}

# Install Tailscale if it's missing (first install, or an FPPOS upgrade wiped it).
ensure_installed() {
    ts_installed && return 0
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

# tailscaled's BackendState: Running, Stopped, NeedsLogin, NeedsMachineAuth, ...
ts_backend_state() {
    tailscale status --json 2>/dev/null \
        | sed -n 's/^[[:space:]]*"BackendState": "\([A-Za-z]*\)".*/\1/p' | head -n 1
}

# Succeeds if this device is signed in to a tailnet, connected or not.
ts_logged_in() {
    case "$(ts_backend_state)" in
        Running|Starting|Stopped|NeedsMachineAuth) return 0 ;;
        *) return 1 ;;
    esac
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
        $SUDO setsid nohup tailscaled "$NO_LOGS_FLAG" "${extra[@]}" \
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

# Add NO_LOGS_FLAG to the FLAGS tailscaled's systemd unit reads. Succeeds only
# if it changed the file.
disable_log_upload() {
    [ -f "$TS_DEFAULTS" ] || return 1
    grep -q -- "$NO_LOGS_FLAG" "$TS_DEFAULTS" && return 1
    local flags
    flags=$(sed -n 's/^FLAGS=//p' "$TS_DEFAULTS" | tail -n 1 | sed 's/^"\(.*\)"$/\1/')
    flags="${flags:+$flags }$NO_LOGS_FLAG"
    $SUDO sed -i '/^FLAGS=/d' "$TS_DEFAULTS"
    echo "FLAGS=\"$flags\"" | $SUDO tee -a "$TS_DEFAULTS" >/dev/null
    log "Turned off Tailscale's diagnostic log upload ($NO_LOGS_FLAG)"
    return 0
}

# Make sure tailscaled is running with the plugin's flags. Leaves a daemon that
# is already up and configured alone.
ensure_tailscaled() {
    if [ -d /run/systemd/system ] && disable_log_upload && systemctl is-active --quiet tailscaled; then
        log "Restarting tailscaled to apply it..."
        $SUDO systemctl restart tailscaled
        wait_ready 15
    fi
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
    # Only kill it if the PID still belongs to our worker (PIDs get reused). It
    # was started with setsid, so killing its process group also stops the
    # `tailscale up` it's waiting on.
    if [ -n "$pid" ] && ps -p "$pid" -o args= 2>/dev/null | grep -q 'ts-ctl.sh _up-worker'; then
        $SUDO kill -- -"$pid" 2>/dev/null
    fi
    $SUDO rm -f "$UP_PIDFILE"
}
