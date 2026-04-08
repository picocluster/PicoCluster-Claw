#!/bin/bash
# jetson-shrink.sh — Shrink a dd-captured Jetson Orin Nano SD card image
# Handles GPT partition tables and relocates backup GPT header after truncation.
#
# Usage: jetson-shrink.sh [-z] [-a] imagefile.img [newimagefile.img]
#   -z  Run zerofree on the rootfs before shrinking (slower, but image compresses much better)
#   -a  Auto-expand rootfs on first boot after flashing

set -euo pipefail

usage() {
  echo "Usage: $0 [-z] [-a] imagefile.img [newimagefile.img]"
  echo "  -z  Zero free blocks (slower, but image compresses better)"
  echo "  -a  Auto-expand rootfs on first boot"
  exit 1
}

cleanup() {
  if [[ -n "${loopback:-}" ]] && losetup "$loopback" &>/dev/null; then
    if mountpoint -q "${mountdir:-/dev/null}" 2>/dev/null; then
      umount "$mountdir" 2>/dev/null || true
    fi
    losetup -d "$loopback" 2>/dev/null || true
  fi
  [[ -d "${mountdir:-}" ]] && rmdir "$mountdir" 2>/dev/null || true
}
trap cleanup EXIT

run_zerofree=false
auto_expand=false

while getopts ":za" opt; do
  case "${opt}" in
    z) run_zerofree=true ;;
    a) auto_expand=true ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

img="${1:-}"
if [[ -z "$img" ]]; then
  usage
fi
if [[ ! -f "$img" ]]; then
  echo "ERROR: $img is not a file"
  exit 2
fi
if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 3
fi

# Check dependencies
deps=(parted losetup tune2fs e2fsck resize2fs truncate sgdisk)
$run_zerofree && deps+=(zerofree)
for cmd in "${deps[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is not installed"
    exit 4
  fi
done

# Copy to new file if requested
if [[ -n "${2:-}" ]]; then
  echo "Copying $1 to $2..."
  cp --reflink=auto --sparse=always "$1" "$2"
  old_owner=$(stat -c %u:%g "$1")
  chown "$old_owner" "$2"
  img="$2"
fi

beforesize=$(stat -c %s "$img")
beforehuman=$(numfmt --to=iec-i --suffix=B "$beforesize")
echo "Image: $img ($beforehuman)"

# --- Identify the APP (rootfs) partition ---
# On Jetson Orin Nano, the rootfs is the ext4 partition labeled "APP".
# It is partition number 1 in the GPT table but physically last on disk.
app_line=$(parted -ms "$img" unit B print | grep ':ext4:APP:' || true)

if [[ -z "$app_line" ]]; then
  echo "ERROR: Could not find ext4 APP partition. Partition layout:"
  parted -ms "$img" unit B print
  exit 5
fi

partnum=$(echo "$app_line" | cut -d ':' -f 1)
partstart=$(echo "$app_line" | cut -d ':' -f 2 | tr -d 'B')
partend=$(echo "$app_line" | cut -d ':' -f 3 | tr -d 'B')
partsize=$(echo "$app_line" | cut -d ':' -f 4 | tr -d 'B')

echo "APP partition: #${partnum}, offset ${partstart}B, size $(numfmt --to=iec-i --suffix=B "$partsize")"

# --- Set up loop device for the APP partition ---
loopback=$(losetup -f --show -o "$partstart" "$img")
echo "Loop device: $loopback"

# --- Filesystem check ---
echo "Checking filesystem..."
e2fsck -p -f "$loopback"

# --- Optional: zerofree for better compression ---
if $run_zerofree; then
  echo "Zeroing free blocks (this may take a while)..."
  zerofree -v "$loopback"
fi

# --- Get filesystem info ---
tune2fs_output=$(tune2fs -l "$loopback")
currentsize=$(echo "$tune2fs_output" | grep '^Block count:' | tr -d ' ' | cut -d ':' -f 2)
blocksize=$(echo "$tune2fs_output" | grep '^Block size:' | tr -d ' ' | cut -d ':' -f 2)

# --- Optional: set up auto-expand on first boot ---
if $auto_expand; then
  echo "Setting up auto-expand on first boot..."
  mountdir=$(mktemp -d)
  mount "$loopback" "$mountdir"

  # Create a systemd service that expands the rootfs on first boot
  cat > "$mountdir/etc/systemd/system/expand-rootfs.service" <<'EXPAND_EOF'
[Unit]
Description=Expand root filesystem to fill partition
DefaultDependencies=no
Before=local-fs-pre.target
ConditionPathExists=/etc/expand-rootfs-flag

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
  ROOT_DEV=$(findmnt -n -o SOURCE /); \
  resize2fs "$ROOT_DEV"; \
  rm -f /etc/expand-rootfs-flag; \
  systemctl disable expand-rootfs.service'

