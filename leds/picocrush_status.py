#!/usr/bin/env python3
"""
PicoCrush LED status daemon — runs on picocrush (Orin Nano).

Boot sequence:
  1. Rainbow sweep on startup
  2. Orange fill as CUDA initializes
  3. Amber progress bar as llama-server loads model
  4. Green pulse when llama-server health check passes

Runtime status:
  - Dim blue: idle, model loaded
  - Orange fill: prompt processing (prefill)
  - Green pulse: token generation
  - All off: llama-server stopped
  - Red: GPU error / overtemp

Monitors llama-server health on http://127.0.0.1:8080/health
and inference activity via /slots endpoint.
"""

import sys
import os
import time
import math
import signal
import json
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apa102 import Blinkt, sweep, fill, pulse, rainbow_cycle, flash, NUM_LEDS

LLAMA_HEALTH_URL = "http://127.0.0.1:8080/health"
LLAMA_SLOTS_URL = "http://127.0.0.1:8080/slots"
POLL_INTERVAL = 1  # seconds between status checks
BOOT_TIMEOUT = 180  # model loading can take a while
THERMAL_WARN = 80.0  # degrees C

running = True


def signal_handler(sig, frame):
    global running
    running = False


def check_llama_health():
    """Check if llama-server is healthy."""
    try:
        resp = urllib.request.urlopen(LLAMA_HEALTH_URL, timeout=3)
        data = json.loads(resp.read())
        return data.get("status") == "ok"
    except Exception:
        return False


def check_llama_busy():
    """Check if llama-server is actively processing inference."""
    try:
        resp = urllib.request.urlopen(LLAMA_SLOTS_URL, timeout=2)
        slots = json.loads(resp.read())
        for slot in slots:
            state = slot.get("state", 0)
            if state != 0:  # 0 = idle
                return True
        return False
    except Exception:
        return False


def read_gpu_temp():
    """Read GPU/SoC temperature on Jetson."""
    try:
        with open("/sys/devices/virtual/thermal/thermal_zone0/temp", "r") as f:
            return float(f.read().strip()) / 1000.0
    except Exception:
        return 0.0


def check_network():
    """Check if network is up."""
    try:
        import subprocess
        result = subprocess.run(
            ["ip", "-4", "route", "show", "default"],
            capture_output=True, text=True, timeout=5,
        )
        return "default" in result.stdout
    except Exception:
        return False


def boot_sequence(leds):
    """Visual boot sequence — run once at startup."""
    # Stage 1: Rainbow — "I'm alive"
    rainbow_cycle(leds, cycles=1, delay=0.015, brightness=0.15)

    # Stage 2: Orange sweep — CUDA initializing
    for _ in range(3):
        sweep(leds, 255, 100, 0, delay=0.04, brightness=0.3)
        if check_network():
            break

    # Stage 3: Amber progress — waiting for llama-server to load model
    fill(leds, 255, 140, 0, delay=0.06, brightness=0.2)

    start = time.time()
    while time.time() - start < BOOT_TIMEOUT and running:
        elapsed = time.time() - start
        # Progress bar: amber fills up
        filled = min(NUM_LEDS, int((elapsed / BOOT_TIMEOUT) * NUM_LEDS) + 1)
        for i in range(NUM_LEDS):
            if i < filled:
                br = 0.1 + 0.15 * math.sin(time.time() * 2) ** 2
                leds.set_pixel(i, 255, 140, 0, br)
            else:
                leds.set_pixel(i, 0, 0, 0, 0)
        leds.show()
        time.sleep(0.15)

        if check_llama_health():
            # Model loaded — celebrate!
            flash(leds, 0, 255, 0, times=3, on_time=0.15, off_time=0.1, brightness=0.4)
            return True

    # Timeout
    flash(leds, 255, 0, 0, times=5, on_time=0.2, off_time=0.1, brightness=0.4)
    return False


def idle_pattern(leds, step):
    """Dim blue breathing — idle, model loaded."""
    br = 0.02 + 0.08 * (math.sin(step * 0.04) ** 2)
    leds.set_all(0, 20, 180, br)
    leds.show()


def inference_pattern(leds, step):
    """Green chase — actively generating tokens."""
    pos = step % (NUM_LEDS * 2)
    for i in range(NUM_LEDS):
        dist = abs(i - (pos % NUM_LEDS))
        if dist > NUM_LEDS // 2:
            dist = NUM_LEDS - dist
        br = max(0.02, 0.35 * (1.0 - dist / 4.0))
        leds.set_pixel(i, 0, 255, 40, max(0, br))
    leds.show()


def thermal_warning(leds, temp, step):
    """Red/orange pulse — thermal warning."""
    intensity = min(1.0, (temp - THERMAL_WARN) / 15.0)
    br = 0.15 + 0.35 * (math.sin(step * 0.15) ** 2) * intensity
    leds.set_all(255, int(40 * (1 - intensity)), 0, br)
    leds.show()


def error_pattern(leds, step):
    """Red pulse — server down."""
    br = 0.1 + 0.3 * (math.sin(step * 0.1) ** 2)
    leds.set_all(255, 0, 0, br)
    leds.show()


def runtime_loop(leds):
    """Main runtime loop — monitor llama-server and show status."""
    step = 0
    consecutive_failures = 0

    while running:
        # Check thermal
        temp = read_gpu_temp()
        if temp >= THERMAL_WARN:
            thermal_warning(leds, temp, step)
            step += 1
            time.sleep(0.1)
            continue

        # Check health every few steps
        if step % (POLL_INTERVAL * 10) == 0:
            healthy = check_llama_health()
            if not healthy:
                consecutive_failures += 1
            else:
                consecutive_failures = 0

        if consecutive_failures > 3:
            error_pattern(leds, step)
        elif consecutive_failures > 0:
            # Brief hiccup
            leds.set_all(255, 100, 0, 0.05)
            leds.show()
        else:
            # Check if actively inferencing
            busy = check_llama_busy() if step % 5 == 0 else False
            if busy:
                inference_pattern(leds, step)
            else:
                idle_pattern(leds, step)

        step += 1
        time.sleep(0.1)


def main():
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    with Blinkt(platform="orin", brightness=0.2) as leds:
        boot_sequence(leds)
        if running:
            runtime_loop(leds)


if __name__ == "__main__":
    main()
