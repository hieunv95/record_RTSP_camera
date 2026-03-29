#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../.env}"
source "$SCRIPT_DIR/env_loader.sh"

if [[ -f "$ENV_FILE" ]]; then
    load_env_file "$ENV_FILE"
fi

# Configuration with defaults
RECORD_DIR="${RECORD_DIR:-/data/camera}"
RCLONE_REMOTE="${RCLONE_REMOTE:-cam}"
RCLONE_PATH="${RCLONE_PATH:-camera}"
DELETE_AFTER_SYNC="${DELETE_AFTER_SYNC:-true}"
DISK_USAGE_THRESHOLD="${DISK_USAGE_THRESHOLD:-80}"
RCLONE_CONF="${RCLONE_CONF:-}"

# Build rclone command base (if custom config exists)
RCLONE_BASE_CMD=(rclone)
if [[ -n "$RCLONE_CONF" && -f "$RCLONE_CONF" ]]; then
    RCLONE_BASE_CMD+=(--config "$RCLONE_CONF")
fi

# Low-memory rclone flags for ARM devices (2GB RAM)
RCLONE_FLAGS=(--check-first --transfers 1 --checkers 2 --buffer-size 0 --low-level-retries 3 --retries 3)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Check disk usage and force cleanup if above threshold
check_disk_usage() {
    if [[ "$DISK_USAGE_THRESHOLD" -eq 0 ]]; then
        return
    fi
    local usage
    local oldest_date_dir
    usage=$(df "$RECORD_DIR" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    if [[ -n "$usage" && "$usage" -ge "$DISK_USAGE_THRESHOLD" ]]; then
        log "WARNING: Disk usage at ${usage}% (threshold: ${DISK_USAGE_THRESHOLD}%). Forcing cleanup of oldest date directories..."
        oldest_date_dir=$(find "$RECORD_DIR" -mindepth 1 -maxdepth 2 -type d \
            -regextype posix-extended -regex '.*/[0-9]{2}-[0-9]{2}-[0-9]{4}' \
            -not -name "$(date +%d-%m-%Y)" \
            -printf '%T@ %p\n' | sort -n | head -1 | cut -d' ' -f2-)

        if [[ -n "$oldest_date_dir" && -d "$oldest_date_dir" ]]; then
            log "Deleting oldest directory: ${oldest_date_dir#$RECORD_DIR/}"
            rm -rf "$oldest_date_dir"
            find "$RECORD_DIR" -mindepth 1 -maxdepth 1 -type d -empty -delete
        else
            log "No eligible date directory found for forced cleanup."
        fi
    fi
}

# Sync all existing date directories to cloud
sync_recordings() {
    local sync_errors=0
    local synced_dirs=()

    while IFS= read -r dir; do
        [[ -d "$dir" ]] || continue
        local dirname rel_path
        dirname=$(basename "$dir")
        rel_path="${dir#$RECORD_DIR/}"

        # Skip if directory is empty
        if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
            log "Skipping empty directory: $rel_path"
            continue
        fi

        log "Syncing: $rel_path -> ${RCLONE_REMOTE}:${RCLONE_PATH}/$rel_path"
        if "${RCLONE_BASE_CMD[@]}" sync "$dir" "${RCLONE_REMOTE}:${RCLONE_PATH}/$rel_path" "${RCLONE_FLAGS[@]}"; then
            log "Sync completed: $rel_path"
            synced_dirs+=("$dir")
        else
            log "ERROR: Sync failed for $rel_path (exit code: $?)" >&2
            ((sync_errors++))
        fi
    done < <(
        find "$RECORD_DIR" -mindepth 1 -maxdepth 2 -type d \
            -regextype posix-extended -regex '.*/[0-9]{2}-[0-9]{2}-[0-9]{4}' | sort
    )

    # Delete successfully synced directories
    if [[ "$DELETE_AFTER_SYNC" == "true" ]]; then
        for dir in "${synced_dirs[@]:-}"; do
            [[ -n "$dir" && -d "$dir" ]] || continue
            log "Deleting synced directory: ${dir#$RECORD_DIR/}"
            rm -rf "$dir"
        done
        find "$RECORD_DIR" -mindepth 1 -maxdepth 1 -type d -empty -delete
    fi

    return $sync_errors
}

mkdir -p "$RECORD_DIR"

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
