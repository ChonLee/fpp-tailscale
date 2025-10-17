#!/bin/bash
# fpp-install.sh
# FPP Tailscale Plugin Install Script

PLUGIN_DIR="/home/fpp/media/plugins/fpp-tailscale"
AUTH_FILE="$PLUGIN_DIR/auth_url.txt"

echo "Starting FPP Tailscale Plugin installation..."

# 1. Update package lists
sudo apt-get update -y

# 2. Install Tailscale if not already installed
if ! command -v tailscale >/dev/null 2>&1; then
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
else
    echo "Tailscale already installed."
fi

# 3. Ensure plugin directory exists
mkdir -p "$PLUGIN_DIR"

# 4. Create placeholder auth_url.txt if it doesn't exist
if [ ! -f "$AUTH_FILE" ]; then
    echo "Creating placeholder auth_url.txt..."
    echo "Waiting for authorization link..." > "$AUTH_FILE"
fi

# 5. Set permissions so FPP can read the file
chown fpp:fpp "$AUTH_FILE"
chmod 644 "$AUTH_FILE"

# 6. Provide instructions to user
echo ""
echo "Installation complete!"
echo "To authorize Tailscale, click the 'Authorize Tailscale' button in the plugin page."
echo "If you have an auth key, you can run:"
echo "sudo tailscale up --authkey=<YOUR_KEY> > $AUTH_FILE 2>&1 &"

exit 0
