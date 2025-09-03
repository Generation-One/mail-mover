#!/bin/bash

# Quick IMAP Connection Test
# Simple test that avoids complex environment parsing

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_success() { echo -e "${GREEN}✓ $*${NC}"; }
log_error() { echo -e "${RED}✗ $*${NC}"; }
log_warning() { echo -e "${YELLOW}⚠ $*${NC}"; }
log_info() { echo -e "${BLUE}ℹ $*${NC}"; }
log_header() { echo -e "\n${BOLD}${BLUE}=== $* ===${NC}"; }

# Test SSL connection
test_ssl_connection() {
    local host="$1"
    local port="${2:-993}"
    
    log_info "Testing SSL connection to $host:$port"
    
    if timeout 10 openssl s_client -connect "$host:$port" -quiet </dev/null >/dev/null 2>&1; then
        log_success "SSL connection successful"
        return 0
    else
        log_error "SSL connection failed"
        return 1
    fi
}

# Test DNS resolution
test_dns() {
    local host="$1"
    
    log_info "Testing DNS resolution for $host"
    
    if nslookup "$host" >/dev/null 2>&1; then
        log_success "DNS resolution successful"
        return 0
    else
        log_error "DNS resolution failed"
        return 1
    fi
}

# Test using Python if available
test_with_python() {
    local host="$1"
    local user="$2"
    local pass="$3"
    
    if ! command -v python3 >/dev/null 2>&1; then
        log_warning "Python3 not available, skipping detailed tests"
        return 0
    fi
    
    if [[ ! -f "test-imap-connection.py" ]]; then
        log_warning "Python test script not found, skipping detailed tests"
        return 0
    fi
    
    log_info "Running Python IMAP tests..."
    
    if python3 test-imap-connection.py \
        --host "$host" \
        --username "$user" \
        --password "$pass" \
        --stability-duration 5 >/dev/null 2>&1; then
        log_success "Python IMAP tests passed"
        return 0
    else
        log_error "Python IMAP tests failed"
        return 1
    fi
}

# Main test function
test_server() {
    local host="$1"
    local user="$2"
    local pass="$3"
    local name="$4"
    
    log_header "Testing $name Server: $user@$host"
    
    local tests_passed=0
    local total_tests=3
    
    # DNS Test
    if test_dns "$host"; then
        ((tests_passed++))
    fi
    
    # SSL Connection Test
    if test_ssl_connection "$host" "993"; then
        ((tests_passed++))
    fi
    
    # Python detailed tests
    if test_with_python "$host" "$user" "$pass"; then
        ((tests_passed++))
    fi
    
    # Summary for this server
    echo
    if [[ $tests_passed -eq $total_tests ]]; then
        log_success "$name server: All tests passed ($tests_passed/$total_tests)"
        return 0
    else
        log_error "$name server: Some tests failed ($tests_passed/$total_tests)"
        return 1
    fi
}

# Extract value from .env file safely
get_env_value() {
    local key="$1"
    local env_file="${2:-.env}"
    
    if [[ -f "$env_file" ]]; then
        # Look for the key and extract the value, handling quotes
        grep "^${key}=" "$env_file" | head -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//'
    fi
}

# Main execution
main() {
    log_header "Quick IMAP Connection Test - $(date)"
    
    if [[ ! -f ".env" ]]; then
        log_error ".env file not found!"
        log_info "Please copy .env.example to .env and configure your settings"
        exit 1
    fi
    
    # Extract configuration safely
    HOST_1=$(get_env_value "HOST_1")
    USER_1=$(get_env_value "USER_1")
    PASSWORD_1=$(get_env_value "PASSWORD_1")
    
    HOST_2=$(get_env_value "HOST_2")
    USER_2=$(get_env_value "USER_2")
    PASSWORD_2=$(get_env_value "PASSWORD_2")
    
    local overall_result=0
    
    # Test source server
    if [[ -n "$HOST_1" && -n "$USER_1" && -n "$PASSWORD_1" ]]; then
        if ! test_server "$HOST_1" "$USER_1" "$PASSWORD_1" "Source"; then
            overall_result=1
        fi
    else
        log_warning "Source server configuration incomplete, skipping"
    fi
    
    # Test destination server
    if [[ -n "$HOST_2" && -n "$USER_2" && -n "$PASSWORD_2" ]]; then
        if ! test_server "$HOST_2" "$USER_2" "$PASSWORD_2" "Destination"; then
            overall_result=1
        fi
    else
        log_warning "Destination server configuration incomplete, skipping"
    fi
    
    # Overall summary
    log_header "Overall Test Results"
    if [[ $overall_result -eq 0 ]]; then
        log_success "All IMAP connections are working properly!"
    else
        log_error "Some IMAP connection issues detected. Check the details above."
    fi
    
    return $overall_result
}

# Show usage
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << EOF
Quick IMAP Connection Test

USAGE:
    $0

This script will:
1. Read configuration from .env file
2. Test DNS resolution for IMAP servers
3. Test SSL connections
4. Run detailed Python tests if available

The script safely handles passwords with spaces and special characters.
EOF
    exit 0
fi

main "$@"
