#!/bin/bash
echo "Uninstalling Tailscale..."

# Stop and disable Tailscale service
sudo systemctl stop tailscaled
sudo systemctl disable tailscaled

# Uninstall Tailscale
sudo apt-get remove -y tailscale
sudo apt-get purge -y tailscale

# Clean up authorization file
rm -f /home/fpp/media/plugins/fpp-tailscale/auth_url.txt

echo "Tailscale uninstalled."
