#!/bin/bash

# Health check script for IMAP synchronization service
# Checks if the sync process is running and healthy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/data/imapsync.pid"
HEALTH_FILE="${SCRIPT_DIR}/data/health"
MAX_AGE=300  # 5 minutes

# Check if PID file exists and process is running
check_process() {
    if [[ ! -f "$PID_FILE" ]]; then
        echo "ERROR: PID file not found"
        return 1
    fi
    
    local pid
    pid=$(cat "$PID_FILE")
    
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "ERROR: Process $pid is not running"
        return 1
    fi
    
    return 0
}

# Check health status file
check_health_status() {
    if [[ ! -f "$HEALTH_FILE" ]]; then
        echo "ERROR: Health file not found"
        return 1
    fi
    
    local status
    status=$(head -n1 "$HEALTH_FILE")
    
    if [[ "$status" != "healthy" ]]; then
        echo "ERROR: Service status is $status"
        return 1
    fi
    
    # Check if health file is recent
    local health_time
    if health_time=$(sed -n '2p' "$HEALTH_FILE" 2>/dev/null) && [[ -n "$health_time" ]]; then
        local current_time
        current_time=$(date '+%s')
        local age=$((current_time - health_time))
        
        if [[ $age -gt $MAX_AGE ]]; then
            echo "ERROR: Health status is stale (${age}s old)"
            return 1
        fi
    fi
    
    return 0
}

# Main health check
main() {
    if check_process && check_health_status; then
        echo "OK: Service is healthy"
        exit 0
    else
        echo "CRITICAL: Service is unhealthy"
        exit 1
    fi
}

main "$@"
