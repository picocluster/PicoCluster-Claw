# PicoClaw

A self-hosted AI agent appliance built on [PicoCluster](https://picocluster.com) hardware. PicoClaw pairs a Raspberry Pi 5 running [OpenClaw](https://github.com/openclaw/openclaw) with an NVIDIA Jetson Orin Nano running local LLM inference — giving you a private, always-on AI agent for under $2/month in electricity.

## Architecture

```
picoclaw (RPi5 8GB)              picocrush (Orin Nano Super 8GB)
├── OpenClaw gateway             ├── llama-server (llama.cpp)
├── Browser automation           ├── GPU-accelerated inference
├── WebChat dashboard            ├── Multiple GGUF models
└── Agent orchestration          └── OpenAI-compatible API
        │                                    │
        └──── HTTP (port 8080) ──────────────┘
```

## Hardware

| Component | Role | Power |
|-----------|------|------:|
| Raspberry Pi 5 (8GB) | Agent orchestrator | ~3-7.5W |
| NVIDIA Jetson Orin Nano Super (8GB) | LLM inference | ~6-20W |
| MicroSD (RPi5, 64GB+) | Boot + OS |  |
| NVMe SSD (Orin, 256GB+) | Models + llama.cpp |  |
| PicoCluster case + 50W PSU | Enclosure + power |  |

**Total power:** ~14W idle, ~20W typical, ~35W peak

## Quick Start

### 1. Flash golden images

Flash the PicoClaw images to both nodes using `dd` or your preferred imaging tool.

### 2. Configure the pair

```bash
# On picoclaw (RPi5):
sudo ./scripts/setup/configure-pair.sh picoclaw

# On picocrush (Orin Nano):
sudo ./scripts/setup/configure-pair.sh picocrush
```

### 3. Run Ansible provisioning

```bash
# From picoclaw:
cd ansible
ansible-playbook -i inventory/cluster.yml site.yml --become
```

This installs and configures:
- **picocrush:** llama.cpp with CUDA, downloads models, starts llama-server
- **picoclaw:** Node.js, OpenClaw, WebChat gateway

### 4. Access your agent

- **WebChat:** Open `http://picoclaw:18789` in your browser (token: `picocluster-token`)
- **Terminal:** `ssh picocluster@picoclaw` then `openclaw tui`
- **API:** `curl http://picoclaw:18789/v1/chat/completions`

## Repository Structure

```
PicoClaw/
├── ansible/                        # Ansible provisioning playbooks
│   ├── inventory/cluster.yml       #   Node IPs and SSH config
│   ├── group_vars/                 #   Shared and per-node variables
│   ├── roles/
│   │   ├── common/                 #   Base setup (both nodes)
│   │   ├── orin_inference/         #   llama.cpp + models (picocrush)
│   │   └── rpi5_openclaw/          #   OpenClaw gateway (picoclaw)
│   ├── site.yml                    #   Full provisioning playbook
│   └── validate.yml                #   Smoke tests
├── scripts/
│   ├── imaging/                    # Image capture and management
│   │   ├── jetson-shrink.sh        #   Shrink dd-captured Orin images
│   │   ├── resize_ubuntu.sh        #   Expand Orin rootfs after flash
│   │   ├── resize_raspbian.sh      #   Expand RPi5 rootfs after flash
│   │   └── sd-to-nvme.sh           #   Migrate Orin boot to NVMe
│   ├── setup/                      # Node setup and configuration
│   │   ├── build-rpi5-image.sh     #   Strip + harden Raspbian
│   │   ├── build-orin-image.sh     #   Strip + harden JetPack
│   │   └── configure-pair.sh       #   Set IPs, hostnames, configs
│   └── testing/                    # Stress tests and benchmarking
│       ├── stress-test-rpi5.sh     #   RPi5 power/thermal testing
│       └── stress-test-orin.sh     #   Orin power/thermal testing
└── docs/                           # Documentation
    ├── benchmark-report.md         #   Power, thermal, performance data
    ├── storage-options.md          #   Drive sizing and recommendations
    ├── roadmap.md                  #   Project roadmap and phases
    └── picoclcaw-deployment-plan.md #  Deployment architecture
```

## Models

Default model set (~11GB, all Q4_K_M quantization):

| Model | Size | Speed | Use Case |
|-------|-----:|------:|----------|
| Llama 3.2 3B | 1.9GB | ~18 t/s | Primary agent model |
| Llama 3.1 8B | 4.7GB | ~10 t/s | Higher quality |
| Phi-3.5 Mini 3.8B | 2.3GB | ~17 t/s | Strong reasoning |
| Qwen 2.5 3B | 2.0GB | ~18 t/s | Code / structured output |

All models run fully on GPU (ngl 99) on the 8GB Orin Nano.

## Energy Cost

| Scenario | Power | Monthly | Annual |
|----------|------:|--------:|-------:|
| Idle (waiting for tasks) | 14W | $1.61 | $19.62 |
| Typical agent workload | 20W | $2.30 | $28.03 |
| Realistic blend (90% idle) | 15W | $1.73 | $21.02 |

*Your own private AI agent for under $2/month.*

## Security

PicoClaw runs entirely on your local network with no cloud dependencies:

- OpenClaw gateway bound to LAN with token authentication
- llama-server restricted to picoclaw IP only via firewall
- SSH hardened (no root login)
- UFW firewall on both nodes
- fail2ban on SSH
- Automatic security updates
- No API keys sent to external services

See [docs/picoclcaw-deployment-plan.md](docs/picoclcaw-deployment-plan.md) for the full security hardening checklist.

## License

Apache 2.0

## Links

- [PicoCluster](https://picocluster.com)
- [OpenClaw](https://github.com/openclaw/openclaw)
- [llama.cpp](https://github.com/ggerganov/llama.cpp)
