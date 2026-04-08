#!/bin/bash
# Start ThreadWeaver backend and frontend

# Start backend
cd /app/backend
/app/venv/bin/python server.py &
BACKEND_PID=$!

# Wait for backend
sleep 3

# Start frontend (vite dev server, binds to 0.0.0.0)
cd /app/frontend
npx vite --host 0.0.0.0 --port 5173 &
FRONTEND_PID=$!

# Wait for either to exit
wait -n $BACKEND_PID $FRONTEND_PID
kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
