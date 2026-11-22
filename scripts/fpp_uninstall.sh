#!/bin/bash
#
# FPP uninstall script: logs out, removes Tailscale entirely, and deletes the
# plugin's config and log. If Tailscale was installed before the plugin, it's
# left installed, with what the plugin changed put back.
#
# On the uninstall half of a Reinstall, FPP 10.4+ sets FPP_PLUGIN_REINSTALL=1.
# Tailscale is removed all the same (fpp_install.sh installs it again), but the
# plugin's settings are kept, and so is Tailscale's sign-in: the copy of
# tailscaled's state in the plugin's data folder, which fpp_install.sh puts
# back (it's kept there for FPP OS upgrades too; see keep_ts_state). Anything
# other than 1 (FPP 10.3 and earlier leave it unset) is a real uninstall.
#

. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
LOG_ECHO=1

REINSTALL=
[ "${FPP_PLUGIN_REINSTALL:-0}" = "1" ] && REINSTALL=1

# Purge what apt installed along with tailscale (APT_ADDED), now that it's
# gone. On FPP before 10 that's iptables, since only FPP 10 installs declared
# dependencies; on FPP 10, FPP itself removes iptables once nothing needs it.
# Only if removing them takes nothing else with them.
remove_added_packages() {
    command -v apt-get >/dev/null 2>&1 || return 0
    local extra
    local -a list
    mapfile -t list < <(grep -E '^[a-z0-9][a-z0-9.+-]*$' "$APT_ADDED" 2>/dev/null | sort -u)
    [ "${#list[@]}" -gt 0 ] || return 0
    extra=$(apt-get -s purge "${list[@]}" 2>/dev/null | sed -n 's/^Purg \([^ :]*\).*/\1/p' \
        | grep -vxF -f <(printf '%s\n' "${list[@]}") | tr '\n' ' ')
    if [ -n "$extra" ]; then
        log "Leaving ${list[*]} installed: removing them would also remove $extra"
        return 0
    fi
    log "Removing what was installed with Tailscale: ${list[*]}"
    $SUDO apt-get purge -y "${list[@]}" >> "$LOG_FILE" 2>&1 && rm -f "$APT_ADDED"
}

log "=== Uninstalling Tailscale plugin ==="

kill_pending_up

# The Tailscale that was here before the plugin is gone (an FPP OS upgrade
# replaces the system): there's nothing of it to put back.
if [ -f "$PREINSTALLED_MARKER" ] && ! ts_installed; then
    rm -f "$PREINSTALLED_MARKER"
fi

if [ -f "$PREINSTALLED_MARKER" ]; then
    # Tailscale was here before the plugin: leave it installed and signed in,
    # and put back what the plugin changed.
    log "Tailscale was installed before this plugin, so it's left in place."
    restore_preinstalled
    # A Reinstall keeps the marker, and the plugin hasn't connected it since.
    [ -n "$REINSTALL" ] && sed -i '/^connected=/d' "$PREINSTALLED_MARKER"
elif ts_installed && ! ts_installed_by_plugin; then
    # No marker, but the plugin didn't install this Tailscale either: this
    # script already ran once (and removed the marker with the plugin's data),
    # or the marker was lost. Leave Tailscale as it is.
    log "Tailscale wasn't installed by this plugin, so it's left in place."
else
    if [ -z "$REINSTALL" ] && command -v tailscale >/dev/null 2>&1; then
        log "Logging out of Tailscale..."
        timeout 15 $SUDO tailscale down >/dev/null 2>&1
        timeout 15 $SUDO tailscale logout >/dev/null 2>&1
    fi

    log "Stopping tailscaled..."
    if [ -d /run/systemd/system ]; then
        $SUDO systemctl disable --now tailscaled >/dev/null 2>&1
    fi
    $SUDO pkill -x tailscaled 2>/dev/null
    for _ in $(seq 1 10); do
        pgrep -x tailscaled >/dev/null || break
        sleep 1
    done

    # A Reinstall keeps the sign-in for the new install. After an OS upgrade
    # Tailscale is already gone, and the copy made when it last connected
    # stays as it is.
    if [ -n "$REINSTALL" ] && [ -s "$TS_STATE" ]; then
        log "Reinstall: keeping Tailscale's sign-in for the new install"
        keep_ts_state
    fi
    # tailscaled's state and cache; the package purge doesn't remove them.
    $SUDO rm -rf /var/lib/tailscale /var/cache/tailscale

    if command -v apt-get >/dev/null 2>&1; then
        log "Removing the Tailscale package and its apt source..."
        $SUDO apt-get purge -y tailscale >> "$LOG_FILE" 2>&1
        if dpkg -s tailscale-archive-keyring >/dev/null 2>&1; then
            $SUDO apt-get purge -y tailscale-archive-keyring >> "$LOG_FILE" 2>&1
        fi
        $SUDO rm -f "$APT_LIST" "$APT_KEYRING" "$LEGACY_APT_KEYRING"
        # The pin marks Tailscale as the plugin's (ts_installed_by_plugin), so
        # it stays until the package is gone: a run that failed to purge it
        # can then be repeated.
        ts_installed || $SUDO rm -f "$APT_PIN"
        # apt's cached copies of that source's package lists, and the
        # downloaded package.
        $SUDO rm -f /var/lib/apt/lists/pkgs.tailscale.com_* \
            /var/cache/apt/archives/tailscale_*.deb /var/cache/apt/archives/tailscale-archive-keyring_*.deb
    fi

    # A Reinstall keeps them, as FPP keeps its own packages for one.
    [ -n "$REINSTALL" ] || remove_added_packages

    # FPP's own network settings for tailscale0, if any were saved on its
    # Network page, deleted through FPP's API (FPP 10.1+); FPP drops the
    # matching systemd-networkd file the next time it sets up the network.
    # Older FPP has no such API, and the leftover file is harmless there, since
    # systemd-networkd doesn't manage tailscale0. A Reinstall keeps them.
    if [ -z "$REINSTALL" ]; then
        curl -fsS -m 10 -X DELETE "http://localhost/api/network/interface/tailscale0" >/dev/null 2>&1 || true
    fi
fi

if [ -n "$REINSTALL" ]; then
    log "Reinstall: the plugin's settings were kept."
else
    log "Removing plugin configuration and logs..."
    rm -f "$CONFIG_FILE" "$CONFIG_FILE.tmp" "$LOG_FILE"
    rm -rf "$DATA_DIR"
fi

echo "=== Tailscale plugin uninstalled ==="
exit 0
