#!/bin/bash
# install-clustercrush.sh — Install Ollama + models on Orin Nano
# Run on a golden image (after build-orin-image.sh + configure-pair.sh)
#
# Installs: Ollama (CUDA), pulls default model set
# Configures: systemd service, firewall, MAXN power mode
#
# Usage: sudo bash install-clustercrush.sh [clusterclaw-ip]
set -euo pipefail

CLAW_IP="${1:-10.1.10.220}"
OLLAMA_PORT="11434"
USER="picocluster"
INSTALL_DIR="/opt/clusterclaw"

# Models to pull (first one is the default)
MODELS=(
  "llama3.2:3b"
  "llama3.1:8b"
  "phi3.5:3.8b"
  "qwen2.5:3b"
  "gemma3:4b"
  "deepseek-r1:7b"
  "starcoder2:3b"
  "llava:7b"
  "moondream:1.8b"
)

if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 1
fi

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ============================================================
log "=== PicoCrush Install (clustercrush / Orin Nano) ==="
log "  Allow inference from: ${CLAW_IP}"
log "  Models: ${MODELS[*]}"
log ""

# ============================================================
# Set hostname (so golden images don't need it baked in)
# ============================================================
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" != "clustercrush" ]]; then
  log "--- Setting hostname: ${CURRENT_HOSTNAME} → clustercrush ---"
  hostnamectl set-hostname clustercrush
  sed -i "s/127\.0\.1\.1.*/127.0.1.1\tclustercrush/" /etc/hosts
  if ! grep -q "clustercrush" /etc/hosts; then
    cat >> /etc/hosts <<HOSTS

# BEGIN PICOCLUSTER CLAW
10.1.10.220  clusterclaw
10.1.10.221  clustercrush
# END PICOCLUSTER CLAW
HOSTS
  fi
  log "  Hostname set to clustercrush"
else
  log "Hostname already set: clustercrush"
fi

# ============================================================
# 0. Resize filesystem if needed
# ============================================================
DISK="/dev/mmcblk0"
PARTNUM=1
PARTDEV="${DISK}p${PARTNUM}"
DISK_SIZE=$(lsblk -b -n -o SIZE "$DISK" 2>/dev/null | head -1)
PART_SIZE=$(lsblk -b -n -o SIZE "$PARTDEV" 2>/dev/null | head -1)

if [[ -n "$DISK_SIZE" && -n "$PART_SIZE" ]]; then
  THRESHOLD=$(( DISK_SIZE * 90 / 100 ))
  if (( PART_SIZE < THRESHOLD )); then
    log "--- Step 0: Resizing filesystem ---"
    if command -v sgdisk &>/dev/null; then
      START_SECTOR=$(sgdisk -i "$PARTNUM" "$DISK" | grep 'First sector:' | awk '{print $3}')
      sgdisk -e "$DISK"
      sgdisk -d "$PARTNUM" -n "${PARTNUM}:${START_SECTOR}:0" -c "${PARTNUM}:APP" -t "${PARTNUM}:8300" "$DISK"
      partprobe "$DISK"
      resize2fs "$PARTDEV"
      log "Filesystem resized: $(df -h / | awk 'NR==2 {print $2}')"
    else
      log "WARNING: sgdisk not found — run resize_ubuntu.sh manually"
    fi
  else
    log "Filesystem already sized correctly: $(df -h / | awk 'NR==2 {print $2}')"
  fi
fi

# ============================================================
# Cleanup: Remove legacy leftover files
# ============================================================
log "--- Cleanup: Removing legacy files ---"
LEGACY_FILES=(
  "/home/${USER}/genKeys.sh"
  "/home/${USER}/resizeAllNodes.sh"
  "/home/${USER}/resize_ubuntu.sh"
  "/home/${USER}/restartAllNodes.sh"
  "/home/${USER}/stopAllNodes.sh"
  "/home/${USER}/testAllNodes.sh"
  "/home/${USER}/build-orin-image.sh"
  "/home/${USER}/install-clustercrush.sh"
)
for f in "${LEGACY_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    rm -f "$f"
    log "  Removed $f"
  fi
done
if [[ -d "/home/${USER}/.ansible" ]]; then
  rm -rf "/home/${USER}/.ansible"
  log "  Removed .ansible/"
fi

# ============================================================
# Clone PicoCluster Claw repo (for user-bin scripts + update scripts)
# ============================================================
log "--- PicoCluster Claw repo ---"
if ! command -v git &>/dev/null; then
  apt install -y git 2>/dev/null | tail -1
fi
if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/picocluster/PicoCluster-Claw.git "$INSTALL_DIR"
  log "PicoCluster Claw repo cloned"
else
  cd "$INSTALL_DIR" && git pull --ff-only 2>&1 | tail -3
  log "PicoCluster Claw repo updated"
fi

# ============================================================
# 1. Verify CUDA
# ============================================================
log "--- Step 1/6: Verify CUDA ---"
if ! nvidia-smi &>/dev/null; then
  log "ERROR: nvidia-smi failed. CUDA not available."
  exit 1
fi
log "CUDA OK: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null)"

# ============================================================
# 2. Install Ollama
# ============================================================
log "--- Step 2/6: Install Ollama ---"
# Ollama installer requires zstd for extraction
apt install -y zstd 2>/dev/null | tail -1

