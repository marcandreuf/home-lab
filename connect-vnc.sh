#!/bin/bash

# Default values
DEFAULT_USER="ubdesk1"
DEFAULT_LOCAL_PORT=59003
DEFAULT_REMOTE_PORT=5901
DEFAULT_VNC_DISPLAY=1

# Function to show usage
show_usage() {
    echo "Usage: $0 <HOST_IP> [USER] [LOCAL_PORT] [REMOTE_PORT] [VNC_DISPLAY]"
    echo ""
    echo "Parameters:"
    echo "  HOST_IP      - Remote host IP address (required)"
    echo "  USER         - SSH username (default: $DEFAULT_USER)"
    echo "  LOCAL_PORT   - Local port for tunnel (default: $DEFAULT_LOCAL_PORT)"
    echo "  REMOTE_PORT  - Remote VNC port (default: $DEFAULT_REMOTE_PORT)"
    echo "  VNC_DISPLAY  - VNC display number (default: $DEFAULT_VNC_DISPLAY)"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100"
    echo "  $0 192.168.1.100 myuser 59004 5902 2"
}

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up..."
    if [[ -n "$SSH_PID" ]] && kill -0 "$SSH_PID" 2>/dev/null; then
        echo "Killing SSH tunnel (PID: $SSH_PID)"
        kill "$SSH_PID"
    fi
    exit 0
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Parse parameters
if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_usage
    exit 1
fi

HOST_IP="$1"
USER="${2:-$DEFAULT_USER}"
LOCAL_PORT="${3:-$DEFAULT_LOCAL_PORT}"
REMOTE_PORT="${4:-$DEFAULT_REMOTE_PORT}"
VNC_DISPLAY="${5:-$DEFAULT_VNC_DISPLAY}"

# Validate HOST_IP
if [[ ! "$HOST_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "Error: Invalid IP address format"
    exit 1
fi

# Validate ports
if ! [[ "$LOCAL_PORT" =~ ^[0-9]+$ ]] || ! [[ "$REMOTE_PORT" =~ ^[0-9]+$ ]]; then
    echo "Error: Ports must be numeric"
    exit 1
fi

echo "Connecting to $HOST_IP as $USER"
echo "Using local port: $LOCAL_PORT, remote port: $REMOTE_PORT, VNC display: $VNC_DISPLAY"

# Test SSH connection first
echo "Testing SSH connection..."
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$USER@$HOST_IP" 'echo "SSH connection successful"' 2>/dev/null; then
    echo "Error: Cannot establish SSH connection to $USER@$HOST_IP"
    exit 1
fi

# Check if VNC server is already running on the specified display
echo "Checking VNC server status..."
VNC_CHECK_OUTPUT=$(ssh -o ConnectTimeout=10 "$USER@$HOST_IP" "vncserver -list 2>/dev/null" || echo "")

if echo "$VNC_CHECK_OUTPUT" | grep -q ":$VNC_DISPLAY[[:space:]]"; then
    echo "VNC server already running on display :$VNC_DISPLAY"
    echo "$VNC_CHECK_OUTPUT" | grep ":$VNC_DISPLAY"
    echo "Proceeding with connection..."
else
    echo "Starting VNC server on display :$VNC_DISPLAY..."
    VNC_START_OUTPUT=$(ssh -t "$USER@$HOST_IP" "vncserver :$VNC_DISPLAY" 2>&1)
    
    # Check if it failed to start (but ignore "already running" messages)
    if [[ $? -ne 0 ]] && [[ ! "$VNC_START_OUTPUT" =~ "already running" ]]; then
        echo "Error: Failed to start VNC server"
        echo "$VNC_START_OUTPUT"
        exit 1
    elif [[ "$VNC_START_OUTPUT" =~ "already running" ]]; then
        echo "VNC server was already running on display :$VNC_DISPLAY"
    else
        echo "VNC server started successfully"
    fi
fi

# Show current VNC servers
echo "Current VNC servers:"
ssh "$USER@$HOST_IP" 'vncserver -list'

# Check if local port is already in use
if lsof -Pi ":$LOCAL_PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Warning: Port $LOCAL_PORT is already in use"
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create SSH tunnel
echo "Creating SSH tunnel: localhost:$LOCAL_PORT -> $HOST_IP:$REMOTE_PORT"
ssh -L "$LOCAL_PORT:localhost:$REMOTE_PORT" -C -N -l "$USER" "$HOST_IP" &
SSH_PID=$!

# Wait a moment for tunnel to establish
sleep 2

# Check if tunnel is working
if ! kill -0 "$SSH_PID" 2>/dev/null; then
    echo "Error: SSH tunnel failed to establish"
    exit 1
fi

# Test the tunnel
if ! nc -z localhost "$LOCAL_PORT" 2>/dev/null; then
    echo "Error: Cannot connect to local port $LOCAL_PORT"
    exit 1
fi

echo "SSH tunnel established successfully (PID: $SSH_PID)"
echo "Starting VNC viewer..."

# Start VNC viewer
if command -v vncviewer >/dev/null 2>&1; then
    vncviewer "localhost::$LOCAL_PORT"
else
    echo "Error: vncviewer not found. Please install a VNC client."
    exit 1
fi

# Cleanup will be handled by the trap