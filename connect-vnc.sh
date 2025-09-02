#!/bin/bash

# connect-vnc.sh: Connect to a remote VNC session via SSH tunnel
#
# Usage:
#   ./connect-vnc.sh <HOST_IP> [USER] [LOCAL_PORT] [REMOTE_PORT] [VNC_DISPLAY] [--restart]
#
# Parameters:
#   HOST_IP      - Remote host IP address (required)
#   USER         - SSH username (default: ubdesk1)
#   LOCAL_PORT   - Local port for tunnel (default: 59003)
#   REMOTE_PORT  - Remote VNC port (default: 5901)
#   VNC_DISPLAY  - VNC display number (default: 1)
#   --restart    - (Optional) Restart the VNC server on the remote host. WARNING: This will kill all running apps in the VNC session!
#
# Examples:
#   ./connect-vnc.sh 192.168.1.100
#   ./connect-vnc.sh 192.168.1.100 myuser 59004 5902 2
#   ./connect-vnc.sh 192.168.1.100 myuser 59003 5901 1 --restart
#
# Notes:
# - By default, the script will connect to an existing VNC session if available, preserving all running apps.
# - Use --restart only if you need to reset the VNC session (e.g., authentication issues). This will terminate all running processes in the session.

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
    
    # Kill SSH tunnel
    if [[ -n "$SSH_PID" ]] && kill -0 "$SSH_PID" 2>/dev/null; then
        echo "Killing SSH tunnel (PID: $SSH_PID)"
        kill "$SSH_PID" 2>/dev/null
        sleep 2
        # Force kill if still running
        if kill -0 "$SSH_PID" 2>/dev/null; then
            kill -9 "$SSH_PID" 2>/dev/null
        fi
    fi
    
    # Kill any remaining SSH tunnels on this port
    cleanup_local_port
    
    exit 0
}

# Function to clean up local port
cleanup_local_port() {
    echo "Checking for processes using local port $LOCAL_PORT..."
    local pids=$(lsof -t -i:"$LOCAL_PORT" 2>/dev/null)
    if [[ -n "$pids" ]]; then
        echo "Killing processes on port $LOCAL_PORT: $pids"
        echo "$pids" | xargs kill -TERM 2>/dev/null || true
        sleep 2
        # Force kill any remaining
        local remaining_pids=$(lsof -t -i:"$LOCAL_PORT" 2>/dev/null)
        if [[ -n "$remaining_pids" ]]; then
            echo "Force killing remaining processes: $remaining_pids"
            echo "$remaining_pids" | xargs kill -9 2>/dev/null || true
        fi
    fi
}

# Function to restart VNC server
restart_vnc_server() {
    echo "Restarting VNC server on display :$VNC_DISPLAY..."
    
    # Kill existing VNC server
    ssh "$USER@$HOST_IP" "vncserver -kill :$VNC_DISPLAY" 2>/dev/null || true
    sleep 2
    
    # Force kill if still running
    ssh "$USER@$HOST_IP" "pkill -f 'Xvnc.*:$VNC_DISPLAY'" 2>/dev/null || true
    sleep 1
    
    # Start VNC server
    echo "Starting fresh VNC server..."
    VNC_START_OUTPUT=$(ssh -t "$USER@$HOST_IP" "vncserver :$VNC_DISPLAY -localhost no" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        echo "VNC server restarted successfully"
        return 0
    else
        echo "Error restarting VNC server:"
        echo "$VNC_START_OUTPUT"
        return 1
    fi
}

# Function to handle VNC connection with retry logic
connect_vnc_with_retry() {
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo "VNC connection attempt $attempt/$max_attempts"
        
        # Verify tunnel is still working
        if ! nc -z localhost "$LOCAL_PORT" 2>/dev/null; then
            echo "SSH tunnel is down, re-establishing..."
            if ! establish_ssh_tunnel; then
                echo "Failed to re-establish SSH tunnel"
                return 1
            fi
        fi
        
        # Start VNC viewer
        if command -v vncviewer >/dev/null 2>&1; then
            echo "Starting VNC viewer on localhost::$LOCAL_PORT"
            vncviewer "localhost::$LOCAL_PORT" 2>/dev/null
            vnc_exit_code=$?
            
            if [[ $vnc_exit_code -eq 0 ]]; then
                echo "VNC session ended normally"
                return 0
            fi
            
            echo "VNC viewer exited with code: $vnc_exit_code"
            
            # If this isn't the last attempt, ask user what to do
            if [[ $attempt -lt $max_attempts ]]; then
                echo ""
                echo "VNC connection failed. Options:"
                echo "1) Retry connection (attempt $((attempt + 1))/$max_attempts)"
                echo "2) Restart VNC server and retry"
                echo "3) Exit"
                echo ""
                read -p "Choose option (1-3): " -n 1 -r choice
                echo ""
                
                case $choice in
                    1)
                        echo "Retrying connection..."
                        ;;
                    2)
                        if restart_vnc_server; then
                            echo "VNC server restarted, retrying connection..."
                        else
                            echo "Failed to restart VNC server"
                            return 1
                        fi
                        ;;
                    3|*)
                        echo "Exiting..."
                        return 1
                        ;;
                esac
            fi
        else
            echo "Error: vncviewer not found. Please install a VNC client."
            return 1
        fi
        
        ((attempt++))
        sleep 2
    done
    
    echo "All VNC connection attempts failed"
    return 1
}

