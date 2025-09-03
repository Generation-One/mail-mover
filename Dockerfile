# Multi-stage build for IMAP synchronization service
# Base: Alpine Linux 3.20 with imapsync from GitHub source

# Build stage - Install imapsync and dependencies
FROM alpine:3.20 AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    make \
    perl \
    perl-dev \
    perl-app-cpanminus \
    gcc \
    musl-dev \
    openssl-dev \
    zlib-dev \
    linux-headers

# Install Alpine Perl packages for SSL support
RUN apk add --no-cache \
    perl-net-ssleay \
    perl-io-socket-ssl

# Install remaining Perl modules required by imapsync
RUN cpanm --notest \
    Mail::IMAPClient \
    Digest::MD5 \
    Digest::HMAC_MD5 \
    Term::ReadKey \
    File::Spec \
    IO::Socket::INET6 \
    Unicode::String \
    Data::Uniqid \
    JSON::WebToken \
    LWP::UserAgent \
    HTML::Entities \
    Encode::IMAPUTF7 \
    JSON \
    CGI \
    Authen::NTLM \
    Crypt::OpenSSL::RSA \
    Dist::CheckConflicts \
    File::Copy::Recursive \
    File::Tail \
    IO::Tee \
    Module::Implementation \
    Package::Stash \
    Readonly \
    Regexp::Common \
    Sys::MemInfo

# Clone and install imapsync from GitHub
WORKDIR /tmp
RUN git clone https://github.com/imapsync/imapsync.git && \
    cd imapsync && \
    cp imapsync /usr/local/bin/ && \
    chmod +x /usr/local/bin/imapsync

# Runtime stage - Minimal Alpine with only runtime dependencies
FROM alpine:3.20

# Install runtime dependencies
RUN apk add --no-cache \
    perl \
    perl-io-socket-ssl \
    perl-digest-md5 \
    perl-digest-hmac \
    perl-term-readkey \
    perl-unicode-string \
    perl-lwp-useragent-determined \
    perl-html-parser \
    perl-json \
    perl-cgi \
    perl-net-ssleay \
    ca-certificates \
    tzdata \
    bash \
    python3 \
    py3-pip

# Install Python packages for IDLE and Push modes
# Use --break-system-packages for Alpine Linux compatibility
RUN pip3 install --no-cache-dir --break-system-packages \
    google-auth \
    google-auth-oauthlib \
    google-auth-httplib2 \
    google-api-python-client \
    google-cloud-pubsub

# Copy imapsync and Perl modules from builder
COPY --from=builder /usr/local/bin/imapsync /usr/local/bin/
COPY --from=builder /usr/local/share/perl5 /usr/local/share/perl5
COPY --from=builder /usr/local/lib/perl5 /usr/local/lib/perl5

# Create non-root user for security
RUN addgroup -g 1000 imapsync && \
    adduser -D -u 1000 -G imapsync -s /bin/bash imapsync

# Create directories for logs and data with proper permissions
RUN mkdir -p /app/logs /app/data && \
    chown -R imapsync:imapsync /app && \
    chmod -R 755 /app/logs /app/data

# Copy sync script, health check, Python scripts, setup script, ps wrapper, sleep wrapper, and permission fix script
COPY sync-script.sh /app/
COPY health-check.sh /app/
COPY imap-idle-sync.py /app/
COPY gmail-push-sync.py /app/
COPY setup-connection-mode.sh /app/
COPY fix-permissions.sh /app/
COPY ps-wrapper.sh /usr/local/bin/ps
COPY sleep-wrapper.sh /usr/local/bin/sleep
RUN chmod +x /app/sync-script.sh /app/health-check.sh /app/imap-idle-sync.py /app/gmail-push-sync.py /app/setup-connection-mode.sh /app/fix-permissions.sh /usr/local/bin/ps /usr/local/bin/sleep && \
    chown imapsync:imapsync /app/sync-script.sh /app/health-check.sh /app/imap-idle-sync.py /app/gmail-push-sync.py /app/setup-connection-mode.sh /app/fix-permissions.sh

# Switch to non-root user
USER imapsync
WORKDIR /app

# Environment variables with defaults
ENV POLL_SECONDS=15 \
    FOLDER=INBOX \
    LOG_LEVEL=INFO \
    HEALTH_CHECK_PORT=8080

# Expose health check port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD /app/health-check.sh

# Default command
CMD ["/app/sync-script.sh"]
