#!/usr/bin/env python3
"""
PicoClaw LED status daemon — runs on picoclaw (RPi5).

Boot sequence:
  1. Rainbow sweep on startup
  2. Blue fill as services come up
  3. Green pulse when OpenClaw gateway is ready

Runtime status:
  - Breathing blue: idle, waiting for commands
  - Green chase: agent processing
  - White flash: sending to LLM
  - Solid green: response received
  - Red: error state

Monitors OpenClaw gateway health on http://127.0.0.1:18789
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

GATEWAY_HEALTH_URL = "http://127.0.0.1:18789/__openclaw__/canvas/"
GATEWAY_PORT = 18789
POLL_INTERVAL = 3  # seconds between health checks
BOOT_TIMEOUT = 120  # max seconds to wait for gateway during boot

running = True


def signal_handler(sig, frame):
    global running
    running = False


def check_gateway():
    """Check if OpenClaw gateway is responding."""
    try:
        req = urllib.request.Request(
            f"http://127.0.0.1:{GATEWAY_PORT}/__openclaw__/canvas/",
            method="HEAD",
        )
        resp = urllib.request.urlopen(req, timeout=3)
        return resp.status < 500
    except Exception:
        return False


def check_network():
    """Check if network interface has an IP."""
    try:
        import subprocess
        result = subprocess.run(
            ["ip", "-4", "addr", "show", "dev", "eth0"],
            capture_output=True, text=True, timeout=5,
        )
        return "inet " in result.stdout
    except Exception:
        return False


def boot_sequence(leds):
    """Visual boot sequence — run once at startup."""
    # Stage 1: Rainbow — "I'm alive"
    rainbow_cycle(leds, cycles=1, delay=0.015, brightness=0.15)

    # Stage 2: Blue sweep — waiting for network
    for attempt in range(20):
        sweep(leds, 0, 0, 255, delay=0.04, brightness=0.3)
        if check_network():
            break

    # Stage 3: Blue fill — network up, waiting for OpenClaw
    fill(leds, 0, 80, 255, delay=0.06, brightness=0.2)

    # Stage 4: Wait for gateway with amber pulsing progress
    start = time.time()
    while time.time() - start < BOOT_TIMEOUT and running:
        elapsed = time.time() - start
        # Progress fill: amber LEDs fill up as we wait
        filled = min(NUM_LEDS, int((elapsed / BOOT_TIMEOUT) * NUM_LEDS) + 1)
        for i in range(NUM_LEDS):
            if i < filled:
                br = 0.1 + 0.15 * math.sin(time.time() * 3) ** 2
                leds.set_pixel(i, 255, 140, 0, br)
            else:
                leds.set_pixel(i, 0, 0, 40, 0.05)
        leds.show()
        time.sleep(0.1)

        if check_gateway():
            # Gateway is up — celebrate!
            flash(leds, 0, 255, 0, times=3, on_time=0.15, off_time=0.1, brightness=0.4)
            return True

    # Timeout — gateway didn't start
    flash(leds, 255, 0, 0, times=5, on_time=0.2, off_time=0.1, brightness=0.4)
    return False


def idle_breathing(leds, step):
    """Breathing blue — idle state."""
    br = 0.03 + 0.12 * (math.sin(step * 0.05) ** 2)
    leds.set_all(0, 40, 255, br)
    leds.show()


def error_pattern(leds, step):
    """Red pulse — error state."""
    br = 0.1 + 0.3 * (math.sin(step * 0.1) ** 2)
    leds.set_all(255, 0, 0, br)
    leds.show()


def runtime_loop(leds):
    """Main runtime loop — monitor gateway and show status."""
    step = 0
    consecutive_failures = 0

    while running:
        gateway_ok = check_gateway()

        if gateway_ok:
            consecutive_failures = 0
            idle_breathing(leds, step)
        else:
            consecutive_failures += 1
            if consecutive_failures > 3:
                error_pattern(leds, step)
            else:
                # Brief hiccup — dim blue
                leds.set_all(0, 20, 100, 0.05)
                leds.show()

        step += 1
        time.sleep(0.1)

        # Full health check every POLL_INTERVAL seconds
        if step % (POLL_INTERVAL * 10) == 0:
            pass  # health check runs every iteration anyway for responsiveness


def main():
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    with Blinkt(platform="rpi5", brightness=0.2) as leds:
        gateway_ready = boot_sequence(leds)
        if running:
            runtime_loop(leds)


if __name__ == "__main__":
    main()
