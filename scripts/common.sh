#!/bin/bash
#
# Shared helpers for the fpp-tailscale scripts. Source this file; don't run it.
#

# FPP's own paths (MEDIADIR, LOGDIR, CFGDIR), so a relocated media directory
# works. The defaults are only for when FPP's common can't be sourced.
: "${FPPDIR:=/opt/fpp}"
# shellcheck source=/dev/null
. "${FPPDIR}/scripts/common" 2>/dev/null || true
: "${MEDIADIR:=/home/fpp/media}"
: "${LOGDIR:=${MEDIADIR}/logs}"
: "${CFGDIR:=${MEDIADIR}/config}"

# FPP 8+ runs boot hooks via system(), which may not have sbin on PATH.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$CFGDIR/plugin.fpp-tailscale"
DATA_DIR="$MEDIADIR/plugindata/fpp-tailscale"
# Present if Tailscale was installed before the plugin was; uninstall then
# leaves Tailscale alone.
PREINSTALLED_MARKER="$DATA_DIR/preinstalled"
# Packages apt installed along with tailscale, one per line.
APT_ADDED="$DATA_DIR/apt-added"
LOG_DIR="$LOGDIR"
# FPP's naming for plugin logs: plugin-<repoName>.log
LOG_FILE="$LOG_DIR/plugin-fpp-tailscale.log"
UP_PIDFILE="/run/fpp-tailscale-up.pid"

# Tailscale's apt source. The list keeps the name Tailscale's own updater
# (`tailscale update`, automatic updates) reads and edits.
APT_LIST="/etc/apt/sources.list.d/tailscale.list"
APT_KEYRING="/etc/apt/keyrings/tailscale-archive-keyring.gpg"
APT_PIN="/etc/apt/preferences.d/tailscale"
# Written by tailscale.com/install.sh, which older plugin versions ran.
LEGACY_APT_KEYRING="/usr/share/keyrings/tailscale-archive-keyring.gpg"

# Sign-in links work like a one-time password until they're used, so they're
# kept out of the log. The plugin page shows the current one.
REDACT_SED='s#https://login\.tailscale\.com/a/[A-Za-z0-9]*#[sign-in link, shown on the plugin page]#g'
TS_DEFAULTS="/etc/default/tailscaled"
# Turns off tailscaled's diagnostic log upload to log.tailscale.com, as declared
# in pluginInfo.json's privacy block.
NO_LOGS_FLAG="--no-logs-no-support"
TS_STATE_DIR="/var/lib/tailscale"
TS_SOCKET="/var/run/tailscale/tailscaled.sock"

# Hooks run as root, so this is empty there. (Set after FPP's common, which
# defines its own SUDO.)
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

# split_flags LINE - print each argument of a command line that Tailscale
# printed, one per line, undoing its shell quoting (xargs reads the same
# quotes). Fails unless every argument is a --flag or --flag=value.
split_flags() {
    local out a
    out=$(printf '%s\n' "$1" | xargs -n 1 printf '%s\n' 2>/dev/null) || return 1
    [ -n "$out" ] || return 1
    while IFS= read -r a; do
        [[ "$a" == --[a-z]* ]] || return 1
    done <<< "$out"
    printf '%s\n' "$out"
}

# Filter: remove sign-in links from output headed for the log.
redact() {
    sed -u "$REDACT_SED"
}

# Remove sign-in links that older versions wrote to the log, including FPP's
# rotated copies. Rewritten in place, so anything appending keeps working.
redact_old_logs() {
    local f tmp
    for f in "$LOG_FILE" "$LOG_FILE".[0-9]*; do
        [ -f "$f" ] || continue
        tmp="$f.redact"
        case "$f" in
            *.gz)
                zcat "$f" 2>/dev/null | grep -q 'login\.tailscale\.com/a/' || continue
                zcat "$f" | sed "$REDACT_SED" | gzip > "$tmp" && cat "$tmp" > "$f"
                ;;
            *)
                grep -q 'login\.tailscale\.com/a/' "$f" || continue
                sed "$REDACT_SED" "$f" > "$tmp" && cat "$tmp" > "$f"
                ;;
        esac
        rm -f "$tmp"
    done
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

