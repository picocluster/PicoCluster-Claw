#!/bin/bash
# resize_raspbian.sh — Expand rootfs partition to fill SD card (MBR/Raspbian)
# Run as root on the RPi5 after flashing a shrunk image.
set -euo pipefail

if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 1
fi

DISK="/dev/mmcblk0"
PARTNUM=2
PARTDEV="${DISK}p${PARTNUM}"

# Get current start sector of the root partition
start_sector=$(fdisk -l "$DISK" | grep "^${PARTDEV}" | awk '{print $2}')
if [[ -z "$start_sector" ]]; then
  echo "ERROR: Could not find partition $PARTNUM on $DISK"
  exit 2
fi

echo "Root partition starts at sector $start_sector"

# Delete and recreate partition 2 using all remaining space
echo "Expanding partition $PARTNUM to fill disk..."
fdisk "$DISK" <<EOF > /dev/null 2>&1
d
$PARTNUM
n
p
$PARTNUM
$start_sector

w
EOF

# Reread partition table
partprobe "$DISK"

# Expand the filesystem
echo "Resizing filesystem..."
resize2fs "$PARTDEV"

echo "Resize complete"
df -h "$PARTDEV"
