#!/bin/bash
# update-picoclaw.sh — Update PicoClaw on RPi5
# Usage: sudo bash update-picoclaw.sh [component]
#        sudo bash update-picoclaw.sh           # Update all
#        sudo bash update-picoclaw.sh openclaw   # Update OpenClaw only
#        sudo bash update-picoclaw.sh threadweaver
set -euo pipefail

if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 1
fi

COMPONENT="${1:-all}"
INSTALL_DIR="/opt/picoclcaw"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

cd "$INSTALL_DIR"

case "$COMPONENT" in
  all)
    log "Updating PicoClaw repo..."
    git pull --ff-only 2>&1 | tail -3
    log "Rebuilding all containers..."
    docker compose build --pull 2>&1 | tail -10
    docker compose up -d
    systemctl restart picoclaw-leds 2>/dev/null || true
    ;;
  openclaw)
    log "Rebuilding OpenClaw container..."
    docker compose build --pull --no-cache openclaw
    docker compose up -d openclaw
    ;;
  threadweaver)
    log "Rebuilding ThreadWeaver container..."
    docker compose build --pull --no-cache threadweaver
    docker compose up -d threadweaver
    ;;
  leds)
    git pull --ff-only 2>&1 | tail -3
    cp leds/apa102.py leds/picoclaw_status.py /opt/picoclcaw/leds/ 2>/dev/null
    systemctl restart picoclaw-leds
    ;;
  *)
    echo "Usage: $0 [all|openclaw|threadweaver|leds]"
    exit 1
    ;;
esac

log ""
log "=== Status ==="
docker compose ps 2>/dev/null
log "  Blinkt LEDs: $(systemctl is-active picoclaw-leds 2>/dev/null || echo 'n/a')"
