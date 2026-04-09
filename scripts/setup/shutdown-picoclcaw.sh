#!/bin/bash
# shutdown-picoclcaw.sh — Cleanly shut down the PicoClaw cluster
# Usage: sudo bash shutdown-picoclcaw.sh          # Shutdown both nodes
#        sudo bash shutdown-picoclcaw.sh picoclaw  # Shutdown picoclaw only
#        sudo bash shutdown-picoclcaw.sh picocrush # Shutdown picocrush only
set -euo pipefail

NODE="${1:-all}"
CRUSH_IP="${CRUSH_IP:-10.1.10.221}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

shutdown_picoclaw() {
  log "Stopping Docker containers..."
  docker compose -f /opt/picoclcaw/docker-compose.yml down 2>/dev/null || true
  log "Stopping LED daemon..."
  systemctl stop picoclaw-leds 2>/dev/null || true
  log "Shutting down picoclaw..."
  shutdown -h now
}

shutdown_picocrush() {
  log "Shutting down picocrush ($CRUSH_IP)..."
  ssh -o ConnectTimeout=5 picocluster@"$CRUSH_IP" 'sudo shutdown -h now' 2>/dev/null || {
    log "WARNING: Could not SSH to picocrush. Try manually: ssh picocluster@picocrush 'sudo shutdown -h now'"
  }
}

case "$NODE" in
  all)
    log "=== Shutting down PicoClaw cluster ==="
    shutdown_picocrush
    sleep 2
    shutdown_picoclaw
    ;;
  picoclaw)
    log "=== Shutting down picoclaw ==="
    shutdown_picoclaw
    ;;
  picocrush)
    log "=== Shutting down picocrush ==="
    shutdown_picocrush
    ;;
  *)
    echo "Usage: $0 [all|picoclaw|picocrush]"
    exit 1
    ;;
esac
