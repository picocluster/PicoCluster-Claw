#!/bin/bash
# update-picocrush.sh — Update PicoCluster Claw software on Orin Nano
# Usage: sudo bash update-picocrush.sh [component]
#        sudo bash update-picocrush.sh             # Update Ollama + pull models
#        sudo bash update-picocrush.sh ollama       # Update Ollama only
#        sudo bash update-picocrush.sh models       # Pull any missing default models
#        sudo bash update-picocrush.sh pull <model> # Pull a specific model
set -euo pipefail

if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 1
fi

COMPONENT="${1:-all}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

DEFAULT_MODELS=("llama3.2:3b" "llama3.1:8b" "phi3.5:3.8b" "qwen2.5:3b" "gemma3:4b" "deepseek-r1:7b" "starcoder2:3b" "llava:7b" "moondream:1.8b")

update_ollama() {
  log "Updating Ollama..."
  curl -fsSL https://ollama.ai/install.sh | sh
  systemctl restart ollama
  sleep 3
  log "Ollama $(ollama --version 2>/dev/null)"
}

update_models() {
  log "Pulling default models..."
  for model in "${DEFAULT_MODELS[@]}"; do
    log "  $model..."
    ollama pull "$model" 2>&1 | tail -1
  done
}

case "$COMPONENT" in
  all)
    update_ollama
    update_models
    ;;
  ollama)
    update_ollama
    ;;
  models)
    update_models
    ;;
  pull)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: $0 pull <model>"
      echo "Example: $0 pull gemma2:2b"
      exit 1
    fi
    ollama pull "$2"
    ;;
  *)
    echo "Usage: $0 [all|ollama|models|pull <model>]"
    exit 1
    ;;
esac

log ""
log "=== Status ==="
log "  Ollama: $(systemctl is-active ollama)"
log "  Models:"
ollama list 2>&1 | sed 's/^/    /'
