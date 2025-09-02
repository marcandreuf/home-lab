#!/bin/bash
# cleanup-vnc.sh: Explicitly clean up VNC server, SSH tunnel, and running apps on remote VM
# Usage: ./cleanup-vnc.sh <HOST_IP> [USER] [VNC_DISPLAY] [LOCAL_PORT]

DEFAULT_USER="ubdesk1"
DEFAULT_VNC_DISPLAY=1
DEFAULT_LOCAL_PORT=59003

HOST_IP="$1"
USER="${2:-$DEFAULT_USER}"
VNC_DISPLAY="${3:-$DEFAULT_VNC_DISPLAY}"
LOCAL_PORT="${4:-$DEFAULT_LOCAL_PORT}"

if [[ -z "$HOST_IP" ]]; then
    echo "Usage: $0 <HOST_IP> [USER] [VNC_DISPLAY] [LOCAL_PORT]"
    exit 1
fi

echo "Cleaning up VNC session and SSH tunnel for $USER@$HOST_IP..."

# Kill SSH tunnel on local machine
pids=$(lsof -t -i:"$LOCAL_PORT" 2>/dev/null)
if [[ -n "$pids" ]]; then
    echo "Killing SSH tunnel processes on port $LOCAL_PORT: $pids"
    echo "$pids" | xargs kill -TERM 2>/dev/null || true
    sleep 2
    remaining_pids=$(lsof -t -i:"$LOCAL_PORT" 2>/dev/null)
    if [[ -n "$remaining_pids" ]]; then
        echo "Force killing remaining SSH tunnel processes: $remaining_pids"
        echo "$remaining_pids" | xargs kill -9 2>/dev/null || true
    fi
else
    echo "No SSH tunnel processes found on port $LOCAL_PORT."
fi

# Kill VNC server and running apps on remote VM
ssh "$USER@$HOST_IP" "vncserver -kill :$VNC_DISPLAY; pkill -f 'Xvnc.*:$VNC_DISPLAY'; pkill -u $USER" 2>/dev/null || true

echo "Cleanup complete."
