#!/bin/bash
# wol-proxmox.sh - Wake on LAN script for Proxmox server
#
# Usage:
#   ./wol-proxmox.sh <MAC_ADDRESS> <BROADCAST_IP>
#
# Parameters:
#   MAC_ADDRESS    - MAC address of target device (e.g., "aa:bb:cc:dd:ee:ff")
#   BROADCAST_IP   - Broadcast address of network (e.g., "192.168.1.255")
#
# Example:
#   ./wol-proxmox.sh "aa:bb:cc:dd:ee:ff" "192.168.1.255"
#
# To find your MAC address, run on the target device:
#   cat /sys/class/net/enp9s0/address
#
# To find your broadcast address:
#   ip -4 addr show | grep brd

# Prevent locale warnings when running via SSH
export LC_ALL=C.UTF-8

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <MAC_ADDRESS> <BROADCAST_IP>"
  echo "Example: $0 'aa:bb:cc:dd:ee:ff' '192.168.1.255'"
  exit 1
fi

MAC="$1"
BROADCAST="$2"

echo "Sending magic packet to $BROADCAST:9 with $MAC"

wakeonlan -i $BROADCAST $MAC

if [ $? -eq 0 ]; then
    echo "✓ Magic packet sent successfully"
else
    echo "✗ Failed to send magic packet"
fi
