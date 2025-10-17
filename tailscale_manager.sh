#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ACTION=$1
set -e

ACTION=$1

TAILSCALE_BIN="/usr/sbin/tailscale"
LOG_FILE="/tmp/tailscale_install.log"

install_tailscale() {
    echo "Installing Tailscale..." | tee $LOG_FILE
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian bookworm main" | sudo tee /etc/apt/sources.list.d/tailscale.list
    sudo apt-get update -qq | tee -a $LOG_FILE
    sudo apt-get install -y tailscale | tee -a $LOG_FILE
    echo "Tailscale installed." | tee -a $LOG_FILE
}

show_auth_link() {
    if ! $TAILSCALE_BIN status &>/dev/null; then
        echo "Tailscale not running"
        exit 1
    fi
    LINK=$($TAILSCALE_BIN up --qr 2>/dev/null || echo "")
    echo "$LINK"
}

tailscale_up() {
    sudo $TAILSCALE_BIN up
}

tailscale_down() {
    sudo $TAILSCALE_BIN down
}

tailscale_status() {
    $TAILSCALE_BIN status --json || echo "{}"
}

case "$ACTION" in
    install)
        install_tailscale
        ;;
    auth)
        show_auth_link
        ;;
    up)
        tailscale_up
        ;;
    down)
        tailscale_down
        ;;
    status)
        tailscale_status
        ;;
    *)
        echo "Usage: $0 {install|auth|up|down|status}"
        ;;
esac
