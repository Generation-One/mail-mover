#!/usr/bin/env python3
"""
Gmail Push Notification-based email synchronization
Uses Gmail API + Pub/Sub for real-time notifications
"""

import os
import json
import logging
import threading
import time
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from google.cloud import pubsub_v1
import subprocess

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('/app/logs/gmail-push.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class GmailPushSync:
    def __init__(self):
        self.gmail_service = None
        self.subscriber = None
        self.running = False
        self.sync_lock = threading.Lock()
        
        # Configuration
        self.config = {
            'project_id': os.getenv('GOOGLE_CLOUD_PROJECT'),
            'subscription_name': os.getenv('PUBSUB_SUBSCRIPTION', 'gmail-sync-subscription'),
            'topic_name': os.getenv('PUBSUB_TOPIC', 'gmail-sync-topic'),
            'credentials_file': os.getenv('GOOGLE_CREDENTIALS', '/app/credentials.json'),
            'token_file': os.getenv('GOOGLE_TOKEN', '/app/token.json'),
            
            # Destination IMAP settings
            'host2': os.getenv('HOST_2'),
            'user2': os.getenv('USER_2'),
            'password2': os.getenv('PASSWORD_2'),
            'ssl2': os.getenv('SSL2', 'true').lower() == 'true',
            'folder': os.getenv('FOLDER', 'INBOX'),
            'move': os.getenv('MOVE', 'false').lower() == 'true'
        }
        
        # Gmail API scopes
        self.scopes = ['https://www.googleapis.com/auth/gmail.readonly']
    
    def authenticate_gmail(self):
        """Authenticate with Gmail API"""
        creds = None
        
        # Load existing token
        if os.path.exists(self.config['token_file']):
            creds = Credentials.from_authorized_user_file(self.config['token_file'], self.scopes)
        
        # If no valid credentials, get new ones
        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                flow = InstalledAppFlow.from_client_secrets_file(
                    self.config['credentials_file'], self.scopes)
                creds = flow.run_local_server(port=0)
            
            # Save credentials for next run
            with open(self.config['token_file'], 'w') as token:
                token.write(creds.to_json())
        
        self.gmail_service = build('gmail', 'v1', credentials=creds)
        logger.info("Gmail API authenticated successfully")
    
    def setup_push_notifications(self):
        """Set up Gmail push notifications"""
        try:
            # Create watch request
            request = {
                'topicName': f'projects/{self.config["project_id"]}/topics/{self.config["topic_name"]}',
                'labelIds': ['INBOX']
            }
            
            result = self.gmail_service.users().watch(userId='me', body=request).execute()
            logger.info(f"Gmail watch set up: {result}")
            
            # Set up Pub/Sub subscriber
            subscriber_path = self.subscriber.subscription_path(
                self.config['project_id'], 
                self.config['subscription_name']
            )
            
            logger.info(f"Listening for messages on {subscriber_path}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to set up push notifications: {e}")
            return False
    
    def sync_emails_gmail_api(self):
        """Sync emails using Gmail API + imapsync for destination"""
        with self.sync_lock:
            logger.info("Starting Gmail API synchronization...")
            
            try:
                # Get recent messages from Gmail API
                results = self.gmail_service.users().messages().list(
                    userId='me', 
                    labelIds=['INBOX'],
                    maxResults=50  # Adjust as needed
                ).execute()
                
                messages = results.get('messages', [])
                logger.info(f"Found {len(messages)} messages to process")
                
                # For each message, we could process individually
                # But for simplicity, let's trigger a full imapsync
                return self.sync_with_imapsync()
                
            except Exception as e:
                logger.error(f"Gmail API sync error: {e}")
                return False
    
    def sync_with_imapsync(self):
        """Fallback to imapsync for actual synchronization"""
        logger.info("Performing imapsync synchronization...")
        
        # Build imapsync command (Gmail source)
        cmd = [
            'imapsync',
            '--host1', 'imap.gmail.com',
            '--user1', os.getenv('USER_1'),
            '--password1', os.getenv('PASSWORD_1'),
            '--ssl1',
            '--host2', self.config['host2'],
            '--user2', self.config['user2'],
            '--password2', self.config['password2'],
            '--folder', self.config['folder'],
            '--useuid', '--automap', '--fastio1', '--fastio2',
            '--syncinternaldates', '--skipcrossduplicates'
        ]
        
        if self.config['ssl2']:
            cmd.append('--ssl2')
        
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
        except Exception as e:
            logger.error(f"Synchronization error: {e}")
            return False
    
    def callback(self, message):
        """Handle Pub/Sub messages (Gmail notifications)"""
        try:
            # Decode the message
            data = json.loads(message.data.decode('utf-8'))
            logger.info(f"Received Gmail notification: {data}")
            
            # Trigger synchronization
            self.sync_emails_gmail_api()
            
            # Acknowledge the message
            message.ack()
            
        except Exception as e:
            logger.error(f"Error processing notification: {e}")
            message.nack()
    
    def start(self):
        """Start the Gmail push notification service"""
        logger.info("Starting Gmail Push Notification synchronization service...")
        
        try:
            # Initialize Pub/Sub subscriber
            self.subscriber = pubsub_v1.SubscriberClient()
            
            # Authenticate Gmail
            self.authenticate_gmail()
            
            # Set up push notifications
            if not self.setup_push_notifications():
                raise Exception("Failed to set up push notifications")
            
            # Initial sync
            self.sync_emails_gmail_api()
            
            # Start listening for notifications
            self.running = True
            subscription_path = self.subscriber.subscription_path(
                self.config['project_id'], 
                self.config['subscription_name']
            )
            
            # Configure flow control
            flow_control = pubsub_v1.types.FlowControl(max_messages=100)
            
            logger.info("Listening for Gmail push notifications...")
            streaming_pull_future = self.subscriber.subscribe(
                subscription_path, 
                callback=self.callback,
                flow_control=flow_control
            )
            
            # Keep the main thread running
            try:
                streaming_pull_future.result()
            except KeyboardInterrupt:
                streaming_pull_future.cancel()
                
        except Exception as e:
            logger.error(f"Failed to start Gmail push service: {e}")
            raise
    
    def stop(self):
        """Stop the service"""
        logger.info("Stopping Gmail Push Notification service...")
        self.running = False

if __name__ == "__main__":
    try:
        sync_service = GmailPushSync()
        sync_service.start()
    except Exception as e:
        logger.error(f"Failed to start service: {e}")
        exit(1)
