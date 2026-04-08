FROM node:24-slim

WORKDIR /app
RUN apt-get update && apt-get install -y git python3 python3-pip python3-venv && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/nosqltips/ThreadWeaver.git .

# Install frontend dependencies
WORKDIR /app/frontend
RUN npm install

# Install backend dependencies
WORKDIR /app/backend
RUN python3 -m venv /app/venv
RUN /app/venv/bin/pip install --no-cache-dir -r requirements.txt

# Default environment for PicoClaw
ENV LLM_PROVIDER=local
ENV LOCAL_BASE_URL=http://10.1.10.221:8080/v1
ENV LOCAL_MODEL=Llama-3.2-3B-Instruct-Q4_K_M.gguf

EXPOSE 8000 5173

# Start both backend and frontend
WORKDIR /app
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh
CMD ["/app/start.sh"]
