#!/bin/bash

# IMAP Synchronization Service
# Production-ready script with proper logging, error handling, and health monitoring

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/logs/imapsync.log"
PID_FILE="${SCRIPT_DIR}/data/imapsync.pid"
HEALTH_FILE="${SCRIPT_DIR}/data/health"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$PID_FILE")"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

# Signal handlers for graceful shutdown
cleanup() {
    log "INFO" "Received shutdown signal, cleaning up..."
    rm -f "$PID_FILE" "$HEALTH_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Validate required environment variables
validate_config() {
    local required_vars=("HOST_1" "USER_1" "PASSWORD_1" "HOST_2" "USER_2" "PASSWORD_2")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log "ERROR" "Missing required environment variables: ${missing_vars[*]}"
        exit 1
    fi
    
    log "INFO" "Configuration validation passed"
}

# Test IMAP connections
test_connections() {
    log "INFO" "Testing IMAP connections..."
    
    # Build imapsync command for connection testing
    local test_cmd="imapsync"
    test_cmd+=" --host1 '$HOST_1' --user1 '$USER_1' --password1 '$PASSWORD_1'"
    test_cmd+=" --host2 '$HOST_2' --user2 '$USER_2' --password2 '$PASSWORD_2'"
    
    # Add SSL/TLS options
    [[ "${SSL1:-}" == "true" ]] && test_cmd+=" --ssl1"
    [[ "${SSL2:-}" == "true" ]] && test_cmd+=" --ssl2"
    [[ "${NOTLS1:-}" == "true" ]] && test_cmd+=" --notls1"
    [[ "${NOTLS2:-}" == "true" ]] && test_cmd+=" --notls2"
    
    # Test connection only
    test_cmd+=" --justconnect --debug"
    
    if eval "$test_cmd" >> "$LOG_FILE" 2>&1; then
        log "INFO" "Connection test successful"
        return 0
    else
        log "ERROR" "Connection test failed"
        return 1
    fi
}

# Build imapsync command
build_sync_command() {
    local cmd="imapsync"
    
    # Connection parameters
    cmd+=" --host1 '$HOST_1' --user1 '$USER_1' --password1 '$PASSWORD_1'"
    cmd+=" --host2 '$HOST_2' --user2 '$USER_2' --password2 '$PASSWORD_2'"
    
    # Folder selection
    cmd+=" --folder '${FOLDER:-INBOX}'"
    
    # SSL/TLS options
    [[ "${SSL1:-}" == "true" ]] && cmd+=" --ssl1"
    [[ "${SSL2:-}" == "true" ]] && cmd+=" --ssl2"
    [[ "${NOTLS1:-}" == "true" ]] && cmd+=" --notls1"
    [[ "${NOTLS2:-}" == "true" ]] && cmd+=" --notls2"
    
    # Move mode (delete from source after successful copy)
    [[ "${MOVE:-}" == "true" ]] && cmd+=" --delete1"
    
    # Date filtering - only sync emails from last N days (if configured)
    if [[ -n "${DATE_FILTER_DAYS:-}" ]] && [[ "${DATE_FILTER_DAYS}" -gt 0 ]]; then
        local days_ago="${DATE_FILTER_DAYS}"
        cmd+=" --maxage $days_ago"
        log "INFO" "Date filter enabled: syncing emails from last $days_ago days"
    else
        log "INFO" "No date filter applied: syncing all emails"
    fi

    # Performance and reliability flags
    cmd+=" --useuid --automap --fastio1 --fastio2 --syncinternaldates --skipcrossduplicates"

    # Logging and debug
    cmd+=" --debug --debugimap"
    
    echo "$cmd"
}

# Perform synchronization
sync_emails() {
    local sync_cmd
    sync_cmd=$(build_sync_command)
    
    log "INFO" "Starting email synchronization..."
    log "DEBUG" "Sync command: imapsync [credentials hidden] --folder '${FOLDER:-INBOX}' [options]"
    
    if eval "$sync_cmd" >> "$LOG_FILE" 2>&1; then
        log "INFO" "Synchronization completed successfully"
        echo "healthy" > "$HEALTH_FILE"
        return 0
    else
        local exit_code=$?
        log "ERROR" "Synchronization failed with exit code: $exit_code"
        echo "unhealthy" > "$HEALTH_FILE"
        return $exit_code
    fi
}

# Update health status
update_health() {
    echo "healthy" > "$HEALTH_FILE"
    echo "$(date '+%s')" >> "$HEALTH_FILE"
}

# IMAP IDLE mode - keeps connection open
start_idle_mode() {
    log "INFO" "Starting IMAP IDLE synchronization..."

    # Check if Python IDLE script exists
    if [[ -f "/app/imap-idle-sync.py" ]]; then
        python3 /app/imap-idle-sync.py
    else
        log "ERROR" "IMAP IDLE script not found, falling back to polling mode"
        start_poll_mode
    fi
}

# Gmail Push Notification mode
start_push_mode() {
    log "INFO" "Starting Gmail Push Notification synchronization..."

    # Check if Gmail push script exists
    if [[ -f "/app/gmail-push-sync.py" ]]; then
        python3 /app/gmail-push-sync.py
    else
        log "ERROR" "Gmail Push script not found, falling back to polling mode"
        start_poll_mode
    fi
}

# Traditional polling mode (original behavior)
start_poll_mode() {
    log "INFO" "Starting traditional polling mode..."

    # Main sync loop
    while true; do
        update_health

        if sync_emails; then
            log "INFO" "Sync cycle completed, waiting ${POLL_SECONDS:-15} seconds..."
        else
            log "WARN" "Sync cycle failed, waiting ${POLL_SECONDS:-15} seconds before retry..."
        fi

        sleep "${POLL_SECONDS:-15}"
    done
}

# Main execution
main() {
    log "INFO" "IMAP Synchronization Service starting..."
    log "INFO" "Version: 1.0.0"
    log "INFO" "Poll interval: ${POLL_SECONDS:-15} seconds"
    log "INFO" "Target folder: ${FOLDER:-INBOX}"
    log "INFO" "Move mode: ${MOVE:-false}"
    
    # Store PID
    echo $$ > "$PID_FILE"
    
    # Validate configuration
    validate_config
    
    # Test connections on startup
    if ! test_connections; then
        log "ERROR" "Initial connection test failed, exiting"
        exit 1
    fi
    
    # Choose sync mode based on configuration
    local sync_mode="${SYNC_MODE:-poll}"

    case "$sync_mode" in
        "idle")
            log "INFO" "Starting IMAP IDLE mode..."
            start_idle_mode
            ;;
        "push")
            log "INFO" "Starting Gmail Push Notification mode..."
            start_push_mode
            ;;
        *)
            log "INFO" "Starting polling mode..."
            start_poll_mode
            ;;
    esac
}

# Start main execution
main "$@"
