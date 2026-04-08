# PicoClaw Ansible Provisioning Reference

## Cluster Architecture

```
RPi5 (10.1.10.220) — Control node + OpenClaw agent orchestrator
  └── Runs: Ansible, OpenClaw, browser automation
  └── OS: Raspbian (64-bit)
  └── User: picocluster

Orin Nano (10.1.10.240) — Inference node
  └── Runs: llama-server (llama.cpp, GPU-accelerated)
  └── OS: Ubuntu (JetPack 6.x)
  └── User: picocluster
  └── NVMe: /mnt/nvme (models + llama.cpp build)
```

## Directory Structure

```
ansible/
├── inventory/
│   └── cluster.yml                 # Node IPs, SSH users, connection type
├── group_vars/
│   ├── all.yml                     # Shared: timezone, inference endpoint, base packages
│   ├── rpi5.yml                    # Node.js version, OpenClaw config, swap size
│   └── orin.yml                    # Model list, llama-server config, power mode, NVMe paths
├── roles/
│   ├── common/                     # Applied to BOTH nodes
│   │   ├── tasks/main.yml          #   apt upgrade, base utils, hostname, /etc/hosts, NVMe mount
│   │   └── handlers/main.yml       #   systemd reload
│   ├��─ orin_inference/             # Applied to Orin Nano only
│   │   ├── tasks/
│   │   │   ├── main.yml            #   CUDA verify, power mode, orchestrates sub-tasks
│   │   │   ├── llama_server.yml    #   Clone + build llama.cpp, deploy systemd service
│   │   │   └── models.yml          #   Download GGUF models from HuggingFace
│   │   ├── templates/
│   │   │   ├── llama-server.service.j2   # systemd unit template
│   │   │   └── llama-server.env.j2       # environment file template
│   │   └── handlers/main.yml      #   systemd reload, llama-server restart
│   └── rpi5_openclaw/              # Applied to RPi5 only
│       ├── tasks/main.yml          #   Node.js 24, npm openclaw, swap, config, systemd daemon
│       ├── templates/
│       │   └── openclaw-config.json.j2   # OpenClaw LLM endpoint config
│       └── handlers/main.yml      #   swap restart, openclaw restart
├── site.yml                        # Full provisioning playbook
└── validate.yml                    # Smoke tests: health, inference, cross-node connectivity
```

## Prerequisites

### On RPi5 (control node)

```bash
# Install Ansible
sudo apt update
sudo apt install -y ansible

# Set up SSH key auth to Orin Nano (if not already done)
ssh-keygen -t ed25519     # skip if key exists
ssh-copy-id picocluster@10.1.10.240
```

### On Orin Nano

- Fresh OS install (JetPack 6.x / Ubuntu)
- NVMe drive installed (will be formatted and mounted by playbook)
- SSH access from RPi5 working

## Usage

### Full provisioning (both nodes)

```bash
cd ansible
ansible-playbook -i inventory/cluster.yml site.yml
```

### Provision a single node

```bash
# Orin Nano only
ansible-playbook -i inventory/cluster.yml site.yml --limit orin

# RPi5 only
ansible-playbook -i inventory/cluster.yml site.yml --limit rpi5
```

### Validate the cluster

```bash
ansible-playbook -i inventory/cluster.yml validate.yml
```

### Dry run (check mode)

```bash
ansible-playbook -i inventory/cluster.yml site.yml --check
```

## What Each Role Does

### common (both nodes)
1. Updates apt cache and upgrades all packages
2. Installs base utilities (curl, git, htop, tmux, jq, etc.)
3. Sets timezone and hostname
4. Configures /etc/hosts so both nodes can resolve each other
5. Mounts NVMe on Orin Nano (skipped on RPi5)
6. Reboots if packages were upgraded

### orin_inference (Orin Nano)
1. Verifies CUDA is available (nvidia-smi)
2. Sets power mode to MAXN and enables max clocks
3. Persists power mode via systemd (survives reboot)
4. Clones and builds llama.cpp with CUDA (skipped if binary exists)
5. Downloads GGUF models from HuggingFace (skipped if files exist)
6. Deploys llama-server as a systemd service
7. Waits for health endpoint to confirm server is ready

