#!/bin/bash

# Simple IMAP Connection Test Script
# Uses your existing .env configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

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

# Load environment variables safely
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        log_info "Loading configuration from .env"

        # Load environment variables while handling spaces in values
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue

            # Remove leading/trailing whitespace from key
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # Skip if key is empty after trimming
            [[ -z "$key" ]] && continue

            # Export the variable (value may contain spaces)
            export "$key"="$value"
        done < "$ENV_FILE"
    else
        log_error ".env file not found!"
        log_info "Please copy .env.example to .env and configure your settings"
        exit 1
    fi
}

# Test basic connection using openssl
test_ssl_connection() {
    local host="$1"
    local port="${2:-993}"
    
    log_header "Testing SSL Connection"
    log_info "Testing SSL connection to $host:$port"
    
    if timeout 10 openssl s_client -connect "$host:$port" -quiet </dev/null 2>/dev/null; then
        log_success "SSL connection to $host:$port successful"
        return 0
    else
        log_error "SSL connection to $host:$port failed"
        return 1
    fi
}

# Test connection using telnet (for non-SSL)
test_plain_connection() {
    local host="$1"
    local port="${2:-143}"
    
    log_header "Testing Plain Connection"
    log_info "Testing plain connection to $host:$port"
    
    if timeout 10 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
        log_success "Plain connection to $host:$port successful"
        return 0
    else
        log_error "Plain connection to $host:$port failed"
        return 1
    fi
}

# Test IMAP using imapsync dry-run
test_imap_with_imapsync() {
    local host="$1"
    local user="$2"
    local pass="$3"
    local ssl_flag="$4"
    
    log_header "Testing IMAP with imapsync"
    log_info "Testing IMAP authentication and basic functionality"
    
    local cmd="imapsync --host1 '$host' --user1 '$user' --password1 '$pass'"
    
    if [[ "$ssl_flag" == "true" ]]; then
        cmd+=" --ssl1"
    fi
    
    # Use a dummy host2 for testing (won't actually sync)
    cmd+=" --host2 'dummy.example.com' --user2 'dummy' --password2 'dummy'"
    cmd+=" --justconnect --dry --debug"
    
    if eval "$cmd" >/dev/null 2>&1; then
        log_success "IMAP connection and authentication successful"
        return 0
    else
        log_error "IMAP connection or authentication failed"
        log_info "Check your credentials and server settings"
        return 1
    fi
}

# Test using Python script if available
test_with_python() {
    local host="$1"
    local user="$2"
    local pass="$3"
    local ssl_flag="$4"
    
    if [[ -f "${SCRIPT_DIR}/test-imap-connection.py" ]]; then
        log_header "Running Comprehensive Python Tests"
        
        local ssl_arg=""
        if [[ "$ssl_flag" != "true" ]]; then
            ssl_arg="--no-ssl"
        fi
        
        if python3 "${SCRIPT_DIR}/test-imap-connection.py" \
            --host "$host" \
            --username "$user" \
            --password "$pass" \
            --stability-duration 10 \
            $ssl_arg; then
            log_success "Python IMAP tests completed successfully"
            return 0
        else
            log_warning "Python IMAP tests found some issues"
            return 1
        fi
    else
        log_info "Python test script not found, skipping comprehensive tests"
        return 0
    fi
}

# Test DNS resolution
test_dns() {
    local host="$1"
    
    log_header "Testing DNS Resolution"
    log_info "Resolving $host"
    
    if nslookup "$host" >/dev/null 2>&1; then
        local ip=$(nslookup "$host" 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}' || echo "unknown")
        log_success "DNS resolution successful: $host -> $ip"
        return 0
    else
        log_error "DNS resolution failed for $host"
        return 1
    fi
}

