#!/usr/bin/env python3
"""Time MCP Server — give the LLM access to current date/time."""

import os
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp_base import run_server

TOOLS = [
    {
        "name": "get_current_time",
        "description": "Get the current date and time. Returns local time by default. LLMs should use this when asked about the current time or date since their training data is static.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "timezone": {
                    "type": "string",
                    "description": "Timezone (e.g. 'UTC', 'local'). Default: local",
                    "default": "local",
                },
            },
        },
    },
    {
        "name": "get_day_of_week",
        "description": "Get the current day of the week.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "time_until",
        "description": "Calculate time remaining until a target date/time. Useful for countdowns and scheduling.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "target": {
                    "type": "string",
                    "description": "Target date/time in ISO format (e.g. '2026-12-25' or '2026-12-25T15:00:00')",
                },
            },
            "required": ["target"],
        },
    },
    {
        "name": "format_duration",
        "description": "Format a number of seconds as a human-readable duration.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "seconds": {
                    "type": "integer",
                    "description": "Number of seconds",
                },
            },
            "required": ["seconds"],
        },
    },
]


def handle_call(name, args):
    if name == "get_current_time":
        tz_name = args.get("timezone", "local")
        if tz_name.lower() == "utc":
            now = datetime.now(timezone.utc)
            return now.strftime("%Y-%m-%d %H:%M:%S UTC")
        else:
            now = datetime.now()
            return now.strftime("%A, %B %d, %Y at %I:%M:%S %p %Z").strip()

    elif name == "get_day_of_week":
        return datetime.now().strftime("%A")

    elif name == "time_until":
        target_str = args.get("target", "")
        try:
            if "T" in target_str:
                target = datetime.fromisoformat(target_str)
            else:
                target = datetime.fromisoformat(target_str + "T00:00:00")
            now = datetime.now()
            delta = target - now
            if delta.total_seconds() < 0:
                return f"{target_str} was {abs(delta.days)} days ago"
            days = delta.days
            hours = delta.seconds // 3600
            minutes = (delta.seconds % 3600) // 60
            return f"{days} days, {hours} hours, {minutes} minutes until {target_str}"
        except Exception as e:
            return f"Error parsing target: {e}"

    elif name == "format_duration":
        try:
            s = int(args.get("seconds", 0))
            days = s // 86400
            hours = (s % 86400) // 3600
            minutes = (s % 3600) // 60
            seconds = s % 60
            parts = []
            if days:
                parts.append(f"{days}d")
            if hours:
                parts.append(f"{hours}h")
            if minutes:
                parts.append(f"{minutes}m")
            if seconds or not parts:
                parts.append(f"{seconds}s")
            return " ".join(parts)
        except Exception as e:
            return f"Error: {e}"

    return f"Unknown tool: {name}"


if __name__ == "__main__":
    run_server("picoclcaw-time", "1.0.0", TOOLS, handle_call)
