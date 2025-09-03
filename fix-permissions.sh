#!/bin/bash

# Fix permissions for mounted volumes
# This script ensures that the imapsync user can write to logs and data directories

echo "Fixing permissions for mounted volumes..."

# Get current user info
CURRENT_USER=$(whoami)
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

echo "Running as user: $CURRENT_USER (UID: $CURRENT_UID, GID: $CURRENT_GID)"

# Ensure directories exist with proper permissions
mkdir -p /app/logs /app/data

# If running as root, fix ownership properly
if [ "$CURRENT_UID" = "0" ]; then
    echo "Running as root, fixing ownership..."
    chown -R 1000:1000 /app/logs /app/data
    chmod -R 755 /app/logs /app/data
else
    echo "Running as non-root user, attempting permission fixes..."
    # Try to fix permissions as much as possible
    chmod 755 /app/logs /app/data 2>/dev/null || true
    chmod 644 /app/logs/* 2>/dev/null || true
    chmod 644 /app/data/* 2>/dev/null || true
fi

# Test write permissions
if touch /app/logs/test.log 2>/dev/null; then
    rm -f /app/logs/test.log
    echo "✓ Logs directory is writable"
else
    echo "✗ Warning: Logs directory may not be writable"
fi

if touch /app/data/test.pid 2>/dev/null; then
    rm -f /app/data/test.pid
    echo "✓ Data directory is writable"
else
    echo "✗ Warning: Data directory may not be writable"
fi

echo "Permission fix completed."
