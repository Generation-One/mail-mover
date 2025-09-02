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
    zlib-dev

# Install Perl modules required by imapsync
RUN cpanm --notest \
    Mail::IMAPClient \
    IO::Socket::SSL \
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
    CGI

# Clone and install imapsync from GitHub
WORKDIR /tmp
RUN git clone https://github.com/imapsync/imapsync.git && \
    cd imapsync && \
    make install

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
    ca-certificates \
    tzdata \
    bash

# Copy imapsync and Perl modules from builder
COPY --from=builder /usr/local/bin/imapsync /usr/local/bin/
COPY --from=builder /usr/local/share/perl5 /usr/local/share/perl5

# Create non-root user for security
RUN addgroup -g 1000 imapsync && \
    adduser -D -u 1000 -G imapsync -s /bin/bash imapsync

# Create directories for logs and data
RUN mkdir -p /app/logs /app/data && \
    chown -R imapsync:imapsync /app

# Copy sync script
COPY sync-script.sh /app/
RUN chmod +x /app/sync-script.sh && \
    chown imapsync:imapsync /app/sync-script.sh

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
