#!/bin/bash
# update-linux.sh — Update PicoCluster Claw on Linux Solo
# Usage: bash update-linux.sh [--force]
set -euo pipefail

INSTALL_DIR="${HOME}/picocluster-claw"
FORCE="${1:-}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

cd "$INSTALL_DIR"

# Check versions
CURRENT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
LATEST=$(git ls-remote origin HEAD 2>/dev/null | cut -c1-7 || echo "unknown")

log "Current: $CURRENT"
log "Latest:  $LATEST"

if [[ "$CURRENT" == "$LATEST" && "$FORCE" != "--force" ]]; then
  log "Already up to date. Use --force to rebuild anyway."
  exit 0
fi

log "Updating..."

# Pull repo
git pull --ff-only 2>&1 | tail -5

# Update containers
log "Pulling ThreadWeaver image from GHCR..."
docker compose -f docker-compose.yml -f docker-compose.linux.yml pull threadweaver 2>&1 | tail -5
log "Rebuilding local containers..."
docker compose -f docker-compose.yml -f docker-compose.linux.yml build --pull openclaw portal 2>&1 | tail -10

# Restart
log "Restarting..."
docker compose -f docker-compose.yml -f docker-compose.linux.yml up -d threadweaver openclaw portal 2>&1 | tail -10

# Wait for health
log "Waiting for services..."
for i in $(seq 1 20); do
  if curl -sf --max-time 2 http://127.0.0.1:5173/ > /dev/null 2>&1; then
    log "ThreadWeaver ready"
    break
  fi
  sleep 3
done

# Update user scripts
if [[ -d "$INSTALL_DIR/scripts/user-bin/linux" ]]; then
  cp "$INSTALL_DIR/scripts/user-bin/linux/"* "${HOME}/bin/" 2>/dev/null
  chmod +x "${HOME}/bin/"*
  log "User scripts updated"
fi

# Report
NEW=$(git rev-parse --short HEAD 2>/dev/null)
log ""
log "=== Update complete ==="
log "  Version: $NEW"
log "  Status:  $(docker ps --format '{{.Names}}: {{.Status}}' | grep threadweaver)"
