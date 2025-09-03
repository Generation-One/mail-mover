# Deployment Guide

This document explains how to deploy the mail-mover service in different environments.

## Local Development

For local development with `.env` file:

```bash
# Uses docker-compose.yml + docker-compose.override.yml (automatic)
# The override file enables .env file loading
docker-compose up -d
```

## Production/Remote Deployment

### Option 1: Using Portainer with Environment Variables

1. **In Portainer**: Set environment variables directly in the container configuration
2. **Deploy using base configuration only**:

```bash
# Rename or remove the override file to prevent .env loading
mv docker-compose.override.yml docker-compose.override.yml.disabled
docker-compose up -d
```

### Option 2: Using Production Override File

```bash
# Use the production-specific override
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Option 3: Environment Variables Only

Set these environment variables in your deployment system:

```bash
HOST_1=imap.mail.me.com
USER_1=sent@me.com
PASSWORD_1=your-app-password
HOST_2=imap.gmail.com
USER_2=frank@generation.one
PASSWORD_2=your-gmail-app-password
SYNC_MODE=idle
DATE_FILTER_DAYS=30
MAX_EMAILS_PER_SYNC=1000
FOLDER=INBOX
MOVE=false
SSL1=true
SSL2=true
LOG_LEVEL=INFO
```

## File Structure

- `docker-compose.yml` - Base configuration (no .env file by default)
- `docker-compose.override.yml` - Local development (enables .env file)
- `docker-compose.prod.yml` - Production configuration (named volumes, no .env)
- `.env` - Local environment variables (ignored in production)

## Troubleshooting

### Permission Issues

The container includes automatic permission fixing. If you still encounter issues:

1. Check container logs for permission fix messages
2. Ensure mounted volumes have proper permissions
3. Consider using named volumes instead of bind mounts in production

### Environment Variable Issues

1. **Local**: Ensure `.env` file exists and `docker-compose.override.yml` is present
2. **Remote**: Ensure environment variables are set in your orchestrator (Portainer, etc.)
3. **Verify**: Check container logs for "Missing required environment variables" messages
