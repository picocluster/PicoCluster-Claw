#!/bin/bash
# shutdown-clusterclaw.sh — Cleanly shut down the PicoCluster Claw cluster
# Usage: sudo bash shutdown-clusterclaw.sh          # Shutdown both nodes
#        sudo bash shutdown-clusterclaw.sh clusterclaw  # Shutdown clusterclaw only
#        sudo bash shutdown-clusterclaw.sh clustercrush # Shutdown clustercrush only
set -euo pipefail

NODE="${1:-all}"
CRUSH_IP="${CRUSH_IP:-10.1.10.221}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

shutdown_clusterclaw() {
  log "Stopping Docker containers..."
  docker compose -f /opt/clusterclaw/docker-compose.yml down 2>/dev/null || true
  log "Stopping LED daemon..."
  systemctl stop clusterclaw-leds 2>/dev/null || true
  log "Shutting down clusterclaw..."
  shutdown -h now
}

shutdown_clustercrush() {
  log "Shutting down clustercrush ($CRUSH_IP)..."
  ssh -o ConnectTimeout=5 picocluster@"$CRUSH_IP" 'sudo shutdown -h now' 2>/dev/null || {
    log "WARNING: Could not SSH to clustercrush. Try manually: ssh picocluster@clustercrush 'sudo shutdown -h now'"
  }
}

case "$NODE" in
  all)
    log "=== Shutting down PicoCluster Claw cluster ==="
    shutdown_clustercrush
    sleep 2
    shutdown_clusterclaw
    ;;
  clusterclaw)
    log "=== Shutting down clusterclaw ==="
    shutdown_clusterclaw
    ;;
  clustercrush)
    log "=== Shutting down clustercrush ==="
    shutdown_clustercrush
    ;;
  *)
    echo "Usage: $0 [all|clusterclaw|clustercrush]"
    exit 1
    ;;
esac
