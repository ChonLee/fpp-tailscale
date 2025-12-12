#!/bin/bash
#
# FPP Uninstall Script for Tailscale Plugin
# Cleans up Tailscale installation completely
#

LOG_FILE="/var/log/fpp-tailscale.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "=== Uninstalling Tailscale Plugin ==="

# Disconnect from Tailscale network
log "Disconnecting from Tailscale..."
sudo tailscale down 2>/dev/null || true
sudo tailscale logout 2>/dev/null || true

# Stop and disable service
log "Stopping tailscaled service..."
sudo systemctl stop tailscaled 2>/dev/null || true
sudo systemctl disable tailscaled 2>/dev/null || true

# Kill any running processes
sudo pkill -x tailscaled 2>/dev/null || true

# Remove Tailscale package
log "Removing Tailscale package..."
sudo apt-get remove -y tailscale 2>/dev/null || true
sudo apt-get purge -y tailscale 2>/dev/null || true
sudo apt-get autoremove -y 2>/dev/null || true

# Clean up plugin config file
log "Removing plugin configuration..."
rm -f /home/fpp/media/config/plugin.fpp-tailscale

# Clean up log file
log "Cleaning up log files..."
rm -f /var/log/fpp-tailscale.log

log "=== Tailscale Plugin Fully Uninstalled ==="

exit 0
