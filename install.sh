#!/bin/bash
# FPP Tailscale plugin install script

PLUGIN_DIR="$(dirname "$0")"

echo "Setting execute permissions for tailscale_manager.sh..."
chmod +x "$PLUGIN_DIR/tailscale_manager.sh"

echo "FPP Tailscale plugin installed successfully."
exit 0
