#!/bin/bash
set -e

CONFIG="/home/openclaw/.openclaw/openclaw.json"

# Write the default config only on first start.
# On subsequent starts, preserve user customizations but patch the token
# so a rotated OPENCLAW_TOKEN env var is always reflected.
if [ ! -f "$CONFIG" ]; then
cat > "$CONFIG" <<EOF
{
  "gateway": {
    "mode": "local",
    "auth": {
      "token": "${OPENCLAW_TOKEN:-picocluster-token}"
    },
    "bind": "lan",
    "trustedProxies": ["172.16.0.0/12", "127.0.0.1", "::1"],
    "controlUi": {
      "allowedOrigins": [
        "https://claw.local",
        "https://claw.local:443",
        "https://threadweaver.local",
        "https://threadweaver.local:443",
        "http://control.local",
        "http://clusterclaw:18789",
        "https://localhost:18790",
        "https://127.0.0.1:18790",
        "http://localhost:18789",
        "http://127.0.0.1:18789"
      ],
      "dangerouslyDisableDeviceAuth": true
    }
  },
  "models": {
    "providers": {
      "local": {
        "baseUrl": "${LOCAL_BASE_URL:-http://clustercrush:11434/v1}",
        "apiKey": "none",
        "models": [
          {"id": "granite4.1:8b", "name": "Granite 4.1 8B"},
          {"id": "llama3.2:3b", "name": "Llama 3.2 3B"},
          {"id": "llama3.1:8b", "name": "Llama 3.1 8B"},
          {"id": "phi3.5:3.8b", "name": "Phi 3.5 Mini"},
          {"id": "qwen3.5:4b", "name": "Qwen 3.5 4B"},
          {"id": "qwen3.5:9b", "name": "Qwen 3.5 9B"},
          {"id": "ministral-3:8b", "name": "Ministral 3 8B"},
          {"id": "deepseek-r1:7b", "name": "DeepSeek R1 7B"},
          {"id": "nemotron-3-nano:4b", "name": "Nemotron 3 Nano 4B"},
          {"id": "gemma4:e4b", "name": "Gemma 4 E4B"}
        ]
      }
    }
  }
}
EOF
chmod 600 "$CONFIG"
else
  # Config exists — patch only the auth token so a rotated OPENCLAW_TOKEN is picked up.
  TOKEN="${OPENCLAW_TOKEN:-picocluster-token}"
  if command -v jq &>/dev/null; then
    tmp=$(mktemp)
    jq --arg t "$TOKEN" '.gateway.auth.token = $t' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
    chmod 600 "$CONFIG"
  fi
fi

exec openclaw gateway --port 18789
