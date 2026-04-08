FROM node:24-slim AS frontend

WORKDIR /app
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/nosqltips/ThreadWeaver.git .

# Patch API_BASE for LAN access (baked into image)
RUN sed -i "s|const API_BASE = 'http://localhost:8000/api'|const API_BASE = '/api'|g" \
    frontend/src/lib/api.ts frontend/src/routes/+page.svelte

# Patch vite config: allow LAN hosts + proxy /api to backend
RUN printf 'import { sveltekit } from "@sveltejs/kit/vite";\nimport { defineConfig } from "vite";\n\nexport default defineConfig({\n\tplugins: [sveltekit()],\n\tserver: {\n\t\tallowedHosts: true,\n\t\tproxy: {\n\t\t\t"/api": {\n\t\t\t\ttarget: "http://127.0.0.1:8000",\n\t\t\t\tchangeOrigin: true\n\t\t\t}\n\t\t}\n\t}\n});\n' > frontend/vite.config.js

WORKDIR /app/frontend
RUN npm install

# Backend
FROM python:3.12-slim AS backend
WORKDIR /app
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/nosqltips/ThreadWeaver.git .
WORKDIR /app/backend
RUN pip install --no-cache-dir -r requirements.txt

# Patch model discovery: add OpenAI /v1/models fallback for llama-server
COPY patch-llama-server.py /tmp/patch-llama-server.py
RUN python3 /tmp/patch-llama-server.py /app/backend/server.py

# Final image
FROM node:24-slim

RUN apt-get update && apt-get install -y python3 python3-venv && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy backend with patched server.py and installed deps
COPY --from=backend /app/backend /app/backend
COPY --from=backend /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=backend /usr/local/bin/uvicorn /usr/local/bin/uvicorn

# Copy frontend with patches and node_modules
COPY --from=frontend /app/frontend /app/frontend

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

ENV LLM_PROVIDER=local
ENV LOCAL_BASE_URL=http://picocrush:8080/v1
ENV LOCAL_MODEL=Llama-3.2-3B-Instruct-Q4_K_M.gguf

EXPOSE 5173 8000

CMD ["/app/start.sh"]
