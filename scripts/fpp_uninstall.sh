#!/bin/bash
#
# FPP uninstall script: logs out, removes Tailscale entirely, and deletes the
# plugin's config and log. If Tailscale was installed before the plugin, it's
# left as it is.
#
# Plugin Manager's Reinstall runs this too, then installs the plugin again. A
# Reinstall keeps Tailscale signed in and the plugin's settings. FPP 10.2+
# marks a Reinstall's uninstall in its plugin history, but only after this
# script exits, so there the removal runs from a copy in /run once FPP has
# written that record. Older FPP has no such record: everything is removed
# straight away.
#

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
LOG_ECHO=1

FPP_HISTORY="$CFGDIR/pluginHistory.jsonl"
STAGE_DIR="/run/fpp-tailscale-uninstall"

remove_all() {
    if [ -f "$PREINSTALLED_MARKER" ]; then
        # Tailscale was here before the plugin: leave it installed and signed in.
        log "Tailscale was installed before this plugin, so it's left in place."
    else
        if command -v tailscale >/dev/null 2>&1; then
            log "Logging out of Tailscale..."
            timeout 15 $SUDO tailscale down >/dev/null 2>&1
            timeout 15 $SUDO tailscale logout >/dev/null 2>&1
        fi

        log "Stopping tailscaled..."
        if [ -d /run/systemd/system ]; then
            $SUDO systemctl disable --now tailscaled >/dev/null 2>&1
        fi
        $SUDO pkill -x tailscaled 2>/dev/null
        # tailscaled's own cache; the package purge doesn't remove it.
        $SUDO rm -rf /var/cache/tailscale

        if command -v apt-get >/dev/null 2>&1; then
            log "Removing the Tailscale package and its apt source..."
            $SUDO apt-get purge -y tailscale >> "$LOG_FILE" 2>&1
            if dpkg -s tailscale-archive-keyring >/dev/null 2>&1; then
                $SUDO apt-get purge -y tailscale-archive-keyring >> "$LOG_FILE" 2>&1
            fi
            $SUDO rm -f "$APT_LIST" "$APT_KEYRING" "$APT_PIN" "$LEGACY_APT_KEYRING"
            # apt's cached copies of that source's package lists, and the
            # downloaded package.
            $SUDO rm -f /var/lib/apt/lists/pkgs.tailscale.com_* \
                /var/cache/apt/archives/tailscale_*.deb /var/cache/apt/archives/tailscale-archive-keyring_*.deb
        fi

        # FPP's own network settings for tailscale0, if any were saved on its
        # Network page, deleted through FPP's API (FPP 10+); FPP drops the matching
        # systemd-networkd file the next time it sets up the network. Older FPP
        # has no such API, and the leftover file is harmless there, since
        # systemd-networkd doesn't manage tailscale0.
        curl -fsS -m 10 -X DELETE "http://localhost/api/network/interface/tailscale0" >/dev/null 2>&1 || true
    fi

    log "Removing plugin configuration and logs..."
    rm -f "$CONFIG_FILE" "$CONFIG_FILE.tmp" "$LOG_FILE"
    rm -rf "$DATA_DIR"
}

# finish_after_fpp START PLUGIN_DIR - run from the copy in $STAGE_DIR. Waits
# for FPP to record this uninstall (after line START of its plugin history),
# then removes everything unless it was the first half of a Reinstall.
finish_after_fpp() {
    local start=$1 plugin_dir=$2 entry=""
    for _ in $(seq 600); do
        entry=$(tail -n +"$((start + 1))" "$FPP_HISTORY" 2>/dev/null \
            | grep '"action":"uninstall","plugin":"fpp-tailscale"' | tail -n 1)
        [ -n "$entry" ] && break
        sleep 1
    done
    case "$entry" in
        *'"reinstall":true'*)
            log "Reinstall: Tailscale and the plugin's settings were kept." ;;
        "")
            # No record after 10 minutes. If the plugin is back, it was reinstalled.
            [ -d "$plugin_dir" ] || remove_all ;;
        *)
            remove_all ;;
    esac
    rm -rf "$STAGE_DIR"
}

if [ "$1" = "--finish" ]; then
    LOG_ECHO=
    finish_after_fpp "$2" "$3"
    exit 0
fi

log "=== Uninstalling Tailscale plugin ==="

kill_pending_up

if grep -qF "['reinstall'] = true" "$FPPDIR/www/api/controllers/plugin.php" 2>/dev/null; then
    # FPP deletes the plugin directory next, so run from a copy.
    rm -rf "$STAGE_DIR"
    mkdir -p "$STAGE_DIR"
    cp "$PLUGIN_DIR/scripts/common.sh" "$PLUGIN_DIR/scripts/fpp_uninstall.sh" "$STAGE_DIR/"
    lines=$(cat "$FPP_HISTORY" 2>/dev/null | wc -l)
    setsid bash "$STAGE_DIR/fpp_uninstall.sh" --finish "$lines" "$PLUGIN_DIR" </dev/null >/dev/null 2>&1 &
    log "A Reinstall keeps Tailscale signed in and the plugin's settings. Otherwise, Tailscale and the settings are removed once FPP finishes uninstalling."
    echo "=== Tailscale plugin uninstalled ==="
    exit 0
fi

remove_all

echo "=== Tailscale plugin uninstalled ==="
exit 0
