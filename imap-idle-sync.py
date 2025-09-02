#!/usr/bin/env python3
"""
IMAP IDLE-based email synchronization service
Keeps persistent connections open to avoid rate limits
"""

import imaplib
import time
import logging
import os
import sys
import signal
import threading
from email.mime.text import MIMEText
import subprocess
import json
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('/app/logs/imap-idle.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class IMAPIdleSync:
    def __init__(self):
        self.source_conn = None
        self.running = False
        self.idle_thread = None
        self.sync_lock = threading.Lock()
        
        # Configuration from environment
        self.config = {
            'host1': os.getenv('HOST_1'),
            'user1': os.getenv('USER_1'),
            'password1': os.getenv('PASSWORD_1'),
            'host2': os.getenv('HOST_2'),
            'user2': os.getenv('USER_2'),
            'password2': os.getenv('PASSWORD_2'),
            'folder': os.getenv('FOLDER', 'INBOX'),
            'ssl1': os.getenv('SSL1', 'true').lower() == 'true',
            'ssl2': os.getenv('SSL2', 'true').lower() == 'true',
            'move': os.getenv('MOVE', 'false').lower() == 'true',
            'idle_timeout': int(os.getenv('IDLE_TIMEOUT', '1740'))  # 29 minutes (Gmail limit is 30)
        }
        
        # Validate configuration
        required = ['host1', 'user1', 'password1', 'host2', 'user2', 'password2']
        missing = [k for k in required if not self.config[k]]
        if missing:
            raise ValueError(f"Missing required config: {missing}")
    
    def connect_source(self):
        """Establish connection to source IMAP server"""
        try:
            if self.config['ssl1']:
                self.source_conn = imaplib.IMAP4_SSL(self.config['host1'])
            else:
                self.source_conn = imaplib.IMAP4(self.config['host1'])
            
            self.source_conn.login(self.config['user1'], self.config['password1'])
            self.source_conn.select(self.config['folder'])
            logger.info(f"Connected to source: {self.config['host1']}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to source: {e}")
            return False
    
    def sync_emails(self):
        """Perform email synchronization using imapsync"""
        with self.sync_lock:
            logger.info("Starting email synchronization...")
            
            # Build imapsync command
            cmd = [
                'imapsync',
                '--host1', self.config['host1'],
                '--user1', self.config['user1'],
                '--password1', self.config['password1'],
                '--host2', self.config['host2'],
                '--user2', self.config['user2'],
                '--password2', self.config['password2'],
                '--folder', self.config['folder'],
                '--useuid', '--automap', '--fastio1', '--fastio2',
                '--syncinternaldates', '--skipcrossduplicates'
            ]
            
            # Add SSL options
            if self.config['ssl1']:
                cmd.append('--ssl1')
            if self.config['ssl2']:
                cmd.append('--ssl2')
            
            # Add move mode if enabled
            if self.config['move']:
                cmd.append('--delete1')
            
            try:
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
                if result.returncode == 0:
                    logger.info("Synchronization completed successfully")
                    return True
                else:
                    logger.error(f"Synchronization failed: {result.stderr}")
                    return False
            except subprocess.TimeoutExpired:
                logger.error("Synchronization timed out")
                return False
            except Exception as e:
                logger.error(f"Synchronization error: {e}")
                return False
    
    def idle_loop(self):
        """Main IDLE loop - keeps connection open and listens for changes"""
        while self.running:
            try:
                if not self.source_conn:
                    if not self.connect_source():
                        time.sleep(30)
                        continue
                
                logger.info("Starting IDLE mode...")
                
                # Start IDLE
                self.source_conn.send(b'IDLE\r\n')
                
                # Wait for responses with timeout
                start_time = time.time()
                while self.running and (time.time() - start_time) < self.config['idle_timeout']:
                    try:
                        # Check for IDLE responses (non-blocking)
                        response = self.source_conn.response('IDLE')
                        if response[0] == 'OK':
                            # New messages arrived
                            logger.info("New messages detected, triggering sync...")
                            
                            # Exit IDLE mode
                            self.source_conn.send(b'DONE\r\n')
                            
                            # Perform synchronization
                            self.sync_emails()
                            
                            # Restart IDLE
                            break
                    except imaplib.IMAP4.abort:
                        logger.warning("IMAP connection aborted, reconnecting...")
                        self.source_conn = None
                        break
                    except Exception as e:
                        logger.debug(f"IDLE check: {e}")
                        time.sleep(1)
                
                # Periodic sync even without new messages (every 29 minutes)
                if self.running and (time.time() - start_time) >= self.config['idle_timeout']:
                    logger.info("IDLE timeout reached, performing periodic sync...")
                    try:
                        self.source_conn.send(b'DONE\r\n')
                    except:
                        pass
                    self.sync_emails()
                    # Reconnect to refresh IDLE
                    self.source_conn = None
                
            except Exception as e:
                logger.error(f"IDLE loop error: {e}")
                self.source_conn = None
                time.sleep(30)
    
    def start(self):
        """Start the IDLE synchronization service"""
        logger.info("Starting IMAP IDLE synchronization service...")
        self.running = True
        
        # Initial sync
        self.sync_emails()
        
        # Start IDLE thread
        self.idle_thread = threading.Thread(target=self.idle_loop, daemon=True)
        self.idle_thread.start()
        
        # Keep main thread alive
        try:
            while self.running:
                time.sleep(1)
        except KeyboardInterrupt:
            self.stop()
    
    def stop(self):
        """Stop the synchronization service"""
        logger.info("Stopping IMAP IDLE synchronization service...")
        self.running = False
        
        if self.source_conn:
            try:
                self.source_conn.send(b'DONE\r\n')
                self.source_conn.logout()
            except:
                pass
        
        if self.idle_thread:
            self.idle_thread.join(timeout=5)

def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logger.info(f"Received signal {signum}, shutting down...")
    if 'sync_service' in globals():
        sync_service.stop()
    sys.exit(0)

if __name__ == "__main__":
    # Set up signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    try:
        sync_service = IMAPIdleSync()
        sync_service.start()
    except Exception as e:
        logger.error(f"Failed to start service: {e}")
        sys.exit(1)
