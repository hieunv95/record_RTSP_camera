# record_RTSP_camera

Record RTSP camera streams and sync to cloud storage (Google Drive, OneDrive, Dropbox) via rclone.  
Optimized for **Armbian Bookworm / Debian 12** on ARM64 boards with limited resources (2GB RAM, 10GB disk).

## Features

- Hourly RTSP recording with ffmpeg (copy mode, no re-encoding)
- Single-camera and multi-camera support
- Automatic cloud sync every 2 hours via rclone
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
nano .env  # Set RTSP_URL and other settings
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
nano .env  # Set RTSP_URL and other settings
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
- Setup cron jobs (record hourly, sync every 2h)

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
| `RTSP_URL` | *(optional)* | Single-camera RTSP URL: `rtsp://user:pass@host:port/path` |
| `CAMERAS` | *(optional)* | Multi-camera list: `front=rtsp://...;back=rtsp://...` (takes precedence over `RTSP_URL`) |
| `RECORD_DIR` | `/data/camera` | Recording storage directory |
| `RECORD_DURATION` | `3580` | Seconds per recording segment (~1h) |
| `RCLONE_REMOTE` | `cam` | Rclone remote name |
| `RCLONE_PATH` | `camera` | Cloud folder path |
| `SYNC_INTERVAL_HOURS` | `2` | Hours between sync runs |
| `DELETE_AFTER_SYNC` | `true` | Delete local files after successful sync |
| `DISK_USAGE_THRESHOLD` | `80` | Force cleanup at N% disk usage (0=disable) |
| `TZ` | `Asia/Ho_Chi_Minh` | Timezone |

Set either `RTSP_URL` (single camera) or `CAMERAS` (multiple cameras).

### Multi-camera folder layout

- Single-camera (`RTSP_URL`): `RECORD_DIR/DD-MM-YYYY/*.mp4` (legacy layout)
- Multi-camera (`CAMERAS`): `RECORD_DIR/<camera-name>/DD-MM-YYYY/*.mp4`

Cloud sync preserves the same relative structure under `RCLONE_PATH`.

### Migrate legacy single-camera folders

If you switch from `RTSP_URL` to `CAMERAS`, migrate old folders once:

```bash
# Dry run (recommended first)
DRY_RUN=true ./record/migrate_legacy_layout.sh front

# Apply migration to camera name "front"
./record/migrate_legacy_layout.sh front
```

- Argument is target camera name (default: `camera`)
- Script moves `RECORD_DIR/DD-MM-YYYY/*` to `RECORD_DIR/<camera>/DD-MM-YYYY/*`
- Existing files in destination are never overwritten

---

## Storage Estimates

| Camera Bitrate | Per Hour | Per Day (24h) | 10GB Disk Holds |
|---------------|----------|---------------|-----------------|
| 2 Mbps | ~900 MB | ~21 GB | ~11 hours |
| 4 Mbps | ~1.8 GB | ~43 GB | ~5 hours |
| 8 Mbps | ~3.6 GB | ~86 GB | ~2 hours |

With `SYNC_INTERVAL_HOURS=2`, only ~2 hours of footage stays on disk at a time.

---

## Troubleshooting

```bash
# Test RTSP stream manually
ffmpeg -i "rtsp://user:pass@host:port/path" -t 10 -y test.mp4

# Test rclone sync
rclone ls cam:camera/

# Check container health
docker compose logs --tail=50

# Force manual sync
docker compose exec recorder /app/rclone.sh
```
