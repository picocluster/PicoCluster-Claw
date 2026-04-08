#!/bin/bash
set -e

# Generate config from environment variables if not mounted
if [[ ! -f /home/openclaw/.openclaw/openclaw.json ]]; then
  cat > /home/openclaw/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "mode": "local",
    "auth": {
      "token": "${OPENCLAW_TOKEN:-picocluster-token}"
    },
    "bind": "0.0.0.0"
  },
  "models": {
    "providers": {
      "local": {
        "baseUrl": "${LOCAL_BASE_URL:-http://picocrush:8080/v1}",
        "apiKey": "none",
        "models": [
          {
            "id": "${LOCAL_MODEL:-Llama-3.2-3B-Instruct-Q4_K_M.gguf}",
            "name": "Llama 3.2 3B"
          }
        ]
      }
    }
  }
}
EOF
  chmod 600 /home/openclaw/.openclaw/openclaw.json
fi

exec openclaw gateway --port 18789