# run_apt CMD... - run an apt command with its output in the log. During
# install (LOG_ECHO set) it also goes to FPP's install window, which shows
# whole lines as they arrive, with a line every 15 seconds so a long, quiet
# download doesn't look stuck.
run_apt() {
    if [ -z "$LOG_ECHO" ]; then
        "$@" >> "$LOG_FILE" 2>&1
        return
    fi
    local hb rc
    (
        s=0
        # sleep's own output goes nowhere, so a sleep left running after the
        # kill below can't hold the install window's pipe open.
        while sleep 15 > /dev/null 2>&1; do
            s=$((s + 15))
            echo "    ...still working (${s}s)"
        done
    ) &
    hb=$!
    "$@" 2>&1 | tee -a "$LOG_FILE"
    rc=${PIPESTATUS[0]}
    kill "$hb" 2>/dev/null
    wait "$hb" 2>/dev/null
    return "$rc"
}

# Add Tailscale's apt source, as FPP's plugin guidelines (§14.14) require: the
# signing key ships with the plugin (apt/, fingerprint
# 2596 A99E AAB3 3821 893C  0A79 458C A832 957F 5868, the same for every
# Debian and Raspbian release), and a pin lets the source supply only the
# tailscale package. Safe to run again; it also replaces the source that
# tailscale.com/install.sh set up for older plugin versions.
setup_apt_source() {
    local id codename
    id=$(. /etc/os-release && echo "$ID")
    codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
    case "$id" in
        debian|raspbian|ubuntu) ;;
        *) log "ERROR: Tailscale has no apt packages for this OS ($id)"; return 1 ;;
    esac
    if [ -z "$codename" ]; then
        log "ERROR: can't tell which $id release this is"
        return 1
    fi
    $SUDO mkdir -p "$(dirname "$APT_KEYRING")"
    $SUDO install -m 644 "$PLUGIN_DIR/apt/tailscale-archive-keyring.gpg" "$APT_KEYRING" || return 1
    printf '# Added by the fpp-tailscale plugin.\ndeb [signed-by=%s] https://pkgs.tailscale.com/stable/%s %s main\n' \
        "$APT_KEYRING" "$id" "$codename" | $SUDO tee "$APT_LIST" >/dev/null || return 1
    $SUDO tee "$APT_PIN" >/dev/null <<'EOF' || return 1
# Added by the fpp-tailscale plugin: pkgs.tailscale.com may supply the
# tailscale package and nothing else.
Package: *
Pin: origin pkgs.tailscale.com
Pin-Priority: -1

Package: tailscale
Pin: origin pkgs.tailscale.com
Pin-Priority: 500
EOF
    # tailscale.com/install.sh also installed this package for its own copy of
    # the key. Ours replaces it.
    if dpkg -s tailscale-archive-keyring >/dev/null 2>&1; then
        $SUDO apt-get purge -y tailscale-archive-keyring >> "$LOG_FILE" 2>&1
    fi
    $SUDO rm -f "$LEGACY_APT_KEYRING"
}

# Switch an install made by an older plugin version (via tailscale.com/
# install.sh) to the plugin's own apt source. Leaves a Tailscale that was
# installed before the plugin alone.
migrate_apt_source() {
    [ -f "$PREINSTALLED_MARKER" ] && return 0
    ts_installed || return 0
    grep -q "$APT_KEYRING" "$APT_LIST" 2>/dev/null && [ -f "$APT_PIN" ] && return 0
    log "Switching Tailscale to the plugin's apt source"
    setup_apt_source
}

