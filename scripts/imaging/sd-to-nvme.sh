#!/bin/bash
# sd-to-nvme.sh — Clone SD card to NVMe and make it bootable on Jetson Orin Nano
# Run this on the Orin Nano while booted from SD card.
#
# What it does:
#   1. Clones all SD card partitions to NVMe (preserving Jetson boot partitions)
#   2. Expands the APP (rootfs) partition to fill the NVMe drive
#   3. Fixes extlinux.conf to boot from NVMe
#   4. Fixes fstab and ESP UUID to avoid conflicts with SD card
#   5. Sets UEFI boot order to prefer NVMe
#
# After running: shut down, remove SD card, and boot from NVMe.

set -euo pipefail

if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 1
fi

SD="/dev/mmcblk0"
NVME="/dev/nvme0n1"
SD_APP="${SD}p1"
NVME_APP="${NVME}p1"
NVME_ESP="${NVME}p10"

# --- Safety checks ---
if [[ ! -b "$SD" ]]; then
  echo "ERROR: SD card not found at $SD"
  exit 2
fi
if [[ ! -b "$NVME" ]]; then
  echo "ERROR: NVMe drive not found at $NVME"
  exit 2
fi

for cmd in sgdisk rsync efibootmgr mkfs.vfat; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd not found"
    exit 3
  fi
done

# Check if anything on NVMe is mounted
nvme_mounts=$(mount | grep "$NVME" || true)
if [[ -n "$nvme_mounts" ]]; then
  echo "Unmounting NVMe partitions..."
  mount | grep "$NVME" | awk '{print $1}' | while read dev; do
    umount "$dev" 2>/dev/null || true
  done
fi

sd_size=$(blockdev --getsize64 "$SD")
nvme_size=$(blockdev --getsize64 "$NVME")
echo "SD card:  $(numfmt --to=iec-i --suffix=B "$sd_size")"
echo "NVMe:    $(numfmt --to=iec-i --suffix=B "$nvme_size")"
echo ""

if (( nvme_size < sd_size )); then
  echo "ERROR: NVMe ($nvme_size) is smaller than SD card ($sd_size)"
  exit 4
fi

read -p "This will ERASE all data on $NVME. Continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# --- Step 1: Clone partition table ---
echo ""
echo "=== Step 1/6: Cloning GPT partition table ==="
sgdisk -Z "$NVME"                    # Zap existing GPT
sgdisk -R "$NVME" "$SD"              # Replicate SD partition table to NVMe
sgdisk -G "$NVME"                    # Randomize NVMe GUIDs (avoid conflicts)
partprobe "$NVME"
sleep 2

echo "Partition table cloned."

# --- Step 2: Copy all non-APP partitions (small Jetson boot partitions) ---
echo ""
echo "=== Step 2/6: Copying Jetson boot partitions ==="
# Get all partition numbers except APP (partition 1)
partnums=$(sgdisk -p "$SD" | awk '/^ +[0-9]/ {print $1}' | grep -v '^1$')

for pnum in $partnums; do
  sd_part="${SD}p${pnum}"
  nvme_part="${NVME}p${pnum}"
  if [[ -b "$sd_part" ]] && [[ -b "$nvme_part" ]]; then
    psize=$(blockdev --getsize64 "$sd_part")
    echo "  Partition $pnum: $(numfmt --to=iec-i --suffix=B "$psize")"
    dd if="$sd_part" of="$nvme_part" bs=4M status=none
  fi
done
echo "Boot partitions copied."

# --- Step 3: Expand APP partition to fill NVMe ---
echo ""
echo "=== Step 3/6: Expanding APP partition to fill NVMe ==="
app_start=$(sgdisk -i 1 "$NVME" | grep 'First sector:' | awk '{print $3}')
sgdisk -d 1 -n "1:${app_start}:0" -c 1:APP -t 1:8300 "$NVME"
partprobe "$NVME"
sleep 1
echo "APP partition expanded."

# --- Step 4: Copy rootfs ---
echo ""
echo "=== Step 4/6: Copying rootfs (this will take a while) ==="
# Format the expanded APP partition
mkfs.ext4 -L APP -F "$NVME_APP"

# Mount NVMe and rsync from live root (SD is already mounted as /)
nvme_mount=$(mktemp -d)
mount "$NVME_APP" "$nvme_mount"

echo "  Syncing files from live root to NVMe..."
rsync -aHAXx --info=progress2 / "$nvme_mount/"

# --- Step 5: Fix boot configuration on NVMe ---
echo ""
echo "=== Step 5/6: Fixing boot configuration ==="

# Fix extlinux.conf: change root device to NVMe
sed -i 's|root=/dev/mmcblk0p1|root=/dev/nvme0n1p1|g' "$nvme_mount/boot/extlinux/extlinux.conf"
echo "  extlinux.conf: root=/dev/nvme0n1p1"

# Fix fstab: give NVMe ESP a new UUID to avoid conflict with SD card ESP
# (both currently share UUID 3FFC-5543 from the clone)
new_esp_uuid=$(python3 -c "import random; print(f'{random.randint(0,0xFFFF):04X}-{random.randint(0,0xFFFF):04X}')")
sed -i "s/UUID=3FFC-5543/UUID=$new_esp_uuid/" "$nvme_mount/etc/fstab"
echo "  fstab: ESP UUID=$new_esp_uuid"

umount "$nvme_mount"

# Format NVMe ESP with the new UUID and copy contents from SD ESP
mkfs.vfat -F 32 -i "$(echo "$new_esp_uuid" | tr -d '-')" "$NVME_ESP"
esp_mount=$(mktemp -d)
mount "$NVME_ESP" "$esp_mount"
cp -a /boot/efi/. "$esp_mount/"
umount "$esp_mount"
rmdir "$nvme_mount" "$esp_mount"

echo "  Boot configuration updated."

# --- Step 6: Set UEFI boot order to prefer NVMe ---
echo ""
echo "=== Step 6/6: Setting UEFI boot order ==="

# Find the NVMe boot entry number
nvme_bootnum=$(efibootmgr | grep -i 'nvme\|TEAM' | head -1 | grep -o 'Boot[0-9]*' | grep -o '[0-9]*')

if [[ -n "$nvme_bootnum" ]]; then
  # Get current boot order, move NVMe to front
  current_order=$(efibootmgr | grep 'BootOrder:' | awk '{print $2}')
  # Remove NVMe entry from current position, prepend it
  new_order="${nvme_bootnum},$(echo "$current_order" | sed "s/${nvme_bootnum},//;s/,${nvme_bootnum}//")"
  efibootmgr -o "$new_order"
  echo "  Boot order: $new_order (NVMe first)"
else
  echo "  WARNING: Could not find NVMe UEFI boot entry"
  echo "  You may need to select NVMe manually from UEFI boot menu"
fi

echo ""
echo "========================================"
echo "Done! NVMe is ready to boot."
echo ""
echo "Next steps:"
echo "  1. sudo shutdown -h now"
echo "  2. Remove the SD card"
echo "  3. Power on — should boot from NVMe"
echo ""
echo "If it doesn't boot, re-insert SD card and check:"
echo "  efibootmgr -v"
echo "  mount /dev/nvme0n1p1 /mnt && cat /mnt/boot/extlinux/extlinux.conf"
echo "========================================"
