# PicoCluster Claw

A self-hosted AI agent appliance built on [PicoCluster](https://picocluster.com) hardware. PicoCluster Claw pairs a Raspberry Pi 5 running [OpenClaw](https://github.com/openclaw/openclaw) and [ThreadWeaver](https://github.com/nosqltips/ThreadWeaver) with an NVIDIA Jetson Orin Nano running [Ollama](https://ollama.com) for local LLM inference — giving you a private, always-on AI for under $2/month in electricity.

## Architecture

```
clusterclaw (RPi5 8GB)                clustercrush (Orin Nano Super 8GB)
├── Portal :80                     ├── Ollama :11434
├── ThreadWeaver :5173             ├── 9 LLM models (GPU-accelerated)
├── OpenClaw Gateway :18789        ├── Vision, Code, Reasoning models
├── Caddy HTTPS proxy :18790       ├── OpenAI-compatible API
├── Blinkt! LED status             └── CUDA / cuDNN / TensorRT
└── Docker containers                      │
        │                                  │
        └──── HTTP (port 11434) ───────────┘
```

## Hardware

| Component | Role | Power |
|-----------|------|------:|
| Raspberry Pi 5 (8GB) | Web UIs, agent orchestrator | ~3-7.5W |
| NVIDIA Jetson Orin Nano Super (8GB) | LLM inference (Ollama) | ~6-20W |
| MicroSD 128GB (both nodes) | Boot + OS | |
| NVMe SSD 256GB+ (Orin) | Model storage | |
| PicoCluster case + 50W PSU | Enclosure + power | |
| Pimoroni Blinkt! (RPi5) | LED status indicator | |

**Total power:** ~14W idle, ~20W typical, ~35W peak

## Quick Start

### 1. Flash golden images

Flash the PicoCluster Claw images to both nodes using `dd` or your preferred imaging tool.

### 2. Install clustercrush (Orin Nano)

```bash
sudo bash install-clustercrush.sh
```

Installs Ollama with CUDA, pulls 9 default models, configures firewall and power mode.

### 3. Install clusterclaw (RPi5)

```bash
sudo bash install-clusterclaw.sh
```

Installs Docker containers (ThreadWeaver, OpenClaw, Portal, Caddy), Blinkt! LED daemon, configures firewall.

### 4. Access your AI

Open **http://clusterclaw** in your browser for the PicoCluster Claw portal with links to all services.

| Interface | URL | Notes |
|-----------|-----|-------|
| **PicoCluster Claw Portal** | `http://clusterclaw` | Landing page with status and docs |
| **ThreadWeaver** | `http://clusterclaw:5173` | Chat UI — works directly over HTTP |
| **OpenClaw Dashboard** | `https://localhost:18790` | Requires SSH tunnel (see below) |
| **OpenClaw TUI** | `ssh picocluster@clusterclaw` then `openclaw tui` | Terminal chat |
| **Ollama API** | `http://clustercrush:11434/v1` | OpenAI-compatible endpoint |

**SSH tunnel for OpenClaw Dashboard:**
```bash
ssh -L 18790:localhost:18790 picocluster@clusterclaw
```
Then open `https://localhost:18790` (token: `picocluster-token`)

See [docs/access-guide.md](docs/access-guide.md) for all access methods including Tailscale, Telegram, and mobile.

## Models

9 models installed by default (~27GB on NVMe). Ollama manages loading/unloading automatically.

| Model | Size | Type |
|-------|-----:|------|
| llama3.2:3b | 2.0 GB | General (primary) |
| llama3.1:8b | 4.9 GB | General (quality) |
| gemma3:4b | 3.3 GB | General (multilingual) |
| phi3.5:3.8b | 2.2 GB | Reasoning |
| deepseek-r1:7b | 4.7 GB | Reasoning (chain-of-thought) |
| qwen2.5:3b | 1.9 GB | Code / structured output |
| starcoder2:3b | 1.7 GB | Code generation |
| llava:7b | 4.7 GB | Vision (image understanding) |
| moondream:1.8b | 1.7 GB | Vision (lightweight) |

```bash
# Add more models on clustercrush:
ollama pull <model>
ollama list
```

## Management

| Task | Command |
|------|---------|
| Update ThreadWeaver | `sudo bash /opt/clusterclaw/scripts/setup/update-threadweaver.sh` |
| Update all containers | `sudo bash /opt/clusterclaw/scripts/setup/update-clusterclaw.sh` |
| Update Ollama + models | `sudo bash /opt/clusterclaw/scripts/setup/update-clustercrush.sh` |
| Container status | `cd /opt/clusterclaw && sudo docker compose ps` |
| View logs | `cd /opt/clusterclaw && sudo docker compose logs -f` |
| Restart services | `cd /opt/clusterclaw && sudo docker compose restart` |
| Add a model | `ssh clustercrush` then `ollama pull <model>` |
| Validate cluster | `bash /opt/clusterclaw/scripts/setup/validate-pair.sh` |

## Blinkt! LED Status

The Pimoroni Blinkt! on clusterclaw provides visual feedback:

- **Scanning eye**: Idle — color-shifting Larson scanner with blink and look-around behaviors
- **Green/cyan chase**: LLM inference active (color cycling)
- **Purple pulse**: OpenClaw agent thinking
- **Amber pulse**: Service degraded
- **Red pulse**: Services down
- **Boot sequence**: Rainbow → blue sweep → amber progress → green ready

## MCP Servers

PicoCluster Claw ships with 5 MCP (Model Context Protocol) servers that auto-connect to ThreadWeaver on startup, giving local LLMs **28 tools** to work with — including physical LED control, system monitoring, time awareness, sandboxed file operations, and Ollama management.

> **User:** "Make the LEDs purple and tell me the GPU memory usage on clustercrush"
> **LLM:** *calls `leds__set_led_color` and `clustercrush__get_gpu_memory`* → Blinkt! turns purple, reports VRAM stats

| Server | Tools | Purpose |
|--------|------:|---------|
| **leds** | 5 | Control Blinkt! LEDs (color, progress, pulse, clear) |
| **system** | 6 | clusterclaw stats (CPU, memory, disk, temperature, uptime, network) |
| **clustercrush** | 4 | Ollama management (list models, active models, GPU memory, pull new) |
| **time** | 4 | Current time/date, countdowns, duration formatting |
| **files** | 5 | Sandboxed file operations (read, write, list, delete) |

All servers are stdio-based MCP servers mounted into the ThreadWeaver container. See [docs/mcp-tools.md](docs/mcp-tools.md) for the full tool reference and HTTP API.

LED controls are also available on the portal page and via the HTTP API on port 7777.

## Repository Structure

```
PicoCluster Claw/
├── docker-compose.yml              # All services (ThreadWeaver, OpenClaw, Portal, Caddy)
├── portal/                         # PicoCluster Claw landing page (nginx on port 80)
├── openclaw/                       # OpenClaw Dockerfile + config
├── threadweaver/                   # ThreadWeaver Dockerfile + patches
├── leds/                           # Blinkt! LED driver, status daemon, MCP server
├── mcp/                            # MCP servers (system, clustercrush, time, files)
├── scripts/
│   ├── setup/                      # Install, update, configure, validate scripts
│   ├── imaging/                    # Image capture, shrink, resize, NVMe migration
│   └── testing/                    # Stress tests and benchmarking
└── docs/                           # Documentation
    ├── access-guide.md             # All access methods and troubleshooting
    ├── mcp-tools.md                # All 5 MCP servers + HTTP API reference
    ├── demo-script.md              # Live demo walkthrough
    ├── blog-post.md                # "Talk to Your AI and Watch It Light Up"
    ├── benchmark-report.md         # Power, thermal, performance data
    ├── storage-options.md          # Drive sizing recommendations
    └── roadmap.md                  # Project roadmap
```

## Energy Cost

| Scenario | Power | Monthly | Annual |
|----------|------:|--------:|-------:|
| Idle (waiting for tasks) | 14W | $1.61 | $19.62 |
| Typical agent workload | 20W | $2.30 | $28.03 |
| Realistic blend (90% idle) | 15W | $1.73 | $21.02 |

*Your own private AI for under $2/month.*

## Security

- All services run on your local network — no cloud dependencies
- OpenClaw in Docker container (isolated)
- OpenClaw dashboard requires HTTPS + token authentication
- Ollama restricted to clusterclaw IP via firewall
- SSH hardened (no root login)
- UFW firewall on both nodes
- fail2ban on SSH
- Automatic security updates

## Services Overview

| Service | Node | Port | Container |
|---------|------|------|-----------|
| PicoCluster Claw Portal | clusterclaw | 80 | nginx |
| ThreadWeaver UI | clusterclaw | 5173 | threadweaver |
| ThreadWeaver API | clusterclaw | 8000 | threadweaver |
| OpenClaw Gateway | clusterclaw | 18789 | openclaw |
| OpenClaw HTTPS | clusterclaw | 18790 | caddy |
| Blinkt! LEDs | clusterclaw | GPIO | native |
| LED API | clusterclaw | 7777 | native |
| LED MCP Server | clusterclaw | stdio | native (auto-connected) |
| OpenClaw LED Bridge | clusterclaw | — | native (log monitor) |
| Shutdown API | clusterclaw | 8888 | python |
| Ollama | clustercrush | 11434 | native |

## Default Credentials

| Service | Credential | Value |
|---------|-----------|-------|
| SSH (both nodes) | User / Password | `picocluster` / `picocluster` |
| OpenClaw | Gateway Token | `picocluster-token` |
| Ollama | Auth | None (firewall-restricted) |

> **Note:** Hostnames, IPs, and credentials shown are defaults. If you changed them via `configure-pair.sh`, substitute your values.

## License

Apache 2.0

## Links

- [PicoCluster](https://picocluster.com)
- [ThreadWeaver](https://github.com/nosqltips/ThreadWeaver)
- [OpenClaw](https://github.com/openclaw/openclaw)
- [Ollama](https://ollama.com)
- [llama.cpp](https://github.com/ggerganov/llama.cpp)
