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
        
        # Configuration from environment with safety defaults
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
            'idle_timeout': int(os.getenv('IDLE_TIMEOUT', '1740')),  # 29 minutes (Gmail limit is 30)
            'date_filter_days': int(os.getenv('DATE_FILTER_DAYS', '30')),
            'max_emails_per_sync': int(os.getenv('MAX_EMAILS_PER_SYNC', '1000')),
            'max_email_size': int(os.getenv('MAX_EMAIL_SIZE', '50000000'))  # 50MB
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
    
    def update_health_file(self, status="healthy"):
        """Update health status file for Docker health checks"""
        try:
            health_file = "/app/data/health"
            with open(health_file, 'w') as f:
                f.write(f"{status}\n")
                f.write(f"{int(time.time())}\n")
        except Exception as e:
            logger.warning(f"Failed to update health file: {e}")

    def check_existing_emails(self):
        """Check for existing emails in both source and destination folders and log statistics"""
        try:
            import datetime
            cutoff_date = datetime.datetime.now() - datetime.timedelta(days=self.config['date_filter_days'])
            date_str = cutoff_date.strftime("%d-%b-%Y")

            source_count = 0
            dest_count = 0

            # Check source folder
            if self.source_conn:
                try:
                    result, message_ids = self.source_conn.search(None, f'SINCE {date_str}')
                    if result == 'OK':
                        ids = message_ids[0].split() if message_ids[0] else []
                        source_count = len(ids)
                        logger.info(f"📧 SOURCE: Found {source_count} emails in {self.config['user1']}@{self.config['host1']}:{self.config['folder']} from last {self.config['date_filter_days']} days")
                    else:
                        logger.warning(f"Failed to search source emails: {result}")
                except Exception as e:
                    logger.error(f"Failed to check source emails: {e}")

            # Check destination folder
            dest_conn = None
            try:
                # Connect to destination
                if self.config['ssl2']:
                    dest_conn = imaplib.IMAP4_SSL(self.config['host2'])
                else:
                    dest_conn = imaplib.IMAP4(self.config['host2'])

                dest_conn.login(self.config['user2'], self.config['password2'])
                dest_conn.select(self.config['folder'])

                result, message_ids = dest_conn.search(None, f'SINCE {date_str}')
                if result == 'OK':
                    ids = message_ids[0].split() if message_ids[0] else []
                    dest_count = len(ids)
                    logger.info(f"📧 DESTINATION: Found {dest_count} emails in {self.config['user2']}@{self.config['host2']}:{self.config['folder']} from last {self.config['date_filter_days']} days")
                else:
                    logger.warning(f"Failed to search destination emails: {result}")

            except Exception as e:
                logger.error(f"Failed to check destination emails: {e}")
            finally:
                if dest_conn:
                    try:
                        dest_conn.close()
                        dest_conn.logout()
                    except:
                        pass

            # Calculate potential emails to move
            potential_to_move = max(0, source_count - dest_count) if source_count > 0 else 0

            logger.info(f"📊 SYNC ANALYSIS:")
            logger.info(f"   • Source emails: {source_count}")
            logger.info(f"   • Destination emails: {dest_count}")
            logger.info(f"   • Potentially need to sync: {potential_to_move} emails")

            if source_count > self.config['max_emails_per_sync']:
                logger.warning(f"⚠️  Source email count ({source_count}) exceeds sync limit ({self.config['max_emails_per_sync']})")
                logger.info(f"   Will sync only the most recent {self.config['max_emails_per_sync']} emails")

            if potential_to_move == 0:
                logger.info("✅ No emails need to be synchronized - folders appear to be in sync")
            elif potential_to_move > 0:
                logger.info(f"🔄 Ready to synchronize {min(potential_to_move, self.config['max_emails_per_sync'])} emails")

            return source_count

        except Exception as e:
            logger.error(f"Failed to check existing emails: {e}")
            return 0

    def sync_emails(self):
        """Perform email synchronization using imapsync with safety limits"""
        with self.sync_lock:
            start_time = time.time()
            logger.info("Starting email synchronization...")
            logger.info(f"Source: {self.config['user1']}@{self.config['host1']}:{self.config['folder']}")
            logger.info(f"Destination: {self.config['user2']}@{self.config['host2']}:{self.config['folder']}")

            # Check existing emails first
            email_count = self.check_existing_emails()

            # Build imapsync command with safety limits
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
                '--syncinternaldates', '--skipcrossduplicates',
                '--maxage', str(self.config['date_filter_days']),
                '--maxmessages', str(self.config['max_emails_per_sync']),
                '--maxsize', str(self.config['max_email_size'])
                # Note: --sleep option removed as it's not supported in this version of imapsync
            ]

            # Add SSL options
            if self.config['ssl1']:
                cmd.append('--ssl1')
            if self.config['ssl2']:
                cmd.append('--ssl2')

            # Add move mode if enabled
            if self.config['move']:
                cmd.append('--delete1')

            logger.info(f"Sync limits: {self.config['date_filter_days']} days, {self.config['max_emails_per_sync']} emails max, {self.config['max_email_size']/1024/1024:.1f}MB per email")

            try:
                logger.info("🔄 Starting imapsync process...")
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)  # 10 minute timeout
                duration = time.time() - start_time

                if result.returncode == 0:
                    # Parse output for detailed statistics
                    output = result.stdout + result.stderr

                    # Extract comprehensive statistics from imapsync output
                    import re

                    # Look for various patterns in imapsync output
                    transferred = 0
                    skipped = 0
                    errors = 0

                    # Try different patterns that imapsync might use
                    patterns = [
                        (r'Transferred:\s*(\d+)', 'transferred'),
                        (r'Skipped:\s*(\d+)', 'skipped'),
                        (r'Errors:\s*(\d+)', 'errors'),
                        (r'(\d+)\s+messages\s+transferred', 'transferred'),
                        (r'(\d+)\s+messages\s+skipped', 'skipped'),
                        (r'(\d+)\s+messages\s+copied', 'transferred'),
                        (r'Total\s+bytes\s+transferred:\s*(\d+)', 'bytes'),
                    ]

                    stats = {}
                    for pattern, stat_type in patterns:
                        match = re.search(pattern, output, re.IGNORECASE)
                        if match:
                            stats[stat_type] = int(match.group(1))

                    transferred = stats.get('transferred', 0)
                    skipped = stats.get('skipped', 0)
                    errors = stats.get('errors', 0)
                    bytes_transferred = stats.get('bytes', 0)

                    logger.info(f"✅ Synchronization completed successfully in {duration:.1f}s")
                    logger.info(f"📊 SYNC RESULTS:")
                    logger.info(f"   • Messages transferred: {transferred}")
                    logger.info(f"   • Messages skipped: {skipped}")
                    if errors > 0:
                        logger.warning(f"   • Errors encountered: {errors}")
                    if bytes_transferred > 0:
                        logger.info(f"   • Data transferred: {bytes_transferred/1024/1024:.1f} MB")

                    if transferred > 0:
                        logger.info(f"🎉 Successfully moved {transferred} emails!")
                    elif skipped > 0:
                        logger.info("ℹ️  All emails were already synchronized (skipped)")
                    else:
                        logger.info("ℹ️  No emails needed to be moved")

                    # Log a sample of the imapsync output for debugging
                    if output.strip():
                        logger.debug(f"Imapsync output sample: {output[:200]}...")

                    self.update_health_file("healthy")
                    return True
                else:
                    logger.error(f"❌ Synchronization failed after {duration:.1f}s with exit code: {result.returncode}")
                    logger.error(f"Error output: {result.stderr[:500]}")  # Limit error output

                    # Log stdout as well in case it contains useful info
                    if result.stdout.strip():
                        logger.info(f"Stdout: {result.stdout[:500]}")

                    self.update_health_file("unhealthy")
                    return False

            except subprocess.TimeoutExpired:
                duration = time.time() - start_time
                logger.error(f"Synchronization timed out after {duration:.1f}s")
                self.update_health_file("unhealthy")
                return False
            except Exception as e:
                duration = time.time() - start_time
                logger.error(f"Synchronization error after {duration:.1f}s: {e}")
                self.update_health_file("unhealthy")
                return False
    
    def idle_loop(self):
        """Main IDLE loop - keeps connection open and listens for changes"""
        while self.running:
            try:
                if not self.source_conn:
                    if not self.connect_source():
                        self.update_health_file("unhealthy")
                        time.sleep(30)
                        continue

                logger.info("📡 IDLE mode activated - listening for new emails...")
                self.update_health_file("healthy")

                # Start IDLE
                self.source_conn.send(b'IDLE\r\n')

                # Wait for responses with timeout
                start_time = time.time()
                last_health_update = time.time()

                while self.running and (time.time() - start_time) < self.config['idle_timeout']:
                    try:
                        # Update health file every 30 seconds
                        if time.time() - last_health_update > 30:
                            self.update_health_file("healthy")
                            last_health_update = time.time()

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
                        self.update_health_file("unhealthy")
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
                self.update_health_file("unhealthy")
                time.sleep(30)
    
    def start(self):
        """Start the IDLE synchronization service"""
        logger.info("Starting IMAP IDLE synchronization service...")
        self.running = True

        # Initial sync
        logger.info("🔄 Performing initial synchronization...")
        sync_success = self.sync_emails()

        # Log summary before starting IDLE mode
        if sync_success:
            logger.info("✅ Initial synchronization completed successfully")
        else:
            logger.warning("⚠️  Initial synchronization had issues, but continuing with IDLE mode")

        logger.info("🎯 STARTING REAL-TIME MONITORING:")
        logger.info("   • IDLE mode will now monitor for new emails")
        logger.info("   • New emails will be detected and synced automatically")
        logger.info("   • System is ready for real-time email synchronization")

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
