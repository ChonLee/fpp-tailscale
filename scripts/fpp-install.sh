#!/bin/bash
echo "Installing Tailscale..."

# Add the Tailscale package repository and install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Enable and start Tailscale
sudo systemctl enable --now tailscaled

# Run Tailscale and capture the authorization URL
auth_link=$(sudo tailscale up 2>&1 | grep "https://login.tailscale.com")

# Store the authorization URL in a file to display in the FPP web UI
echo "$auth_link" > /home/fpp/media/plugins/fpp-tailscale/auth_url.txt

echo "Tailscale installed. Follow the displayed authorization link to complete setup."
