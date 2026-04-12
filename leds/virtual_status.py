#!/usr/bin/env python3
"""
PicoCluster Claw — Virtual LED Status Daemon (Mac Solo Edition)

Replaces the GPIO Blinkt! LED daemon on non-GPIO platforms (Mac Mini, etc).
Exposes the exact same HTTP API on port 7777 so all existing consumers
(ThreadWeaver MCP, OpenClaw bridge, shutdown API, agent notifier) work
unchanged. State is served via GET /status for web-based rendering.

POST endpoints (same as led_api.py):
  POST /set_status     {"color": "blue", "duration": 10}
  POST /set_progress   {"percent": 50, "color": "green"}
  POST /pulse_success  {}
  POST /pulse_error    {"message": "..."}
  POST /flash          {"color": "red", "duration": 90}
  POST /clear          {}

GET endpoint (new, for web rendering):
  GET /status          Returns current state as JSON

Optional macOS notifications for error/flash states.

Usage:
  python3 virtual_status.py [--port 7777] [--notify]
"""

import sys
import os
import json
import time
import subprocess
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler

# --------------------------------------------------------------------------
# State (matches led_api.py exactly)
# --------------------------------------------------------------------------
COLOR_MAP = {
    "red":    (255, 0, 0),
    "green":  (0, 255, 0),
    "blue":   (0, 60, 255),
    "amber":  (255, 140, 0),
    "orange": (255, 40, 0),
    "cyan":   (0, 200, 255),
    "purple": (120, 0, 255),
    "white":  (255, 255, 255),
    "off":    (0, 0, 0),
}

# Reverse lookup for JSON responses
COLOR_NAMES = {v: k for k, v in COLOR_MAP.items()}

_state = {
    "mode": "idle",       # idle, status, progress, pulse_success, pulse_error, flash
    "color": None,        # (r, g, b) or None
    "color_name": None,   # "blue", "red", etc.
    "message": "",
    "percent": 0,
    "timestamp": 0,
    "duration": 0,
}
_lock = threading.Lock()
_notify_enabled = False


def get_state():
    """Get current LED state with auto-expiry."""
    with _lock:
        if _state["duration"] > 0:
            elapsed = time.time() - _state["timestamp"]
            if elapsed >= _state["duration"]:
                _state["mode"] = "idle"
                _state["color"] = None
                _state["color_name"] = None
                _state["message"] = ""
                _state["percent"] = 0
                _state["duration"] = 0
        return dict(_state)


def set_state(**kwargs):
    """Update LED state."""
    with _lock:
        _state.update(kwargs)
        _state["timestamp"] = time.time()
        # Resolve color name
        if _state["color"] and _state["color"] in COLOR_NAMES:
            _state["color_name"] = COLOR_NAMES[_state["color"]]


def _run(cmd):
    """Run a shell command and return stdout."""
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return r.stdout.strip()
    except Exception as e:
        return f"error: {e}"


def _handle_sysinfo(metric):
    """Return macOS system info for the given metric."""
    import re

    if metric == "cpu":
        cores = _run("sysctl -n hw.ncpu")
        load = _run("sysctl -n vm.loadavg").strip("{ }")
        cpu_brand = _run("sysctl -n machdep.cpu.brand_string")
        return f"CPU: {cpu_brand}\nCores: {cores}\nLoad avg: {load}"

    elif metric == "memory":
        try:
            page_size = int(_run("sysctl -n hw.pagesize"))
            total = int(_run("sysctl -n hw.memsize"))
            vm = _run("vm_stat")
            pages = {}
            for line in vm.split("\n"):
                m = re.match(r'(.+?):\s+(\d+)', line)
                if m:
                    pages[m.group(1).strip().lower()] = int(m.group(2))
            active = pages.get("pages active", 0) * page_size
            wired = pages.get("pages wired down", 0) * page_size
            compressed = pages.get("pages occupied by compressor", 0) * page_size
            used = active + wired + compressed
            avail = total - used
            def fmt(b):
                gb = b / (1024**3)
                return f"{gb:.1f} GB" if gb >= 1 else f"{b / (1024**2):.0f} MB"
            return f"Total: {fmt(total)}, Used: {fmt(used)}, Available: {fmt(avail)}"
        except Exception as e:
            return f"error: {e}"

    elif metric == "disk":
        return _run("df -h / | tail -1")

    elif metric == "temperature":
        # Try powermetrics (needs sudo)
        try:
            r = subprocess.run(
                ["sudo", "-n", "powermetrics", "--samplers", "smc", "-n", "1", "-i", "1"],
                capture_output=True, text=True, timeout=5
            )
            if r.returncode == 0:
                for line in r.stdout.split("\n"):
                    if "die temperature" in line.lower() or "cpu die" in line.lower():
                        m = re.search(r'(\d+\.?\d*)\s*C', line)
                        if m:
                            c = float(m.group(1))
                            return f"CPU temperature: {c:.1f}C ({c * 9/5 + 32:.1f}F)"
        except Exception:
            pass
        return "CPU temperature: not available (requires sudo or osx-cpu-temp)"

    elif metric == "uptime":
        return _run("uptime")

    elif metric == "network":
        output = _run("ifconfig")
        result = []
        current_iface = None
        for line in output.split("\n"):
            if not line.startswith("\t") and ":" in line:
                current_iface = line.split(":")[0]
            elif "inet " in line and current_iface:
                ip = line.strip().split()[1]
                if not ip.startswith("127."):
                    result.append(f"{current_iface}: {ip}")
        return "\n".join(result) if result else "No active network interfaces"

    return f"Unknown metric: {metric}"


