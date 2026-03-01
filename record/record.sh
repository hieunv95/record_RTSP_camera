#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../.env}"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# Configuration with defaults
RTSP_URL="${RTSP_URL:?ERROR: RTSP_URL is not set. Check your .env file.}"
RECORD_DIR="${RECORD_DIR:-/data/camera}"
RECORD_DURATION="${RECORD_DURATION:-3580}"

# Date variables
TODAY=$(date +%d-%m-%Y)
TIMESTAMP=$(date +%d-%m-%Y--%H-%M)
OUTPUT_DIR="$RECORD_DIR/$TODAY"
OUTPUT_FILE="$OUTPUT_DIR/$TIMESTAMP.mp4"

# Create output directory
mkdir -p "$OUTPUT_DIR"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Recording started: $OUTPUT_FILE"

# Record RTSP stream
# -vcodec copy: no video re-encoding (critical for low-power ARM)
# -acodec copy: no audio re-encoding
# -t: duration in seconds
# -loglevel warning: reduce log noise
ffmpeg \
    -rtsp_transport tcp \
    -i "$RTSP_URL" \
    -vcodec copy \
    -acodec copy \
    -t "$RECORD_DURATION" \
    -loglevel warning \
    -y "$OUTPUT_FILE"

EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
    FILE_SIZE=$(du -h "$OUTPUT_FILE" 2>/dev/null | cut -f1)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Recording completed: $OUTPUT_FILE ($FILE_SIZE)"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ffmpeg exited with code $EXIT_CODE" >&2
fi

exit $EXIT_CODE
