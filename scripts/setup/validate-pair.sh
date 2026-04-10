#!/bin/bash
# validate-pair.sh — End-to-end health checks for a PicoCluster Claw pair
# Run from either node.
#
# Usage: bash validate-pair.sh
set -euo pipefail

CLAW_IP="${CLAW_IP:-10.1.10.220}"
CRUSH_IP="${CRUSH_IP:-10.1.10.221}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass=0
fail=0
warn=0

check() {
  local label="$1"
  local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}  $label"
    ((pass++))
  else
    echo -e "  ${RED}FAIL${NC}  $label"
    ((fail++))
  fi
}

warn_check() {
  local label="$1"
  local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}  $label"
    ((pass++))
  else
    echo -e "  ${YELLOW}WARN${NC}  $label"
    ((warn++))
  fi
}

echo "=== PicoCluster Claw Pair Validation ==="
echo "  clusterclaw: $CLAW_IP"
echo "  clustercrush: $CRUSH_IP"
echo ""

# --- Network ---
echo "--- Network ---"
check "Ping clusterclaw ($CLAW_IP)" "ping -c 1 -W 2 $CLAW_IP"
check "Ping clustercrush ($CRUSH_IP)" "ping -c 1 -W 2 $CRUSH_IP"
check "SSH clusterclaw" "ssh -o ConnectTimeout=5 -o BatchMode=yes picocluster@$CLAW_IP true 2>/dev/null || timeout 5 bash -c 'echo | nc -w 2 $CLAW_IP 22'"
check "SSH clustercrush" "ssh -o ConnectTimeout=5 -o BatchMode=yes picocluster@$CRUSH_IP true 2>/dev/null || timeout 5 bash -c 'echo | nc -w 2 $CRUSH_IP 22'"
echo ""

# --- clustercrush services ---
echo "--- clustercrush (Orin Nano) ---"
check "Ollama health" "curl -sf --max-time 5 http://$CRUSH_IP:11434/api/tags | grep -q models"
check "Ollama models" "curl -sf --max-time 5 http://$CRUSH_IP:11434/api/tags | grep -q name"
warn_check "GPU accessible" "ssh -o ConnectTimeout=5 picocluster@$CRUSH_IP 'nvidia-smi' 2>/dev/null"
warn_check "Ollama service enabled" "ssh -o ConnectTimeout=5 picocluster@$CRUSH_IP 'systemctl is-enabled ollama' 2>/dev/null"

# Inference test
echo -n "  "
INFERENCE=$(curl -sf --max-time 30 "http://$CRUSH_IP:11434/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"test","messages":[{"role":"user","content":"Say OK"}],"max_tokens":5}' 2>/dev/null)
if echo "$INFERENCE" | grep -q '"content"'; then
  echo -e "${GREEN}PASS${NC}  Inference round-trip"
  ((pass++))
else
  echo -e "${RED}FAIL${NC}  Inference round-trip"
  ((fail++))
fi
echo ""

# --- clusterclaw services ---
echo "--- clusterclaw (RPi5) ---"
check "OpenClaw gateway" "curl -sf --max-time 5 http://$CLAW_IP:18789/__openclaw__/canvas/ >/dev/null"
warn_check "OpenClaw service enabled" "ssh -o ConnectTimeout=5 picocluster@$CLAW_IP 'systemctl is-enabled openclaw' 2>/dev/null"
check "ThreadWeaver backend" "curl -sf --max-time 5 http://$CLAW_IP:8000/api/settings | grep -q provider"
check "ThreadWeaver frontend" "curl -sf --max-time 5 http://$CLAW_IP:5173/ | grep -q html"
warn_check "ThreadWeaver service enabled" "ssh -o ConnectTimeout=5 picocluster@$CLAW_IP 'systemctl is-enabled threadweaver' 2>/dev/null"
check "ThreadWeaver model discovery" "curl -sf --max-time 5 http://$CLAW_IP:5173/api/models/local | grep -q models"
warn_check "Blinkt! LED service" "ssh -o ConnectTimeout=5 picocluster@$CLAW_IP 'systemctl is-active clusterclaw-leds' 2>/dev/null"
echo ""

# --- Cross-node connectivity ---
echo "--- Cross-node ---"
check "clusterclaw → clustercrush inference" "curl -sf --max-time 10 http://$CLAW_IP:5173/api/models/local | grep -q models"
echo ""

# --- Firewall ---
echo "--- Firewall ---"
warn_check "clustercrush UFW active" "ssh -o ConnectTimeout=5 picocluster@$CRUSH_IP 'sudo ufw status | grep -q active' 2>/dev/null"
warn_check "clusterclaw UFW active" "ssh -o ConnectTimeout=5 picocluster@$CLAW_IP 'sudo ufw status | grep -q active' 2>/dev/null"
echo ""

# --- Model info ---
echo "--- Model ---"
ACTIVE_MODEL=$(curl -sf --max-time 5 "http://$CRUSH_IP:11434/api/tags" 2>/dev/null | python3 -c "import sys,json; models=json.load(sys.stdin).get('models',[]); print(', '.join(m['name'] for m in models) if models else 'none loaded')" 2>/dev/null || echo "unknown")
echo "  Active model: $ACTIVE_MODEL"
GPU_MEM=$(ssh -o ConnectTimeout=5 picocluster@$CRUSH_IP 'nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader' 2>/dev/null || echo "unknown")
echo "  GPU memory: $GPU_MEM"
echo ""

# --- Summary ---
echo "============================================"
total=$((pass + fail + warn))
echo -e "  ${GREEN}PASS: $pass${NC}  ${RED}FAIL: $fail${NC}  ${YELLOW}WARN: $warn${NC}  (total: $total)"
if [[ $fail -eq 0 ]]; then
  echo -e "  ${GREEN}PicoCluster Claw pair is operational.${NC}"
else
  echo -e "  ${RED}$fail check(s) failed — review above.${NC}"
fi
echo "============================================"

exit $fail
