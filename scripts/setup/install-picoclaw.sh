#!/bin/bash
# install-picoclaw.sh — Install full PicoClaw stack on RPi5
# Run on a golden image (after build-rpi5-image.sh + configure-pair.sh)
#
# Installs: Node.js, OpenClaw, ThreadWeaver, Blinkt! LEDs
# Configures: systemd services, firewall, LLM endpoint
#
# Usage: sudo bash install-picoclaw.sh [picocrush-ip]
set -euo pipefail

CRUSH_IP="${1:-10.1.10.221}"
LLAMA_PORT="8080"
DEFAULT_MODEL="Llama-3.2-3B-Instruct-Q4_K_M.gguf"
OPENCLAW_TOKEN="picocluster-token"
TW_DIR="/opt/picoclcaw/threadweaver"
LED_DIR="/opt/picoclcaw/leds"
USER="picocluster"

if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 1
fi

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ============================================================
log "=== PicoClaw Install (picoclaw / RPi5) ==="
log "  LLM endpoint: http://${CRUSH_IP}:${LLAMA_PORT}/v1"
log "  Model: ${DEFAULT_MODEL}"
log ""

BEFORE_DISK=$(df -h / | awk 'NR==2 {print $3}')

# ============================================================
# 1. Node.js
# ============================================================
log "--- Step 1/7: Node.js ---"
if ! command -v node &>/dev/null || [[ "$(node -v | tr -d 'v' | cut -d. -f1)" -lt 22 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt install -y nodejs
  log "Node.js $(node -v) installed"
else
  log "Node.js $(node -v) already installed"
fi

# ============================================================
# 2. OpenClaw
# ============================================================
log "--- Step 2/7: OpenClaw ---"
if ! command -v openclaw &>/dev/null; then
  npm install -g openclaw
  log "OpenClaw $(openclaw --version) installed"
else
  log "OpenClaw $(openclaw --version) already installed"
fi

# OpenClaw config
mkdir -p "/home/${USER}/.openclaw"
cat > "/home/${USER}/.openclaw/openclaw.json" <<EOF
{
  "gateway": {
    "mode": "local",
    "auth": {
      "token": "${OPENCLAW_TOKEN}"
    },
    "bind": "0.0.0.0"
  },
  "models": {
    "providers": {
      "local": {
        "baseUrl": "http://${CRUSH_IP}:${LLAMA_PORT}/v1",
        "apiKey": "none",
        "models": [
          {
            "id": "${DEFAULT_MODEL}",
            "name": "Llama 3.2 3B"
          }
        ]
      }
    }
  }
}
EOF
chmod 600 "/home/${USER}/.openclaw/openclaw.json"
chown -R "${USER}:${USER}" "/home/${USER}/.openclaw"
log "OpenClaw configured (gateway on 0.0.0.0:18789, token auth)"

# OpenClaw systemd service
cat > /etc/systemd/system/openclaw.service <<EOF
[Unit]
Description=OpenClaw Gateway
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${USER}
Environment=HOME=/home/${USER}
ExecStart=/usr/bin/openclaw gateway --port 18789
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# ============================================================
# 3. ThreadWeaver
# ============================================================
log "--- Step 3/7: ThreadWeaver ---"
if [[ ! -d "$TW_DIR/.git" ]]; then
  mkdir -p "$TW_DIR"
  git clone --depth 1 https://github.com/nosqltips/ThreadWeaver.git "$TW_DIR"
  log "ThreadWeaver cloned"
else
  log "ThreadWeaver already installed"
fi

# Backend
cd "$TW_DIR/backend"
if [[ ! -d "$TW_DIR/venv" ]]; then
  python3 -m venv "$TW_DIR/venv"
  "$TW_DIR/venv/bin/pip" install --no-cache-dir -r requirements.txt 2>&1 | tail -3
  log "Backend dependencies installed"
fi

cat > "$TW_DIR/backend/.env" <<EOF
LLM_PROVIDER=local
LOCAL_BASE_URL=http://${CRUSH_IP}:${LLAMA_PORT}/v1
LOCAL_MODEL=${DEFAULT_MODEL}
EOF

# Frontend
cd "$TW_DIR/frontend"
if [[ ! -d "$TW_DIR/frontend/node_modules" ]]; then
  npm install 2>&1 | tail -3
  log "Frontend dependencies installed"
fi

# Patch API_BASE for LAN access
sed -i "s|const API_BASE = 'http://localhost:8000/api'|const API_BASE = '/api'|g" \
  "$TW_DIR/frontend/src/lib/api.ts" \
  "$TW_DIR/frontend/src/routes/+page.svelte" 2>/dev/null

# Patch vite config for LAN access + proxy
cat > "$TW_DIR/frontend/vite.config.js" <<'VITE'
import { sveltekit } from "@sveltejs/kit/vite";
import { defineConfig } from "vite";

export default defineConfig({
	plugins: [sveltekit()],
	server: {
		allowedHosts: true,
		proxy: {
			'/api': {
				target: 'http://127.0.0.1:8000',
				changeOrigin: true
			}
		}
	}
});
VITE

# Patch model discovery for llama-server (OpenAI-compatible /v1/models)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/../../threadweaver/patch-llama-server.py" ]]; then
  python3 "$SCRIPT_DIR/../../threadweaver/patch-llama-server.py" "$TW_DIR/backend/server.py"
elif [[ -f "/home/${USER}/threadweaver/patch-llama-server.py" ]]; then
  python3 "/home/${USER}/threadweaver/patch-llama-server.py" "$TW_DIR/backend/server.py"
else
  log "WARNING: patch-llama-server.py not found — model discovery may not work"
fi

chown -R "${USER}:${USER}" "$TW_DIR"

# ThreadWeaver systemd service
cat > /etc/systemd/system/threadweaver.service <<EOF
[Unit]
Description=ThreadWeaver Chat UI
After=network.target

[Service]
Type=forking
User=${USER}
WorkingDirectory=${TW_DIR}
ExecStart=/bin/bash -c '\
  cd ${TW_DIR}/backend && ${TW_DIR}/venv/bin/python server.py & \
  cd ${TW_DIR}/frontend && npx vite --host 0.0.0.0 --port 5173 &'
ExecStop=/bin/bash -c 'pkill -f "server.py" ; pkill -f "vite.*5173"'
Restart=always
RestartSec=5
Environment=HOME=/home/${USER}
EnvironmentFile=${TW_DIR}/backend/.env

[Install]
WantedBy=multi-user.target
EOF
log "ThreadWeaver configured"

# ============================================================
# 4. Blinkt! LEDs
# ============================================================
log "--- Step 4/7: Blinkt! LEDs ---"
apt install -y python3-gpiod 2>/dev/null || pip3 install --break-system-packages gpiod 2>/dev/null

mkdir -p "$LED_DIR"
# Copy LED files from repo if available
for f in apa102.py picoclaw_status.py picoclaw-leds.service; do
  for src in "$SCRIPT_DIR/../../leds/$f" "/home/${USER}/leds/$f"; do
    if [[ -f "$src" ]]; then
      cp "$src" "$LED_DIR/"
      break
    fi
  done
done
chmod 644 "$LED_DIR"/*.py 2>/dev/null

if [[ -f "$LED_DIR/picoclaw-leds.service" ]]; then
  cp "$LED_DIR/picoclaw-leds.service" /etc/systemd/system/
  log "Blinkt! LED daemon configured"
else
  log "WARNING: LED service file not found — skipping Blinkt!"
fi

# ============================================================
# 5. Firewall
# ============================================================
log "--- Step 5/7: Firewall ---"
ufw allow 18789/tcp comment "OpenClaw WebChat/Gateway" 2>/dev/null || true
ufw deny 18791/tcp comment "OpenClaw control" 2>/dev/null || true
ufw deny 18792/tcp comment "OpenClaw CDP relay" 2>/dev/null || true
ufw allow 5173/tcp comment "ThreadWeaver UI" 2>/dev/null || true
ufw allow 8000/tcp comment "ThreadWeaver API" 2>/dev/null || true
log "Firewall configured"

# ============================================================
# 6. Enable and start all services
# ============================================================
log "--- Step 6/7: Starting services ---"
systemctl daemon-reload
for svc in openclaw threadweaver picoclaw-leds; do
  if [[ -f "/etc/systemd/system/${svc}.service" ]]; then
    systemctl enable "$svc"
    systemctl start "$svc"
    log "  $svc: $(systemctl is-active $svc)"
  fi
done

# ============================================================
# 7. Smoke test
# ============================================================
log "--- Step 7/7: Smoke tests ---"
sleep 5

# OpenClaw
if openclaw health &>/dev/null; then
  log "  OpenClaw gateway: OK"
else
  log "  OpenClaw gateway: WAITING (may take a few seconds)"
fi

# ThreadWeaver
if curl -s --max-time 5 http://127.0.0.1:8000/api/settings &>/dev/null; then
  log "  ThreadWeaver backend: OK"
else
  log "  ThreadWeaver backend: WAITING"
fi

# llama-server on picocrush
if curl -s --max-time 5 "http://${CRUSH_IP}:${LLAMA_PORT}/health" &>/dev/null; then
  log "  llama-server (${CRUSH_IP}): OK"
else
  log "  llama-server (${CRUSH_IP}): NOT REACHABLE"
fi

AFTER_DISK=$(df -h / | awk 'NR==2 {print $3}')

log ""
log "============================================"
log "  PicoClaw Install Complete"
log "============================================"
log ""
log "  ThreadWeaver:  http://picoclaw:5173"
log "  OpenClaw:      http://picoclaw:18789  (token: ${OPENCLAW_TOKEN})"
log "  OpenClaw TUI:  openclaw tui"
log ""
log "  Disk: ${BEFORE_DISK} → ${AFTER_DISK}"
log "============================================"
