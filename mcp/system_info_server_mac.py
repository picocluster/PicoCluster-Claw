#!/usr/bin/env python3
"""System Info MCP Server — macOS edition.

Same tool names and schemas as the Linux version (system_info_server.py)
so ThreadWeaver sees identical tools regardless of platform. Uses macOS
commands (sysctl, vm_stat, ifconfig) instead of Linux (/proc, free, ip).
"""

import os
import sys
import subprocess
import re

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp_base import run_server

TOOLS = [
    {
        "name": "get_cpu_info",
        "description": "Get CPU usage, load average, and core count.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_memory_info",
        "description": "Get RAM usage.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_disk_info",
        "description": "Get disk usage for the main filesystem.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_temperature",
        "description": "Get the CPU/SoC temperature (Apple Silicon).",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_uptime",
        "description": "Get how long this machine has been running.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_network_info",
        "description": "Get network interface info and IP addresses.",
        "inputSchema": {"type": "object", "properties": {}},
    },
]


def _run(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return r.stdout.strip()
    except Exception as e:
        return f"error: {e}"


def _get_memory_info():
    """Parse vm_stat + sysctl to get human-readable memory info."""
    try:
        page_size = int(_run("sysctl -n hw.pagesize"))
        total_bytes = int(_run("sysctl -n hw.memsize"))

        vm_stat = _run("vm_stat")
        # Parse page counts from vm_stat output
        pages = {}
        for line in vm_stat.split("\n"):
            match = re.match(r'(.+?):\s+(\d+)', line)
            if match:
                key = match.group(1).strip().lower()
                pages[key] = int(match.group(2))

        free = pages.get("pages free", 0) * page_size
        active = pages.get("pages active", 0) * page_size
        inactive = pages.get("pages inactive", 0) * page_size
        wired = pages.get("pages wired down", 0) * page_size
        compressed = pages.get("pages occupied by compressor", 0) * page_size

        used = active + wired + compressed
        available = total_bytes - used

        def fmt(b):
            gb = b / (1024**3)
            if gb >= 1:
                return f"{gb:.1f} GB"
            return f"{b / (1024**2):.0f} MB"

        return (
            f"Total:      {fmt(total_bytes)}\n"
            f"Used:       {fmt(used)}\n"
            f"Available:  {fmt(available)}\n"
            f"Active:     {fmt(active)}\n"
            f"Wired:      {fmt(wired)}\n"
            f"Compressed: {fmt(compressed)}\n"
            f"Inactive:   {fmt(inactive)}\n"
            f"Free:       {fmt(free)}"
        )
    except Exception as e:
        return f"Could not read memory info: {e}"


def _get_temperature():
    """Try to read Apple Silicon SoC temperature.

    powermetrics requires root, so we try it first and fall back to
    a simpler approach if it fails.
    """
    # Try powermetrics (needs sudo)
    try:
        r = subprocess.run(
            ["sudo", "-n", "powermetrics", "--samplers", "smc", "-n", "1", "-i", "1"],
            capture_output=True, text=True, timeout=5
        )
        if r.returncode == 0:
            for line in r.stdout.split("\n"):
                if "die temperature" in line.lower() or "cpu die" in line.lower():
                    match = re.search(r'(\d+\.?\d*)\s*C', line)
                    if match:
                        c = float(match.group(1))
                        return f"CPU temperature: {c:.1f}C ({c * 9/5 + 32:.1f}F)"
    except Exception:
        pass

    # Try osx-cpu-temp if installed (brew install osx-cpu-temp)
    try:
        temp = _run("osx-cpu-temp 2>/dev/null")
        if temp and "not found" not in temp:
            return f"CPU temperature: {temp}"
    except Exception:
        pass

    return "CPU temperature: not available (requires sudo or osx-cpu-temp)"


def handle_call(name, args):
    if name == "get_cpu_info":
        cores = _run("sysctl -n hw.ncpu")
        load = _run("sysctl -n vm.loadavg").strip("{ }")
        cpu_brand = _run("sysctl -n machdep.cpu.brand_string")
        return f"CPU: {cpu_brand}\nCores: {cores}\nLoad avg: {load}"

    elif name == "get_memory_info":
        return _get_memory_info()

    elif name == "get_disk_info":
        return _run("df -h / | tail -1")

    elif name == "get_temperature":
        return _get_temperature()

    elif name == "get_uptime":
        return _run("uptime")

    elif name == "get_network_info":
        # Parse ifconfig for active interfaces with IPv4
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
        return "\n".join(result) if result else "No active network interfaces found"

    return f"Unknown tool: {name}"


if __name__ == "__main__":
    run_server("system-info", "1.0.0", TOOLS, handle_call)
