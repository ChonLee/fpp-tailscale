#!/bin/bash
# fpp-install.sh
# Install Tailscale and write auth link

AUTH_FILE="/home/fpp/media/plugins/fpp-tailscale/auth_url.txt"

echo "Installing Tailscale..."

# Install curl if missing
if ! command -v curl >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y curl
fi

# Add Tailscale repo
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.gpg | sudo gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian bookworm main" | sudo tee /etc/apt/sources.list.d/tailscale.list

# Install Tailscale
sudo apt-get update
sudo apt-get install -y tailscale

# Check installation
if ! command -v tailscale >/dev/null 2>&1; then
    echo "Tailscale install failed"
    exit 1
fi

# Start Tailscale in headless mode and get auth URL
AUTH_URL=$(sudo tailscale up --authkey= --qr --accept-routes 2>&1 | grep "https://login.tailscale.com")

if [ -z "$AUTH_URL" ]; then
    echo "Failed to get Tailscale auth URL"
    exit 1
fi

# Write auth URL to file
mkdir -p "$(dirname "$AUTH_FILE")"
echo "$AUTH_URL" > "$AUTH_FILE"

echo "Tailscale installed. Authorization link written to $AUTH_FILE"