# Install Tailscale if it's missing (first install, or an FPP OS upgrade wiped
# it). It isn't declared in pluginInfo.json's dependencies because it isn't in
# Debian: it comes from Tailscale's own apt source, which the plugin adds
# (guidelines §6.2). Its Debian dependency, iptables, is declared for FPP 10,
# which installs it first; older FPP has apt pull it in here. The package's
# own install script starts tailscaled; a runtime mask stops that, since only
# Connect (or auto-connect) may start it (§4.4). The mask goes away on unmask
# or reboot.
ensure_installed() {
    ts_installed && return 0
    log "Tailscale not found, installing it from pkgs.tailscale.com..."
    setup_apt_source || return 1
    local masked="" rc before
    before=$(installed_packages)
    if [ -d /run/systemd/system ] && $SUDO systemctl mask --runtime tailscaled >/dev/null 2>&1; then
        masked=1
    fi
    # Refresh only Tailscale's source first: usually enough, and much faster
    # than refreshing everything (Raspbian's lists alone are ~16 MB). If the
    # install still fails, the image's Debian lists are probably too old for
    # the Debian packages Tailscale needs (iptables and its libraries), so
    # refresh all and retry.
    log "Updating Tailscale's package list..."
    run_apt $SUDO apt-get update -o Dir::Etc::SourceList=sources.list.d/tailscale.list \
        -o Dir::Etc::SourceParts=- -o APT::Get::List-Cleanup=0
    log "Downloading and installing Tailscale..."
    run_apt $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale
    rc=$?
    if [ "$rc" -ne 0 ]; then
        log "Refreshing all package lists and trying again (this can take a few minutes)..."
        run_apt $SUDO apt-get update \
            && run_apt $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale
        rc=$?
    fi
    [ -n "$masked" ] && $SUDO systemctl unmask --runtime tailscaled >/dev/null 2>&1
    if [ "$rc" -ne 0 ] || ! ts_installed; then
        log "ERROR: failed to install Tailscale"
        return 1
    fi
    # What apt brought in with it (iptables, unless FPP 10 already installed
    # it as a declared dependency), so uninstalling can remove that too.
    mkdir -p "$DATA_DIR"
    comm -13 <(echo "$before") <(installed_packages) | grep -vx tailscale >> "$APT_ADDED"
    id fpp >/dev/null 2>&1 && chown -R fpp:fpp "$DATA_DIR"
    disable_log_upload >/dev/null
    log "Tailscale installed: $(tailscale version 2>/dev/null | head -n1)"
}

# Names of the installed packages, sorted.
installed_packages() {
    dpkg-query -W -f='${Status} ${Package}\n' 2>/dev/null | awk '$3 == "installed" { print $4 }' | sort
}

# Succeeds once tailscaled answers on its socket.
ts_ready() {
    timeout 5 tailscale status --json 2>/dev/null | grep -q '"BackendState"'
}

