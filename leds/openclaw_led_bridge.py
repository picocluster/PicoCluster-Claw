#!/usr/bin/env python3
"""
OpenClaw → LED Bridge

Monitors OpenClaw gateway logs and triggers LED API calls based on agent events.
Runs as a sidecar alongside the LED daemon.

Events detected:
  - Agent run start → set_status purple
  - Agent tool use → set_status cyan
  - Agent run end (success) → pulse_success
  - Agent run end (error) → pulse_error
  - Idle (no events for 5s) → clear (return to scanner)
"""

import subprocess
import time
import json
import urllib.request
import re
import sys

LED_API = "http://127.0.0.1:7777"
OPENCLAW_CONTAINER = "openclaw"
IDLE_TIMEOUT = 5  # seconds before clearing LED state


def led_call(endpoint, data=None):
    """Call the LED API."""
    try:
        body = json.dumps(data or {}).encode()
        req = urllib.request.Request(
            f"{LED_API}/{endpoint}",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=2)
    except Exception:
        pass


def main():
    print("OpenClaw LED bridge starting...")
    print(f"Monitoring container: {OPENCLAW_CONTAINER}")
    print(f"LED API: {LED_API}")

    last_event_time = time.time()
    is_active = False

    # Follow OpenClaw container logs
    proc = subprocess.Popen(
        ["docker", "logs", "-f", "--since", "1s", OPENCLAW_CONTAINER],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    try:
        for line in proc.stdout:
            now = time.time()

            # Detect agent run start
            if "embedded_run_agent_start" in line or "agent:run:start" in line:
                led_call("set_status", {"color": "purple", "message": "thinking"})
                last_event_time = now
                is_active = True

            # Detect tool use
            elif "tool_call" in line or "agent:tool" in line or "[tools]" in line:
                led_call("set_status", {"color": "cyan", "message": "using tool"})
                last_event_time = now
                is_active = True

            # Detect agent run end (success)
            elif ("embedded_run_agent_end" in line and "isError\":false" in line) or \
                 ("agent:run:end" in line and "error" not in line.lower()):
                led_call("pulse_success")
                last_event_time = now
                is_active = True

            # Detect agent run end (error)
            elif ("embedded_run_agent_end" in line and "isError\":true" in line) or \
                 "agent:run:error" in line:
                led_call("pulse_error")
                last_event_time = now
                is_active = True

            # Detect message delivery
            elif "message_send" in line or "Message delivered" in line:
                led_call("pulse_success")
                last_event_time = now

            # Clear after idle timeout
            if is_active and (now - last_event_time) > IDLE_TIMEOUT:
                led_call("clear")
                is_active = False

    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()
        led_call("clear")


if __name__ == "__main__":
    main()
