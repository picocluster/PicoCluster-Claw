#!/bin/bash
set -e

# Write .env from environment variables
cat > /app/backend/.env <<EOF
LLM_PROVIDER=${LLM_PROVIDER:-local}
LOCAL_BASE_URL=${LOCAL_BASE_URL:-http://picocrush:8080/v1}
LOCAL_MODEL=${LOCAL_MODEL:-Llama-3.2-3B-Instruct-Q4_K_M.gguf}
EOF

# Start backend using venv
cd /app/backend
/app/venv/bin/python server.py &
BACKEND_PID=$!

sleep 3

# Auto-connect LED MCP server if available
if [ -f /opt/mcp/led_server.py ]; then
  curl -sf -X POST http://127.0.0.1:8000/api/mcp/connect \
    -H "Content-Type: application/json" \
    -d '{"name":"leds","command":"python3","args":["/opt/mcp/led_server.py"]}' \
    && echo "LED MCP server connected" \
    || echo "LED MCP server connection failed (will retry on next restart)"
fi

# Start frontend
cd /app/frontend
npx vite --host 0.0.0.0 --port 5173 &
FRONTEND_PID=$!

wait -n $BACKEND_PID $FRONTEND_PID
kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
