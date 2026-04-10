#!/usr/bin/env python3
"""System Info MCP Server — expose picocluster-claw system stats as AI tools."""

import os
import sys
import subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp_base import run_server

TOOLS = [
    {
        "name": "get_cpu_info",
        "description": "Get CPU usage, load average, and core count for picocluster-claw.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_memory_info",
        "description": "Get RAM and swap usage for picocluster-claw.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_disk_info",
        "description": "Get disk usage for picocluster-claw's filesystem.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_temperature",
        "description": "Get the CPU temperature in Celsius for picocluster-claw.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_uptime",
        "description": "Get how long picocluster-claw has been running.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_network_info",
        "description": "Get network interface info and IP addresses for picocluster-claw.",
        "inputSchema": {"type": "object", "properties": {}},
    },
]


def _run(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except Exception as e:
        return f"error: {e}"


def handle_call(name, args):
    if name == "get_cpu_info":
        load = _run("cat /proc/loadavg")
        cores = _run("nproc")
        usage = _run("top -bn1 | grep 'Cpu(s)' | awk '{print $2 \"% user, \" $4 \"% system, \" $8 \"% idle\"}'")
        return f"Cores: {cores}\nLoad avg: {load}\n{usage}"

    elif name == "get_memory_info":
        return _run("free -h | head -3")

    elif name == "get_disk_info":
        return _run("df -h / | tail -1")

    elif name == "get_temperature":
        temp_c = _run("cat /sys/class/thermal/thermal_zone0/temp")
        try:
            c = int(temp_c) / 1000
            return f"CPU temperature: {c:.1f}C ({c * 9/5 + 32:.1f}F)"
        except ValueError:
            return f"Could not read temperature: {temp_c}"

    elif name == "get_uptime":
        return _run("uptime -p") + "\n" + _run("uptime")

    elif name == "get_network_info":
        return _run("ip -4 -br addr show")

    return f"Unknown tool: {name}"


if __name__ == "__main__":
    run_server("picocluster-claw-system-info", "1.0.0", TOOLS, handle_call)
