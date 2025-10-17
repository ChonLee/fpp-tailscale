#!/bin/bash
# fpp-start.sh
# FPP Tailscale Plugin Start Script

PLUGIN_DIR="/home/fpp/media/plugins/fpp-tailscale"
AUTH_FILE="$PLUGIN_DIR/auth_url.txt"

echo "Starting Tailscale..."

# Make sure the plugin directory exists
mkdir -p "$PLUGIN_DIR"

# Check if Tailscale is installed
if ! command -v tailscale >/dev/null 2>&1; then
    echo "Tailscale is not installed. Please run fpp-install.sh first."
    exit 1
fi

# Stop Tailscale if already running
if tailscale status >/dev/null 2>&1; then
    echo "Stopping existing Tailscale session..."
    sudo tailscale down
fi

# Start Tailscale in up mode and capture the auth URL
echo "Bringing Tailscale up..."
# This will output the auth URL if not yet authenticated
AUTH_URL=$(sudo tailscale up --accept-routes --accept-dns --reset 2>&1 | grep "https://login.tailscale.com")

# If the URL is found, write it to auth_url.txt
if [ -n "$AUTH_URL" ]; then
    echo "$AUTH_URL" > "$AUTH_FILE"
    echo "Authorization URL written to $AUTH_FILE"
else
    # If Tailscale is already authenticated, show running status
    echo "Tailscale is already authorized or running."
    echo "Tailscale is authorized and running!" > "$AUTH_FILE"
fi

# Set permissions so FPP web interface can read the file
chown fpp:fpp "$AUTH_FILE"
chmod 644 "$AUTH_FILE"

echo "Tailscale start process complete."
exit 0
