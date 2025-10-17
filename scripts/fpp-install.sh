#!/bin/bash
# FPP Tailscale Plugin Installer
# Author: John Myers

PLUGIN_DIR="$(dirname "$(readlink -f "$0")")"
AUTH_FILE="$PLUGIN_DIR/../auth_url.txt"

echo "Installing Tailscale..."

# Install Tailscale using official install script
curl -fsSL https://tailscale.com/install.sh | sh

# Enable the daemon
sudo systemctl enable --now tailscaled

# Bring up Tailscale and capture the auth link
# Run in background to avoid blocking
(
    # Wait a few seconds to ensure tailscaled is ready
    sleep 3

    # Get auth URL
    auth_link=$(sudo tailscale up 2>&1 | grep "https://login.tailscale.com")

    # Write auth link to plugin folder
    if [ -n "$auth_link" ]; then
        echo "$auth_link" > "$AUTH_FILE"
        chmod 644 "$AUTH_FILE"
        echo "Tailscale auth link saved to $AUTH_FILE"
    else
        echo "Could not generate Tailscale auth link"
    fi
) &

echo "Tailscale installation started. Authorization link will appear in the plugin shortly."
