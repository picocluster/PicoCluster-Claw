#!/bin/bash
# shutdown-picocluster-claw.sh — Cleanly shut down the PicoCluster Claw cluster
# Usage: sudo bash shutdown-picocluster-claw.sh          # Shutdown both nodes
#        sudo bash shutdown-picocluster-claw.sh picocluster-claw  # Shutdown picocluster-claw only
#        sudo bash shutdown-picocluster-claw.sh picocrush # Shutdown picocrush only
set -euo pipefail

NODE="${1:-all}"
CRUSH_IP="${CRUSH_IP:-10.1.10.221}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

shutdown_picocluster-claw() {
  log "Stopping Docker containers..."
  docker compose -f /opt/picocluster-claw/docker-compose.yml down 2>/dev/null || true
  log "Stopping LED daemon..."
  systemctl stop picocluster-claw-leds 2>/dev/null || true
  log "Shutting down picocluster-claw..."
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
    log "=== Shutting down PicoCluster Claw cluster ==="
    shutdown_picocrush
    sleep 2
    shutdown_picocluster-claw
    ;;
  picocluster-claw)
    log "=== Shutting down picocluster-claw ==="
    shutdown_picocluster-claw
    ;;
  picocrush)
    log "=== Shutting down picocrush ==="
    shutdown_picocrush
    ;;
  *)
    echo "Usage: $0 [all|picocluster-claw|picocrush]"
    exit 1
    ;;
esac
