#!/bin/bash

# Docker Container Test Script
# Tests the running Docker container functionality

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

# Test container status
test_container_status() {
    log_header "Container Status"
    
    if docker-compose ps | grep -q "Up"; then
        log_success "Container is running"
        
        # Get detailed status
        local status=$(docker-compose ps --format "table {{.Name}}\t{{.Status}}")
        echo "$status"
        return 0
    else
        log_error "Container is not running"
        return 1
    fi
}

# Test container processes
test_container_processes() {
    log_header "Container Processes"
    
    log_info "Checking running processes inside container..."
    docker-compose exec imap-sync ps aux
    
    # Check if key processes are running
    if docker-compose exec imap-sync ps aux | grep -q "python3.*imap-idle-sync.py"; then
        log_success "IDLE Python script is running"
    else
        log_warning "IDLE Python script not found"
    fi
    
    if docker-compose exec imap-sync ps aux | grep -q "imapsync"; then
        log_success "imapsync process is running"
    else
        log_warning "imapsync process not found"
    fi
}

# Test container logs
test_container_logs() {
    log_header "Recent Container Logs"
    
    log_info "Last 15 log entries:"
    docker-compose logs --tail=15 imap-sync
}

# Test container health
test_container_health() {
    log_header "Container Health"
    
    # Check if health check script exists and runs
    if docker-compose exec imap-sync test -f /app/health-check.sh; then
        log_success "Health check script exists"
        
        log_info "Running health check..."
        if docker-compose exec imap-sync /app/health-check.sh; then
            log_success "Health check passed"
        else
            log_warning "Health check failed"
        fi
    else
        log_error "Health check script not found"
    fi
}

# Test environment variables
test_environment_variables() {
    log_header "Environment Variables"
    
    log_info "Checking key environment variables..."
    
    # Check SYNC_MODE
    local sync_mode=$(docker-compose exec imap-sync printenv SYNC_MODE 2>/dev/null || echo "not set")
    echo "SYNC_MODE: $sync_mode"
    
    # Check if HOST_2 (Gmail) is set
    local host2=$(docker-compose exec imap-sync printenv HOST_2 2>/dev/null || echo "not set")
    echo "HOST_2: $host2"
    
    # Check if USER_2 is set
    local user2=$(docker-compose exec imap-sync printenv USER_2 2>/dev/null || echo "not set")
    echo "USER_2: $user2"
    
    if [[ "$sync_mode" == "idle" ]]; then
        log_success "IDLE mode is configured"
    else
        log_warning "SYNC_MODE is not set to 'idle'"
    fi
}

# Test file permissions and structure
test_file_structure() {
    log_header "File Structure"
    
    log_info "Checking application files..."
    
    local files=(
        "/app/sync-script.sh"
        "/app/health-check.sh"
        "/app/imap-idle-sync.py"
        "/app/gmail-push-sync.py"
    )
    
    for file in "${files[@]}"; do
        if docker-compose exec imap-sync test -f "$file"; then
            if docker-compose exec imap-sync test -x "$file"; then
                log_success "$file exists and is executable"
            else
                log_warning "$file exists but is not executable"
            fi
        else
            log_error "$file does not exist"
        fi
    done
}

# Test network connectivity from container
test_network_connectivity() {
    log_header "Network Connectivity"
    
    log_info "Testing DNS resolution from container..."
    
    # Test Gmail IMAP
    if docker-compose exec imap-sync nslookup imap.gmail.com >/dev/null 2>&1; then
        log_success "Can resolve imap.gmail.com"
    else
        log_error "Cannot resolve imap.gmail.com"
    fi
    
    # Test SSL connection to Gmail
    log_info "Testing SSL connection to Gmail..."
    if timeout 10 docker-compose exec imap-sync openssl s_client -connect imap.gmail.com:993 -quiet </dev/null >/dev/null 2>&1; then
        log_success "SSL connection to Gmail successful"
    else
        log_error "SSL connection to Gmail failed"
    fi
}

# Test Python dependencies
test_python_dependencies() {
    log_header "Python Dependencies"
    
    log_info "Checking Python and required packages..."
    
    # Check Python version
    local python_version=$(docker-compose exec imap-sync python3 --version 2>/dev/null || echo "Python not found")
    echo "Python version: $python_version"
    
    # Check if imaplib is available
    if docker-compose exec imap-sync python3 -c "import imaplib; print('imaplib OK')" 2>/dev/null; then
        log_success "Python imaplib is available"
    else
        log_error "Python imaplib is not available"
    fi
    
    # Check Google packages (for push mode)
    if docker-compose exec imap-sync python3 -c "import google.auth; print('Google auth OK')" 2>/dev/null; then
        log_success "Google authentication packages are available"
    else
        log_warning "Google authentication packages not available (needed for push mode)"
    fi
}

# Main test execution
main() {
    log_header "Docker Container Test Suite - $(date)"
    
    local tests_passed=0
    local total_tests=0
    
    # Run all tests
    local test_functions=(
        "test_container_status"
        "test_environment_variables"
        "test_file_structure"
        "test_python_dependencies"
        "test_network_connectivity"
        "test_container_processes"
        "test_container_health"
        "test_container_logs"
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
        log_success "All tests passed! Docker container is working perfectly."
        return 0
    elif [[ $tests_passed -ge $((total_tests * 80 / 100)) ]]; then
        log_warning "Most tests passed. Minor issues detected."
        return 1
    else
        log_error "Multiple test failures. Check the container configuration."
        return 2
    fi
}

# Show usage
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << EOF
Docker Container Test Script

USAGE:
    $0

This script tests the running Docker container:
- Container status and health
- Process verification
- Environment variables
- File structure and permissions
- Network connectivity
- Python dependencies
- Recent logs

Make sure the container is running before executing this script:
    docker-compose up -d
EOF
    exit 0
fi

main "$@"
