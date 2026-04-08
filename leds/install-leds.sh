#!/bin/bash
# install-leds.sh — Install PicoClaw LED status daemon on either node
# Usage: sudo bash install-leds.sh picoclaw   (on RPi5)
#        sudo bash install-leds.sh picocrush  (on Orin Nano)
set -euo pipefail

NODE="${1:-picoclaw}"
if [[ "$NODE" != "picoclaw" ]]; then
  echo "Usage: $0 picoclaw"
  echo "Note: Blinkt! LEDs are only supported on RPi5 (picoclaw)."
  echo "      Orin Nano GPIO pinmux does not support the Blinkt! pin mapping."
  exit 1
fi

if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/opt/picoclcaw/leds"

echo "=== Installing PicoClaw LED daemon ($NODE) ==="

# Install Python gpiod (RPi5 Trixie)
apt install -y python3-gpiod 2>/dev/null || pip3 install --break-system-packages gpiod

# Copy LED files
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/apa102.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/picoclaw_status.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/picocrush_status.py" "$INSTALL_DIR/"
chmod 644 "$INSTALL_DIR"/*.py

# Install systemd service
cp "$SCRIPT_DIR/picoclaw-leds.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable picoclaw-leds.service
systemctl start picoclaw-leds.service

echo "=== Done ==="
systemctl status picoclaw-leds.service --no-pager | head -10
