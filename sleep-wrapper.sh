#!/bin/sh

# sleep command wrapper for BusyBox compatibility
# Handles GNU sleep options that BusyBox doesn't support

# Debug: log the command being called (commented out to reduce noise)
# echo "sleep wrapper called with: $*" >&2

# Parse arguments to handle specific sleep commands
case "$*" in
    *"--"*)
        # Remove GNU-style long options and just sleep for the numeric value
        for arg in "$@"; do
            case "$arg" in
                [0-9]*)
                    # Found a numeric argument, use it
                    /bin/busybox sleep "$arg"
                    exit $?
                    ;;
            esac
        done
        # If no numeric argument found, default to 1 second
        /bin/busybox sleep 1
        ;;
    *)
        # Default case - pass through to busybox sleep
        /bin/busybox sleep "$@"
        ;;
esac
