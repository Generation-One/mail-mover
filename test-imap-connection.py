#!/usr/bin/env python3
"""
IMAP Connection Testing Script
Tests IMAP connections, IDLE support, and basic functionality
"""

import imaplib
import ssl
import sys
import os
import time
import argparse
from datetime import datetime

# Colors for output
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    BOLD = '\033[1m'
    END = '\033[0m'

def print_success(msg):
    print(f"{Colors.GREEN}✓ {msg}{Colors.END}")

def print_error(msg):
    print(f"{Colors.RED}✗ {msg}{Colors.END}")

def print_warning(msg):
    print(f"{Colors.YELLOW}⚠ {msg}{Colors.END}")

def print_info(msg):
    print(f"{Colors.BLUE}ℹ {msg}{Colors.END}")

def print_header(msg):
    print(f"\n{Colors.BOLD}{Colors.BLUE}=== {msg} ==={Colors.END}")

class IMAPTester:
    def __init__(self, host, username, password, use_ssl=True, port=None):
        self.host = host
        self.username = username
        self.password = password
        self.use_ssl = use_ssl
        self.port = port or (993 if use_ssl else 143)
        self.connection = None
        
    def test_basic_connection(self):
        """Test basic IMAP connection"""
        print_header("Testing Basic IMAP Connection")
        
        try:
            print_info(f"Connecting to {self.host}:{self.port} (SSL: {self.use_ssl})")
            
            if self.use_ssl:
                self.connection = imaplib.IMAP4_SSL(self.host, self.port)
            else:
                self.connection = imaplib.IMAP4(self.host, self.port)
                
            print_success(f"Connected to {self.host}")
            return True
            
        except Exception as e:
            print_error(f"Connection failed: {e}")
            return False
    
    def test_authentication(self):
        """Test IMAP authentication"""
        print_header("Testing Authentication")
        
        if not self.connection:
            print_error("No connection available")
            return False
            
        try:
            print_info(f"Authenticating as {self.username}")
            result = self.connection.login(self.username, self.password)
            print_success(f"Authentication successful: {result}")
            return True
            
        except Exception as e:
            print_error(f"Authentication failed: {e}")
            return False
    
    def test_folder_listing(self):
        """Test folder listing"""
        print_header("Testing Folder Listing")
        
        if not self.connection:
            print_error("No connection available")
            return False
            
        try:
            result, folders = self.connection.list()
            if result == 'OK':
                print_success(f"Found {len(folders)} folders:")
                for folder in folders[:10]:  # Show first 10 folders
                    folder_name = folder.decode('utf-8') if isinstance(folder, bytes) else str(folder)
                    print(f"  - {folder_name}")
                if len(folders) > 10:
                    print(f"  ... and {len(folders) - 10} more folders")
                return True
            else:
                print_error(f"Failed to list folders: {result}")
                return False
                
        except Exception as e:
            print_error(f"Folder listing failed: {e}")
            return False
    
    def test_inbox_selection(self):
        """Test INBOX selection and message count"""
        print_header("Testing INBOX Selection")
        
        if not self.connection:
            print_error("No connection available")
            return False
            
        try:
            result, data = self.connection.select('INBOX')
            if result == 'OK':
                message_count = int(data[0])
                print_success(f"Selected INBOX with {message_count} messages")
                return True
            else:
                print_error(f"Failed to select INBOX: {result}")
                return False
                
        except Exception as e:
            print_error(f"INBOX selection failed: {e}")
            return False
    
    def test_idle_support(self):
        """Test IMAP IDLE support"""
        print_header("Testing IMAP IDLE Support")
        
        if not self.connection:
            print_error("No connection available")
            return False
            
        try:
            # Check if IDLE is in capabilities
            result, capabilities = self.connection.capability()
            if result == 'OK':
                caps = capabilities[0].decode('utf-8').upper()
                if 'IDLE' in caps:
                    print_success("Server supports IDLE capability")
                    
                    # Test actual IDLE command
                    print_info("Testing IDLE command...")
                    self.connection.send(b'IDLE\r\n')
                    
                    # Wait for IDLE response
                    time.sleep(2)
                    
                    # Exit IDLE
                    self.connection.send(b'DONE\r\n')
                    
                    print_success("IDLE command test successful")
                    return True
                else:
                    print_error("Server does not support IDLE capability")
                    print_info(f"Available capabilities: {caps}")
                    return False
            else:
                print_error(f"Failed to get capabilities: {result}")
                return False
                
        except Exception as e:
            print_error(f"IDLE test failed: {e}")
            return False
    
    def test_recent_messages(self):
        """Test fetching recent messages"""
        print_header("Testing Recent Messages")
        
        if not self.connection:
            print_error("No connection available")
            return False
            
        try:
            # Search for recent messages
            result, message_ids = self.connection.search(None, 'ALL')
            if result == 'OK':
                ids = message_ids[0].split()
                if ids:
                    # Get the last 3 messages
                    recent_ids = ids[-3:] if len(ids) >= 3 else ids
                    print_success(f"Found {len(ids)} total messages, checking last {len(recent_ids)}")
                    
                    for msg_id in recent_ids:
                        result, msg_data = self.connection.fetch(msg_id, '(ENVELOPE)')
                        if result == 'OK':
                            print_info(f"Message {msg_id.decode()}: {len(msg_data[0])} bytes")
                        else:
                            print_warning(f"Failed to fetch message {msg_id.decode()}")
                    
                    return True
                else:
                    print_warning("No messages found in INBOX")
                    return True
            else:
                print_error(f"Failed to search messages: {result}")
                return False
                
        except Exception as e:
            print_error(f"Recent messages test failed: {e}")
            return False
    
    def test_connection_stability(self, duration=30):
        """Test connection stability over time"""
        print_header(f"Testing Connection Stability ({duration}s)")
        
        if not self.connection:
            print_error("No connection available")
            return False
            
        try:
            print_info(f"Testing connection stability for {duration} seconds...")
            start_time = time.time()
            
            while time.time() - start_time < duration:
                # Send NOOP to keep connection alive
                result = self.connection.noop()
                if result[0] != 'OK':
                    print_error(f"Connection lost: {result}")
                    return False
                
                time.sleep(5)  # Check every 5 seconds
                elapsed = int(time.time() - start_time)
                print(f"\r  Connection stable for {elapsed}s...", end='', flush=True)
            
            print()  # New line
            print_success(f"Connection remained stable for {duration} seconds")
            return True
            
        except Exception as e:
            print_error(f"Connection stability test failed: {e}")
            return False
    
    def close_connection(self):
        """Close IMAP connection"""
        if self.connection:
            try:
                self.connection.logout()
                print_success("Connection closed successfully")
            except:
                pass
    
    def run_all_tests(self, stability_duration=30):
        """Run all IMAP tests"""
        print_header(f"IMAP Connection Test - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print_info(f"Testing: {self.username}@{self.host}:{self.port}")
        
        tests = [
            ("Basic Connection", self.test_basic_connection),
            ("Authentication", self.test_authentication),
            ("Folder Listing", self.test_folder_listing),
            ("INBOX Selection", self.test_inbox_selection),
            ("IDLE Support", self.test_idle_support),
            ("Recent Messages", self.test_recent_messages),
            ("Connection Stability", lambda: self.test_connection_stability(stability_duration))
        ]
        
        results = {}
        for test_name, test_func in tests:
            try:
                results[test_name] = test_func()
            except Exception as e:
                print_error(f"Test '{test_name}' crashed: {e}")
                results[test_name] = False
        
        # Summary
        print_header("Test Results Summary")
        passed = sum(1 for result in results.values() if result)
        total = len(results)
        
        for test_name, result in results.items():
            status = "PASS" if result else "FAIL"
            color = Colors.GREEN if result else Colors.RED
            print(f"{color}{status:4}{Colors.END} - {test_name}")
        
        print(f"\nOverall: {passed}/{total} tests passed")
        
        if passed == total:
            print_success("All tests passed! IMAP connection is working perfectly.")
        elif passed >= total * 0.8:
            print_warning("Most tests passed. Minor issues detected.")
        else:
            print_error("Multiple test failures. Check your IMAP configuration.")
        
        self.close_connection()
        return results

def main():
    parser = argparse.ArgumentParser(description='Test IMAP connection and functionality')
    parser.add_argument('--host', required=True, help='IMAP server hostname')
    parser.add_argument('--username', required=True, help='IMAP username/email')
    parser.add_argument('--password', required=True, help='IMAP password')
    parser.add_argument('--port', type=int, help='IMAP port (default: 993 for SSL, 143 for non-SSL)')
    parser.add_argument('--no-ssl', action='store_true', help='Disable SSL/TLS')
    parser.add_argument('--stability-duration', type=int, default=30, help='Connection stability test duration in seconds')
    
    args = parser.parse_args()
    
    tester = IMAPTester(
        host=args.host,
        username=args.username,
        password=args.password,
        use_ssl=not args.no_ssl,
        port=args.port
    )
    
    results = tester.run_all_tests(args.stability_duration)
    
    # Exit with appropriate code
    passed = sum(1 for result in results.values() if result)
    total = len(results)
    sys.exit(0 if passed == total else 1)

if __name__ == "__main__":
    main()
