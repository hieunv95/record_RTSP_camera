FROM debian:bookworm-slim

LABEL maintainer="duchoa23" \
      description="RTSP Camera Recorder with cloud sync" \
      org.opencontainers.image.source="https://github.com/duchoa23/record_RTSP_camera"

# Install minimal dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        rclone \
        ca-certificates \
        curl \
        tzdata && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install supercronic (lightweight cron for containers)
# Auto-detect architecture for multi-arch support (amd64/arm64)
ARG SUPERCRONIC_VERSION=v0.2.33
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then \
        SUPERCRONIC_URL="https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-arm64"; \
    else \
        SUPERCRONIC_URL="https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64"; \
    fi && \
    curl -fsSL "$SUPERCRONIC_URL" -o /usr/local/bin/supercronic && \
    chmod +x /usr/local/bin/supercronic

# Create app and data directories
RUN mkdir -p /app /data/camera /config

# Copy scripts
COPY record/record.sh /app/record.sh
COPY record/rclone.sh /app/rclone.sh
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod 755 /app/*.sh

# Default environment
ENV RECORD_DIR=/data/camera \
    RECORD_DURATION=3580 \
    RCLONE_REMOTE=cam \
    RCLONE_PATH=camera \
    RCLONE_CONF=/config/rclone.conf \
    SYNC_INTERVAL_HOURS=2 \
    DELETE_AFTER_SYNC=true \
    DISK_USAGE_THRESHOLD=80 \
    TZ=Asia/Ho_Chi_Minh \
    ENV_FILE=/config/.env

VOLUME ["/data", "/config"]

ENTRYPOINT ["/app/entrypoint.sh"]
