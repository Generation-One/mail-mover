# Connection Modes - Avoiding Google Rate Limits

This document explains the different synchronization modes available to avoid Google API rate limits and improve efficiency.

## Overview

Instead of polling Gmail every 15 seconds (which can hit rate limits), you can now use persistent connections:

1. **Poll Mode** (default) - Original behavior, polls every N seconds
2. **IDLE Mode** - Keeps IMAP connection open, real-time notifications
3. **Push Mode** - Gmail Push Notifications via Google Cloud Pub/Sub

## 1. Poll Mode (Default)

**Current behavior** - polls Gmail every `POLL_SECONDS` (default: 15 seconds).

```bash
# .env configuration
SYNC_MODE=poll
POLL_SECONDS=15
```

**Pros:**
- Simple, no additional setup required
- Works with any IMAP server

**Cons:**
- Can hit Google rate limits with frequent polling
- Not real-time (delay = polling interval)
- More resource intensive

## 2. IDLE Mode (Recommended)

**IMAP IDLE** keeps a persistent connection open and receives real-time notifications when new emails arrive.

```bash
# .env configuration
SYNC_MODE=idle
IDLE_TIMEOUT=1740  # 29 minutes (Gmail limit is 30)
```

**Pros:**
- Real-time notifications (no polling delay)
- Avoids rate limits (single persistent connection)
- More efficient resource usage
- Works with Gmail and most IMAP servers

**Cons:**
- Requires stable network connection
- Some firewalls may close idle connections

**How it works:**
1. Opens persistent IMAP connection to Gmail
2. Sends IMAP IDLE command
3. Gmail notifies when new messages arrive
4. Triggers sync immediately
5. Refreshes connection every 29 minutes (Gmail requirement)

## 3. Push Mode (Most Efficient for Gmail)

**Gmail Push Notifications** use Google Cloud Pub/Sub for instant notifications.

```bash
# .env configuration
SYNC_MODE=push
GOOGLE_CLOUD_PROJECT=your-project-id
PUBSUB_TOPIC=gmail-sync-topic
PUBSUB_SUBSCRIPTION=gmail-sync-subscription
```

**Pros:**
- Instant notifications (fastest)
- No persistent connections needed
- Most efficient for high-volume Gmail accounts
- Scales better than IDLE

**Cons:**
- Gmail only (not other IMAP servers)
- Requires Google Cloud setup
- More complex configuration

## Setup Instructions

### For IDLE Mode

1. Update your `.env` file:
```bash
SYNC_MODE=idle
IDLE_TIMEOUT=1740
```

2. Rebuild and restart:
```bash
make build
make restart
```

### For Push Mode (Gmail Only)

1. **Set up Google Cloud Project:**
```bash
# Create project
gcloud projects create your-project-id

# Enable APIs
gcloud services enable gmail.googleapis.com
gcloud services enable pubsub.googleapis.com
```

2. **Create Pub/Sub Topic and Subscription:**
```bash
# Create topic
gcloud pubsub topics create gmail-sync-topic

# Create subscription
gcloud pubsub subscriptions create gmail-sync-subscription \
    --topic=gmail-sync-topic
```

3. **Set up Gmail API credentials:**
   - Go to Google Cloud Console
   - Create OAuth 2.0 credentials
   - Download `credentials.json`
   - Place in your project directory

4. **Update `.env` file:**
```bash
SYNC_MODE=push
GOOGLE_CLOUD_PROJECT=your-project-id
PUBSUB_TOPIC=gmail-sync-topic
PUBSUB_SUBSCRIPTION=gmail-sync-subscription
```

5. **Rebuild and restart:**
```bash
make build
make restart
```

6. **First run authentication:**
```bash
# The service will prompt for OAuth authentication on first run
make logs
```

## Rate Limit Comparison

| Mode | Connections/Hour | Rate Limit Risk | Real-time |
|------|------------------|-----------------|-----------|
| Poll (15s) | 240 | High | No (15s delay) |
| Poll (60s) | 60 | Medium | No (60s delay) |
| IDLE | 2-3 | Very Low | Yes |
| Push | 0 | None | Yes |

## Troubleshooting

### IDLE Mode Issues

**Connection drops:**
```bash
# Check logs
make logs

# Increase timeout if needed
IDLE_TIMEOUT=900  # 15 minutes
```

**Firewall issues:**
```bash
# Test IDLE support
telnet imap.gmail.com 993
# After login: A001 IDLE
```

### Push Mode Issues

**Authentication errors:**
```bash
# Verify credentials file exists
ls -la credentials.json

# Check OAuth scopes
# Ensure Gmail API is enabled
```

**Pub/Sub errors:**
```bash
# Verify topic exists
gcloud pubsub topics list

# Check subscription
gcloud pubsub subscriptions list
```

## Migration Guide

### From Poll to IDLE
1. Change `SYNC_MODE=idle` in `.env`
2. Rebuild container
3. Monitor logs for connection stability

### From Poll to Push
1. Complete Google Cloud setup (see above)
2. Change `SYNC_MODE=push` in `.env`
3. Add Google Cloud configuration
4. Rebuild container
5. Complete OAuth flow on first run

## Performance Monitoring

Monitor your chosen mode:

```bash
# Check connection status
make status

# Monitor logs
make logs

# Check resource usage
docker stats imap-sync
```

## Recommendations

- **Small personal accounts:** Use IDLE mode
- **High-volume Gmail accounts:** Use Push mode
- **Multiple IMAP providers:** Use IDLE mode
- **Corporate/firewall restrictions:** Use Poll mode with longer intervals
