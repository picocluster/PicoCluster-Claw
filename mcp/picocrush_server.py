#!/usr/bin/env python3
"""Picocrush Control MCP Server — manage Ollama models and GPU on picocrush."""

import os
import sys
import json
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp_base import run_server

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://10.1.10.221:11434")
CRUSH_IP = os.environ.get("CRUSH_IP", "10.1.10.221")

TOOLS = [
    {
        "name": "list_ollama_models",
        "description": "List all LLM models installed on picocrush (the Jetson Orin Nano). Shows name, size, and parameter count.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_active_models",
        "description": "Get models currently loaded in GPU memory on picocrush. Shows which model is warm and ready.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_gpu_memory",
        "description": "Get NVIDIA GPU memory usage on picocrush (Jetson Orin Nano).",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "pull_ollama_model",
        "description": "Download a new model to picocrush from the Ollama library. Example model names: gemma3:1b, qwen2.5-coder:7b, mistral:7b",
        "inputSchema": {
            "type": "object",
            "properties": {
                "model": {"type": "string", "description": "Model name (e.g. llama3.2:3b)"},
            },
            "required": ["model"],
        },
    },
]


def _http_get(url):
    try:
        resp = urllib.request.urlopen(url, timeout=5)
        return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}


def _http_post(url, data):
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(data).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        resp = urllib.request.urlopen(req, timeout=600)
        return resp.read().decode()
    except Exception as e:
        return f"error: {e}"


def handle_call(name, args):
    if name == "list_ollama_models":
        data = _http_get(f"{OLLAMA_HOST}/api/tags")
        if "error" in data:
            return f"Error: {data['error']}"
        models = data.get("models", [])
        if not models:
            return "No models installed."
        lines = []
        for m in models:
            size_gb = m.get("size", 0) / (1024**3)
            params = m.get("details", {}).get("parameter_size", "")
            lines.append(f"  {m['name']}: {size_gb:.1f}GB ({params})")
        return f"Installed models on picocrush:\n" + "\n".join(lines)

    elif name == "get_active_models":
        data = _http_get(f"{OLLAMA_HOST}/api/ps")
        if "error" in data:
            return f"Error: {data['error']}"
        models = data.get("models", [])
        if not models:
            return "No models currently loaded in GPU memory."
        lines = []
        for m in models:
            vram_gb = m.get("size_vram", 0) / (1024**3)
            expires = m.get("expires_at", "unknown")
            lines.append(f"  {m['name']}: {vram_gb:.1f}GB VRAM, expires {expires}")
        return f"Active models on picocrush:\n" + "\n".join(lines)

    elif name == "get_gpu_memory":
        import subprocess
        try:
            result = subprocess.run(
                ["ssh", "-o", "ConnectTimeout=3", "-o", "BatchMode=yes",
                 f"picocluster@{CRUSH_IP}",
                 "nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader"],
                capture_output=True, text=True, timeout=10,
            )
            return result.stdout.strip() or "Could not query GPU"
        except Exception as e:
            return f"Error: {e}"

    elif name == "pull_ollama_model":
        model = args.get("model", "")
        if not model:
            return "Error: model name required"
        return f"Pulling {model} on picocrush...\n" + _http_post(
            f"{OLLAMA_HOST}/api/pull", {"name": model, "stream": False}
        )[:500]

    return f"Unknown tool: {name}"


if __name__ == "__main__":
    run_server("picoclcaw-picocrush", "1.0.0", TOOLS, handle_call)
