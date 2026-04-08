#!/bin/bash
# resize_ubuntu.sh — Expand the APP (rootfs) partition to fill the SD card
# Works with GPT partition tables (Jetson Orin Nano)
set -euo pipefail

if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 1
fi

if ! command -v sgdisk &>/dev/null; then
  echo "ERROR: sgdisk not found. Install with: sudo apt install gdisk"
  exit 1
fi

DISK="/dev/mmcblk0"
PARTNUM=1
PARTDEV="${DISK}p${PARTNUM}"

# Get current start sector of the APP partition
start_sector=$(sgdisk -i "$PARTNUM" "$DISK" | grep 'First sector:' | awk '{print $3}')
if [[ -z "$start_sector" ]]; then
  echo "ERROR: Could not find partition $PARTNUM on $DISK"
  exit 2
fi

echo "APP partition starts at sector $start_sector"

# Fix GPT to match actual disk size (moves backup header to end)
echo "Fixing GPT to match disk size..."
sgdisk -e "$DISK"

# Delete and recreate partition 1 using all remaining space
# :0 means "use last available sector"
echo "Expanding partition $PARTNUM to fill disk..."
sgdisk -d "$PARTNUM" -n "${PARTNUM}:${start_sector}:0" -c "${PARTNUM}:APP" -t "${PARTNUM}:8300" "$DISK"

# Reread partition table
partprobe "$DISK"

# Expand the filesystem
echo "Resizing filesystem..."
resize2fs "$PARTDEV"

echo "Resize complete"
df -h "$PARTDEV"
