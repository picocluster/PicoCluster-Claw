#!/usr/bin/env bash
# Reconfigure PicoClaw network settings across all config files in one shot.
# Run on the RPi5 (claw) as root after changing IPs or hostnames.
#
# Usage:
#   sudo bash scripts/network-config.sh [OPTIONS]
#
# Options:
#   --claw-ip   <ip>     RPi5 IP address       (default: current value in .env)
#   --crush-ip  <ip>     Orin IP address       (default: current value in .env)
#   --gateway   <ip>     Gateway IP            (default: current value in .env)
#   --domain    <suffix> mDNS domain suffix    (default: local)
#   --dry-run            Show changes without applying
#
# Example:
#   sudo bash scripts/network-config.sh --claw-ip 192.168.1.50 --crush-ip 192.168.1.51

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ANSIBLE_DIR="/home/picocluster/picocluster-claw/ansible"
ENV_FILE="$REPO_DIR/.env"
AVAHI_HOSTS="/etc/avahi/hosts"

DRY_RUN=false

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
CLAW_IP=""
CRUSH_IP=""
GATEWAY=""
DOMAIN="local"

while [[ $# -gt 0 ]]; do
    case $1 in
        --claw-ip)   CLAW_IP="$2";   shift 2 ;;
        --crush-ip)  CRUSH_IP="$2";  shift 2 ;;
        --gateway)   GATEWAY="$2";   shift 2 ;;
        --domain)    DOMAIN="$2";    shift 2 ;;
        --dry-run)   DRY_RUN=true;   shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Read current values from .env as defaults
# ---------------------------------------------------------------------------
current_crush_ip() { grep '^CRUSH_IP=' "$ENV_FILE" | cut -d= -f2; }

[ -z "$CRUSH_IP" ] && CRUSH_IP="$(current_crush_ip)"

log() { echo "  [net] $*"; }
apply() {
    if $DRY_RUN; then
        echo "  [dry-run] $*"
    else
        eval "$*"
    fi
}

echo "=== PicoClaw Network Config ==="
echo "  claw.local   = ${CLAW_IP:-(unchanged)}"
echo "  crush.local  = $CRUSH_IP"
echo "  gateway      = ${GATEWAY:-(unchanged)}"
echo "  domain       = $DOMAIN"
$DRY_RUN && echo "  (dry-run — no changes applied)"
echo ""

# ---------------------------------------------------------------------------
# 1. Update .env (CRUSH_IP)
# ---------------------------------------------------------------------------
log "Updating $ENV_FILE ..."
apply "sed -i 's|^CRUSH_IP=.*|CRUSH_IP=${CRUSH_IP}|' \"$ENV_FILE\""

# ---------------------------------------------------------------------------
# 2. Update /etc/avahi/hosts (threadweaver.local alias)
# ---------------------------------------------------------------------------
if [ -n "$CLAW_IP" ]; then
    log "Updating $AVAHI_HOSTS ..."
    apply "cat > \"$AVAHI_HOSTS\" <<'EOF'
# PicoClaw mDNS aliases — managed by network-config.sh
${CLAW_IP}  threadweaver.${DOMAIN}
EOF"
    apply "systemctl restart avahi-daemon"
fi

# ---------------------------------------------------------------------------
# 3. Update Ansible inventory (if present)
# ---------------------------------------------------------------------------
INVENTORY="$ANSIBLE_DIR/inventory/cluster.yml"
if [ -f "$INVENTORY" ]; then
    log "Updating Ansible inventory $INVENTORY ..."
    if [ -n "$CLAW_IP" ]; then
        apply "sed -i 's|ansible_host: [0-9.]*  # claw|ansible_host: ${CLAW_IP}  # claw|' \"$INVENTORY\""
        # Fallback: plain ansible_host line for claw block
        apply "sed -i '/claw:/,/crush:/{s|ansible_host: [0-9.]*|ansible_host: ${CLAW_IP}|}' \"$INVENTORY\""
    fi
    if [ -n "$CRUSH_IP" ]; then
        apply "sed -i '/crush:/,\$/{s|ansible_host: [0-9.]*|ansible_host: ${CRUSH_IP}|}' \"$INVENTORY\""
    fi
fi

# ---------------------------------------------------------------------------
# 4. Restart Docker services to pick up new .env
# ---------------------------------------------------------------------------
log "Restarting Docker services ..."
apply "cd \"$REPO_DIR\" && docker compose up -d"

echo ""
echo "Done. Services restarted with new network settings."
if [ -n "$CLAW_IP" ]; then
    echo "CA cert available at: http://claw.${DOMAIN}/ca.crt"
fi
