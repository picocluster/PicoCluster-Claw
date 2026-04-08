# PicoCluster Storage Options — RPi5 + Orin Nano

> **Pricing updated April 2026.** NVMe prices have risen significantly due to AI-driven NAND shortages.

## Current NVMe Pricing (April 2026)

| Capacity | Approx. Price | Notes |
|----------|-------------:|-------|
| 256GB    | ~$75         | M.2 2280, Gen3/Gen4 |
| 512GB    | ~$125        | |
| 1TB      | ~$200        | |

---

## Storage Requirements by Node

### RPi5 (OpenClaw orchestrator)
- OS (Raspberry Pi OS Lite 64-bit): ~4GB
- Node.js + OpenClaw + deps: ~2-4GB
- Browser automation stack (Playwright/Chromium): ~1-2GB
- Logs, cache, workspace: ~5-10GB
- **Total footprint:** ~12-20GB

### Orin Nano (llama.cpp inference)
- OS lives on eMMC (57GB onboard, non-replaceable) — adequate
- NVMe is for model storage + llama.cpp build
- Default model set (~11GB):
  - Llama 3.2 3B Q4_K_M: 1.9GB
  - Llama 3.1 8B Q4_K_M: 4.7GB
  - Phi-3.5 Mini Q4_K_M: 2.3GB
  - Qwen 2.5 3B Q4_K_M: 2.0GB
- Optional models:
  - Moondream2 (vision): 1.9GB
  - Llama 3.2 Vision 11B Q4_K_M: 6.2GB

---

## Recommended Configurations

### Low Cost (Recommended)

| Node | Storage | Est. Cost | Notes |
|------|---------|----------:|-------|
| RPi5 | 64GB microSD | ~$12 | Samsung PRO Endurance or SanDisk MAX Endurance |
| Orin Nano | 256GB NVMe | ~$75 | OS on eMMC, models + llama.cpp on NVMe |
| **Per pair** | | **~$87** | |
| **5-pair cluster** | | **~$435** | |

Why this works:
- RPi5 workload is ~15GB and mostly read-heavy (OpenClaw orchestration, not constant writes)
- High-endurance microSD cards are rated for continuous writes and cost a fraction of NVMe + HAT
- 256GB NVMe on Orin fits 20+ quantized models comfortably
- Saves ~$50-60 per node vs NVMe on RPi5

### Mid-Range

| Node | Storage | Est. Cost | Notes |
|------|---------|----------:|-------|
| RPi5 | 128GB microSD | ~$20 | Extra headroom for logs and workspace |
| Orin Nano | 512GB NVMe | ~$125 | Room for large models and future additions |
| **Per pair** | | **~$145** | |
| **5-pair cluster** | | **~$725** | |

### Performance (NVMe on both)

| Node | Storage | Est. Cost | Notes |
|------|---------|----------:|-------|
| RPi5 | 256GB NVMe + M.2 HAT | ~$100 | NVMe (~$75) + HAT (~$25) |
| Orin Nano | 512GB NVMe | ~$125 | Future-proof model storage |
| **Per pair** | | **~$225** | |
| **5-pair cluster** | | **~$1,125** | |

Only justified if the RPi5 is doing heavy write workloads (large datasets, constant logging, database). For OpenClaw agent orchestration, microSD is sufficient.

---

## RPi5 Storage Details

### microSD (Recommended for cost)

| Capacity | Card | Est. Cost | Notes |
|----------|------|----------:|-------|
| 64GB | Samsung PRO Endurance | ~$12 | Write-optimized, rated for continuous writes |
| 128GB | Samsung PRO Endurance | ~$20 | Extra headroom |
| 128GB | SanDisk MAX Endurance | ~$20 | Alternative, similar endurance rating |

- Pros: No extra hardware, lowest cost, fits any case
- Cons: Slower than NVMe (~100 MB/s vs ~800 MB/s), wear risk under heavy writes
- Verdict: **Best value for OpenClaw appliance.** The workload is read-heavy; endurance-rated cards handle it fine.

### NVMe via M.2 HAT (Performance option)

| Component | Est. Cost |
|-----------|----------:|
| 256GB NVMe (2280) | ~$75 |
| M.2 HAT (Pimoroni NVMe Base / Pineboards HatDrive) | ~$15-25 |
| **Total** | **~$90-100** |

- Pros: Fast (~800+ MB/s), reliable, clean cable-free mounting
- Cons: 5-8x the cost of microSD, adds height to RPi5 stack, check case clearance
- Verdict: Only if write-heavy workloads justify the cost.

> **Case note:** Check PicoCluster acrylic case clearance before ordering a HAT. 2242 form factor is shorter and fits more cases; top-mount HATs with 2280 drives may conflict with case lids.

---

## Orin Nano Storage Details

The Orin Nano Dev Kit has:
- **eMMC:** 57GB onboard (not removable) — OS lives here, adequate
- **M.2 slot:** M-key, 2280, PCIe Gen3 x4 — models go here

The eMMC handles the OS + llama.cpp binary + systemd config. The NVMe is purely for model storage.

| Capacity | Est. Cost | Fits | Notes |
|----------|----------:|------|-------|
| 256GB | ~$75 | ~20+ Q4 models | **Recommended — covers current and near-future needs** |
| 512GB | ~$125 | ~40+ Q4 models | Future-proof, room for large vision models |
| 1TB | ~$200 | Overkill for one node | Only if also storing datasets or scratch space |

> **Gen3 note:** The Orin Nano M.2 slot is PCIe Gen3 x4 (~3.5 GB/s max). Gen4 drives work but run at Gen3 speeds. No need to pay Gen4 premium unless using the same drives elsewhere.

---

## LLM Model Storage Reference

| Model | Size (Q4_K_M) | Context | Gen Speed | Use Case |
|-------|--------------|---------|----------:|----------|
| Llama 3.2 1B | 0.7GB | 128K | ~80 t/s | Ultra-fast routing, classification |
| **Llama 3.2 3B** | **1.9GB** | **128K** | **~18 t/s** | **Primary agent model** |
| Phi-3.5 Mini 3.8B | 2.3GB | 128K | ~17 t/s | Strong reasoning |
| Qwen 2.5 3B | 2.0GB | 32K | ~18 t/s | Code / structured output |
| Llama 3.1 8B | 4.7GB | 128K | ~10 t/s | Highest quality; slower |
| Moondream2 | 1.9GB | 2K | ~15 t/s | Vision (lightweight) |
| Llama 3.2 Vision 11B | 6.2GB | 128K | ~7 t/s | Best vision + language; tight fit |

Default set (4 models): ~11GB
Full set (all 7): ~20GB
