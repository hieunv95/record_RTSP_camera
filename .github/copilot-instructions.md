# Copilot Instructions for record_RTSP_camera

## Project Overview
Records RTSP camera streams every 5 minutes via ffmpeg, syncs to cloud (Google Drive/OneDrive/Dropbox) immediately after each recording via rclone. Targets **Armbian Bookworm / Debian 12 ARM64** with 2GB RAM, 10GB disk. Dual deployment: bare-metal (`setup.sh`) and Docker.

## Architecture
```
Cron */5 → record/record.sh (ffmpeg copy-mode → <camera>/DD-MM-YYYY/DD-MM-YYYY--HH-MM.mkv)
Immediately after each record run → record/rclone.sh (sync date dirs → cloud, delete on success, disk cleanup)
```
- **Docker**: `entrypoint.sh` generates crontab from env vars → runs `supercronic` as PID 1
- **Bare-metal**: `setup.sh` installs via apt-get, creates `/etc/cron.d/record-camera`

## Configuration
All settings in `.env` (see `.env.example`). Scripts load via:
```bash
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../.env}"  # ENV_FILE env var → fallback to ../.env
set -a; source "$ENV_FILE"; set +a
```
Key vars: `CAMERAS` (required), `RECORD_DIR`, `RECORD_DURATION`, `RCLONE_REMOTE`, `RCLONE_PATH`, `DELETE_AFTER_SYNC`, `DISK_USAGE_THRESHOLD`, `TZ`

## Critical Constraints (ARM 2GB RAM / 10GB disk)
- **ffmpeg**: Always `-vcodec copy -acodec copy` — never re-encode (`-vcodec libx264` will OOM)
- **ffmpeg**: Always `-rtsp_transport tcp` for stream stability
- **rclone**: Always `--transfers 1 --checkers 2 --buffer-size 0` to limit memory
- **Docker**: `mem_limit: 512m`, `memswap_limit: 768m`
- **Disk**: `check_disk_usage()` in rclone.sh auto-deletes oldest dir when above threshold

## Script Conventions
- All scripts: `set -euo pipefail`, structured `[timestamp] message` logging
- `record.sh`: Fails fast if `CAMERAS` unset and writes to canonical `<camera>/DD-MM-YYYY` layout
- `rclone.sh`: Iterates date dirs and deletes only after confirmed sync success (`$? -eq 0`)
- rclone.sh `RCLONE_CONF` flag: auto-appends `--config $RCLONE_CONF` if file exists (Docker mounts to `/config/rclone.conf`)

## File Paths
| Context | Scripts | Recordings | Config |
|---------|---------|-----------|--------|
| Docker | `/app/*.sh` | `/data/camera/` | `/config/.env`, `/config/rclone.conf` |
| Bare-metal | `/opt/record/*.sh` | `/opt/record/camera/` | `/opt/record/.env` |

## Testing
```bash
docker compose logs -f                           # live logs
docker compose exec recorder /app/rclone.sh      # manual sync
docker stats rtsp-recorder                        # memory check
ffmpeg -rtsp_transport tcp -i "<RTSP_URL>" -t 10 -y test.mkv  # test stream
du -sh data/camera/*/                             # disk usage
```

## Key Files
| File | Purpose |
|------|---------|
| `.env.example` | Config template with all variables and defaults |
| `record/record.sh` | Hourly ffmpeg RTSP capture (copy mode, no transcoding) |
| `record/rclone.sh` | Cloud sync + conditional delete + disk usage cleanup |
| `setup.sh` | Bare-metal Debian 12 installer (apt-get, /etc/cron.d/) |
| `Dockerfile` | `debian:bookworm-slim` + ffmpeg + rclone + supercronic (multi-arch) |
| `docker-compose.yml` | Volumes, memory limits, log rotation, restart policy |
| `entrypoint.sh` | Dynamic crontab from env vars → exec supercronic |

