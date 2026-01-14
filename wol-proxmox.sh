#!/bin/bash
# start-server.sh - Wake on LAN script for Proxmox server

# Prevent locale warnings when running via SSH
export LC_ALL=C.UTF-8

MAC="xx:xx:xx:xx:xx:xx"  # Replace with your enp9s0 MAC from `cat /sys/class/net/enp9s0/address`
BROADCAST="192.168.219.255"

echo "Sending magic packet to $BROADCAST:9 with $MAC"

wakeonlan -i $BROADCAST $MAC

if [ $? -eq 0 ]; then
    echo "✓ Magic packet sent successfully"
else
    echo "✗ Failed to send magic packet"
fi
