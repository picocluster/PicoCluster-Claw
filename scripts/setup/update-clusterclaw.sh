#!/bin/bash
# update-clusterclaw.sh — Update PicoCluster Claw on RPi5
# Usage: sudo bash update-clusterclaw.sh [component]
#        sudo bash update-clusterclaw.sh           # Update all
#        sudo bash update-clusterclaw.sh openclaw   # Update OpenClaw only
#        sudo bash update-clusterclaw.sh threadweaver
set -euo pipefail

if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 1
fi

COMPONENT="${1:-all}"
INSTALL_DIR="/opt/clusterclaw"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

cd "$INSTALL_DIR"

case "$COMPONENT" in
  all)
    log "Updating PicoCluster Claw repo..."
    git pull --ff-only 2>&1 | tail -3
    log "Rebuilding all containers..."
    docker compose build --pull 2>&1 | tail -10
    docker compose up -d
    systemctl restart clusterclaw-leds 2>/dev/null || true
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
    cp leds/apa102.py leds/clusterclaw_status.py /opt/clusterclaw/leds/ 2>/dev/null
    systemctl restart clusterclaw-leds
    ;;
  *)
    echo "Usage: $0 [all|openclaw|threadweaver|leds]"
    exit 1
    ;;
esac

log ""
log "=== Status ==="
docker compose ps 2>/dev/null
log "  Blinkt LEDs: $(systemctl is-active clusterclaw-leds 2>/dev/null || echo 'n/a')"
