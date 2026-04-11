#!/bin/bash
# install-mac.sh — Install PicoCluster Claw on Apple Silicon Mac
# Runs the same Docker stack as the cluster variant, with Ollama native (Metal GPU).
#
# Usage: bash install-mac.sh [model]
#   model: default Ollama model (default: llama3.2:3b)
set -euo pipefail

DEFAULT_MODEL="${1:-llama3.2:3b}"
INSTALL_DIR="${HOME}/picocluster-claw"
OPENCLAW_TOKEN="picocluster-token"

# Models to pull (same set as the cluster, minus duplicates the user can add later)
MODELS=(
  "llama3.2:3b"
  "llama3.1:8b"
  "gemma3:4b"
  "deepseek-r1:7b"
  "qwen2.5:3b"
)

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== PicoCluster Claw — Mac Solo Install ==="
log "  Model: ${DEFAULT_MODEL}"
log "  Install dir: ${INSTALL_DIR}"
log ""

# ============================================================
# 1. Prerequisites
# ============================================================
log "--- Step 1/6: Prerequisites ---"

# Apple Silicon check
if [[ "$(uname -m)" != "arm64" ]]; then
  log "ERROR: This installer requires Apple Silicon (arm64). Detected: $(uname -m)"
  exit 1
fi
log "  Apple Silicon: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'arm64')"

# Homebrew
if ! command -v brew &>/dev/null; then
  log "  Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  log "  Homebrew: $(brew --version | head -1)"
fi

# Docker Desktop
if ! command -v docker &>/dev/null; then
  log "  Installing Docker Desktop..."
  brew install --cask docker
  log "  >>> Please open Docker Desktop from Applications and complete setup <<<"
  log "  >>> Then re-run this script <<<"
  exit 1
fi
if ! docker info &>/dev/null 2>&1; then
  log "  ERROR: Docker Desktop is installed but not running."
  log "  >>> Open Docker Desktop from Applications, wait for it to start, then re-run <<<"
  exit 1
fi
log "  Docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"

# Ollama
if ! command -v ollama &>/dev/null; then
  log "  Installing Ollama..."
  brew install ollama
fi
log "  Ollama: $(ollama --version 2>/dev/null || echo 'installed')"

# ============================================================
# 2. Ollama setup
# ============================================================
log "--- Step 2/6: Ollama ---"

# Start Ollama if not running
if ! curl -sf --max-time 2 http://localhost:11434/api/tags &>/dev/null; then
  log "  Starting Ollama..."
  brew services start ollama 2>/dev/null || true
  for i in $(seq 1 30); do
    if curl -sf --max-time 2 http://localhost:11434/api/tags &>/dev/null; then
      log "  Ollama ready (attempt $i)"
      break
    fi
    if [ "$i" -eq 30 ]; then
      log "  ERROR: Ollama failed to start after 30 attempts"
      exit 1
    fi
    sleep 2
  done
else
  log "  Ollama already running"
fi

# ============================================================
# 3. Pull models
# ============================================================
log "--- Step 3/6: Pull models ---"
for model in "${MODELS[@]}"; do
  log "  Pulling $model..."
  ollama pull "$model" 2>&1 | tail -1
done

log "  Installed models:"
ollama list 2>&1 | tail -n +2 | awk '{printf "    %s (%s)\n", $1, $3$4}'

# ============================================================
# 4. Clone repo + Docker
# ============================================================
log "--- Step 4/6: PicoCluster Claw repo + Docker ---"

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/picocluster/PicoCluster-Claw.git "$INSTALL_DIR"
  log "  Repo cloned"
else
  cd "$INSTALL_DIR" && git pull --ff-only 2>&1 | tail -3
  log "  Repo updated"
fi

# Write .env
cat > "$INSTALL_DIR/.env" <<ENV
CRUSH_IP=127.0.0.1
DEFAULT_MODEL=${DEFAULT_MODEL}
OPENCLAW_TOKEN=${OPENCLAW_TOKEN}
ENV

