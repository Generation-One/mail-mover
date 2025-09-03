#!/bin/bash

# Test Environment Loading Script
# Tests the conditional environment file loading

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_success() { echo -e "${GREEN}✅ $*${NC}"; }
log_error() { echo -e "${RED}❌ $*${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
log_header() { echo -e "\n${BOLD}${BLUE}=== $* ===${NC}"; }

# Load environment variables from file if available (same logic as sync-script.sh)
load_env_file() {
    local env_files=(".env.test" ".env" ".env.example")
    
    for env_file in "${env_files[@]}"; do
        if [[ -f "$env_file" ]]; then
            log_info "Loading environment from $env_file"
            set -a
            source "$env_file" 2>/dev/null || true
            set +a
            return 0
        fi
    done
    
    log_warning "No environment file found, using system environment variables"
    return 0
}

# Test environment loading
test_env_loading() {
    log_header "Testing Environment Loading"
    
    # Clear any existing variables
    unset HOST_1 USER_1 PASSWORD_1 HOST_2 USER_2 PASSWORD_2
    unset SYNC_MODE DATE_FILTER_DAYS MAX_EMAILS_PER_SYNC
    
    # Load environment
    load_env_file
    
    # Check what was loaded
    log_info "Environment variables loaded:"
    
    local vars=("HOST_1" "USER_1" "HOST_2" "USER_2" "SYNC_MODE" "DATE_FILTER_DAYS" "MAX_EMAILS_PER_SYNC")
    local loaded_count=0
    
    for var in "${vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            if [[ "$var" == *"PASSWORD"* ]]; then
                echo "  $var: [HIDDEN]"
            else
                echo "  $var: ${!var}"
            fi
            ((loaded_count++))
        else
            echo "  $var: (not set)"
        fi
    done
    
    if [[ $loaded_count -gt 0 ]]; then
        log_success "Environment loading successful ($loaded_count variables loaded)"
        return 0
    else
        log_warning "No environment variables loaded"
        return 1
    fi
}

# Test with different file scenarios
test_file_scenarios() {
    log_header "Testing File Priority Scenarios"
    
    # Backup existing files
    [[ -f ".env.test" ]] && mv ".env.test" ".env.test.backup"
    [[ -f ".env" ]] && mv ".env" ".env.backup"
    
    # Test 1: Only .env.example exists
    log_info "Test 1: Only .env.example exists"
    if test_env_loading; then
        log_success "Successfully loaded from .env.example"
    else
        log_error "Failed to load from .env.example"
    fi
    
    # Test 2: Create .env and test priority
    if [[ -f ".env.backup" ]]; then
        cp ".env.backup" ".env"
        log_info "Test 2: Both .env and .env.example exist"
        if test_env_loading; then
            log_success "Successfully loaded from .env (higher priority)"
        else
            log_error "Failed to load from .env"
        fi
        rm ".env"
    fi
    
    # Test 3: Create .env.test and test highest priority
    if [[ -f ".env.test.backup" ]]; then
        cp ".env.test.backup" ".env.test"
        log_info "Test 3: .env.test exists (highest priority)"
        if test_env_loading; then
            log_success "Successfully loaded from .env.test (highest priority)"
        else
            log_error "Failed to load from .env.test"
        fi
        rm ".env.test"
    fi
    
    # Restore backups
    [[ -f ".env.test.backup" ]] && mv ".env.test.backup" ".env.test"
    [[ -f ".env.backup" ]] && mv ".env.backup" ".env"
}

# Test safety defaults
test_safety_defaults() {
    log_header "Testing Safety Defaults"
    
    load_env_file
    
    # Set defaults (same logic as sync-script.sh)
    SYNC_MODE="${SYNC_MODE:-poll}"
    POLL_SECONDS="${POLL_SECONDS:-15}"
    FOLDER="${FOLDER:-INBOX}"
    MOVE="${MOVE:-false}"
    DATE_FILTER_DAYS="${DATE_FILTER_DAYS:-30}"
    MAX_EMAILS_PER_SYNC="${MAX_EMAILS_PER_SYNC:-1000}"
    
    log_info "Safety defaults applied:"
    echo "  SYNC_MODE: $SYNC_MODE"
    echo "  DATE_FILTER_DAYS: $DATE_FILTER_DAYS"
    echo "  MAX_EMAILS_PER_SYNC: $MAX_EMAILS_PER_SYNC"
    echo "  FOLDER: $FOLDER"
    echo "  MOVE: $MOVE"
    
    # Validate safety limits
    if [[ "$DATE_FILTER_DAYS" -le 365 ]] && [[ "$MAX_EMAILS_PER_SYNC" -le 10000 ]]; then
        log_success "Safety limits are reasonable"
        return 0
    else
        log_warning "Safety limits might be too high"
        return 1
    fi
}

# Test Docker environment simulation
test_docker_env() {
    log_header "Testing Docker Environment Simulation"
    
    # Simulate Docker environment (no .env files, only environment variables)
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Set some environment variables
    export HOST_1="imap.gmail.com"
    export USER_1="test@example.com"
    export SYNC_MODE="idle"
    
    log_info "Simulating Docker environment (no .env files)"
    
    if load_env_file; then
        log_info "Environment variables from system:"
        echo "  HOST_1: $HOST_1"
        echo "  USER_1: $USER_1"
        echo "  SYNC_MODE: $SYNC_MODE"
        log_success "Docker environment simulation successful"
        cd - >/dev/null
        rm -rf "$temp_dir"
        return 0
    else
        log_error "Docker environment simulation failed"
        cd - >/dev/null
        rm -rf "$temp_dir"
        return 1
    fi
}

# Main test execution
main() {
    log_header "Environment Loading Test Suite - $(date)"
    
    local tests_passed=0
    local total_tests=0
    
    # Run tests
    local test_functions=(
        "test_env_loading"
        "test_file_scenarios"
        "test_safety_defaults"
        "test_docker_env"
    )
    
    for test_func in "${test_functions[@]}"; do
        ((total_tests++))
        if $test_func; then
            ((tests_passed++))
        fi
        echo
    done
    
    # Summary
    log_header "Test Results Summary"
    echo "Tests passed: $tests_passed/$total_tests"
    
    if [[ $tests_passed -eq $total_tests ]]; then
        log_success "All environment loading tests passed!"
        return 0
    else
        log_warning "Some environment loading tests failed"
        return 1
    fi
}

# Show usage
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << EOF
Environment Loading Test Script

USAGE:
    $0

This script tests the conditional environment file loading:
- Priority: .env.test > .env > .env.example
- Fallback to system environment variables
- Safety defaults application
- Docker environment simulation

The script tests the same logic used in sync-script.sh
EOF
    exit 0
fi

main "$@"
