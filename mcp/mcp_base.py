"""
Shared MCP stdio server base — reduces boilerplate across PicoClaw MCP servers.

Usage:
    from mcp_base import run_server

    TOOLS = [
        {"name": "my_tool", "description": "...", "inputSchema": {...}},
    ]

    def handle_call(name, args):
        if name == "my_tool":
            return "result text"
        return f"Unknown tool: {name}"

    run_server("server-name", "1.0.0", TOOLS, handle_call)
"""

import sys
import json


def _send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def run_server(name, version, tools, handle_call):
    """Run an MCP stdio server loop.

    Args:
        name: server name
        version: server version string
        tools: list of tool definitions (dicts with name, description, inputSchema)
        handle_call: function(tool_name, arguments) -> str result
    """
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            continue

        method = req.get("method", "")
        req_id = req.get("id")

        if method == "initialize":
            _send({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": name, "version": version},
                },
            })

        elif method == "notifications/initialized":
            pass

        elif method == "tools/list":
            _send({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {"tools": tools},
            })

        elif method == "tools/call":
            params = req.get("params", {})
            tool_name = params.get("name", "")
            arguments = params.get("arguments", {})
            try:
                result_text = handle_call(tool_name, arguments)
            except Exception as e:
                result_text = f"Error: {e}"
            _send({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": str(result_text)}],
                    "isError": False,
                },
            })

        elif req_id is not None:
            _send({
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32601, "message": f"Method not found: {method}"},
            })
