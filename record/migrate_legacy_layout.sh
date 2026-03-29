#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../.env}"

if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

RECORD_DIR="${RECORD_DIR:-/data/camera}"
TARGET_CAMERA_NAME="${1:-${LEGACY_CAMERA_NAME:-camera}}"
DRY_RUN="${DRY_RUN:-false}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

trim() {
    local value="$1"
    value="${value#${value%%[![:space:]]*}}"
    value="${value%${value##*[![:space:]]}}"
    printf '%s' "$value"
}

sanitize_camera_name() {
    local camera_name
    camera_name=$(trim "$1")
    camera_name="${camera_name// /_}"
    camera_name="${camera_name//[^a-zA-Z0-9_-]/_}"
    [[ -n "$camera_name" ]] || camera_name="camera"
    printf '%s' "$camera_name"
}

TARGET_CAMERA_NAME="$(sanitize_camera_name "$TARGET_CAMERA_NAME")"

if [[ ! -d "$RECORD_DIR" ]]; then
    log "ERROR: RECORD_DIR does not exist: $RECORD_DIR" >&2
    exit 1
fi

if [[ "$DRY_RUN" != "true" && "$DRY_RUN" != "false" ]]; then
    log "ERROR: DRY_RUN must be true or false." >&2
    exit 1
fi

log "Migration started"
log "Record dir: $RECORD_DIR"
log "Target camera name: $TARGET_CAMERA_NAME"
log "Dry run: $DRY_RUN"

declare -a LEGACY_DIRS=()
while IFS= read -r dir; do
    LEGACY_DIRS+=("$dir")
done < <(
    find "$RECORD_DIR" -mindepth 1 -maxdepth 1 -type d \
        -regextype posix-extended -regex '.*/[0-9]{2}-[0-9]{2}-[0-9]{4}' | sort
)

if [[ ${#LEGACY_DIRS[@]} -eq 0 ]]; then
    log "No legacy date directories found. Nothing to migrate."
    exit 0
fi

log "Found ${#LEGACY_DIRS[@]} legacy date directories"

move_item() {
    local src="$1"
    local dst="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY_RUN] Move: $src -> $dst"
        return
    fi

    if [[ -e "$dst" ]]; then
        log "WARNING: Destination already exists, skipping: $dst"
        return
    fi

    mv "$src" "$dst"
}

migrated_dirs=0
skipped_items=0

for src_dir in "${LEGACY_DIRS[@]}"; do
    date_name="$(basename "$src_dir")"
    dst_dir="$RECORD_DIR/$TARGET_CAMERA_NAME/$date_name"

    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$dst_dir"
    else
        log "[DRY_RUN] Ensure dir: $dst_dir"
    fi

    shopt -s nullglob dotglob
    items=("$src_dir"/*)
    shopt -u nullglob dotglob

    if [[ ${#items[@]} -eq 0 ]]; then
        log "Skipping empty legacy directory: $date_name"
    else
        for item in "${items[@]}"; do
            base_name="$(basename "$item")"
            if [[ -e "$dst_dir/$base_name" ]]; then
                log "WARNING: Target exists, skipping item: $date_name/$base_name"
                ((skipped_items+=1))
                continue
            fi
            move_item "$item" "$dst_dir/$base_name"
        done
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY_RUN] Remove source dir if empty: $src_dir"
        ((migrated_dirs+=1))
        continue
    fi

    if rmdir "$src_dir" 2>/dev/null; then
        ((migrated_dirs+=1))
        log "Migrated directory: $date_name -> $TARGET_CAMERA_NAME/$date_name"
    else
        log "WARNING: Source directory not empty after move (some files may have been skipped): $src_dir"
    fi
done

log "Migration finished. Migrated dirs: $migrated_dirs, skipped items: $skipped_items"
