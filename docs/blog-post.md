# Talk to Your AI and Watch It Light Up: Building PicoCluster Claw

*A self-hosted AI appliance that runs 9 models on 14 watts — and has a personality.*

---

## The Idea

What if you could have your own private AI that lives on your desk, costs less than a cup of coffee per month to run, and physically lights up when it's thinking?

That's PicoCluster Claw — a two-board AI appliance that pairs a Raspberry Pi 5 with an NVIDIA Jetson Orin Nano. The Pi handles the web interfaces. The Jetson runs the models. Between them sits a strip of 8 RGB LEDs that turns natural conversation into a light show.

## The Hardware

PicoCluster Claw is built on PicoCluster hardware:

- **picocluster-claw (RPi5 8GB)** — Runs Docker containers for ThreadWeaver (chat UI), OpenClaw (AI agent), and a landing portal. A Pimoroni Blinkt! LED strip on the GPIO header provides visual feedback.
- **picocrush (Orin Nano Super 8GB)** — Runs Ollama with 9 GGUF models on the Jetson's GPU. Inference at 12-18 tokens per second on 3B models.

Total power draw: 14W idle, 20W typical. That's $2/month in electricity.

## 9 Models, Zero Cloud

Ollama manages model loading automatically. Ask a coding question? Use StarCoder2. Need to understand a screenshot? Switch to LLaVA. Want chain-of-thought reasoning? DeepSeek R1 shows its work.

All models run locally on the Jetson's CUDA GPU. No API keys. No data leaves your network. The Pi's firewall restricts the inference endpoint to local traffic only.

| Model | Type | Speed |
|-------|------|-------|
| Llama 3.2 3B | General | ~18 tok/s |
| Gemma 3 4B | Multilingual | ~15 tok/s |
| DeepSeek R1 7B | Reasoning | ~10 tok/s |
| StarCoder2 3B | Code | ~18 tok/s |
| LLaVA 7B | Vision | ~10 tok/s |
| + 4 more | | |

## The Eye

The Blinkt! LED strip does more than blink. It has behaviors:

**Idle:** A single pixel scans back and forth like a Cylon eye, drifting through blues and purples. Every few seconds it pauses, looks left, looks right — like a curious eye checking its surroundings. Occasionally it blinks.

**Thinking:** When any client sends a request to the LLM, the scanner bursts into a colorful chase — cycling through greens, cyans, limes, and sky blues. A white flash marks the start. A green burst marks completion. Then the eye resumes scanning.

**Status:** The LED daemon monitors all three services (ThreadWeaver, OpenClaw, Ollama). Amber pulse means degraded. Red means down. All green means everything's healthy.

All of this happens automatically — no configuration needed.

## The First LED MCP Server

Here's where it gets interesting. We built an MCP server that exposes the LEDs as tools.

MCP (Model Context Protocol) is the emerging standard for giving AI models access to external tools. Our MCP server registers 5 tools: `set_led_color`, `set_led_progress`, `led_pulse_success`, `led_pulse_error`, and `clear_leds`.

When you tell your AI "make the LEDs purple," it calls the tool. When you say "show me progress," it fills the LED bar. When you say "celebrate," it triggers a burst animation.

The AI reads the tool descriptions and figures out what to do from natural language. No hardcoded commands. No special syntax. Just conversation.

This is — as far as we know — the first MCP server that controls physical hardware. A bridge between AI tool use and the real world, running on a $200 appliance.

## The Portal

Every PicoCluster Claw ships with a landing page at `http://picocluster-claw`. Live service status, links to all interfaces, LED controls, cluster management, and shutdown buttons. One URL to manage everything.

## One Command to Install

```bash
# On picocrush (Orin Nano):
sudo bash install-picocrush.sh

# On picocluster-claw (RPi5):
sudo bash install-picocluster-claw.sh
```

That's it. Flash the golden images, run two scripts, and you have a private AI appliance with:
- 9 LLM models (27GB)
- Chat UI with branching conversations
- AI agent with browser automation
- Physical LED status and tool control
- HTTPS dashboard
- Auto-updating containers

## The Cost

| | PicoCluster Claw | Cloud API |
|---|------:|------:|
| Hardware (one-time) | ~$350 | $0 |
| Monthly electricity | $2 | — |
| Monthly API cost | $0 | $50-500+ |
| Privacy | Complete | None |
| Models | 9 local | Provider's choice |
| Internet required | No | Yes |

After 2-3 months, PicoCluster Claw pays for itself if you were spending $50+/month on cloud APIs. After that, it's $2/month forever. And your data never leaves your desk.

## What's Next

- **Community installer** for BYO hardware
- **Telegram/Discord channels** for mobile access
- **Pre-built Docker images** to skip build time
- **More LED effects** — fireworks for special events, custom user animations

PicoCluster Claw is open source at [github.com/picocluster/PicoCluster-Claw](https://github.com/picocluster/PicoCluster-Claw).

---

*Built with PicoCluster hardware, ThreadWeaver, OpenClaw, Ollama, and one very opinionated LED strip.*
