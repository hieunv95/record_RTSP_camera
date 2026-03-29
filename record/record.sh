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
RECORD_DURATION="${RECORD_DURATION:-310}"
CAMERAS="${CAMERAS:-}"

# Date variables
TODAY=$(date +%d-%m-%Y)
TIMESTAMP=$(date +%d-%m-%Y--%H-%M)

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

declare -a CAMERA_NAMES=()
declare -a CAMERA_URLS=()

if [[ -n "$CAMERAS" ]]; then
    IFS=';' read -r -a camera_entries <<< "$CAMERAS"
    for entry in "${camera_entries[@]}"; do
        entry=$(trim "$entry")
        [[ -n "$entry" ]] || continue
        if [[ "$entry" != *=* ]]; then
            echo "ERROR: Invalid CAMERAS entry: '$entry'. Expected format: name=rtsp://..." >&2
            exit 1
        fi

        name=$(sanitize_camera_name "${entry%%=*}")
        url=$(trim "${entry#*=}")
        if [[ -z "$url" ]]; then
            echo "ERROR: Empty RTSP URL for camera '$name' in CAMERAS." >&2
            exit 1
        fi

        CAMERA_NAMES+=("$name")
        CAMERA_URLS+=("$url")
    done

    if [[ ${#CAMERA_NAMES[@]} -eq 0 ]]; then
        echo "ERROR: CAMERAS is set but no valid camera entries were found." >&2
        exit 1
    fi
else
    echo "ERROR: CAMERAS must be set. Format: name=rtsp://...;name2=rtsp://..." >&2
    exit 1
fi

record_single_camera() {
    local camera_name="$1"
    local camera_url="$2"
    local output_dir="$3"
    local output_file="$4"
    local record_timeout

    record_timeout=$((RECORD_DURATION + 5))

    mkdir -p "$output_dir"
    log "Recording started [$camera_name]: $output_file"

    # Record RTSP stream
    # -timeout: kill ffmpeg if it exceeds RECORD_DURATION + 5s grace
    # -nostdin/-hide_banner: reduce interactive/noisy behavior in cron
    # -rtsp_transport tcp: stable RTSP transport
    # -vcodec copy: no video re-encoding (critical for low-power ARM)
    # -acodec copy: no audio re-encoding
    # -t: duration in seconds
    # -loglevel warning: reduce log noise
    timeout "$record_timeout" ffmpeg \
        -nostdin \
        -hide_banner \
        -rtsp_transport tcp \
        -i "$camera_url" \
        -vcodec copy \
        -acodec copy \
        -t "$RECORD_DURATION" \
        -loglevel warning \
        -y "$output_file"
}

declare -a PIDS=()
declare -a PID_CAMERA_NAMES=()
declare -a PID_OUTPUT_FILES=()

for i in "${!CAMERA_NAMES[@]}"; do
    camera_name="${CAMERA_NAMES[$i]}"
    camera_url="${CAMERA_URLS[$i]}"

    output_dir="$RECORD_DIR/$camera_name/$TODAY"
    output_file="$output_dir/$TIMESTAMP.mkv"

    (
        record_single_camera "$camera_name" "$camera_url" "$output_dir" "$output_file"
    ) &

    PIDS+=("$!")
    PID_CAMERA_NAMES+=("$camera_name")
    PID_OUTPUT_FILES+=("$output_file")
done

overall_exit=0
for i in "${!PIDS[@]}"; do
    pid="${PIDS[$i]}"
    camera_name="${PID_CAMERA_NAMES[$i]}"
    output_file="${PID_OUTPUT_FILES[$i]}"

    if wait "$pid"; then
        file_size=$(du -h "$output_file" 2>/dev/null | cut -f1)
        log "Recording completed [$camera_name]: $output_file (${file_size:-unknown})"
    else
        exit_code=$?
        log "ERROR: ffmpeg exited with code $exit_code for camera [$camera_name]" >&2
        overall_exit=1
    fi
done

exit "$overall_exit"