cd "$INSTALL_DIR"
log "  Building containers..."
docker compose -f docker-compose.yml -f docker-compose.mac.yml build 2>&1 | tail -5
log "  Starting containers..."
docker compose -f docker-compose.yml -f docker-compose.mac.yml up -d 2>&1 | tail -10

# Wait for ThreadWeaver health
log "  Waiting for services..."
for i in $(seq 1 30); do
  if curl -sf --max-time 2 http://127.0.0.1:8000/api/settings &>/dev/null; then
    log "  ThreadWeaver ready"
    break
  fi
  sleep 3
done

# ============================================================
# 5. User scripts
# ============================================================
log "--- Step 5/6: User scripts ---"
USER_BIN="${HOME}/bin"
mkdir -p "$USER_BIN"

if [[ -d "$INSTALL_DIR/scripts/user-bin/mac" ]]; then
  cp "$INSTALL_DIR/scripts/user-bin/mac/"* "$USER_BIN/" 2>/dev/null
  chmod +x "$USER_BIN/"*
  log "  Installed Mac scripts: $(ls "$USER_BIN"/pc-* 2>/dev/null | xargs -I{} basename {} | tr '\n' ' ')"
else
  # Fall back to clusterclaw scripts (they mostly work)
  cp "$INSTALL_DIR/scripts/user-bin/clusterclaw/"* "$USER_BIN/" 2>/dev/null
  chmod +x "$USER_BIN/"*
  log "  Installed scripts (cluster variant): $(ls "$USER_BIN"/pc-* 2>/dev/null | xargs -I{} basename {} | tr '\n' ' ')"
fi

# Ensure ~/bin is in PATH
SHELL_RC="${HOME}/.zshrc"
if ! grep -q 'HOME/bin' "$SHELL_RC" 2>/dev/null; then
  cat >> "$SHELL_RC" <<'ZSHRC'

# PicoCluster Claw user scripts
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi
ZSHRC
  log "  Added ~/bin to PATH in .zshrc"
fi

# ============================================================
# 6. Verify
# ============================================================
log "--- Step 6/6: Verify ---"

log "  Docker containers:"
docker ps --format '    {{.Names}}: {{.Status}}'

log ""
TW_OK=$(curl -sf --max-time 5 http://127.0.0.1:8000/api/settings >/dev/null 2>&1 && echo "OK" || echo "FAIL")
OC_OK=$(curl -sf --max-time 5 http://127.0.0.1:18789/__openclaw__/health >/dev/null 2>&1 && echo "OK" || echo "FAIL")
OL_OK=$(curl -sf --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1 && echo "OK" || echo "FAIL")
PT_OK=$(curl -sf --max-time 5 http://localhost:80/ >/dev/null 2>&1 && echo "OK" || echo "FAIL")

log "  ThreadWeaver: ${TW_OK}"
log "  OpenClaw:     ${OC_OK}"
log "  Ollama:       ${OL_OK}"
log "  Portal:       ${PT_OK}"

TOOLS=$(curl -sf http://127.0.0.1:8000/api/tools 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
log "  MCP Tools:    ${TOOLS}"

log ""
log "============================================"
log "  PicoCluster Claw — Mac Solo Install Complete"
log "============================================"
log ""
log "  ThreadWeaver:  http://localhost:5173"
log "  OpenClaw:      http://localhost:18789"
log "  Portal:        http://localhost/"
log "  Ollama:        http://localhost:11434"
log ""
log "  HTTPS (via Caddy, self-signed cert):"
log "    ThreadWeaver:  https://localhost:5174"
log "    OpenClaw:      https://localhost:18790"
log ""
log "  Docker commands:"
log "    cd ${INSTALL_DIR}"
log "    docker compose -f docker-compose.yml -f docker-compose.mac.yml [up -d|down|logs|ps]"
log ""
log "  Manage models:"
log "    ollama list              # Show installed models"
log "    ollama pull <model>      # Download a model"
log "    ollama rm <model>        # Remove a model"
log "============================================"
