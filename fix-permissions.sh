#!/bin/bash

# Fix permissions for mounted volumes
# This script ensures that the imapsync user can write to logs and data directories

echo "Fixing permissions for mounted volumes..."

# Ensure directories exist
mkdir -p /app/logs /app/data

# Fix ownership and permissions for logs and data directories
# Use sudo if available, otherwise try to fix what we can
if command -v sudo >/dev/null 2>&1; then
    sudo chown -R imapsync:imapsync /app/logs /app/data 2>/dev/null || true
    sudo chmod -R 755 /app/logs /app/data 2>/dev/null || true
else
    # Try to fix permissions without sudo
    chown -R imapsync:imapsync /app/logs /app/data 2>/dev/null || true
    chmod -R 755 /app/logs /app/data 2>/dev/null || true
fi

# Ensure the imapsync user can write to these directories
chmod 755 /app/logs /app/data 2>/dev/null || true
chmod 644 /app/logs/* 2>/dev/null || true
chmod 644 /app/data/* 2>/dev/null || true

echo "Permission fix completed."
