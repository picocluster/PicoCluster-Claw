#!/usr/bin/env python3
"""System Info MCP Server — proxy edition for Mac Solo.

Runs inside the Docker container but proxies system info requests to
the virtual LED daemon on the macOS host via host.docker.internal:7777.
This way the LLM gets real macOS stats (CPU, memory, disk, uptime, network)
instead of container-internal Linux stats.

Same tool names and schemas as the Linux and Mac native versions.
"""

import os
import sys
import json
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp_base import run_server

# The virtual LED daemon on the host also serves /sysinfo/{metric}
HOST_URL = os.environ.get("LED_API_URL", "http://host.docker.internal:7777")

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
        "description": "Get the CPU/SoC temperature.",
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

TOOL_TO_METRIC = {
    "get_cpu_info": "cpu",
    "get_memory_info": "memory",
    "get_disk_info": "disk",
    "get_temperature": "temperature",
    "get_uptime": "uptime",
    "get_network_info": "network",
}


def _query_host(metric):
    """Call the host's virtual daemon for system info."""
    try:
        url = f"{HOST_URL}/sysinfo/{metric}"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
            return data.get("result", f"No result for {metric}")
    except Exception as e:
        return f"Error querying host system info: {e}"


def handle_call(name, args):
    metric = TOOL_TO_METRIC.get(name)
    if metric:
        return _query_host(metric)
    return f"Unknown tool: {name}"


if __name__ == "__main__":
    run_server("system-info", "1.0.0", TOOLS, handle_call)