if ! command -v ollama &>/dev/null; then
  curl -fsSL https://ollama.ai/install.sh | sh
  log "Ollama installed"
else
  log "Ollama already installed: $(ollama --version 2>/dev/null)"
fi

# Configure Ollama to listen on all interfaces.
# OLLAMA_KEEP_ALIVE=30m keeps models loaded in GPU memory for 30 minutes after
# the last request (default is 5m). This preserves the benefit of the startup
# prime so the first real user message is fast even if they take a few minutes
# to open the browser and set up the SSH tunnel.
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:${OLLAMA_PORT}"
Environment="OLLAMA_MODELS=/mnt/nvme/ollama/models"
Environment="OLLAMA_KEEP_ALIVE=30m"
EOF

# Create model storage on NVMe if available
if mountpoint -q /mnt/nvme 2>/dev/null; then
  mkdir -p /mnt/nvme/ollama/models
  chown -R ollama:ollama /mnt/nvme/ollama 2>/dev/null || chown -R "$USER:$USER" /mnt/nvme/ollama
  log "Model storage: /mnt/nvme/ollama/models"
else
  log "NVMe not mounted — models will use default location"
  sed -i '/OLLAMA_MODELS/d' /etc/systemd/system/ollama.service.d/override.conf
fi

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

# Wait for Ollama to be ready
log "Waiting for Ollama..."
for i in $(seq 1 30); do
  if curl -sf --max-time 2 http://127.0.0.1:${OLLAMA_PORT}/api/tags &>/dev/null; then
    log "Ollama is ready"
    break
  fi
  sleep 2
done

# ============================================================
# 3. Pull models
# ============================================================
log "--- Step 3/6: Pull models ---"
for model in "${MODELS[@]}"; do
  log "  Pulling $model..."
  ollama pull "$model" 2>&1 | tail -1
done

log "Available models:"
ollama list 2>&1 | head -20

# ============================================================
# 4. Power mode
# ============================================================
log "--- Step 4/6: Power mode ---"
nvpmodel -m 2 2>/dev/null || true
jetson_clocks 2>/dev/null || true

if [[ ! -f /etc/systemd/system/jetson-maxperf.service ]]; then
  cat > /etc/systemd/system/jetson-maxperf.service <<EOF
[Unit]
Description=Set Jetson to MAXN power mode
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nvpmodel -m 2
ExecStartPost=/usr/bin/jetson_clocks
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable jetson-maxperf
fi
log "MAXN power mode set and persisted"

# ============================================================
# 5. Firewall
# ============================================================
log "--- Step 5/6: Firewall ---"
ufw allow from "${CLAW_IP}" to any port "${OLLAMA_PORT}" comment "Ollama from clusterclaw" 2>/dev/null || true
log "Firewall: port ${OLLAMA_PORT} open for ${CLAW_IP} only"

# ============================================================
# Install user management scripts
# ============================================================
log "--- Installing user management scripts ---"
USER_BIN="/home/${USER}/bin"
if [[ -d "$INSTALL_DIR/scripts/user-bin/clustercrush" ]]; then
  mkdir -p "$USER_BIN"
  cp "$INSTALL_DIR/scripts/user-bin/clustercrush/"* "$USER_BIN/"
  chmod +x "$USER_BIN/"*
  chown -R "${USER}:${USER}" "$USER_BIN"
  log "  Installed: $(ls "$USER_BIN" | tr '\n' ' ')"

  # Ensure ~/bin is in PATH for the picocluster user
  if ! grep -q "HOME/bin" "/home/${USER}/.bashrc" 2>/dev/null; then
    cat >> "/home/${USER}/.bashrc" <<'BASHRC'

# PicoCluster Claw user scripts
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi
BASHRC
  fi
else
  log "  WARNING: user-bin/clustercrush not found in repo — skipping"
fi

# ============================================================
# 6. Test
# ============================================================
log "--- Step 6/6: Test ---"

# Health check
if curl -sf --max-time 5 http://127.0.0.1:${OLLAMA_PORT}/api/tags | grep -q "models"; then
  log "Ollama health: OK"
else
  log "Ollama health: FAIL"
fi

# Inference test
log "Inference test..."
RESULT=$(curl -sf --max-time 60 http://127.0.0.1:${OLLAMA_PORT}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODELS[0]}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_tokens\":5}" 2>/dev/null)
if echo "$RESULT" | grep -q '"content"'; then
  log "Inference test: PASSED"
else
  log "Inference test: FAILED"
fi

# GPU info (Jetson uses unified memory — report RAM instead of separate VRAM)
GPU_MEM=$(free -h | awk '/^Mem:/ {printf "%s used / %s total (unified)", $3, $2}')
log "Memory: $GPU_MEM"

log ""
log "============================================"
log "  PicoCrush Install Complete"
log "============================================"
log ""
log "  Ollama: http://clustercrush:${OLLAMA_PORT}"
log "  OpenAI API: http://clustercrush:${OLLAMA_PORT}/v1"
log ""
log "  Manage models:"
log "    ollama list              # Show installed models"
log "    ollama pull <model>      # Download a model"
log "    ollama rm <model>        # Remove a model"
log "    ollama run <model>       # Interactive chat"
log ""
log "  Memory: ${GPU_MEM}"
log "============================================"
