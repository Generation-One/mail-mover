#!/bin/bash

# IMAP Synchronization Service
# Production-ready script with proper logging, error handling, and health monitoring

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/logs/imapsync.log"
PID_FILE="${SCRIPT_DIR}/data/imapsync.pid"
HEALTH_FILE="${SCRIPT_DIR}/data/health"

# Fix permissions for mounted volumes first
if [[ -f "${SCRIPT_DIR}/fix-permissions.sh" ]]; then
    bash "${SCRIPT_DIR}/fix-permissions.sh"
fi

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$PID_FILE")"

# Try to create log file with proper permissions
touch "$LOG_FILE" 2>/dev/null || true
chmod 644 "$LOG_FILE" 2>/dev/null || true

# Logging function with fallback for permission issues
log() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"

    # Always output to stdout (for Docker logs)
    echo "$message"

    # Try to also write to log file (best effort, don't duplicate on failure)
    echo "$message" >> "$LOG_FILE" 2>/dev/null || true
}

# Signal handlers for graceful shutdown
cleanup() {
    log "INFO" "Received shutdown signal, cleaning up..."
    # Only remove files if they were successfully created
    [[ -n "$PID_FILE" && -f "$PID_FILE" ]] && rm -f "$PID_FILE"
    [[ -f "$HEALTH_FILE" ]] && rm -f "$HEALTH_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Load environment variables from file if available
load_env_file() {
    local env_files=(".env.test" ".env" ".env.example")

    for env_file in "${env_files[@]}"; do
        if [[ -f "$env_file" ]]; then
            log "INFO" "Loading environment from $env_file"
            set -a
            source "$env_file" 2>/dev/null || true
            set +a
            return 0
        fi
    done

    log "WARN" "No environment file found, using system environment variables"
    return 0
}

# Validate required environment variables (with alternative names)
validate_config() {
    # Map alternative variable names to standard names
    [[ -z "${HOST_1:-}" && -n "${SOURCE_HOST:-}" ]] && export HOST_1="$SOURCE_HOST"
    [[ -z "${HOST_2:-}" && -n "${DEST_HOST:-}" ]] && export HOST_2="$DEST_HOST"
    [[ -z "${HOST_2:-}" && -n "${DESTINATION_HOST:-}" ]] && export HOST_2="$DESTINATION_HOST"

    [[ -z "${USER_1:-}" && -n "${SOURCE_USER:-}" ]] && export USER_1="$SOURCE_USER"
    [[ -z "${USER_2:-}" && -n "${DEST_USER:-}" ]] && export USER_2="$DEST_USER"
    [[ -z "${USER_2:-}" && -n "${DESTINATION_USER:-}" ]] && export USER_2="$DESTINATION_USER"

    [[ -z "${PASSWORD_1:-}" && -n "${SOURCE_PASSWORD:-}" ]] && export PASSWORD_1="$SOURCE_PASSWORD"
    [[ -z "${PASSWORD_2:-}" && -n "${DEST_PASSWORD:-}" ]] && export PASSWORD_2="$DEST_PASSWORD"
    [[ -z "${PASSWORD_2:-}" && -n "${DESTINATION_PASSWORD:-}" ]] && export PASSWORD_2="$DESTINATION_PASSWORD"

    # Also check for common Portainer/Docker naming patterns
    [[ -z "${HOST_1:-}" && -n "${IMAP_SOURCE_HOST:-}" ]] && export HOST_1="$IMAP_SOURCE_HOST"
    [[ -z "${HOST_2:-}" && -n "${IMAP_DEST_HOST:-}" ]] && export HOST_2="$IMAP_DEST_HOST"
    [[ -z "${USER_1:-}" && -n "${IMAP_SOURCE_USER:-}" ]] && export USER_1="$IMAP_SOURCE_USER"
    [[ -z "${USER_2:-}" && -n "${IMAP_DEST_USER:-}" ]] && export USER_2="$IMAP_DEST_USER"
    [[ -z "${PASSWORD_1:-}" && -n "${IMAP_SOURCE_PASSWORD:-}" ]] && export PASSWORD_1="$IMAP_SOURCE_PASSWORD"
    [[ -z "${PASSWORD_2:-}" && -n "${IMAP_DEST_PASSWORD:-}" ]] && export PASSWORD_2="$IMAP_DEST_PASSWORD"

    local required_vars=("HOST_1" "USER_1" "PASSWORD_1" "HOST_2" "USER_2" "PASSWORD_2")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log "ERROR" "Missing required environment variables: ${missing_vars[*]}"
        log "INFO" "Available environment files: .env.test, .env, .env.example"
        log "INFO" "Set these variables in Portainer:"
        log "INFO" "  HOST_1 (or SOURCE_HOST) = source IMAP server"
        log "INFO" "  USER_1 (or SOURCE_USER) = source email address"
        log "INFO" "  PASSWORD_1 (or SOURCE_PASSWORD) = source app password"
        log "INFO" "  HOST_2 (or DEST_HOST) = destination IMAP server"
        log "INFO" "  USER_2 (or DEST_USER) = destination email address"
        log "INFO" "  PASSWORD_2 (or DEST_PASSWORD) = destination app password"

        # Debug: Show all environment variables that start with HOST_, USER_, PASSWORD_
        log "DEBUG" "Environment variables starting with HOST_:"
        env | grep "^HOST_" || log "DEBUG" "No HOST_ variables found"
        log "DEBUG" "Environment variables starting with USER_:"
        env | grep "^USER_" || log "DEBUG" "No USER_ variables found"
        log "DEBUG" "Environment variables starting with PASSWORD_:"
        env | grep "^PASSWORD_" || log "DEBUG" "No PASSWORD_ variables found"

        # Check for alternative naming patterns
        log "DEBUG" "Alternative naming patterns:"
        env | grep -E "^(SOURCE_|DEST_|DESTINATION_|IMAP_)" || log "DEBUG" "No alternative patterns found"

        # Show all environment variables for debugging
        log "DEBUG" "All environment variables:"
        env | sort

        log "INFO" "Container will wait for environment variables to be configured..."

        # Wait indefinitely instead of exiting (prevents restart loop)
        while [[ ${#missing_vars[@]} -gt 0 ]]; do
            sleep 30
            log "INFO" "Still waiting for environment variables: ${missing_vars[*]}"

            # Re-check environment variables
            missing_vars=()
            for var in "${required_vars[@]}"; do
                if [[ -z "${!var:-}" ]]; then
                    missing_vars+=("$var")
                fi
            done
        done

        log "INFO" "Environment variables now available, continuing..."
    fi

    # Set defaults for optional variables
    SYNC_MODE="${SYNC_MODE:-poll}"
    POLL_SECONDS="${POLL_SECONDS:-15}"
    FOLDER="${FOLDER:-INBOX}"
    MOVE="${MOVE:-false}"
    DATE_FILTER_DAYS="${DATE_FILTER_DAYS:-30}"
    MAX_EMAILS_PER_SYNC="${MAX_EMAILS_PER_SYNC:-1000}"

    log "INFO" "Configuration validation passed"
    log "INFO" "Sync mode: $SYNC_MODE"
    log "INFO" "Date filter: ${DATE_FILTER_DAYS} days"
    log "INFO" "Max emails per sync: $MAX_EMAILS_PER_SYNC"
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

# Build imapsync command with safety limits
build_sync_command() {
    local cmd="imapsync"

    # Connection parameters
    cmd+=" --host1 '$HOST_1' --user1 '$USER_1' --password1 '$PASSWORD_1'"
    cmd+=" --host2 '$HOST_2' --user2 '$USER_2' --password2 '$PASSWORD_2'"

    # Folder selection
    cmd+=" --folder '${FOLDER}'"

    # SSL/TLS options (default to SSL for security)
    if [[ "${SSL1:-true}" == "true" ]]; then
        cmd+=" --ssl1"
    fi
    if [[ "${SSL2:-true}" == "true" ]]; then
        cmd+=" --ssl2"
    fi
    [[ "${NOTLS1:-}" == "true" ]] && cmd+=" --notls1"
    [[ "${NOTLS2:-}" == "true" ]] && cmd+=" --notls2"

    # Move mode (delete from source after successful copy)
    [[ "${MOVE}" == "true" ]] && cmd+=" --delete1"

    # Date filtering - always apply to prevent massive syncs
    local days_ago="${DATE_FILTER_DAYS}"
    cmd+=" --maxage $days_ago"
    log "INFO" "Date filter: syncing emails from last $days_ago days"

    # Email count limits to prevent rate limiting
    local max_emails="${MAX_EMAILS_PER_SYNC}"
    cmd+=" --maxmessages $max_emails"
    log "INFO" "Email limit: maximum $max_emails emails per sync"

    # Size limits to prevent huge transfers
    cmd+=" --maxsize 50000000"  # 50MB max per email
    log "INFO" "Size limit: 50MB maximum per email"

    # Performance and reliability flags
    cmd+=" --useuid --automap --fastio1 --fastio2 --syncinternaldates --skipcrossduplicates"

    # Rate limiting protection
    cmd+=" --sleep 0.1"  # Small delay between operations

    # Enhanced logging
    cmd+=" --debug --debugimap --logfile '$LOG_FILE'"

    echo "$cmd"
}

# Perform synchronization with detailed logging
sync_emails() {
    local sync_cmd
    sync_cmd=$(build_sync_command)

    log "INFO" "Starting email synchronization..."
    log "INFO" "Source: ${USER_1}@${HOST_1}:${FOLDER}"
    log "INFO" "Destination: ${USER_2}@${HOST_2}:${FOLDER}"
    log "DEBUG" "Sync command: imapsync [credentials hidden] --folder '${FOLDER}' --maxage ${DATE_FILTER_DAYS} --maxmessages ${MAX_EMAILS_PER_SYNC}"

    # Create a temporary log file for this sync
    local sync_log="/tmp/sync_$(date +%s).log"

    # Run imapsync and capture output
    local start_time=$(date +%s)
    if eval "$sync_cmd" > "$sync_log" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        # Parse imapsync output for statistics
        local messages_transferred=0
        local messages_skipped=0
        local bytes_transferred=0

        if [[ -f "$sync_log" ]]; then
            # Extract statistics from imapsync output
            messages_transferred=$(grep -o "Transferred: [0-9]*" "$sync_log" | tail -1 | grep -o "[0-9]*" || echo "0")
            messages_skipped=$(grep -o "Skipped: [0-9]*" "$sync_log" | tail -1 | grep -o "[0-9]*" || echo "0")
            bytes_transferred=$(grep -o "Total bytes transferred: [0-9]*" "$sync_log" | grep -o "[0-9]*" || echo "0")

            # Log detailed statistics
            log "INFO" "Synchronization completed successfully in ${duration}s"
            log "INFO" "Messages transferred: $messages_transferred"
            log "INFO" "Messages skipped: $messages_skipped"
            log "INFO" "Bytes transferred: $bytes_transferred"

            # Append sync log to main log
            echo "=== Sync Details $(date) ===" >> "$LOG_FILE"
            cat "$sync_log" >> "$LOG_FILE"
            echo "=== End Sync Details ===" >> "$LOG_FILE"
        fi

        # Clean up temp log
        rm -f "$sync_log"

        echo "healthy" > "$HEALTH_FILE"
        return 0
    else
        local exit_code=$?
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log "ERROR" "Synchronization failed with exit code: $exit_code after ${duration}s"

        # Log error details
        if [[ -f "$sync_log" ]]; then
            log "ERROR" "Error details:"
            tail -20 "$sync_log" | while read line; do
                log "ERROR" "  $line"
            done

            # Append error log to main log
            echo "=== Sync Error $(date) ===" >> "$LOG_FILE"
            cat "$sync_log" >> "$LOG_FILE"
            echo "=== End Sync Error ===" >> "$LOG_FILE"
        fi

        # Clean up temp log
        rm -f "$sync_log"

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
    log "INFO" "Version: 1.1.0"

    # Store PID (with error handling)
    if ! echo $$ > "$PID_FILE" 2>/dev/null; then
        log "WARN" "Could not write PID file to $PID_FILE, continuing without PID file"
        PID_FILE=""  # Disable PID file usage
    else
        log "INFO" "PID file created: $PID_FILE"
    fi

    # Load environment file if available
    load_env_file

    # Validate configuration
    validate_config

    log "INFO" "Poll interval: ${POLL_SECONDS} seconds"
    log "INFO" "Target folder: ${FOLDER}"
    log "INFO" "Move mode: ${MOVE}"
    
    # Test connections on startup (disabled for debugging)
    log "INFO" "Skipping connection test, proceeding with sync..."
    # if ! test_connections; then
    #     log "ERROR" "Initial connection test failed, exiting"
    #     exit 1
    # fi
    
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
