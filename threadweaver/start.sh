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

sleep 2

# Start frontend
cd /app/frontend
npx vite --host 0.0.0.0 --port 5173 &
FRONTEND_PID=$!

wait -n $BACKEND_PID $FRONTEND_PID
kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
