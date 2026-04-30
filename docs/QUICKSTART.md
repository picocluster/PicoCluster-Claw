# 5-Minute Quickstart

Get PicoCluster Claw running in under five minutes — hardware appliance or software install.

## Hardware: PicoCluster Claw appliance

1. **Power on** — plug in both nodes. ClusterClaw (RPi 5) and ClusterCrush (Jetson Orin Nano Super) boot automatically.

2. **Connect** — both nodes join your local network via Ethernet. Find their IPs from your router or use the mDNS hostname:
   ```
   ssh pi@clusterclaw.local
   ssh user@clustercrush.local
   ```

3. **Verify** — check that OpenClaw is running on Claw and Ollama is running on Crush:
   ```bash
   # On clusterclaw
   openclaw status

   # On clustercrush
   ollama list
   ```

4. **Chat** — open ThreadWeaver in your browser at `http://clusterclaw.local:3000`. Select a local model from the Crush node and start chatting.

5. **Run an agent** — from your workstation, point OpenClaw at the cluster:
   ```bash
   openclaw --hub http://clusterclaw.local:8080 "summarize my project README"
   ```

## Software: Mac / Linux / Windows

Install the full stack on your own machine using Docker Compose.

### Prerequisites

- Docker Desktop (Mac/Windows) or Docker Engine + Compose (Linux)
- Ollama installed and running locally (or remote)
- 8 GB RAM recommended

### Install

```bash
git clone https://github.com/picocluster/picocluster-claw.git
cd picocluster-claw

# Mac
docker compose -f docker-compose.yml -f overlays/mac.yml up -d

# Linux
docker compose -f docker-compose.yml -f overlays/linux.yml up -d

# Windows (WSL2)
docker compose -f docker-compose.yml -f overlays/windows.yml up -d
```

ThreadWeaver will be at `http://localhost:3000`.

### Configure

Edit `.env` (created from `.env.example`) to set your model preferences and any cloud API keys:

```bash
cp .env.example .env
# Edit .env — set OLLAMA_BASE_URL, optional OPENAI_API_KEY, etc.
```

## Next steps

- [MCP tools reference](/reference/mcp-tools/) — all 28 tools explained
- [FAQ](/getting-started/faq/) — common questions answered
- [Examples](/operating/examples/) — example prompts for OpenClaw agents
