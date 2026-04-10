#!/bin/bash
# install-leds.sh — Install PicoCluster Claw LED status daemon on either node
# Usage: sudo bash install-leds.sh clusterclaw   (on RPi5)
#        sudo bash install-leds.sh clustercrush  (on Orin Nano)
set -euo pipefail

NODE="${1:-clusterclaw}"
if [[ "$NODE" != "clusterclaw" ]]; then
  echo "Usage: $0 clusterclaw"
  echo "Note: Blinkt! LEDs are only supported on RPi5 (clusterclaw)."
  echo "      Orin Nano GPIO pinmux does not support the Blinkt! pin mapping."
  exit 1
fi

if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/opt/clusterclaw/leds"

echo "=== Installing PicoCluster Claw LED daemon ($NODE) ==="

# Install Python gpiod (RPi5 Trixie)
apt install -y python3-gpiod 2>/dev/null || pip3 install --break-system-packages gpiod

# Copy LED files
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/apa102.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/clusterclaw_status.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/clustercrush_status.py" "$INSTALL_DIR/"
chmod 644 "$INSTALL_DIR"/*.py

# Install systemd service
cp "$SCRIPT_DIR/clusterclaw-leds.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable clusterclaw-leds.service
systemctl start clusterclaw-leds.service

echo "=== Done ==="
systemctl status clusterclaw-leds.service --no-pager | head -10
