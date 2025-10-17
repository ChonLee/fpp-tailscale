#!/bin/bash
# fpp-install.sh
STATUS_FILE="/home/fpp/media/plugins/fpp-tailscale/install_status.txt"
AUTH_FILE="/home/fpp/media/plugins/fpp-tailscale/auth_url.txt"

# Clear previous status
echo "" > "$STATUS_FILE"
echo "" > "$AUTH_FILE"

log() {
    echo "$(date '+%H:%M:%S') $1" >> "$STATUS_FILE"
}

log "Starting Tailscale installation..."

# Install curl if missing
if ! command -v curl >/dev/null 2>&1; then
    log "Installing curl..."
    sudo apt-get update >> "$STATUS_FILE" 2>&1
    sudo apt-get install -y curl >> "$STATUS_FILE" 2>&1
fi

# Add Tailscale repo
log "Adding Tailscale repository..."
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.gpg | sudo gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg >> "$STATUS_FILE" 2>&1
echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian bookworm main" | sudo tee /etc/apt/sources.list.d/tailscale.list >> "$STATUS_FILE" 2>&1

# Install Tailscale
log "Installing Tailscale..."
sudo apt-get update >> "$STATUS_FILE" 2>&1
sudo apt-get install -y tailscale >> "$STATUS_FILE" 2>&1

# Check installation
if ! command -v tailscale >/dev/null 2>&1; then
    log "Tailscale install failed"
    exit 1
fi

log "Tailscale installed."

# Start Tailscale in headless mode and get auth URL
log "Getting Tailscale auth link..."
AUTH_URL=$(sudo tailscale up --authkey= --qr --accept-routes 2>&1 | grep "https://login.tailscale.com")

if [ -z "$AUTH_URL" ]; then
    log "Failed to get Tailscale auth URL"
    exit 1
fi

# Write auth URL to file
mkdir -p "$(dirname "$AUTH_FILE")"
echo "$AUTH_URL" > "$AUTH_FILE"
log "Authorization link written to $AUTH_FILE"
log "Installation complete."
