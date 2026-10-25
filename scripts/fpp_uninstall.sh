#!/bin/bash
#
# FPP uninstall script: logs out, removes Tailscale entirely, and deletes the
# plugin's config and log. If Tailscale was installed before the plugin, it's
# left installed, with what the plugin changed put back.
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
        # Tailscale was here before the plugin: leave it installed and signed
        # in, and put back what the plugin changed.
        log "Tailscale was installed before this plugin, so it's left in place."
        restore_preinstalled
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
        # Network page, deleted through FPP's API (FPP 10.1+); FPP drops the matching
        # systemd-networkd file the next time it sets up the network. Older FPP
        # has no such API, and the leftover file is harmless there, since
        # systemd-networkd doesn't manage tailscale0.
        curl -fsS -m 10 -X DELETE "http://localhost/api/network/interface/tailscale0" >/dev/null 2>&1 || true

        remove_released_packages
    fi

    log "Removing plugin configuration and logs..."
    rm -f "$CONFIG_FILE" "$CONFIG_FILE.tmp" "$LOG_FILE"
    rm -rf "$DATA_DIR"
}

# Remove the packages installed for tailscale, now that it's gone:
# - What apt brought in with it (APT_ADDED). On FPP before 10, that's
#   iptables, since only FPP 10 installs declared dependencies.
# - On FPP 10.2+, what FPP installed for the plugin (pluginInfo.json's
#   dependencies: iptables). FPP releases those before it writes the record
#   finish_after_fpp waits for, while tailscale still needs them, so it
#   leaves them installed and stops tracking them.
# Only what nothing else claims in FPP's package list, and only if removing
# them takes nothing else with them, as FPP itself does.
remove_released_packages() {
    command -v apt-get >/dev/null 2>&1 || return 0
    local pkgs extra
    local -a list
    # shellcheck disable=SC2016 # PHP code, not shell
    pkgs=$(php -r '
        // Everything added since the uninstall before this one: a Reinstall
        // keeps the packages, so its install adds nothing.
        $added = array();
        $reset = false;
        foreach (@file($argv[1], FILE_IGNORE_NEW_LINES) ?: array() as $line) {
            $e = json_decode($line, true);
            if (!is_array($e) || ($e["plugin"] ?? "") !== "fpp-tailscale") {
                continue;
            }
            if (($e["action"] ?? "") === "install") {
                if ($reset) {
                    $added = array();
                    $reset = false;
                }
                $added = array_merge($added, $e["fppPackages"]["added"] ?? array());
            } elseif (($e["action"] ?? "") === "uninstall" && empty($e["reinstall"])) {
                $reset = true;
            }
        }
        $added = array_merge($added, @file($argv[3], FILE_IGNORE_NEW_LINES) ?: array());
        $claimed = array();
        foreach (json_decode((string)@file_get_contents($argv[2]), true) ?: array() as $row) {
            $claimed[] = is_array($row) ? ($row["package"] ?? "") : $row;
        }
        $names = array();
        foreach ($added as $p) {
            $name = preg_replace("/[: ].*/", "", trim($p));
            if (preg_match("/^[a-z0-9][a-z0-9.+-]*$/", $name) && !in_array($name, $claimed, true)) {
                $names[$name] = true;
            }
        }
        foreach (array_keys($names) as $name) {
            echo $name, "\n";
        }
    ' "$FPP_HISTORY" "$CFGDIR/userpackages.json" "$APT_ADDED" 2>/dev/null)
    [ -n "$pkgs" ] || return 0
    mapfile -t list <<< "$pkgs"
    extra=$(apt-get -s purge "${list[@]}" 2>/dev/null | sed -n 's/^Purg \([^ :]*\).*/\1/p' \
        | grep -vxF -f <(echo "$pkgs") | tr '\n' ' ')
    if [ -n "$extra" ]; then
        log "Leaving ${list[*]} installed: removing them would also remove $extra"
        return 0
    fi
    log "Removing what was installed for Tailscale: ${list[*]}"
    $SUDO apt-get purge -y "${list[@]}" >> "$LOG_FILE" 2>&1
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
