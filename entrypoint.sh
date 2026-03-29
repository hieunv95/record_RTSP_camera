#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env_loader.sh"

echo "=== RTSP Camera Recorder Container ==="
echo "Timezone: ${TZ:-Asia/Ho_Chi_Minh}"
echo "Record dir: ${RECORD_DIR:-/data/camera}"
echo "Upload mode: immediate after each recording"
echo ""

# Load .env if exists (Docker env vars take precedence)
ENV_FILE="${ENV_FILE:-/config/.env}"

if [[ -f "$ENV_FILE" ]]; then
    echo "Loading config from: $ENV_FILE"
    load_env_file "$ENV_FILE"
fi

# Validate required config
if [[ -z "${CAMERAS:-}" ]]; then
    echo "ERROR: CAMERAS must be set." >&2
    echo "Set via docker-compose.yml environment, .env file, or -e flag." >&2
    exit 1
fi

IFS=';' read -r -a camera_entries <<< "${CAMERAS}"
camera_count=0
for entry in "${camera_entries[@]}"; do
    [[ -n "${entry//[[:space:]]/}" ]] || continue
    ((camera_count+=1))
done
echo "Cameras configured: ${camera_count}"

# Check rclone config
RCLONE_CONF="${RCLONE_CONF:-/config/rclone.conf}"
if [[ -f "$RCLONE_CONF" ]]; then
    echo "Rclone config found: $RCLONE_CONF"
else
    echo "WARNING: Rclone config not found at $RCLONE_CONF" >&2
    echo "Cloud sync will fail until rclone.conf is mounted." >&2
fi

# Ensure data directory exists
mkdir -p "${RECORD_DIR:-/data/camera}"

# Generate crontab dynamically
CRONTAB_FILE="/tmp/crontab"

cat > "$CRONTAB_FILE" <<EOF
# Record every 5 minutes and sync immediately after recording
*/5 * * * * ENV_FILE=$ENV_FILE RCLONE_CONF=$RCLONE_CONF /app/record.sh && ENV_FILE=$ENV_FILE RCLONE_CONF=$RCLONE_CONF /app/rclone.sh >> /proc/1/fd/1 2>&1
EOF

echo ""
echo "Cron schedule:"
cat "$CRONTAB_FILE"
echo ""
echo "Starting supercronic..."

# Run supercronic as PID 1 (handles signals properly)
exec supercronic -passthrough-logs "$CRONTAB_FILE"
