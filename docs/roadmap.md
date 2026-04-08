# PicoClaw Appliance — Roadmap

## Architecture
- **RPi5 "claw" (8GB)** — Runs OpenClaw (agent orchestrator, browser automation, tool use)
- **Orin Nano Super "crush" (8GB)** — Dedicated local LLM inference via llama.cpp server
- Shared case, shared power, shared network

## Phase 1: Benchmarking (COMPLETE ✅)
- [x] Orin Nano power draw characterization across 15W / 25W / MAXN
- [x] LLM inference benchmarks (TinyLlama 1.1B, Phi-3 3.8B, Llama 3.2 3B)
- [x] Thermal analysis — no throttling detected
- [x] I/O stress testing (NVMe + network) — true headless max: 20.4W at MAXN
- [x] PDU validation — all 3 ports tested at 12V, held 1.81A sustained (21% over 1.5A spec), all cool

## Phase 2: Tooling & Infrastructure (COMPLETE ✅)
- [x] Orin Nano imaging: jetson-shrink.sh (dd capture → shrink → gzip)
- [x] Orin Nano resize: resize_ubuntu.sh (expand rootfs after flash)
- [x] Orin Nano NVMe boot: sd-to-nvme.sh (migrate SD → NVMe)
- [x] Node configuration: configure-pair.sh (IPs, hostnames, config files)
- [x] Ansible playbook structure (site.yml, validate.yml, roles)
- [x] Storage recommendations documented

## Phase 3: Golden Image Creation (NEXT)
- [ ] RPi5: build-rpi5-image.sh — strip + harden Raspbian
- [ ] Orin Nano: build-orin-image.sh — strip + harden JetPack
- [ ] Capture, shrink, and archive golden images
- See: picoclcaw-deployment-plan.md (Part 1)

## Phase 4: PicoClaw Software Install
- [ ] install-claw.sh — OpenClaw in Docker, secured, on RPi5
- [ ] install-crush.sh — llama.cpp + models on Orin Nano
- [ ] validate-pair.sh — end-to-end health and connectivity
- [ ] OpenClaw security hardening (Docker, loopback, token auth, no ClawHub)
- See: picoclcaw-deployment-plan.md (Part 2)

## Phase 5: Community Installer
- [ ] picoclcaw-setup.sh — all-in-one for BYO hardware
- [ ] Auto-detect hardware (RPi5 vs Jetson)
- [ ] Interactive prompts for IP, models, options
- See: picoclcaw-deployment-plan.md (Part 3)

## Phase 6: Power Draw & Validation
- [ ] Both nodes in PicoClaw acrylic case
- [ ] Idle, inference, sustained load power profiles
- [ ] Thermal validation in enclosure under agent workload
- [ ] Two-node PDU load test (claw + crush simultaneously)
- [ ] Determine best model for computer use tasks
- [ ] Iterate on prompt/config until solid for cluster deployment

## Power Budget (Estimated)
| Node | Idle | Max Load |
|------|-----:|---------:|
| RPi5 (claw) | ~3W | ~12W |
| Orin Nano (crush) | ~5-9W | ~25W |
| **Total** | **~8-12W** | **~37W** |

Recommended PSU: 60W minimum with headroom

## Notes
- OpenClaw has had significant security issues in early 2026 — must run in Docker with full hardening
- Small model capability is improving rapidly — hardware stays the same, swap models as better ones release
- Orin Nano generation speed (12-18 tok/s on 3B models) is usable but not fast for agent workloads
- Context length matters for computer use — Llama 3.2 3B (128K) preferred over Phi-3 (4K)
- Multimodal model support may be needed if OpenClaw requires vision

## Key Files
| File | Purpose |
|------|---------|
| picoclcaw-deployment-plan.md | Detailed deployment plan (Parts 1-3) |
| storage-options.md | Storage sizing and pricing |
| benchmark-report.md | Power/performance data |
| ansible/REFERENCE.md | Ansible playbook reference |
| ansible/ | Ansible provisioning playbooks |
| jetson-shrink.sh | Shrink dd-captured Orin images |
| resize_ubuntu.sh | Expand rootfs after flashing |
| sd-to-nvme.sh | Migrate SD → NVMe boot |
| configure-pair.sh | Set IPs, hostnames, hook nodes together |
