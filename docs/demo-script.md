# PicoCluster Claw Demo Script

A step-by-step walkthrough for live demos, videos, or trade shows. Total time: ~10 minutes.

> **Note:** Adjust hostnames and IPs to match your configuration. Defaults shown.

---

## Setup (before the demo)

1. Both nodes powered on and booted
2. Blinkt! scanner animation running on picocluster-claw
3. Browser open to `http://picocluster-claw` (portal)
4. Second browser tab ready for ThreadWeaver

---

## Act 1: The Appliance (~2 min)

**Show the hardware:**
> "This is PicoCluster Claw — a self-hosted AI agent appliance. Two boards: a Raspberry Pi 5 running the web interfaces, and an NVIDIA Jetson Orin Nano running local AI models. The whole thing draws 14 watts at idle — less than a light bulb."

**Point to the Blinkt!:**
> "See the LED scanning back and forth? That's the idle animation. It blinks, looks around — it has personality. Watch..."

*Wait for it to do a look-around or blink*

> "When the AI is thinking, you'll see it light up. Let me show you."

---

## Act 2: Chat with Your Local AI (~3 min)

**Open ThreadWeaver:** `http://picocluster-claw:5173`

> "This is ThreadWeaver — a chat interface that talks directly to the Llama 3.2 model running on the Jetson's GPU. No cloud. No API keys. Everything stays on your network."

**Send a message:**
> Type: "Hello! What can you help me with?"

*Point to the Blinkt! — it should flash white then show the green/cyan chase animation*

> "See the LEDs? Green means the AI is generating a response. The Jetson's GPU is working right now."

*Response arrives, LEDs flash green then return to scanner*

> "And it's back to scanning. Let's try something more fun."

**Switch models:**
> "We have 9 models installed. Let me switch to DeepSeek R1 — it's a reasoning model that shows its thought process."

*Select deepseek-r1:7b in the model dropdown*

> Type: "What's the most efficient way to sort a million integers?"

*Point to the LEDs during the longer response*

---

## Act 3: The LEDs Talk Back (~2 min)

> "Here's where it gets interesting. The AI can actually control the physical LEDs. Watch this."

**Type in ThreadWeaver:**
> "Make the LEDs purple"

*Blinkt! turns purple*

> "The AI called an MCP tool — a standard protocol for AI tool use — that controls the LED strip. It figured out the right color from natural language."

**Type:**
> "Show me a progress bar at 50%"

*Half the LEDs fill up*

**Type:**
> "Now take it to 100% and celebrate"

*Full bar, then green burst*

> "It's reading the tool descriptions and deciding how to use them. No hardcoded commands — just conversation."

**Type:**
> "Clear the LEDs"

*Back to scanner*

---

## Act 4: The Portal (~1 min)

**Show the portal:** `http://picocluster-claw`

> "Every PicoCluster Claw comes with this portal. Live status of all services, model list, management commands, and these LED controls..."

*Click a few color buttons, slide the progress bar*

> "The user can control everything from a browser. Restart the cluster, check service health, play with the LEDs."

---

## Act 5: The Numbers (~1 min)

> "Let's talk about what this costs to run."

*Point to the portal's hardware section or recite:*

> "14 watts idle. 20 watts when the AI is working. That's about $2 a month in electricity. Compare that to a cloud API — GPT-4 at $30 per million tokens, or running your own GPU server at hundreds of watts."

> "Nine models included — general purpose, reasoning, code generation, and two vision models. All running on the Jetson's GPU, all switching automatically."

---

## Act 6: Privacy (~30 sec)

> "The key thing: nothing leaves your network. No API keys. No data sent to the cloud. Your conversations, your data, your models — all local. The Jetson's firewall only allows the Raspberry Pi to talk to it. Everything else is blocked."

---

## Closing

> "PicoCluster Claw. Private AI that fits on your desk, runs on 14 watts, and costs $2 a month. The LED is just showing off."

*Send one more message in ThreadWeaver to trigger the light show*

---

## Backup Demos (if time permits)

### Vision Model
Switch to `llava:7b`, upload a screenshot:
> "This model can understand images. I just uploaded a screenshot of our portal and it's describing what it sees."

### Code Generation
Switch to `starcoder2:3b`:
> "Write me a Python function that calculates Fibonacci numbers"

### OpenClaw Agent
> "We also have OpenClaw — a full AI agent that can browse the web, use tools, and automate tasks. That's the next level."

---

## Troubleshooting During Demo

| Problem | Quick Fix |
|---------|-----------|
| LEDs not responding | `sudo systemctl restart picocluster-claw-leds` on picocluster-claw |
| ThreadWeaver won't load | `sudo docker restart threadweaver` on picocluster-claw |
| Model not responding | `ssh picocrush` then `ollama list` to verify |
| LED MCP tools missing | Restart ThreadWeaver — auto-connects on startup |
