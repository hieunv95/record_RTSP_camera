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
RECORD_TIMEOUT_GRACE="${RECORD_TIMEOUT_GRACE:-20}"
CAMERAS="${CAMERAS:-}"

# Date variables
TODAY=$(date +%y%m%d)
TIMESTAMP=$(date +%y%m%d-%H%M%S)

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

    record_timeout=$((RECORD_DURATION + RECORD_TIMEOUT_GRACE))

    mkdir -p "$output_dir"
    log "Recording started [$camera_name]: $output_file"

    # Record RTSP stream
    # -timeout: kill ffmpeg if it exceeds RECORD_DURATION + RECORD_TIMEOUT_GRACE
    # -nostdin/-hide_banner: reduce interactive/noisy behavior in cron
    # -rtsp_transport tcp: stable RTSP transport
    # -rtsp_flags prefer_tcp: ask RTSP layer to prefer TCP interleaving
    # -use_wallclock_as_timestamps 1: derive packet timestamps from wall clock when source misses PTS/DTS
    # -fflags +genpts+igndts+discardcorrupt: generate/normalize timestamps and skip corrupt packets
    # -map/-dn/-sn: keep only video/audio streams (drop data/subtitle streams often carrying bad timestamps)
    # -vcodec copy: no video re-encoding (critical for low-power ARM)
    # -acodec copy: no audio re-encoding
    # -copytb 1: copy input timebase when stream-copying
    # -muxdelay/-muxpreload 0: reduce muxer buffering for cleaner segment boundaries
    # -t: duration in seconds
    # -loglevel warning: reduce log noise
    timeout "$record_timeout" ffmpeg \
        -nostdin \
        -hide_banner \
        -rtsp_transport tcp \
        -rtsp_flags prefer_tcp \
        -use_wallclock_as_timestamps 1 \
        -fflags +genpts+igndts+discardcorrupt \
        -i "$camera_url" \
        -map 0:v:0 \
        -map 0:a? \
        -dn \
        -sn \
        -vcodec copy \
        -acodec copy \
        -copytb 1 \
        -muxdelay 0 \
        -muxpreload 0 \
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
        if [[ "$exit_code" -eq 124 ]]; then
            if [[ -s "$output_file" ]]; then
                file_size=$(du -h "$output_file" 2>/dev/null | cut -f1)
                log "Recording reached timeout for [$camera_name] but output exists: $output_file (${file_size:-unknown})"
                log "Hint: increase RECORD_TIMEOUT_GRACE if this happens frequently (current=$RECORD_TIMEOUT_GRACE)"
            else
                log "ERROR: ffmpeg timed out (124) and produced no output for camera [$camera_name]" >&2
                overall_exit=1
            fi
        else
            log "ERROR: ffmpeg exited with code $exit_code for camera [$camera_name]" >&2
            overall_exit=1
        fi
    fi
done

exit "$overall_exit"