[Install]
WantedBy=multi-user.target
EXPAND_EOF

  # Create a first-boot script to grow the GPT partition first, then reboot
  cat > "$mountdir/etc/systemd/system/expand-partition.service" <<'PARTEXPAND_EOF'
[Unit]
Description=Expand APP partition to fill disk
DefaultDependencies=no
Before=expand-rootfs.service
ConditionPathExists=/etc/expand-rootfs-flag

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
  DISK=$(lsblk -no PKNAME $(findmnt -n -o SOURCE /)); \
  PARTNUM=$(cat /sys/block/$DISK/$(lsblk -no KNAME $(findmnt -n -o SOURCE /))/partition); \
  sgdisk -e /dev/$DISK; \
  sgdisk -d $PARTNUM -n $PARTNUM:0:0 -c $PARTNUM:APP -t $PARTNUM:8300 /dev/$DISK; \
  partprobe /dev/$DISK; \
  systemctl disable expand-partition.service'

[Install]
WantedBy=multi-user.target
PARTEXPAND_EOF

  touch "$mountdir/etc/expand-rootfs-flag"
  ln -sf /etc/systemd/system/expand-partition.service "$mountdir/etc/systemd/system/multi-user.target.wants/expand-partition.service" 2>/dev/null || true
  ln -sf /etc/systemd/system/expand-rootfs.service "$mountdir/etc/systemd/system/multi-user.target.wants/expand-rootfs.service" 2>/dev/null || true

  umount "$mountdir"
  echo "Auto-expand configured (partition expand + resize2fs on first boot)"
fi

# --- Calculate minimum size ---
minsize=$(resize2fs -P "$loopback" | cut -d ':' -f 2 | tr -d ' ')

if [[ $currentsize -eq $minsize ]]; then
  echo "Image already at minimum filesystem size"
  losetup -d "$loopback"
  loopback=""
  exit 0
fi

# Add padding — more generous than pishrink to avoid edge cases
extra_space=$(( currentsize - minsize ))
if (( extra_space > 50000 )); then
  minsize=$(( minsize + 50000 ))   # ~200MB padding at 4K blocks
elif (( extra_space > 10000 )); then
  minsize=$(( minsize + 10000 ))   # ~40MB
elif (( extra_space > 1000 )); then
  minsize=$(( minsize + 1000 ))    # ~4MB
fi

echo "Shrinking filesystem: $(numfmt --to=iec-i --suffix=B $((currentsize * blocksize))) -> $(numfmt --to=iec-i --suffix=B $((minsize * blocksize)))"

# --- Shrink the filesystem ---
resize2fs -p "$loopback" "$minsize"
sync

# --- Release loop device ---
losetup -d "$loopback"
loopback=""

# --- Shrink the GPT partition ---
partnewsize=$(( minsize * blocksize ))
newpartend=$(( partstart + partnewsize ))

# Use sgdisk for GPT manipulation — much safer than parted for this
# Delete and recreate the APP partition with new size
sgdisk -d "$partnum" "$img"
# sgdisk uses sectors (512 bytes)
startsector=$(( partstart / 512 ))
endsector=$(( newpartend / 512 ))
sgdisk -n "${partnum}:${startsector}:${endsector}" -c "${partnum}:APP" -t "${partnum}:8300" "$img"

# --- Truncate the image ---
# Need space for: partition data + backup GPT (34 sectors = 17408 bytes)
truncate_to=$(( newpartend + 512 * 34 ))
truncate -s "$truncate_to" "$img"

# --- Fix the backup GPT header ---
# After truncation, the backup GPT is gone. sgdisk -e relocates it to the new end.
# Warnings about corrupt backup header are expected here — that's exactly what we're fixing.
echo "Relocating backup GPT header..."
sgdisk -e "$img" 2>/dev/null

# --- Verify ---
echo "Verifying partition table..."
verify_output=$(sgdisk -v "$img" 2>&1)
if echo "$verify_output" | grep -q "No problems found"; then
  echo "  GPT: OK"
else
  echo "  GPT verification output:"
  echo "$verify_output" | grep -v '^$'
fi

aftersize=$(stat -c %s "$img")
afterhuman=$(numfmt --to=iec-i --suffix=B "$aftersize")
savings=$(( (beforesize - aftersize) * 100 / beforesize ))

echo ""
echo "Done! Shrunk $img"
echo "  Before: $beforehuman"
echo "  After:  $afterhuman"
echo "  Saved:  ${savings}%"
echo ""
echo "Tip: Compress further with: gzip -9 $img"