# Main test function
run_tests() {
    local host="$1"
    local user="$2"
    local pass="$3"
    local ssl_flag="$4"
    local port="$5"
    
    log_header "IMAP Connection Test - $(date)"
    log_info "Testing: $user@$host:$port (SSL: $ssl_flag)"
    
    local tests_passed=0
    local total_tests=0
    
    # DNS Test
    ((total_tests++))
    if test_dns "$host"; then
        ((tests_passed++))
    fi
    
    # Connection Test
    ((total_tests++))
    if [[ "$ssl_flag" == "true" ]]; then
        if test_ssl_connection "$host" "$port"; then
            ((tests_passed++))
        fi
    else
        if test_plain_connection "$host" "$port"; then
            ((tests_passed++))
        fi
    fi
    
    # IMAP Test with imapsync
    if command -v imapsync >/dev/null 2>&1; then
        ((total_tests++))
        if test_imap_with_imapsync "$host" "$user" "$pass" "$ssl_flag"; then
            ((tests_passed++))
        fi
    else
        log_warning "imapsync not found, skipping IMAP authentication test"
    fi
    
    # Python comprehensive tests
    if command -v python3 >/dev/null 2>&1; then
        ((total_tests++))
        if test_with_python "$host" "$user" "$pass" "$ssl_flag"; then
            ((tests_passed++))
        fi
    else
        log_warning "python3 not found, skipping comprehensive tests"
    fi
    
    # Summary
    log_header "Test Results Summary"
    echo "Tests passed: $tests_passed/$total_tests"
    
    if [[ $tests_passed -eq $total_tests ]]; then
        log_success "All tests passed! IMAP connection is working perfectly."
        return 0
    elif [[ $tests_passed -ge $((total_tests * 80 / 100)) ]]; then
        log_warning "Most tests passed. Minor issues detected."
        return 1
    else
        log_error "Multiple test failures. Check your IMAP configuration."
        return 2
    fi
}

# Test both source and destination
test_both_servers() {
    load_env
    
    local overall_result=0
    
    # Test source server (HOST_1)
    if [[ -n "${HOST_1:-}" && -n "${USER_1:-}" && -n "${PASSWORD_1:-}" ]]; then
        echo
        log_header "Testing Source Server (HOST_1)"
        local ssl1="${SSL1:-true}"
        local port1="993"
        if [[ "$ssl1" != "true" ]]; then
            port1="143"
        fi
        
        if ! run_tests "$HOST_1" "$USER_1" "$PASSWORD_1" "$ssl1" "$port1"; then
            overall_result=1
        fi
    else
        log_warning "Source server (HOST_1) configuration incomplete, skipping"
    fi
    
    # Test destination server (HOST_2)
    if [[ -n "${HOST_2:-}" && -n "${USER_2:-}" && -n "${PASSWORD_2:-}" ]]; then
        echo
        log_header "Testing Destination Server (HOST_2)"
        local ssl2="${SSL2:-true}"
        local port2="993"
        if [[ "$ssl2" != "true" ]]; then
            port2="143"
        fi
        
        if ! run_tests "$HOST_2" "$USER_2" "$PASSWORD_2" "$ssl2" "$port2"; then
            overall_result=1
        fi
    else
        log_warning "Destination server (HOST_2) configuration incomplete, skipping"
    fi
    
    return $overall_result
}

# Show usage
show_usage() {
    cat << EOF
IMAP Connection Test Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --source     Test only source server (HOST_1)
    --dest       Test only destination server (HOST_2)
    --both       Test both servers (default)
    --help       Show this help

EXAMPLES:
    $0                    # Test both servers from .env
    $0 --source          # Test only source server
    $0 --dest            # Test only destination server

The script will load configuration from .env file automatically.
EOF
}

# Main execution
main() {
    case "${1:-both}" in
        "--source")
            load_env
            if [[ -n "${HOST_1:-}" ]]; then
                local ssl1="${SSL1:-true}"
                local port1="993"
                if [[ "$ssl1" != "true" ]]; then port1="143"; fi
                run_tests "$HOST_1" "$USER_1" "$PASSWORD_1" "$ssl1" "$port1"
            else
                log_error "Source server configuration not found in .env"
                exit 1
            fi
            ;;
        "--dest")
            load_env
            if [[ -n "${HOST_2:-}" ]]; then
                local ssl2="${SSL2:-true}"
                local port2="993"
                if [[ "$ssl2" != "true" ]]; then port2="143"; fi
                run_tests "$HOST_2" "$USER_2" "$PASSWORD_2" "$ssl2" "$port2"
            else
                log_error "Destination server configuration not found in .env"
                exit 1
            fi
            ;;
        "--both"|"")
            test_both_servers
            ;;
        "--help"|"-h")
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
