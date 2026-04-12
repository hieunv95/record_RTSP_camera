# record_RTSP_camera

Record RTSP camera streams and sync to cloud storage (Google Drive, OneDrive, Dropbox) via rclone.  
Optimized for **Armbian Bookworm / Debian 12** on ARM64 boards with limited resources (2GB RAM, 10GB disk).

## Features

- RTSP recording every 5 minutes with ffmpeg (copy mode, no re-encoding)
- Single-camera and multi-camera support
- Automatic cloud sync immediately after each recording via rclone
- Disk space monitoring with auto-cleanup
- Docker support with memory limits for low-power ARM devices
- Sensitive credentials stored in `.env` (not in scripts)

## Requirements

- Linux: Debian 12 (Bookworm) / Armbian Bookworm ARM64
- RTSP camera with accessible stream URL
- Cloud storage account (Google Drive, OneDrive, Dropbox, etc.)
- Docker + Docker Compose (for Docker method) **OR** ffmpeg + rclone (for bare-metal)

---

## Quick Start (Docker - Recommended)

### 1. Clone and configure

```bash
git clone https://github.com/duchoa23/record_RTSP_camera.git
cd record_RTSP_camera

# Create your config
cp .env.example .env
nano .env  # Set CAMERAS and other settings
```

### 2. Setup rclone

```bash
# Configure rclone remote (create remote named 'cam')
rclone config

# Copy config file to project directory
cp ~/.config/rclone/rclone.conf ./rclone.conf
```

### 3. Start

```bash
docker compose up -d
```

### 4. Monitor

```bash
# View logs
docker compose logs -f

# Check disk usage
du -sh data/

# Check container stats
docker stats rtsp-recorder
```

### Stop / Restart

```bash
docker compose down       # Stop
docker compose restart    # Restart
docker compose up -d --build  # Rebuild after changes
```

---

## Bare-Metal Installation (Debian 12 / Armbian)

### 1. Configure

```bash
git clone https://github.com/duchoa23/record_RTSP_camera.git
cd record_RTSP_camera

cp .env.example .env
nano .env  # Set CAMERAS and other settings
```

### 2. Setup rclone

```bash
rclone config  # Create remote named 'cam' (or change RCLONE_REMOTE in .env)
```

### 3. Install

```bash
sudo bash setup.sh
```

This will:
- Install ffmpeg, rclone via apt
- Copy scripts to `/opt/record/`
- Setup cron jobs (record every 5 minutes, sync immediately after each recording, remove folders older than today at 00:00)

### 4. Monitor

```bash
# Check cron jobs
cat /etc/cron.d/record-camera

# View logs
tail -f /var/log/record-camera.log
tail -f /var/log/record-camera-sync.log

# Check disk usage
du -sh /opt/record/camera/
```

---

## Configuration (.env)

| Variable | Default | Description |
|----------|---------|-------------|
| `CAMERAS` | *(required)* | Camera list: `front=rtsp://...;back=rtsp://...` |
| `RECORD_DIR` | `/data/camera` | Recording storage directory |
| `RECORD_DURATION` | `310` | Seconds per recording segment (5 minutes + 10s delay buffer) |
| `RECORD_TIMEOUT_GRACE` | `20` | Extra seconds before timeout kills ffmpeg (reduce false `124` exits) |
| `RCLONE_REMOTE` | `cam` | Rclone remote name |
| `RCLONE_PATH` | `camera` | Cloud folder path |
| `DELETE_AFTER_SYNC` | `true` | Enable local cleanup after successful sync |
| `DELETE_OLDER_THAN_MINUTES` | `60` | Delete only local files older than N minutes |
| `DISK_USAGE_THRESHOLD` | `80` | Force cleanup at N% disk usage (0=disable) |
| `TZ` | `Asia/Ho_Chi_Minh` | Timezone |

Use `CAMERAS` for one or more cameras.

`CAMERAS` now supports raw/unquoted RTSP query strings (including `&` and `;`) with the built-in dotenv parser, but quoting the full value is still recommended for readability.

### Multi-camera folder layout

- Canonical layout: `RECORD_DIR/<camera-name>/YYMMDD/YYMMDD-HHMMSS.mkv`

Cloud sync preserves the same relative structure under `RCLONE_PATH`.

---

## Storage Estimates

| Camera Bitrate | Per Hour | Per Day (24h) | 10GB Disk Holds |
|---------------|----------|---------------|-----------------|
| 2 Mbps | ~900 MB | ~21 GB | ~11 hours |
| 4 Mbps | ~1.8 GB | ~43 GB | ~5 hours |
| 8 Mbps | ~3.6 GB | ~86 GB | ~2 hours |

With immediate sync after each recording, local storage is reduced as soon as uploads succeed.

---

## Troubleshooting

```bash
# Test RTSP stream manually
ffmpeg -rtsp_transport tcp -use_wallclock_as_timestamps 1 -fflags +genpts -i "rtsp://user:pass@host:port/path" -t 10 -c copy -y test.mkv

# Test rclone sync
rclone ls cam:camera/

# Check container health
docker compose logs --tail=50

# Force manual record+sync cycle
docker compose exec recorder /app/record.sh
```
