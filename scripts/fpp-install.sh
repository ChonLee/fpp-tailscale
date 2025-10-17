#!/bin/bash
# fpp-install.sh - Install Tailscale on FPP and generate auth URL

# Get plugin base directory (one level above scripts/)
PLUGIN_DIR="$(dirname "$0")/.."

# Files to communicate with PHP
STATUS_FILE="$PLUGIN_DIR/install_status.txt"
AUTH_FILE="$PLUGIN_DIR/auth_url.txt"

# Clear previous files
> "$STATUS_FILE"
> "$AUTH_FILE"

echo "Starting Tailscale installation..." >> "$STATUS_FILE"

# Update package list
echo "Updating system packages..." >> "$STATUS_FILE"
sudo apt-get update -y >> "$STATUS_FILE" 2>&1

# Install curl if not present
if ! command -v curl >/dev/null 2>&1; then
    echo "Installing curl..." >> "$STATUS_FILE"
    sudo apt-get install curl -y >> "$STATUS_FILE" 2>&1
fi

# Download and install Tailscale
echo "Installing Tailscale..." >> "$STATUS_FILE"
curl -fsSL https://tailscale.com/install.sh | sh >> "$STATUS_FILE" 2>&1

# Bring up Tailscale in auth mode
echo "Starting Tailscale in auth mode..." >> "$STATUS_FILE"
sudo tailscale up --authkey=$(tailscale generate-authkey) --advertise-exit-node --accept-routes --reset >> "$STATUS_FILE" 2>&1 &

# Retrieve auth URL
AUTH_URL=$(sudo tailscale up --qr 2>&1 | grep 'https://login.tailscale.com')
if [ -n "$AUTH_URL" ]; then
    echo "$AUTH_URL" > "$AUTH_FILE"
    echo "Auth URL saved to $AUTH_FILE" >> "$STATUS_FILE"
else
    echo "Unable to get Tailscale auth URL yet." >> "$STATUS_FILE"
fi

echo "Installation script finished." >> "$STATUS_FILE"
