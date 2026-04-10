# PicoCluster Claw Storage Recommendations

## Recommended Configuration

| Node | Boot Device | Storage | Size |
|------|------------|---------|------|
| **picocluster-claw** (RPi5) | MicroSD | OS + Docker + OpenClaw + ThreadWeaver | **128GB** |
| **picocrush** (Orin Nano) | MicroSD | OS (JetPack) | **128GB** |
| **picocrush** (Orin Nano) | NVMe M.2 | Models + llama.cpp | **256GB** |

Filesystem: **ext4** (default for both Raspbian and JetPack)

---

## picocluster-claw (RPi5) — Storage Breakdown

| Component | Size |
|-----------|------|
| Raspbian Desktop (stripped + hardened) | ~3.4GB |
| Docker engine | ~500MB |
| OpenClaw container | ~1.2GB |
| ThreadWeaver container | ~800MB |
| Node.js 24 | ~230MB |
| Blinkt! LED daemon | ~1MB |
| System overhead + logs | ~500MB |
| **Total used** | **~6.6GB** |
| **Free on 128GB card** | **~115GB** |

### Why MicroSD is sufficient
- Workload is mostly reads (Docker image layers, serving web UI)
- No heavy writes (logs are capped, no database)
- High-endurance microSD cards (Samsung PRO Endurance, SanDisk MAX Endurance) handle the write load
- M.2 NVMe via HAT adds cost and case height for speed that isn't noticeable in this use case

### When to consider M.2 NVMe on RPi5
- Heavy logging or data collection workloads
- Running additional databases or storage-intensive services
- Production deployments where SD card wear is a concern over years

---

## picocrush (Orin Nano) — Storage Breakdown

The Orin Nano uses **two storage devices**:

### MicroSD (Boot + OS)

| Component | Size |
|-----------|------|
| JetPack Desktop (stripped + hardened) | ~18GB |
| System utilities + security tools | ~1GB |
| System overhead + logs | ~500MB |
| **Total used** | **~20GB** |
| **Free on 128GB card** | **~100GB** |

### NVMe M.2 (Models + Build)

| Component | Size |
|-----------|------|
| llama.cpp build (CUDA) | ~500MB |
| **Default model set:** | |
| Llama 3.2 3B Q4_K_M | 1.9GB |
| Llama 3.1 8B Q4_K_M | 4.7GB |
| Phi-3.5 Mini Q4_K_M | 2.3GB |
| Qwen 2.5 3B Q4_K_M | 2.0GB |
| **Total used** | **~11.4GB** |
| **Free on 256GB NVMe** | **~230GB** |

### NVMe sizing guide

| NVMe Size | Fits | Use Case |
|-----------|------|----------|
| 256GB | ~20 Q4 models | Standard deployment |
| 512GB | ~40+ Q4 models | Multi-model testing, larger quantizations |
| 1TB | Extensive model library | Research, dataset storage |

### Orin Nano M.2 slot
- M-key, 2280 form factor
- PCIe Gen3 x4 (~3.5 GB/s max)
- Gen4 drives work but run at Gen3 speeds — no need to pay Gen4 premium

---

## LLM Model Reference

Only one model runs at a time on the 8GB Orin Nano (GPU VRAM limit). Use `model-switch` to swap between them.

| Model | Size (Q4_K_M) | Context | Gen Speed | Use Case |
|-------|--------------|---------|----------:|----------|
| Llama 3.2 1B | 0.7GB | 128K | ~80 t/s | Ultra-fast routing, classification |
| **Llama 3.2 3B** | **1.9GB** | **128K** | **~18 t/s** | **Primary agent model** |
| Phi-3.5 Mini 3.8B | 2.3GB | 128K | ~17 t/s | Strong reasoning |
| Qwen 2.5 3B | 2.0GB | 32K | ~18 t/s | Code / structured output |
| Llama 3.1 8B | 4.7GB | 128K | ~10 t/s | Highest quality; slower |
| Moondream2 | 1.9GB | 2K | ~15 t/s | Vision (lightweight) |
| Llama 3.2 Vision 11B | 6.2GB | 128K | ~7 t/s | Best vision + language; tight fit |

### Adding new models
```bash
# On picocrush:
sudo update-picocrush.sh add-model https://huggingface.co/.../model.gguf
sudo model-switch new-model.gguf
```

---

## Boot Device Notes

### MicroSD recommendations
- Use **high-endurance** cards rated for continuous writes
- Samsung PRO Endurance or SanDisk MAX Endurance recommended
- Avoid consumer cards (Samsung EVO, SanDisk Ultra) — lower write endurance
- A1/A2 application performance class preferred for random I/O

### NVMe recommendations (Orin Nano)
- Any M.2 2280 NVMe drive works
- Gen3 is sufficient (Orin slot is Gen3 x4)
- Gen4 drives work but run at Gen3 speeds
