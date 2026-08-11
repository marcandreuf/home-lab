#!/usr/bin/env bash
set -euo pipefail

# Setup: chmod +x zerotier-reset-identity.sh

# Usage: sudo ./zerotier-reset-identity.sh <NETWORK_ID>
# Example: sudo ./zerotier-reset-identity.sh abcd1234abcd1234

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <NETWORK_ID>"
  exit 1
fi

NETWORK_ID="$1"

# Validate NETWORK_ID (hex, 16 chars typical, but be permissive)
if ! [[ "$NETWORK_ID" =~ ^[0-9a-fA-F]{6,}$ ]]; then
  echo "Error: NETWORK_ID must be a non-empty hex string."
  exit 1
fi

echo "[*] Stopping zerotier-one service..."
sudo systemctl stop zerotier-one

echo "[*] Removing ZeroTier identity files to generate a new node ID..."
# Identity files location on Ubuntu with zerotier-one package
IDENTITY_DIR="/var/lib/zerotier-one"
sudo rm -f "${IDENTITY_DIR}/identity.public" "${IDENTITY_DIR}/identity.secret"

echo "[*] Starting zerotier-one service..."
sudo systemctl start zerotier-one

# Wait a moment for the service to initialize and generate identity
sleep 2

echo "[*] Leaving network (if joined)..."
sudo zerotier-cli leave "$NETWORK_ID" || true

echo "[*] Joining network ${NETWORK_ID}..."
sudo zerotier-cli join "$NETWORK_ID"

echo "[*] Waiting a few seconds for membership to settle..."
sleep 3

echo "[*] New ZeroTier node info:"
sudo zerotier-cli info

echo "[*] Networks status:"
sudo zerotier-cli listnetworks

echo "[+] Done. Remember to authorize this new member in your ZeroTier controller and assign it a unique Managed IP."


