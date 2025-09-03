#!/bin/sh

# ps command wrapper for BusyBox compatibility
# Handles specific imapsync ps commands

# Debug: log the command being called (commented out to reduce noise)
# echo "ps wrapper called with: $*" >&2

# Parse arguments to handle specific imapsync commands
case "$*" in
    *"-o rss -p"*)
        # imapsync wants RSS memory for specific PIDs: ps -o rss -p PID1 PID2 ...
        # Extract PIDs after -p and return fake RSS values
        echo "RSS"
        shift; shift; shift  # Remove "ps -o rss -p"
        for pid in "$@"; do
            echo "1024"  # Fake RSS value in KB
        done
        ;;
    *"-e -o pid"*)
        # imapsync wants all PIDs: ps -e -o pid
        echo "PID"
        /bin/busybox ps | tail -n +2 | while read pid user time cmd rest; do
            echo "$pid"
        done
        ;;
    *"-o pid"*)
        # Generic PID request
        echo "PID"
        /bin/busybox ps | tail -n +2 | while read pid user time cmd rest; do
            echo "$pid"
        done
        ;;
    *"sleep"*)
        # Handle sleep-related ps calls - only PIDs of sleep processes
        echo "PID"
        /bin/busybox ps | grep sleep | while read pid user time cmd rest; do
            echo "$pid"
        done || true
        ;;
    *)
        # Default case - provide standard ps output
        /bin/busybox ps "$@"
        ;;
esac
