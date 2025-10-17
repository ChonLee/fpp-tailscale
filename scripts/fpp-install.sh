#!/bin/bash
# fpp-install.sh
# Installs Tailscale on FPP and outputs the auth URL to auth_url.txt

# Location for plugin files
PLUGIN_DIR="/home/fpp/media/plugins/fpp-tailscale"
AUTH_FILE="$PLUGIN_DIR/auth_url.txt"

# Ensure plugin dir exists
mkdir -p "$PLUGIN_DIR"

echo "Installing Tailscale..."

# Install Tailscale using official install script
curl -fsSL https://tailscale.com/install.sh | sh
if [ $? -ne 0 ]; then
    echo "Error installing Tailscale"
    exit 1
fi

echo "Tailscale installed."

# Bring Tailscale up and capture the auth URL
echo "Starting Tailscale to get auth URL..."
AUTH_URL=$(sudo tailscale up --qr | grep -o 'https://login.tailscale.com/[^\ ]*')

if [ -n "$AUTH_URL" ]; then
    echo "Auth URL captured: $AUTH_URL"
    echo "$AUTH_URL" > "$AUTH_FILE"
    chmod 644 "$AUTH_FILE"
else
    echo "Could not get auth URL. Tailscale may already be authorized."
    echo "" > "$AUTH_FILE"
fi

echo "Installation complete. Open your plugin page and click the authorization link."
