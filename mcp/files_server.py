#!/usr/bin/env python3
"""File Operations MCP Server — sandboxed file access for the LLM.

All operations are confined to SANDBOX_DIR (default: /tmp/clusterclaw-sandbox).
This prevents the LLM from reading or modifying sensitive system files.
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp_base import run_server

SANDBOX_DIR = Path(os.environ.get("SANDBOX_DIR", "/tmp/clusterclaw-sandbox")).resolve()
SANDBOX_DIR.mkdir(parents=True, exist_ok=True)

TOOLS = [
    {
        "name": "list_files",
        "description": f"List files in the sandbox directory ({SANDBOX_DIR}). All file operations are confined to this directory for security.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "subdir": {
                    "type": "string",
                    "description": "Optional subdirectory within the sandbox",
                    "default": "",
                },
            },
        },
    },
    {
        "name": "read_file",
        "description": "Read the contents of a file in the sandbox directory.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Relative path within the sandbox directory",
                },
            },
            "required": ["path"],
        },
    },
    {
        "name": "write_file",
        "description": "Write content to a file in the sandbox directory. Creates the file if it doesn't exist.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Relative path within the sandbox",
                },
                "content": {
                    "type": "string",
                    "description": "Content to write to the file",
                },
            },
            "required": ["path", "content"],
        },
    },
    {
        "name": "delete_file",
        "description": "Delete a file in the sandbox directory.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Relative path within the sandbox",
                },
            },
            "required": ["path"],
        },
    },
    {
        "name": "get_sandbox_path",
        "description": "Get the full path of the sandbox directory where files can be read/written.",
        "inputSchema": {"type": "object", "properties": {}},
    },
]


def _resolve(rel_path):
    """Resolve a path and ensure it's inside the sandbox."""
    p = (SANDBOX_DIR / rel_path).resolve()
    try:
        p.relative_to(SANDBOX_DIR)
    except ValueError:
        raise ValueError(f"Path outside sandbox: {rel_path}")
    return p


def handle_call(name, args):
    if name == "get_sandbox_path":
        return str(SANDBOX_DIR)

    elif name == "list_files":
        try:
            base = _resolve(args.get("subdir", ""))
            if not base.exists():
                return f"Directory does not exist: {base.relative_to(SANDBOX_DIR)}"
            entries = sorted(base.iterdir())
            if not entries:
                return f"Empty directory: {base.relative_to(SANDBOX_DIR) or '.'}"
            lines = []
            for e in entries[:50]:
                kind = "DIR" if e.is_dir() else "FILE"
                size = e.stat().st_size if e.is_file() else ""
                lines.append(f"  [{kind}] {e.name} {f'({size} bytes)' if size else ''}")
            return f"Contents of {base.relative_to(SANDBOX_DIR) or '.'}:\n" + "\n".join(lines)
        except Exception as e:
            return f"Error: {e}"

    elif name == "read_file":
        try:
            p = _resolve(args["path"])
            if not p.is_file():
                return f"Not a file: {args['path']}"
            content = p.read_text()
            if len(content) > 10000:
                return content[:10000] + f"\n\n[truncated — {len(content)} total bytes]"
            return content
        except Exception as e:
            return f"Error: {e}"

    elif name == "write_file":
        try:
            p = _resolve(args["path"])
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(args["content"])
            return f"Wrote {len(args['content'])} bytes to {args['path']}"
        except Exception as e:
            return f"Error: {e}"

    elif name == "delete_file":
        try:
            p = _resolve(args["path"])
            if not p.exists():
                return f"File does not exist: {args['path']}"
            p.unlink()
            return f"Deleted {args['path']}"
        except Exception as e:
            return f"Error: {e}"

    return f"Unknown tool: {name}"


if __name__ == "__main__":
    run_server("clusterclaw-files", "1.0.0", TOOLS, handle_call)
