#!/bin/bash

# restart-program.sh - Restart a program by killing and relaunching it
#
# Usage:
#   ./restart-program.sh <PROGRAM_NAME> [--kill-only]
#
# Parameters:
#   PROGRAM_NAME  - Name of the program to restart (required)
#   --kill-only   - (Optional) Kill the program without restarting it
#
# Examples:
#   ./restart-program.sh conky
#   ./restart-program.sh conky --kill-only
#   ./restart-program.sh firefox
#
# The script will:
#   1. Find all processes matching PROGRAM_NAME
#   2. Kill them forcefully (SIGKILL)
#   3. Restart the program (unless --kill-only is specified)

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <PROGRAM_NAME> [--kill-only]"
    echo "Example: $0 conky"
    exit 1
fi

program_name="$1"
restart_program=true

# Check for --kill-only flag
if [[ "$2" == "--kill-only" ]]; then
    restart_program=false
fi

# Find processes matching the program name, but exclude this script itself
pids=$(pgrep -f "$program_name" | grep -v $$)

if [ -z "$pids" ]; then
    echo "No processes found for program '$program_name'."
else
    for pid in $pids; do
        # Check if process still exists before killing it
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 $pid
            if [ $? -eq 0 ]; then
                echo "Successfully killed process $pid for '$program_name'."
            else
                echo "Failed to kill process $pid."
            fi
        fi
    done
fi

if $restart_program; then
    echo "Restarting $program_name..."
    
    # Try to restart the program
    # First, check if the program exists in PATH
    if ! command -v "$program_name" &> /dev/null; then
        echo "Error: '$program_name' not found in PATH"
        exit 1
    fi
    
    # Print the exact command that will be executed
    echo "Executing: nohup \"$program_name\" > \"${program_name}.log\" 2>&1 &"
    
    # Launch the program with nohup to detach it from this script's lifecycle
    nohup "$program_name" > "${program_name}.log" 2>&1 &
    pid=$!
    
    echo "Process launched with PID: $pid"
    
    # Wait a moment for the process to start
    sleep 2
    
    # Verify the process actually started
    if pgrep -f "$program_name" > /dev/null; then
        echo "Successfully started $program_name (PID: $pid)"
    else
        echo "Failed to start $program_name. Check ${program_name}.log for errors:"
        if [ -f "${program_name}.log" ]; then
            tail -5 "${program_name}.log"
        fi
        exit 1
    fi
fi

