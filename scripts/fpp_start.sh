#!/bin/bash
#
# FPP Start Script for Tailscale Plugin
# Ensures tailscaled is installed and running when FPP starts
# Futureproofed: Reinstalls Tailscale if removed by FPPOS update
#

CONFIG_FILE="/home/fpp/media/config/plugin.fpp-tailscale"
LOG_FILE="/var/log/fpp-tailscale.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log "=== FPP Start - Tailscale Plugin ==="

# Check if Tailscale is installed
if ! command -v tailscale &> /dev/null; then
    log "⚠️  Tailscale not found - possibly removed by FPPOS update"
    log "Reinstalling Tailscale..."
    
    if curl -fsSL https://tailscale.com/install.sh | sh >> "$LOG_FILE" 2>&1; then
        log "✓ Tailscale reinstalled successfully"
    else
        log "ERROR: Failed to reinstall Tailscale"
        exit 1
    fi
fi

# Read config value helper for INI files
get_config_value() {
    local key=$1
    if [ -f "$CONFIG_FILE" ]; then
        grep "^${key}\s*=" "$CONFIG_FILE" | cut -d'=' -f2- | tr -d ' '
    fi
}

# Ensure tailscaled is running
if ! pgrep -x "tailscaled" > /dev/null; then
    log "Starting tailscaled daemon..."
    
    # Try systemctl first
    if sudo systemctl enable --now tailscaled >> "$LOG_FILE" 2>&1; then
        log "✓ Tailscaled started via systemctl"
    else
        # Fallback to manual start
        log "Systemctl failed, starting manually..."
        sudo mkdir -p /var/lib/tailscale /var/run/tailscale
        sudo chmod 755 /var/lib/tailscale /var/run/tailscale
        
        if nohup sudo tailscaled --state=/var/lib/tailscale/tailscaled.state >> "$LOG_FILE" 2>&1 &
        then
            log "✓ Tailscaled started manually"
            sleep 2
        else
            log "ERROR: Failed to start tailscaled"
            exit 1
        fi
    fi
else
    log "✓ Tailscaled already running"
fi

# Check auto-connect setting
auto_connect=$(get_config_value "auto_connect")
accept_routes=$(get_config_value "accept_routes")
hostname=$(get_config_value "hostname")

# Use system hostname if not set or default
if [ -z "$hostname" ] || [ "$hostname" = "fpp-player" ]; then
    hostname=$(hostname)
fi

if [ "$auto_connect" = "true" ] || [ "$auto_connect" = "True" ]; then
    log "Auto-connect enabled"
    
    # Wait for daemon to be ready
    sleep 2
    
    # Build tailscale up command with system hostname
    UP_CMD="sudo tailscale up --hostname=${hostname}"
    
    if [ "$accept_routes" = "true" ] || [ "$accept_routes" = "True" ]; then
        UP_CMD="$UP_CMD --accept-routes"
    fi
    
    # Execute connect
    if $UP_CMD >> "$LOG_FILE" 2>&1; then
        log "Auto-connect successful with hostname: ${hostname}"
    else
        log "Auto-connect completed (may need authentication)"
    fi
else
    log "Auto-connect disabled"
fi

log "=== Tailscale Plugin Start Complete ==="
exit 0
