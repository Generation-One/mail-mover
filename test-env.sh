#!/bin/bash

# Simple environment variable test script
# Use this to debug what environment variables are available in the container

echo "=== Environment Variable Debug Test ==="
echo "Date: $(date)"
echo "User: $(whoami) (UID: $(id -u), GID: $(id -g))"
echo ""

echo "=== Required Variables ==="
required_vars=("HOST_1" "USER_1" "PASSWORD_1" "HOST_2" "USER_2" "PASSWORD_2")

for var in "${required_vars[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        if [[ "$var" == *"PASSWORD"* ]]; then
            echo "✓ $var: [SET - ${#!var} characters]"
        else
            echo "✓ $var: ${!var}"
        fi
    else
        echo "✗ $var: NOT SET"
    fi
done

echo ""
echo "=== All Environment Variables Starting with HOST_, USER_, PASSWORD_ ==="
env | grep -E "^(HOST_|USER_|PASSWORD_)" | sort || echo "None found"

echo ""
echo "=== All Environment Variables (first 50) ==="
env | sort | head -50

echo ""
echo "=== Environment Files Check ==="
for file in .env.test .env .env.example; do
    if [[ -f "$file" ]]; then
        echo "✓ $file exists ($(wc -l < "$file") lines)"
    else
        echo "✗ $file not found"
    fi
done

echo ""
echo "=== Working Directory ==="
echo "PWD: $(pwd)"
echo "Contents:"
ls -la

echo ""
echo "=== Test Complete ==="
