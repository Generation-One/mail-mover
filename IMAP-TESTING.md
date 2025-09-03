# IMAP Connection Testing

This directory includes comprehensive IMAP connection testing tools to help diagnose connection issues and verify your setup.

## Quick Testing

### Test Both Servers (Recommended)
```bash
make test-imap
```
Tests both source and destination IMAP servers using your `.env` configuration.

### Test Individual Servers
```bash
make test-imap-source    # Test source server (HOST_1)
make test-imap-dest      # Test destination server (HOST_2)
```

### Comprehensive Python Tests
```bash
make test-imap-python    # Detailed tests with IDLE support check
```

## Manual Testing

### Simple Bash Script
```bash
# Test both servers
./test-imap-simple.sh

# Test specific server
./test-imap-simple.sh --source
./test-imap-simple.sh --dest
```

### Python Script (Advanced)
```bash
# Gmail example
python3 test-imap-connection.py \
    --host imap.gmail.com \
    --username your-email@gmail.com \
    --password your-app-password

# With custom settings
python3 test-imap-connection.py \
    --host imap.gmail.com \
    --username your-email@gmail.com \
    --password your-app-password \
    --port 993 \
    --stability-duration 60
```

## What Gets Tested

### Basic Tests (Bash Script)
- ✅ **DNS Resolution** - Can resolve the hostname
- ✅ **SSL/TLS Connection** - Can establish secure connection
- ✅ **IMAP Authentication** - Credentials work
- ✅ **Basic Functionality** - Can connect and authenticate

### Comprehensive Tests (Python Script)
- ✅ **Basic Connection** - TCP/SSL connection establishment
- ✅ **Authentication** - Login with credentials
- ✅ **Folder Listing** - Can list available folders
- ✅ **INBOX Selection** - Can select and read INBOX
- ✅ **IDLE Support** - Server supports IMAP IDLE (for real-time sync)
- ✅ **Recent Messages** - Can fetch message headers
- ✅ **Connection Stability** - Connection stays alive over time

## Common Issues and Solutions

### Connection Refused
```
✗ SSL connection to imap.gmail.com:993 failed
```
**Solutions:**
- Check hostname spelling
- Verify port (993 for SSL, 143 for plain)
- Check firewall/network restrictions
- Try different network (mobile hotspot)

### Authentication Failed
```
✗ IMAP connection or authentication failed
```
**Solutions:**
- **Gmail**: Use App Password, not regular password
- **2FA accounts**: Generate App Password
- Verify username (full email address)
- Check password for typos

### IDLE Not Supported
```
✗ Server does not support IDLE capability
```
**Solutions:**
- Use polling mode instead: `SYNC_MODE=poll`
- Some servers don't support IDLE
- Check server documentation

### DNS Resolution Failed
```
✗ DNS resolution failed for hostname
```
**Solutions:**
- Check hostname spelling
- Try using IP address instead
- Check DNS settings
- Test with `nslookup hostname`

## Test Output Examples

### Successful Test
```
=== IMAP Connection Test ===
ℹ Testing: user@gmail.com@imap.gmail.com:993

=== Testing DNS Resolution ===
✓ DNS resolution successful: imap.gmail.com -> 142.250.191.109

=== Testing SSL Connection ===
✓ SSL connection to imap.gmail.com:993 successful

=== Testing IMAP with imapsync ===
✓ IMAP connection and authentication successful

Tests passed: 3/3
✓ All tests passed! IMAP connection is working perfectly.
```

### Failed Test
```
=== IMAP Connection Test ===
ℹ Testing: user@gmail.com@imap.gmail.com:993

=== Testing DNS Resolution ===
✓ DNS resolution successful: imap.gmail.com -> 142.250.191.109

=== Testing SSL Connection ===
✓ SSL connection to imap.gmail.com:993 successful

=== Testing IMAP with imapsync ===
✗ IMAP connection or authentication failed
ℹ Check your credentials and server settings

Tests passed: 2/3
✗ Multiple test failures. Check your IMAP configuration.
```

## Troubleshooting Workflow

1. **Start with basic test:**
   ```bash
   make test-imap
   ```

2. **If it fails, test individual components:**
   ```bash
   # Test just the source server
   make test-imap-source
   
   # Test DNS resolution manually
   nslookup imap.gmail.com
   
   # Test SSL connection manually
   openssl s_client -connect imap.gmail.com:993
   ```

3. **Run comprehensive tests:**
   ```bash
   make test-imap-python
   ```

4. **Check specific issues:**
   - **Authentication**: Verify App Password for Gmail
   - **Network**: Try different network/VPN
   - **Firewall**: Check corporate firewall rules
   - **Server**: Verify IMAP is enabled on email account

## Integration with Sync Modes

### Before Switching to IDLE Mode
```bash
# Test IDLE support first
make test-imap-python

# Look for this in output:
# ✓ Server supports IDLE capability
# ✓ IDLE command test successful

# If IDLE is supported, switch modes:
make setup-idle
```

### Before Using Push Mode
```bash
# Test basic Gmail connection first
make test-imap-source

# Then set up Google Cloud (see CONNECTION-MODES.md)
make setup-push
```

## Automated Testing

Add to your deployment pipeline:
```bash
# Test connections before deployment
make test-imap || exit 1

# Deploy if tests pass
make build
make start
```

## Files

- `test-imap-simple.sh` - Quick bash-based tests using your .env
- `test-imap-connection.py` - Comprehensive Python tests with detailed output
- `IMAP-TESTING.md` - This documentation

## Support

If tests continue to fail:
1. Check the specific error messages
2. Verify your email provider's IMAP settings
3. Test with a different email client (Thunderbird, etc.)
4. Contact your email provider's support
