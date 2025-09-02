#!/bin/bash

# Setup script for switching between connection modes
# Helps avoid Google rate limits by using persistent connections

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

show_help() {
    cat << EOF
IMAP Sync Connection Mode Setup

This script helps you configure different sync modes to avoid Google rate limits:

USAGE:
    $0 [MODE]

MODES:
    poll    - Traditional polling (default, may hit rate limits)
    idle    - IMAP IDLE persistent connections (recommended)
    push    - Gmail Push Notifications via Pub/Sub (most efficient)
    help    - Show this help message

EXAMPLES:
    $0 idle    # Switch to IDLE mode (recommended for Gmail)
    $0 push    # Switch to Push mode (requires Google Cloud setup)
    $0 poll    # Switch back to polling mode

For detailed setup instructions, see CONNECTION-MODES.md
EOF
}

check_env_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        error ".env file not found!"
        info "Please copy .env.example to .env and configure your settings first:"
        info "  cp .env.example .env"
        exit 1
    fi
}

backup_env() {
    local backup_file="${ENV_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$ENV_FILE" "$backup_file"
    log "Backed up .env to $backup_file"
}

update_env_var() {
    local var_name="$1"
    local var_value="$2"
    
    if grep -q "^${var_name}=" "$ENV_FILE"; then
        # Update existing variable
        sed -i "s/^${var_name}=.*/${var_name}=${var_value}/" "$ENV_FILE"
    else
        # Add new variable
        echo "${var_name}=${var_value}" >> "$ENV_FILE"
    fi
}

setup_poll_mode() {
    log "Setting up POLL mode..."
    
    update_env_var "SYNC_MODE" "poll"
    
    # Prompt for poll interval
    echo
    info "Current polling interval: $(grep '^POLL_SECONDS=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo '15')"
    read -p "Enter polling interval in seconds (15-300, default 60): " poll_seconds
    poll_seconds=${poll_seconds:-60}
    
    if [[ $poll_seconds -lt 15 || $poll_seconds -gt 300 ]]; then
        warn "Poll interval should be between 15-300 seconds. Using 60."
        poll_seconds=60
    fi
    
    update_env_var "POLL_SECONDS" "$poll_seconds"
    
    log "Poll mode configured with ${poll_seconds}s interval"
    warn "Note: Frequent polling may hit Gmail rate limits. Consider IDLE mode."
}

setup_idle_mode() {
    log "Setting up IDLE mode..."
    
    update_env_var "SYNC_MODE" "idle"
    update_env_var "IDLE_TIMEOUT" "1740"  # 29 minutes
    
    log "IDLE mode configured"
    info "This mode keeps persistent connections open for real-time sync"
    info "Recommended for Gmail to avoid rate limits"
}

setup_push_mode() {
    log "Setting up PUSH mode..."
    
    warn "Push mode requires Google Cloud setup. See CONNECTION-MODES.md for details."
    echo
    
    read -p "Have you completed Google Cloud setup? (y/N): " setup_done
    if [[ ! "$setup_done" =~ ^[Yy]$ ]]; then
        error "Please complete Google Cloud setup first:"
        info "1. Create Google Cloud Project"
        info "2. Enable Gmail and Pub/Sub APIs"
        info "3. Create Pub/Sub topic and subscription"
        info "4. Set up OAuth credentials"
        info ""
        info "See CONNECTION-MODES.md for detailed instructions"
        exit 1
    fi
    
    # Get Google Cloud configuration
    read -p "Google Cloud Project ID: " project_id
    read -p "Pub/Sub Topic (default: gmail-sync-topic): " topic_name
    read -p "Pub/Sub Subscription (default: gmail-sync-subscription): " subscription_name
    
    topic_name=${topic_name:-gmail-sync-topic}
    subscription_name=${subscription_name:-gmail-sync-subscription}
    
    if [[ -z "$project_id" ]]; then
        error "Project ID is required for push mode"
        exit 1
    fi
    
    update_env_var "SYNC_MODE" "push"
    update_env_var "GOOGLE_CLOUD_PROJECT" "$project_id"
    update_env_var "PUBSUB_TOPIC" "$topic_name"
    update_env_var "PUBSUB_SUBSCRIPTION" "$subscription_name"
    update_env_var "GOOGLE_CREDENTIALS" "/app/credentials.json"
    update_env_var "GOOGLE_TOKEN" "/app/token.json"
    
    log "Push mode configured"
    warn "Make sure to place credentials.json in your project directory"
    info "The service will prompt for OAuth authentication on first run"
}

restart_service() {
    log "Restarting service with new configuration..."
    
    if command -v make >/dev/null 2>&1; then
        make restart
    else
        docker-compose restart
    fi
    
    log "Service restarted. Monitor with: make logs"
}

main() {
    local mode="${1:-}"
    
    case "$mode" in
        "help"|"-h"|"--help")
            show_help
            exit 0
            ;;
        "poll"|"idle"|"push")
            ;;
        "")
            error "No mode specified"
            show_help
            exit 1
            ;;
        *)
            error "Unknown mode: $mode"
            show_help
            exit 1
            ;;
    esac
    
    check_env_file
    backup_env
    
    case "$mode" in
        "poll")
            setup_poll_mode
            ;;
        "idle")
            setup_idle_mode
            ;;
        "push")
            setup_push_mode
            ;;
    esac
    
    echo
    log "Configuration updated successfully!"
    
    read -p "Restart service now? (Y/n): " restart_now
    if [[ ! "$restart_now" =~ ^[Nn]$ ]]; then
        restart_service
    else
        info "Remember to restart the service: make restart"
    fi
    
    echo
    log "Setup complete! Current mode: $mode"
    info "Monitor logs: make logs"
    info "Check status: make status"
}

main "$@"
