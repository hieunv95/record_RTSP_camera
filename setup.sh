#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Setup script for RTSP Camera Recorder
# Target OS: Debian 12 (Bookworm) / Armbian Bookworm ARM64
# =============================================================================

INSTALL_DIR="/opt/record"
DATA_DIR="$INSTALL_DIR/camera"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== RTSP Camera Recorder - Setup ==="
echo "Target: Debian 12 / Armbian Bookworm"
echo "Install dir: $INSTALL_DIR"
echo ""

# Check root/sudo
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run with sudo or as root." >&2
    exit 1
fi

# --- Install packages ---
echo "[1/6] Installing packages..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    ffmpeg \
    rclone \
    cron \
    ca-certificates

# --- Configure timezone ---
echo "[2/6] Configuring timezone..."
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    TZ=$(grep -E '^TZ=' "$SCRIPT_DIR/.env" | cut -d= -f2 | tr -d '"' || echo "Asia/Ho_Chi_Minh")
else
    TZ="Asia/Ho_Chi_Minh"
fi
if command -v timedatectl &>/dev/null; then
    timedatectl set-timezone "$TZ"
else
    ln -f -s "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
fi
echo "  Timezone: $TZ"

# --- Ensure NTP sync ---
echo "[3/6] Enabling time synchronization..."
if command -v timedatectl &>/dev/null; then
    timedatectl set-ntp true 2>/dev/null || true
fi

# --- Create directory structure ---
echo "[4/6] Creating directory structure..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR"

# --- Copy scripts ---
echo "[5/6] Installing scripts..."
cp "$SCRIPT_DIR/record/env_loader.sh" "$INSTALL_DIR/env_loader.sh"
cp "$SCRIPT_DIR/record/record.sh" "$INSTALL_DIR/record.sh"
cp "$SCRIPT_DIR/record/cleanup_old_folders.sh" "$INSTALL_DIR/cleanup_old_folders.sh"
chmod 755 "$INSTALL_DIR/env_loader.sh"
chmod 755 "$INSTALL_DIR/record.sh"
chmod 755 "$INSTALL_DIR/cleanup_old_folders.sh"

# Copy .env if it exists and not already installed
if [[ -f "$SCRIPT_DIR/.env" && ! -f "$INSTALL_DIR/.env" ]]; then
    cp "$SCRIPT_DIR/.env" "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    echo "  .env copied to $INSTALL_DIR/.env"
elif [[ ! -f "$INSTALL_DIR/.env" ]]; then
    echo "  WARNING: No .env file found. Copy .env.example to .env and configure it:"
    echo "  cp $SCRIPT_DIR/.env.example $INSTALL_DIR/.env"
fi

# --- Setup cron jobs ---
echo "[6/6] Setting up cron jobs..."
CRON_FILE="/etc/cron.d/record-camera"
cat > "$CRON_FILE" <<EOF
# RTSP Camera Recorder - Cron Jobs
SHELL=/bin/bash
ENV_FILE=$INSTALL_DIR/.env

# Record every 5 minutes (record.sh performs upload and local cleanup)
*/5 * * * * root ENV_FILE=$INSTALL_DIR/.env $INSTALL_DIR/record.sh >> /var/log/record-camera.log 2>&1

# Remove date folders older than today at 00:00 daily
0 0 * * * root ENV_FILE=$INSTALL_DIR/.env $INSTALL_DIR/cleanup_old_folders.sh >> /var/log/record-camera.log 2>&1
EOF
chmod 644 "$CRON_FILE"

# Ensure cron is running
systemctl enable cron 2>/dev/null || true
systemctl start cron 2>/dev/null || true

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Configure your .env:  sudo nano $INSTALL_DIR/.env"
echo "  2. Setup rclone remote:  rclone config"
echo "     (Create a remote named 'cam' or update RCLONE_REMOTE in .env)"
echo "  3. Test recording+sync:  ENV_FILE=$INSTALL_DIR/.env $INSTALL_DIR/record.sh"
echo "  4. Check logs:           tail -f /var/log/record-camera.log"
echo ""