# tailscaled's BackendState: Running, Stopped, NeedsLogin, NeedsMachineAuth, ...
ts_backend_state() {
    timeout 5 tailscale status --json 2>/dev/null \
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
        # exec, so the filter is the only process left and holds nothing but
        # the log: a subshell would keep the caller's pipe (the web UI's exec)
        # open for as long as tailscaled runs.
        $SUDO setsid nohup tailscaled "$NO_LOGS_FLAG" "${extra[@]}" \
            --state="$TS_STATE_DIR/tailscaled.state" \
            --socket="$TS_SOCKET" > >(exec sed -u "$REDACT_SED" >> "$LOG_FILE" 2>&1 9>&-) 2>&1 < /dev/null 9>&- &
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

# A Tailscale that was installed before the plugin is put back as it was when
# the plugin is uninstalled. PREINSTALLED_MARKER holds what the plugin may
# change, as key=value lines, each saved before the plugin first changes it.

# preinstalled_get KEY - print a saved value; fails if it wasn't saved.
preinstalled_get() {
    grep -q "^$1=" "$PREINSTALLED_MARKER" 2>/dev/null || return 1
    sed -n "s/^$1=//p" "$PREINSTALLED_MARKER" | head -n 1
}

# preinstalled_save KEY VALUE - save it, unless it's already saved.
preinstalled_save() {
    [ -f "$PREINSTALLED_MARKER" ] || return 0
    grep -q "^$1=" "$PREINSTALLED_MARKER" || printf '%s=%s\n' "$1" "$2" >> "$PREINSTALLED_MARKER"
}

# Save what isn't saved yet: the service state and tailscaled's FLAGS always,
# and Tailscale's own settings once tailscaled is running.
save_preinstalled() {
    [ -f "$PREINSTALLED_MARKER" ] || return 0
    if [ -d /run/systemd/system ]; then
        preinstalled_save service_enabled "$(systemctl is-enabled tailscaled 2>/dev/null)"
        preinstalled_save service_active "$(systemctl is-active tailscaled 2>/dev/null)"
    fi
    [ -f "$TS_DEFAULTS" ] && preinstalled_save flags "$(grep '^FLAGS=' "$TS_DEFAULTS" | tail -n 1)"
    preinstalled_get hostname >/dev/null && return 0
    ts_ready || return 0
    local prefs k v
    # shellcheck disable=SC2016 # PHP code, not shell
    prefs=$(timeout 10 tailscale debug prefs 2>/dev/null | php -r '
        $p = json_decode(stream_get_contents(STDIN), true);
        if (!is_array($p)) {
            exit(1);
        }
        $apply = isset($p["AutoUpdate"]["Apply"]) ? $p["AutoUpdate"]["Apply"] : null;
        echo "hostname=", isset($p["Hostname"]) ? $p["Hostname"] : "", "\n",
            "accept_routes=", empty($p["RouteAll"]) ? "false" : "true", "\n",
            "auto_update=", $apply === null ? "" : ($apply ? "true" : "false"), "\n",
            "want_running=", empty($p["WantRunning"]) ? "false" : "true", "\n";
    ') || return 0
    while IFS='=' read -r k v; do
        preinstalled_save "$k" "$v"
    done <<< "$prefs"
}

# Put back what save_preinstalled saved. Anything not saved is left as it is.
restore_preinstalled() {
    local v flags_changed="" have_systemd=""
    local -a args=()
    [ -d /run/systemd/system ] && have_systemd=1
    if preinstalled_get hostname >/dev/null; then
        # Tailscale's settings can only be changed while it runs.
        if ! ts_ready && [ -n "$have_systemd" ]; then
            $SUDO systemctl start tailscaled >/dev/null 2>&1
            wait_ready 15
        fi
        if ts_ready; then
            log "Putting back Tailscale's own settings..."
            args=("--hostname=$(preinstalled_get hostname)" "--accept-routes=$(preinstalled_get accept_routes)")
            v=$(preinstalled_get auto_update)
            # It was unset (Tailscale's default), which the CLI can't set
            # again. If the plugin turned it on, turn it off.
            # shellcheck disable=SC2016 # PHP code, not shell
            if [ -z "$v" ] && timeout 10 tailscale debug prefs 2>/dev/null \
                | php -r '$p = json_decode(stream_get_contents(STDIN), true); exit(empty($p["AutoUpdate"]["Apply"]) ? 1 : 0);'; then
                v=false
            fi
            [ -n "$v" ] && args+=("--auto-update=$v")
            timeout 15 $SUDO tailscale set "${args[@]}" >> "$LOG_FILE" 2>&1
            if [ "$(preinstalled_get want_running)" = true ]; then
                ts_logged_in && timeout 15 $SUDO tailscale up >> "$LOG_FILE" 2>&1
            else
                timeout 15 $SUDO tailscale down >> "$LOG_FILE" 2>&1
            fi
        else
            log "WARNING: tailscaled isn't running, so its own settings weren't put back"
        fi
    fi
    if v=$(preinstalled_get flags) && [ -f "$TS_DEFAULTS" ] \
        && [ "$(grep '^FLAGS=' "$TS_DEFAULTS" | tail -n 1)" != "$v" ]; then
        log "Putting back tailscaled's FLAGS in $TS_DEFAULTS"
        $SUDO sed -i '/^FLAGS=/d' "$TS_DEFAULTS"
        [ -n "$v" ] && echo "$v" | $SUDO tee -a "$TS_DEFAULTS" >/dev/null
        flags_changed=1
    fi
    [ -n "$have_systemd" ] || return 0
    case "$(preinstalled_get service_enabled)" in
        enabled) $SUDO systemctl enable tailscaled >/dev/null 2>&1 ;;
        disabled) $SUDO systemctl disable tailscaled >/dev/null 2>&1 ;;
    esac
    case "$(preinstalled_get service_active)" in
        active)
            if [ -n "$flags_changed" ]; then
                $SUDO systemctl restart tailscaled
            else
                $SUDO systemctl start tailscaled
            fi
            ;;
        inactive|failed) $SUDO systemctl stop tailscaled ;;
    esac
}
