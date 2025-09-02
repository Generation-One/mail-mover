# IMAP Synchronization Service

A production-ready containerized service that synchronizes emails between IMAP servers using imapsync. Built on Alpine Linux with comprehensive logging, health checks, and deployment options for Docker Compose and Portainer.

## Features

- **Multiple sync modes** to avoid rate limits:
  - **Poll mode**: Traditional polling (default)
  - **IDLE mode**: Real-time IMAP IDLE connections
  - **Push mode**: Gmail Push Notifications via Pub/Sub
- **One-way synchronization** from source to destination IMAP server
- **Optional move mode** that deletes emails from source after successful copy
- **SSL/TLS support** for secure connections
- **Credential validation** on startup
- **Health monitoring** with Docker health checks
- **Production logging** with rotation and structured output
- **Portainer compatible** for easy web-based management

## Quick Start

### 1. Clone and Configure

```bash
git clone <repository-url>
cd imap-sync
cp .env.example .env
```

### 2. Edit Configuration

Edit `.env` with your IMAP server credentials:

```bash
# Source IMAP server
HOST_1=imap.gmail.com
USER_1=source@gmail.com
PASSWORD_1=your_app_password

# Destination IMAP server
HOST_2=imap.destination.com
USER_2=destination@example.com
PASSWORD_2=your_password

# Sync mode (poll/idle/push) - see CONNECTION-MODES.md
SYNC_MODE=idle  # Recommended for Gmail to avoid rate limits
```

### 3. Deploy with Docker Compose

```bash
make build
make start
make logs  # Monitor the service
```

### 4. Verify Operation

```bash
make status    # Check service health
make test      # Test IMAP connections
```

## Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `HOST_1` | Source IMAP server | `imap.gmail.com` |
| `USER_1` | Source username/email | `source@gmail.com` |
| `PASSWORD_1` | Source password | `app_password_here` |
| `HOST_2` | Destination IMAP server | `imap.destination.com` |
| `USER_2` | Destination username/email | `dest@example.com` |
| `PASSWORD_2` | Destination password | `password_here` |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `POLL_SECONDS` | `15` | Polling interval in seconds |
| `FOLDER` | `INBOX` | Folder to synchronize |
| `MOVE` | `false` | Enable move mode (deletes from source) |
| `SSL1` | `true` | Enable SSL for source server |
| `SSL2` | `true` | Enable SSL for destination server |
| `NOTLS1` | `false` | Disable TLS for source server |
| `NOTLS2` | `false` | Disable TLS for destination server |

## Deployment Options

### Docker Compose (Recommended)

```bash
# Build and start
make build
make start

# Monitor
make logs
make status

# Stop
make stop
```

### Portainer Deployment

1. **Access Portainer** web interface
2. **Create new stack** with name `imap-sync`
3. **Copy docker-compose.yml** content into the web editor
4. **Configure environment variables** in Portainer's environment section:
   ```
   HOST_1=imap.gmail.com
   USER_1=source@gmail.com
   PASSWORD_1=your_app_password
   HOST_2=imap.destination.com
   USER_2=destination@example.com
   PASSWORD_2=your_password
   POLL_SECONDS=15
   FOLDER=INBOX
   SSL1=true
   SSL2=true
   ```
5. **Deploy the stack**

### Manual Docker Run

```bash
docker build -t imap-sync .
docker run -d \
  --name imap-sync \
  --env-file .env \
  --restart unless-stopped \
  -v ./logs:/app/logs \
  -v ./data:/app/data \
  imap-sync:latest
```

## Common IMAP Server Settings

### Gmail
- **Server**: `imap.gmail.com`
- **Port**: 993 (SSL)
- **Requirements**: App Password (not regular password)
- **Setup**: Enable 2FA, generate App Password

### Microsoft Outlook/Exchange Online
- **Server**: `outlook.office365.com`
- **Port**: 993 (SSL)
- **Requirements**: May require App Password

### Yahoo Mail
- **Server**: `imap.mail.yahoo.com`
- **Port**: 993 (SSL)
- **Requirements**: App Password required

### Exchange Server (On-premises)
- **Server**: Usually `mail.domain.com`
- **Port**: 993 (SSL) or 143 (STARTTLS)
- **Requirements**: Check with IT administrator

## Security Considerations

### Credential Management
- **Never commit** `.env` files to version control
- **Use App Passwords** when available (Gmail, Outlook)
- **Rotate credentials** regularly
- **Use environment variables** in production instead of `.env` files

### Network Security
- **Always use SSL/TLS** when possible
- **Firewall rules** to restrict container network access
- **VPN connections** for accessing internal mail servers

### Move Mode Safety
- **Test thoroughly** with `MOVE=false` before enabling move mode
- **Backup important emails** before using move mode
- **Monitor logs** for any synchronization errors
- **Start with small batches** to verify behavior

## Monitoring and Maintenance

### Health Checks
```bash
make health        # Manual health check
make status        # Full service status
docker ps          # Check container status
```

### Log Management
```bash
make logs          # Follow logs in real-time
make logs-tail     # Show recent logs
```

### Backup
```bash
make backup        # Backup logs, data, and config
```

## Troubleshooting

### Service Won't Start
1. **Check configuration**: `make check-config`
2. **Test connections**: `make test`
3. **Review logs**: `make logs`
4. **Verify credentials** and server settings

### Authentication Failures
- **Gmail**: Ensure App Password is used, not regular password
- **2FA enabled accounts**: Generate and use App Passwords
- **Corporate email**: Check with IT for IMAP access requirements
- **Firewall**: Ensure IMAP ports (993, 143) are accessible

### Synchronization Issues
- **Check folder names**: IMAP folder names are case-sensitive
- **Network connectivity**: Verify both servers are accessible
- **Rate limiting**: Some servers limit connection frequency
- **Disk space**: Ensure sufficient space for logs and temporary files

### Performance Issues
- **Rate limiting**: Switch to IDLE or Push mode (see CONNECTION-MODES.md)
- **Increase polling interval**: Set `POLL_SECONDS` to higher value (poll mode only)
- **Resource limits**: Adjust Docker memory/CPU limits
- **Network latency**: Consider server proximity

### Rate Limit Issues (Gmail)
- **Switch to IDLE mode**: Set `SYNC_MODE=idle` in `.env`
- **Use Push notifications**: Set `SYNC_MODE=push` (requires Google Cloud setup)
- **Increase poll interval**: Set `POLL_SECONDS=60` or higher
- **See detailed guide**: Read `CONNECTION-MODES.md` for full setup instructions

### Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| `Connection refused` | Server unreachable | Check hostname, firewall |
| `Authentication failed` | Wrong credentials | Verify username/password |
| `SSL handshake failed` | SSL/TLS issues | Check SSL settings, certificates |
| `Folder not found` | Invalid folder name | Verify folder exists, check case |

## Development

### Local Development
```bash
make debug         # Start with shell access
make shell         # Access running container
```

### Testing
```bash
make test          # Test IMAP connections
make validate      # Validate configuration
```

## Support

### Logs Location
- **Container logs**: `docker-compose logs imap-sync`
- **Application logs**: `./logs/imapsync.log`
- **Health status**: `./data/health`

### Getting Help
1. **Check logs** for error messages
2. **Verify configuration** with `make check-config`
3. **Test connections** with `make test`
4. **Review troubleshooting** section above

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request
