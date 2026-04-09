#!/usr/bin/env python3
"""Tiny shutdown API for PicoClaw portal. Runs on port 8888.
Requires confirmation token to prevent accidental triggers."""

from http.server import HTTPServer, BaseHTTPRequestHandler
import subprocess
import json
import os

TOKEN = os.environ.get("SHUTDOWN_TOKEN", "picocluster-shutdown")
CRUSH_IP = os.environ.get("CRUSH_IP", "10.1.10.221")


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/shutdown":
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len else {}

            if body.get("token") != TOKEN:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b'{"error":"invalid token"}')
                return

            target = body.get("target", "all")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "shutting down", "target": target}).encode())

            # Execute shutdown after sending response
            if target in ("all", "picocrush"):
                subprocess.Popen(
                    ["ssh", "-o", "ConnectTimeout=5", f"picocluster@{CRUSH_IP}", "sudo shutdown -h now"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
            if target in ("all", "picoclaw"):
                subprocess.Popen(["sudo", "shutdown", "-h", "+1", "PicoClaw shutdown requested"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        elif self.path == "/restart":
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len else {}

            if body.get("token") != TOKEN:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b'{"error":"invalid token"}')
                return

            target = body.get("target", "all")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "restarting", "target": target}).encode())

            if target in ("all", "picocrush"):
                subprocess.Popen(
                    ["ssh", "-o", "ConnectTimeout=5", f"picocluster@{CRUSH_IP}", "sudo reboot"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
            if target in ("all", "picoclaw"):
                subprocess.Popen(["sudo", "reboot"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            self.send_response(404)
            self.end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress access logs


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8888), Handler)
    print("Shutdown API listening on :8888")
    server.serve_forever()
