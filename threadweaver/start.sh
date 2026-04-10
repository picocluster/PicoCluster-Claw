#!/bin/bash
set -e

# Write .env from environment variables. Defaults match the Dockerfile ENV
# values; docker-compose overrides these via the `environment:` section.
# LOCAL_MODEL must be an Ollama tag that supports tool calling. llama3.1:8b
# chains tool calls reliably across multi-turn conversations.
cat > /app/backend/.env <<EOF
LLM_PROVIDER=${LLM_PROVIDER:-local}
LOCAL_BASE_URL=${LOCAL_BASE_URL:-http://picocrush:11434/v1}
LOCAL_MODEL=${LOCAL_MODEL:-llama3.1:8b}
EOF

# Start backend using venv
cd /app/backend
/app/venv/bin/python server.py &
BACKEND_PID=$!

# Wait for the backend API to actually accept connections before trying to
# connect MCP servers. On cold Docker starts (reboot, first deploy) the
# `sleep 3` that was here before wasn't always enough — the backend process
# was running but uvicorn hadn't bound the socket yet, so every connect_mcp
# call got "connection refused" and silently failed.
echo "Waiting for backend API..."
for i in $(seq 1 30); do
  if curl -sf --max-time 2 http://127.0.0.1:8000/api/settings > /dev/null 2>&1; then
    echo "Backend ready (attempt $i)"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "WARNING: Backend not ready after 30 attempts — MCP servers may fail to connect"
  fi
  sleep 1
done

# Auto-connect all PicoCluster Claw MCP servers with retry.
# Each server gets up to 3 attempts with a 2-second pause between failures.
connect_mcp() {
  local name="$1"
  local script="$2"
  local max_retries=3
  local attempt=1

  if [ ! -f "$script" ]; then
    echo "MCP skip: ${name} (${script} not found)"
    return
  fi

  while [ "$attempt" -le "$max_retries" ]; do
    if curl -sf -X POST http://127.0.0.1:8000/api/mcp/connect \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"${name}\",\"command\":\"python3\",\"args\":[\"${script}\"]}" \
      > /dev/null 2>&1; then
      echo "MCP connected: ${name}"
      return
    fi
    echo "MCP retry ${attempt}/${max_retries}: ${name}"
    attempt=$((attempt + 1))
    sleep 2
  done
  echo "MCP FAILED: ${name} (gave up after ${max_retries} attempts)"
}

connect_mcp "leds" "/opt/mcp/led_server.py"
connect_mcp "system" "/opt/mcp/servers/system_info_server.py"
connect_mcp "picocrush" "/opt/mcp/servers/picocrush_server.py"
connect_mcp "time" "/opt/mcp/servers/time_server.py"
connect_mcp "files" "/opt/mcp/servers/files_server.py"

# Verify all servers connected
TOOL_COUNT=$(curl -sf http://127.0.0.1:8000/api/tools 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
echo "MCP setup complete: ${TOOL_COUNT} tools available"

# Start frontend
cd /app/frontend
npx vite --host 0.0.0.0 --port 5173 &
FRONTEND_PID=$!

# --------------------------------------------------------------------------
# Prime the default LLM model in the background.
#
# Loads the model into GPU memory on picocrush so the first user message
# gets a fast response instead of a 60-90 second cold start. Runs in the
# background so it doesn't block the frontend from serving pages.
#
# Plain text prime only (no tools) — sending tool schemas during prime was
# making the model "tool-happy" on subsequent requests, and the prime
# doesn't need to validate tool calling, just load the weights.
#
# LED sequence: amber → (prime running) → green pulse → clear (back to scanner)
# --------------------------------------------------------------------------
LED_URL="${LED_API_URL:-http://host.docker.internal:7777}"

prime_model() {
  local base_url="${LOCAL_BASE_URL:-http://picocrush:11434/v1}"
  local model="${LOCAL_MODEL:-llama3.1:8b}"

  echo "Priming ${model} on ${base_url}..."

  # LED: amber = "warming up"
  curl -sf -X POST "${LED_URL}/set_status" \
    -H "Content-Type: application/json" \
    -d '{"color":"amber","duration":120}' > /dev/null 2>&1 || true

  # Simple text-only request to load the model into GPU memory.
  # No tools, no system prompt — just enough to force Ollama to load weights.
  PRIME_RESULT=$(curl -sf --max-time 180 "${base_url}/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_tokens\":5}" 2>&1)

  if echo "$PRIME_RESULT" | grep -q '"choices"'; then
    echo "Model primed: ${model}"
    # LED: green success burst then back to idle scanner
    curl -sf -X POST "${LED_URL}/pulse_success" > /dev/null 2>&1 || true
    sleep 3
    curl -sf -X POST "${LED_URL}/clear" > /dev/null 2>&1 || true
  else
    echo "Model prime failed — will load on first user request"
    curl -sf -X POST "${LED_URL}/pulse_error" > /dev/null 2>&1 || true
    sleep 3
    curl -sf -X POST "${LED_URL}/clear" > /dev/null 2>&1 || true
  fi
}

# Run in background so the frontend is immediately available
prime_model &

wait -n $BACKEND_PID $FRONTEND_PID
kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
