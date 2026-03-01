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
RECORD_DIR="${RECORD_DIR:-/data/camera}"
RCLONE_REMOTE="${RCLONE_REMOTE:-cam}"
RCLONE_PATH="${RCLONE_PATH:-camera}"
DELETE_AFTER_SYNC="${DELETE_AFTER_SYNC:-true}"
DISK_USAGE_THRESHOLD="${DISK_USAGE_THRESHOLD:-80}"
RCLONE_CONF="${RCLONE_CONF:-}"

# Rclone config flag (if custom path specified)
RCLONE_CONF_FLAG=""
if [[ -n "$RCLONE_CONF" && -f "$RCLONE_CONF" ]]; then
    RCLONE_CONF_FLAG="--config $RCLONE_CONF"
fi

# Low-memory rclone flags for ARM devices (2GB RAM)
RCLONE_FLAGS="--check-first --transfers 1 --checkers 2 --buffer-size 0 --low-level-retries 3 --retries 3"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Check disk usage and force cleanup if above threshold
check_disk_usage() {
    if [[ "$DISK_USAGE_THRESHOLD" -eq 0 ]]; then
        return
    fi
    local usage
    usage=$(df "$RECORD_DIR" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    if [[ -n "$usage" && "$usage" -ge "$DISK_USAGE_THRESHOLD" ]]; then
        log "WARNING: Disk usage at ${usage}% (threshold: ${DISK_USAGE_THRESHOLD}%). Forcing cleanup of oldest directories..."
        # Delete oldest directories first (keep today)
        find "$RECORD_DIR" -mindepth 1 -maxdepth 1 -type d -not -name "$(date +%d-%m-%Y)" | sort | head -1 | xargs -r rm -rf
    fi
}

# Sync all existing date directories to cloud
sync_recordings() {
    local sync_errors=0
    local synced_dirs=()

    # Find all date directories in RECORD_DIR
    for dir in "$RECORD_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local dirname
        dirname=$(basename "$dir")

        # Skip if directory is empty
        if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
            log "Skipping empty directory: $dirname"
            continue
        fi

        # Skip today's directory (still being recorded)
        if [[ "$dirname" == "$(date +%d-%m-%Y)" ]]; then
            log "Skipping today's directory: $dirname"
            continue
        fi

        log "Syncing: $dirname -> ${RCLONE_REMOTE}:${RCLONE_PATH}/$dirname"
        # shellcheck disable=SC2086
        if rclone sync "$dir" "${RCLONE_REMOTE}:${RCLONE_PATH}/$dirname" $RCLONE_CONF_FLAG $RCLONE_FLAGS; then
            log "Sync completed: $dirname"
            synced_dirs+=("$dir")
        else
            log "ERROR: Sync failed for $dirname (exit code: $?)" >&2
            ((sync_errors++))
        fi
    done

    # Delete successfully synced directories
    if [[ "$DELETE_AFTER_SYNC" == "true" ]]; then
        for dir in "${synced_dirs[@]:-}"; do
            [[ -n "$dir" && -d "$dir" ]] || continue
            log "Deleting synced directory: $(basename "$dir")"
            rm -rf "$dir"
        done
    fi

    return $sync_errors
}

# Create today's directory (ensure it exists for recording)
mkdir -p "$RECORD_DIR/$(date +%d-%m-%Y)"

# Check disk usage before sync
check_disk_usage

# Run sync
log "Starting cloud sync..."
if sync_recordings; then
    log "All syncs completed successfully."
else
    log "WARNING: Some syncs failed. Files not deleted for failed syncs." >&2
fi

# Final disk usage check
check_disk_usage
log "Sync job finished."