# Function to establish SSH tunnel
establish_ssh_tunnel() {
    # Clean up any existing connections on this port first
    cleanup_local_port
    
    # Create SSH tunnel
    echo "Creating SSH tunnel: localhost:$LOCAL_PORT -> $HOST_IP:$REMOTE_PORT"
    ssh -L "$LOCAL_PORT:127.0.0.1:$REMOTE_PORT" -C -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -l "$USER" "$HOST_IP" &
    SSH_PID=$!
    
    # Wait for tunnel to establish
    echo "Waiting for SSH tunnel to establish..."
    local tunnel_ready=false
    for i in {1..15}; do
        sleep 1
        
        # Check if SSH process is still running
        if ! kill -0 "$SSH_PID" 2>/dev/null; then
            echo "Error: SSH tunnel process died (attempt $i/15)"
            return 1
        fi
        
        # Test if the tunnel is working
        if nc -z localhost "$LOCAL_PORT" 2>/dev/null; then
            echo "SSH tunnel established successfully (attempt $i/15)"
            tunnel_ready=true
            break
        fi
        
        echo "Tunnel not ready yet (attempt $i/15)..."
    done
    
    if ! $tunnel_ready; then
        echo "Error: SSH tunnel failed to establish"
        return 1
    fi
    
    echo "SSH tunnel established successfully (PID: $SSH_PID)"
    return 0
}

## Removed automatic cleanup trap to keep remote session and apps alive


# Parse parameters and flags
RESTART_VNC=false
for arg in "$@"; do
    if [[ "$arg" == "--restart" ]]; then
        RESTART_VNC=true
    fi
done

if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_usage
    echo "  --restart     - Restart VNC server (kills running session and apps!)"
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

# Clean up any existing processes using our local port
cleanup_local_port

# Test SSH connection first
echo "Testing SSH connection..."
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$USER@$HOST_IP" 'echo "SSH connection successful"' 2>/dev/null; then
    echo "Error: Cannot establish SSH connection to $USER@$HOST_IP"
    exit 1
fi



# Check if VNC server is already running on the specified display
echo "Checking VNC server status..."
VNC_CHECK_OUTPUT=$(ssh -o ConnectTimeout=10 "$USER@$HOST_IP" "vncserver -list 2>/dev/null" || echo "")

if $RESTART_VNC; then
    echo "Restarting VNC server as requested by --restart flag. This will kill running apps!"
    if ! restart_vnc_server; then
        exit 1
    fi
elif echo "$VNC_CHECK_OUTPUT" | grep -q ":$VNC_DISPLAY[[:space:]]"; then
    echo "VNC server already running on display :$VNC_DISPLAY"
    echo "$VNC_CHECK_OUTPUT" | grep ":$VNC_DISPLAY"
    echo "Proceeding with existing VNC server..."
else
    echo "VNC server not detected by vncserver -list. Attempting to start it..."
    VNC_START_OUTPUT=$(ssh -t "$USER@$HOST_IP" "vncserver :$VNC_DISPLAY -localhost no" 2>&1)
    if echo "$VNC_START_OUTPUT" | grep -q "already running"; then
        echo "VNC server is already running for display :$VNC_DISPLAY. Proceeding to connect."
    elif echo "$VNC_START_OUTPUT" | grep -q "New '"; then
        echo "VNC server started successfully."
    else
        echo "Failed to start VNC server. Output:"
        echo "$VNC_START_OUTPUT"
        exit 1
    fi
fi

# Show current VNC servers
echo "Current VNC servers:"
ssh "$USER@$HOST_IP" 'vncserver -list'

# Establish SSH tunnel
if ! establish_ssh_tunnel; then
    exit 1
fi

# Connect to VNC with retry logic
echo "Starting VNC connection with retry capability..."
connect_vnc_with_retry

# Cleanup will be handled by the trap