### rpi5_openclaw (RPi5)
1. Installs Node.js 24 via NodeSource (skipped if already installed)
2. Installs OpenClaw globally via npm
3. Configures 2GB swap for stability
4. Deploys OpenClaw config pointing to Orin inference endpoint
5. Installs OpenClaw systemd daemon
6. Enables and starts OpenClaw service

## Configuration Reference

### Changing the default model

Edit `group_vars/orin.yml`:
```yaml
llama_default_model: "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
```
Then re-run: `ansible-playbook -i inventory/cluster.yml site.yml --limit orin`

### Adding a new model

Add to the `orin_models` list in `group_vars/orin.yml`:
```yaml
orin_models:
  - name: NewModel-Q4_K_M.gguf
    url: https://huggingface.co/...
    size_bytes: 1234567890
```
Then re-run the orin role. Existing models won't be re-downloaded.

### Changing the inference port

Edit `group_vars/all.yml`:
```yaml
llama_port: 8080
```
This updates both the llama-server and the OpenClaw config.

### Changing the Orin power mode

Edit `group_vars/orin.yml`:
```yaml
nvpmodel_mode: 2    # 0=15W, 1=25W, 2=MAXN
```

## Timing Expectations

| Step | Duration | Notes |
|------|----------|-------|
| common role (per node) | 2-5 min | Longer on first run with full apt upgrade |
| llama.cpp build | ~10 min | First run only; skipped if binary exists |
| Model downloads | 5-30 min | Depends on internet speed; ~13GB total |
| OpenClaw install | 2-3 min | Node.js + npm |
| **Total first run** | **~20-45 min** | Mostly model downloads |
| **Subsequent runs** | **~2-3 min** | Idempotent, skips completed steps |

## Troubleshooting

### llama.cpp build fails
```bash
# SSH to Orin and check manually
ssh picocluster@10.1.10.240
cd /mnt/nvme/llama.cpp/build
cmake .. -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=87
make -j$(nproc)
```

### Model download fails
```bash
# Download manually on Orin
cd /mnt/nvme/models
wget <url from group_vars/orin.yml>
```
Re-running the playbook will skip existing files.

### openclaw onboard --install-daemon fails
Check the correct flags:
```bash
ssh picocluster@10.1.10.220
openclaw --help
openclaw onboard --help
```
If `--install-daemon` doesn't exist, create the systemd service manually
and update `roles/rpi5_openclaw/tasks/main.yml`.

### RPi5 can't reach Orin inference endpoint
```bash
# From RPi5
curl http://10.1.10.240:8080/health
curl http://10.1.10.240:8080/v1/models
```
Check: firewall, llama-server status, network connectivity.

### Playbook hangs on model download
Model downloads have a 600-second timeout with 3 retries.
For very slow connections, increase timeout in `roles/orin_inference/tasks/models.yml`.

## Installed Models (Default Set)

| Model | File | Size | Use Case |
|-------|------|------|----------|
| Llama 3.2 3B | Llama-3.2-3B-Instruct-Q4_K_M.gguf | 1.9 GB | Primary agent model (default) |
| Llama 3.1 8B | Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf | 4.7 GB | Higher quality, slower |
| Phi-3.5 Mini | Phi-3.5-mini-instruct-Q4_K_M.gguf | 2.3 GB | Strong reasoning |
| Qwen 2.5 3B | Qwen2.5-3B-Instruct-Q4_K_M.gguf | 2.0 GB | Code / structured output |
| **Total** | | **~11 GB** | |

## Storage Recommendations

| Node | Recommended | Minimum | Notes |
|------|-------------|---------|-------|
| RPi5 | 256 GB NVMe via HAT | 64 GB microSD | NVMe recommended for production |
| Orin Nano | 512 GB NVMe | 256 GB NVMe | OS on eMMC, models on NVMe |
