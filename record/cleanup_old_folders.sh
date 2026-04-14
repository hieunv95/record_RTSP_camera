#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../.env}"
source "$SCRIPT_DIR/env_loader.sh"

if [[ -f "$ENV_FILE" ]]; then
    load_env_file "$ENV_FILE"
fi

RECORD_DIR="${RECORD_DIR:-/data/camera}"
YESTERDAY="$(date -d 'yesterday' +%y%m%d)"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

if [[ ! -d "$RECORD_DIR" ]]; then
    log "Record directory not found, skipping cleanup: $RECORD_DIR"
    exit 0
fi

log "Daily cleanup started (keep >= $YESTERDAY) in: $RECORD_DIR"

while IFS= read -r -d '' camera_dir; do
    while IFS= read -r -d '' date_dir; do
        date_name="$(basename "$date_dir")"
        if [[ "$date_name" < "$YESTERDAY" ]]; then
            rm -rf "$date_dir"
            log "Removed old folder: $date_dir"
        fi
    done < <(find "$camera_dir" -mindepth 1 -maxdepth 1 -type d -regextype posix-extended -regex '.*/[0-9]{6}' -print0)
done < <(find "$RECORD_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

log "Daily cleanup completed"
