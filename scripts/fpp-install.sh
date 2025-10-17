#!/bin/bash

PLUGIN_DIR="/home/fpp/media/plugins/fpp-tailscale"
AUTH_FILE="$PLUGIN_DIR/auth_url.txt"

echo "=== Installing Tailscale ==="

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled

# Make sure plugin directory exists
mkdir -p "$PLUGIN_DIR"

# Attempt to start Tailscale and grab auth link
# Run in background to avoid blocking
{
    echo "Starting Tailscale authentication..."
    auth_link=""
    while [ -z "$auth_link" ]; do
        auth_link=$(sudo tailscale up 2>&1 | grep -o "https://login.tailscale.com[^ ]*")
        if [ -z "$auth_link" ]; then
            sleep 2
        fi
    done

    echo "$auth_link" > "$AUTH_FILE"
    echo "Tailscale installed! Authorization link saved to $AUTH_FILE"
} &

# Optional: write a temporary HTML snippet for FPP web UI
UI_FILE="$PLUGIN_DIR/auth_link.html"
echo "<html><body>" > "$UI_FILE"
echo "<h3>Tailscale Authorization</h3>" >> "$UI_FILE"
echo "<p>Click this link to authorize this device:</p>" >> "$UI_FILE"
echo "<a href='#' id='tailscale_link'>Generating link...</a>" >> "$UI_FILE"
echo "<script>
fetch('auth_url.txt')
  .then(r => r.text())
  .then(t => document.getElementById('tailscale_link').href = t)
  .then(t => document.getElementById('tailscale_link').textContent = 'Authorize Tailscale');
</script>" >> "$UI_FILE"
echo "</body></html>" >> "$UI_FILE"

echo "=== Plugin installation finished ==="