def macos_notify(title, message):
    """Send a macOS notification (non-blocking)."""
    if not _notify_enabled:
        return
    try:
        subprocess.Popen([
            "osascript", "-e",
            f'display notification "{message}" with title "PicoCluster Claw" subtitle "{title}"'
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


# --------------------------------------------------------------------------
# HTTP handler — same POST API as led_api.py + GET /status
# --------------------------------------------------------------------------
class VirtualLEDHandler(BaseHTTPRequestHandler):

    def do_GET(self):
        if self.path == "/status":
            state = get_state()
            resp = {
                "mode": state["mode"],
                "color": state.get("color_name"),
                "message": state["message"],
                "percent": state["percent"],
                "timestamp": state["timestamp"],
                "duration": state["duration"],
                "remaining": max(0, state["duration"] - (time.time() - state["timestamp"])) if state["duration"] > 0 else 0,
            }
            self._respond(200, resp)
        elif self.path == "/health":
            self._respond(200, {"status": "ok", "type": "virtual"})
        elif self.path.startswith("/sysinfo/"):
            # System info endpoints — exposed so Docker containers can query
            # macOS host stats via host.docker.internal:7777/sysinfo/{metric}
            metric = self.path.split("/sysinfo/", 1)[1]
            result = _handle_sysinfo(metric)
            self._respond(200, {"metric": metric, "result": result})
        elif self.path == "/sysinfo":
            self._respond(200, {
                "metrics": ["cpu", "memory", "disk", "temperature", "uptime", "network"],
                "platform": "darwin",
            })
        else:
            self._respond(404, {"error": "unknown endpoint"})

    def do_POST(self):
        content_len = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(content_len)) if content_len else {}

        if self.path == "/set_status":
            color_name = body.get("color", "blue")
            color = COLOR_MAP.get(color_name, COLOR_MAP["blue"])
            duration = body.get("duration", 10)
            set_state(mode="status", color=color, color_name=color_name,
                      message=body.get("message", ""), duration=duration)
            self._respond(200, {"status": "ok", "mode": "status", "color": color_name, "duration": duration})

        elif self.path == "/set_progress":
            percent = max(0, min(100, body.get("percent", 0)))
            color_name = body.get("color", "green")
            color = COLOR_MAP.get(color_name, COLOR_MAP["green"])
            duration = body.get("duration", 30)
            set_state(mode="progress", color=color, color_name=color_name,
                      percent=percent, message=body.get("message", ""), duration=duration)
            self._respond(200, {"status": "ok", "mode": "progress", "percent": percent, "duration": duration})

        elif self.path == "/pulse_success":
            set_state(mode="pulse_success", color=COLOR_MAP["green"], color_name="green",
                      message=body.get("message", ""), duration=2)
            macos_notify("Success", body.get("message", "Operation completed"))
            self._respond(200, {"status": "ok", "mode": "pulse_success"})

        elif self.path == "/pulse_error":
            msg = body.get("message", "An error occurred")
            set_state(mode="pulse_error", color=COLOR_MAP["red"], color_name="red",
                      message=msg, duration=3)
            macos_notify("Error", msg)
            self._respond(200, {"status": "ok", "mode": "pulse_error"})

        elif self.path == "/flash":
            color_name = body.get("color", "red")
            color = COLOR_MAP.get(color_name, COLOR_MAP["red"])
            duration = body.get("duration", 90)
            msg = body.get("message", "")
            set_state(mode="flash", color=color, color_name=color_name,
                      message=msg, duration=duration)
            if color_name == "red":
                macos_notify("Alert", msg or "LED flash alert")
            self._respond(200, {"status": "ok", "mode": "flash", "color": color_name, "duration": duration})

        elif self.path == "/clear":
            set_state(mode="idle", color=None, color_name=None,
                      message="", percent=0, duration=0)
            self._respond(200, {"status": "ok", "mode": "idle"})

        else:
            self._respond(404, {"error": "unknown endpoint"})

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def _respond(self, code, data):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, format, *args):
        pass  # Suppress access logs


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def main():
    global _notify_enabled

    port = 7777
    args = sys.argv[1:]
    if "--port" in args:
        port = int(args[args.index("--port") + 1])
    if "--notify" in args:
        _notify_enabled = True

    print(f"PicoCluster Claw Virtual LED Daemon v1.0")
    print(f"  Port: {port}")
    print(f"  Notifications: {'enabled' if _notify_enabled else 'disabled'}")
    print(f"  GET /status for web rendering")
    print(f"  POST endpoints match Blinkt! GPIO daemon")
    print()

    server = HTTPServer(("0.0.0.0", port), VirtualLEDHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down virtual LED daemon")
        server.server_close()


if __name__ == "__main__":
    main()
