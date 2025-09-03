#!/bin/sh

# Debug wrapper to catch all command calls
# This will help us identify what command is causing the "Unknown option: sleep" error

COMMAND_NAME=$(basename "$0")
echo "DEBUG: $COMMAND_NAME called with: $*" >&2

# Handle different commands appropriately
case "$COMMAND_NAME" in
    "perl")
        # Perl is not a BusyBox applet, call it directly
        exec /usr/bin/perl "$@"
        ;;
    "sh")
        # sh is not a BusyBox applet in this context, call it directly
        exec /bin/sh "$@"
        ;;
    *)
        # For other commands, try BusyBox first
        /bin/busybox "$COMMAND_NAME" "$@"
        ;;
esac
