#!/bin/bash
# build-orin-image.sh — Strip and harden a JetPack 6.x Desktop install for PicoCluster Claw golden image
# Run as root on a booted Orin Nano with fresh JetPack desktop.
# After running: dd capture → jetson-shrink.sh → gzip for distribution.
#
# IMPORTANT: This script preserves CUDA, cuDNN, TensorRT, and all NVIDIA runtime libraries.
# Only desktop/GUI and non-essential packages are removed.
#
# Usage:
#   sudo bash build-orin-image.sh            # Full strip + harden
#   sudo bash build-orin-image.sh --dry-run  # Preview only

set -euo pipefail

LOGFILE="/var/log/build-image.log"
DRY_RUN=false
PICOCLUSTER_USER="picocluster"
HOSTNAME_DEFAULT="clustercrush"
MY_IP="10.1.10.221"
PARTNER_IP="10.1.10.220"
PARTNER_HOSTNAME="clusterclaw"
GATEWAY="10.1.10.1"
DNS="8.8.8.8"
SUBNET="24"
NVME_MOUNT="/mnt/nvme"
NVME_DEVICE="/dev/nvme0n1p1"

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

if (( EUID != 0 )) && ! $DRY_RUN; then
  echo "ERROR: Must run as root"
  exit 1
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

run() {
  if $DRY_RUN; then
    log "[DRY RUN] $*"
  else
    log "Running: $*"
    eval "$@" 2>&1 | tee -a "$LOGFILE"
  fi
}

# ============================================================
# STEP 0: Verify environment
# ============================================================
log "=== PicoCluster Claw Orin Nano Golden Image Builder ==="

if [[ "$(uname -m)" != "aarch64" ]]; then
  log "WARNING: Expected aarch64, got $(uname -m)"
fi

# Verify NVIDIA GPU is present
if ! nvidia-smi &>/dev/null; then
  log "ERROR: nvidia-smi failed. Is this a Jetson with CUDA?"
  exit 1
fi
log "NVIDIA GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'Jetson')"

BEFORE_DISK=$(df -h / | awk 'NR==2 {print $3}')
log "Disk used before: $BEFORE_DISK"

# ============================================================
# STEP 1: Strip GUI / Desktop Environment
# ============================================================
log ""
log "=== STEP 1: Stripping desktop environment ==="

# CRITICAL: Do NOT remove nvidia-*, libcuda*, libnvinfer*, libcudnn*
GUI_PACKAGES=(
  ubuntu-desktop ubuntu-desktop-minimal
  gdm3
  gnome-shell gnome-shell-extensions gnome-session gnome-session-bin
  gnome-control-center gnome-tweaks gnome-system-monitor
  gnome-terminal gnome-calculator gnome-calendar gnome-characters
  gnome-clocks gnome-contacts gnome-disk-utility gnome-font-viewer
  gnome-logs gnome-maps gnome-power-manager gnome-screenshot
  gnome-software gnome-startup-applications gnome-text-editor
  gnome-weather gnome-keyring
  mutter
  xwayland
  xserver-xorg xserver-xorg-core
  x11-common x11-utils x11-xkb-utils x11-xserver-utils
  xdg-utils xdg-user-dirs xdg-desktop-portal xdg-desktop-portal-gnome
  nautilus nautilus-extension-gnome-terminal
  baobab
  cheese
  eog
  yelp
  zenity
  gvfs gvfs-backends gvfs-daemons gvfs-fuse
  tracker tracker-miner-fs
  colord
  packagekit
)

run "apt purge -y ${GUI_PACKAGES[*]} 2>/dev/null || true"
run "systemctl set-default multi-user.target"

# ============================================================
# STEP 2: Strip applications
# ============================================================
log ""
log "=== STEP 2: Stripping applications ==="

APP_PACKAGES=(
  firefox
  thunderbird
  libreoffice-base libreoffice-calc libreoffice-common libreoffice-core
  libreoffice-draw libreoffice-impress libreoffice-math libreoffice-writer
  libreoffice-gnome libreoffice-gtk3
  transmission-gtk
  remmina remmina-plugin-rdp remmina-plugin-vnc
  totem totem-plugins
  rhythmbox
  shotwell
  evince evince-common
  gedit gedit-common
  simple-scan
  usb-creator-gtk
  gnome-sudoku gnome-mines gnome-mahjongg aisleriot
  deja-dup
  seahorse
  file-roller
)

run "apt purge -y ${APP_PACKAGES[*]} 2>/dev/null || true"

# ============================================================
# STEP 3: Strip NVIDIA samples/docs (NOT runtime)
# ============================================================
log ""
log "=== STEP 3: Stripping NVIDIA samples and docs (preserving runtime) ==="

NVIDIA_STRIP_PACKAGES=(
  cuda-samples-12-6
  cuda-documentation-12-6
  libnvinfer-samples
)

run "apt purge -y ${NVIDIA_STRIP_PACKAGES[*]} 2>/dev/null || true"

# Remove sample directories
if ! $DRY_RUN; then
  rm -rf /usr/local/cuda/samples 2>/dev/null || true
  rm -rf /usr/src/tensorrt/samples 2>/dev/null || true
  log "Removed NVIDIA sample directories"
fi

# ============================================================
# STEP 4: Strip multimedia
# ============================================================
log ""
log "=== STEP 4: Stripping multimedia ==="

MEDIA_PACKAGES=(
  pulseaudio pulseaudio-utils
  pipewire pipewire-pulse pipewire-alsa wireplumber
  alsa-base alsa-utils
  orca espeak espeak-ng speech-dispatcher
  at-spi2-core
)

run "apt purge -y ${MEDIA_PACKAGES[*]} 2>/dev/null || true"

# ============================================================
# STEP 5: Strip services (Bluetooth, Avahi, CUPS, snap, etc.)
# ============================================================
log ""
log "=== STEP 5: Stripping unnecessary services ==="

SERVICE_PACKAGES=(
  bluez bluetooth
  avahi-daemon avahi-utils libnss-mdns
  cups cups-daemon cups-client cups-common cups-filters cups-browsed
  modemmanager
  snapd
  whoopsie
  apport apport-symptoms
  popularity-contest
  ubuntu-report
)

run "apt purge -y ${SERVICE_PACKAGES[*]} 2>/dev/null || true"

# Remove snap directories
if ! $DRY_RUN; then
  rm -rf /snap /var/snap /var/lib/snapd 2>/dev/null || true
fi

# ============================================================
# STEP 6: Strip fonts and locales
# ============================================================
log ""
log "=== STEP 6: Stripping fonts and extra locales ==="

FONT_PACKAGES=(
  fonts-noto-mono fonts-noto-color-emoji fonts-noto-cjk fonts-noto-cjk-extra
  fonts-noto-extra fonts-noto-ui-core
  fonts-droid-fallback
  fonts-liberation fonts-liberation2
  fonts-freefont-ttf
  fonts-dejavu-core fonts-dejavu-extra
  fonts-ubuntu fonts-ubuntu-console
)

run "apt purge -y ${FONT_PACKAGES[*]} 2>/dev/null || true"

# Remove non-English locales and man pages
if ! $DRY_RUN; then
  find /usr/share/man -mindepth 1 -maxdepth 1 -type d ! -name 'man*' -exec rm -rf {} + 2>/dev/null || true
  find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'en*' ! -name 'locale.alias' -exec rm -rf {} + 2>/dev/null || true
fi

# ============================================================
# STEP 7: Autoremove and clean
# ============================================================
log ""
log "=== STEP 7: Autoremove and clean ==="

run "apt autoremove -y"
run "apt autoclean"
run "apt clean"

MID_DISK=$(df -h / | awk 'NR==2 {print $3}')
log "Disk used after stripping: $MID_DISK (was $BEFORE_DISK)"

# ============================================================
# STEP 8: Verify CUDA is intact
# ============================================================
log ""
log "=== STEP 8: Verifying CUDA is intact ==="

cuda_ok=true

if nvidia-smi &>/dev/null; then
  log "  nvidia-smi: OK"
else
  log "  ERROR: nvidia-smi failed!"
  cuda_ok=false
fi

if ldconfig -p | grep -q libcuda; then
  log "  libcuda: OK"
else
  log "  ERROR: libcuda not found!"
  cuda_ok=false
fi

if ldconfig -p | grep -q libcudnn; then
  log "  libcudnn: OK"
else
  log "  WARNING: libcudnn not found (may need reinstall)"
fi

if ldconfig -p | grep -q libnvinfer; then
  log "  libnvinfer (TensorRT): OK"
else
  log "  WARNING: libnvinfer not found (may need reinstall)"
fi

if ! $cuda_ok; then
  log "CRITICAL: CUDA appears broken. Review removed packages!"
  log "You may need: sudo apt install nvidia-jetpack"
  exit 1
fi

# ============================================================
# STEP 9: Disable remaining services
# ============================================================
log ""
log "=== STEP 9: Disabling unnecessary services ==="

DISABLE_SERVICES=(
  bluetooth
  avahi-daemon
  cups
  cups-browsed
  ModemManager
  snapd
  whoopsie
  apport
)

for svc in "${DISABLE_SERVICES[@]}"; do
  if systemctl list-unit-files "${svc}.service" &>/dev/null; then
    run "systemctl disable ${svc}.service 2>/dev/null || true"
    run "systemctl stop ${svc}.service 2>/dev/null || true"
  fi
done

# ============================================================
# STEP 10: Harden SSH
# ============================================================
log ""
log "=== STEP 10: Hardening SSH ==="

SSHD_CONFIG="/etc/ssh/sshd_config"

if ! $DRY_RUN; then
  # Keep password auth enabled for appliance usability
  sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
  # Disable root login
  sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
  # Enable key-based auth too
  sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
  chmod 600 "$SSHD_CONFIG"
  log "SSH hardened: root login disabled, password + key auth enabled"
else
  log "[DRY RUN] Would harden $SSHD_CONFIG"
fi

# ============================================================
# STEP 11: Install security packages
# ============================================================
log ""
log "=== STEP 11: Installing security packages ==="

run "apt update -qq"
run "apt install -y ufw fail2ban unattended-upgrades"

if ! $DRY_RUN; then
  # Configure UFW — SSH only for now. Port 8080 added in Phase 4 (restricted to clusterclaw IP)
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp comment 'SSH'
  echo "y" | ufw enable
  log "UFW enabled: deny incoming, allow SSH"

  # Configure fail2ban
  cat > /etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
EOF
  systemctl enable fail2ban
  systemctl restart fail2ban
  log "fail2ban configured for SSH"

  # Enable unattended security upgrades
  cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
  log "Unattended security upgrades enabled"
fi

# ============================================================
# STEP 12: Install base tools
# ============================================================
log ""
log "=== STEP 12: Installing base tools ==="

BASE_PACKAGES=(
  curl wget git htop tmux rsync jq
  python3 python3-pip
  net-tools iotop unzip
  gdisk        # includes sgdisk
  network-manager  # needed for configure-pair.sh
  stress-ng fio iperf3
  cmake build-essential libcurl4-openssl-dev  # For llama.cpp build later
)

run "apt install -y ${BASE_PACKAGES[*]}"

# Hold L4T packages — these must NEVER be upgraded via apt.
# Jetson kernel/bootloader updates require NVIDIA's OTA tools.
run "apt-mark hold nvidia-l4t-bootloader nvidia-l4t-kernel nvidia-l4t-kernel-headers nvidia-l4t-kernel-dtbs nvidia-l4t-kernel-oot-modules nvidia-l4t-kernel-oot-headers nvidia-l4t-display-kernel nvidia-l4t-jetson-io nvidia-l4t-initrd 2>/dev/null || true"

# ============================================================
# STEP 13: Configure NVMe
# ============================================================
log ""
log "=== STEP 13: Configuring NVMe mount ==="

if ! $DRY_RUN; then
  mkdir -p "$NVME_MOUNT"
  chown "${PICOCLUSTER_USER}:${PICOCLUSTER_USER}" "$NVME_MOUNT"

  # Add to fstab if not present
  if ! grep -q "$NVME_DEVICE" /etc/fstab; then
    echo "${NVME_DEVICE}  ${NVME_MOUNT}  ext4  defaults,nofail  0  2" >> /etc/fstab
    log "Added NVMe to fstab: $NVME_DEVICE → $NVME_MOUNT"
  else
    log "NVMe already in fstab"
  fi

  # Mount if device exists
  if [[ -b "$NVME_DEVICE" ]]; then
    mount "$NVME_MOUNT" 2>/dev/null || true
    log "NVMe mounted at $NVME_MOUNT"
  else
    log "NVMe device not present (will mount on boot with nofail)"
  fi
fi

# ============================================================
# STEP 14: Power mode — MAXN with persistence
# ============================================================
log ""
log "=== STEP 14: Setting MAXN power mode ==="

if ! $DRY_RUN; then
  nvpmodel -m 2 2>/dev/null || true
  jetson_clocks 2>/dev/null || true

  cat > /etc/systemd/system/jetson-maxperf.service <<'EOF'
[Unit]
Description=Set Jetson to MAXN power mode
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nvpmodel -m 2
ExecStartPost=/usr/bin/jetson_clocks
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable jetson-maxperf.service
  log "MAXN power mode set and persisted via systemd"
fi

# ============================================================
# STEP 15: Configure system
# ============================================================
log ""
log "=== STEP 15: Configuring system ==="

if ! $DRY_RUN; then
  # Set hostname
  hostnamectl set-hostname "$HOSTNAME_DEFAULT"
  log "Hostname set to $HOSTNAME_DEFAULT"

  # Ensure picocluster user exists with correct groups
  if ! id "$PICOCLUSTER_USER" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo "$PICOCLUSTER_USER"
    echo "${PICOCLUSTER_USER}:picocluster" | chpasswd
    log "Created user $PICOCLUSTER_USER"
  else
    usermod -aG sudo "$PICOCLUSTER_USER" 2>/dev/null || true
    log "User $PICOCLUSTER_USER already exists"
  fi

  # Set up SSH directory
  mkdir -p "/home/${PICOCLUSTER_USER}/.ssh"
  chmod 700 "/home/${PICOCLUSTER_USER}/.ssh"
  touch "/home/${PICOCLUSTER_USER}/.ssh/authorized_keys"
  chmod 600 "/home/${PICOCLUSTER_USER}/.ssh/authorized_keys"
  chown -R "${PICOCLUSTER_USER}:${PICOCLUSTER_USER}" "/home/${PICOCLUSTER_USER}/.ssh"

  # Configure journald log rotation
  mkdir -p /etc/systemd/journald.conf.d
  cat > /etc/systemd/journald.conf.d/size.conf <<'EOF'
[Journal]
SystemMaxUse=100M
SystemMaxFileSize=10M
EOF
  systemctl restart systemd-journald
  log "Journald max size set to 100M"
fi

# ============================================================
# STEP 15b: Configure network (static IP, /etc/hosts)
# ============================================================
log ""
log "=== STEP 15b: Configuring network ==="

if ! $DRY_RUN; then
  # Auto-detect primary wired connection
  conn=$(nmcli -t -f NAME,TYPE,DEVICE con show --active 2>/dev/null | grep ':802-3-ethernet:' | head -1 | cut -d ':' -f 1)
  if [[ -z "$conn" ]]; then
    conn=$(nmcli -t -f NAME,TYPE con show 2>/dev/null | grep ':802-3-ethernet' | head -1 | cut -d ':' -f 1)
  fi

  if [[ -n "$conn" ]]; then
    nmcli con mod "$conn" ipv4.addresses "${MY_IP}/${SUBNET}"
    nmcli con mod "$conn" ipv4.gateway "$GATEWAY"
    nmcli con mod "$conn" ipv4.dns "$DNS"
    nmcli con mod "$conn" ipv4.method manual
    log "Static IP configured: $MY_IP/$SUBNET via $conn"
    log "NOTE: IP change takes effect on next boot or 'nmcli con up $conn'"
  else
    log "WARNING: No wired ethernet connection found in NetworkManager"
  fi

  # Update /etc/hosts
  sed -i '/^# BEGIN PICOCLUSTER/,/^# END PICOCLUSTER/d' /etc/hosts
  cat >> /etc/hosts <<EOF

# BEGIN PICOCLUSTER
${MY_IP}  ${HOSTNAME_DEFAULT}
${PARTNER_IP}  ${PARTNER_HOSTNAME}
# END PICOCLUSTER
EOF
  log "Updated /etc/hosts: $HOSTNAME_DEFAULT=$MY_IP, $PARTNER_HOSTNAME=$PARTNER_IP"
fi

# ============================================================
# STEP 16: Clean up
# ============================================================
log ""
log "=== STEP 16: Final cleanup ==="

if ! $DRY_RUN; then
  # Clear logs
  journalctl --vacuum-size=1M 2>/dev/null || true
  find /var/log -type f -name '*.gz' -delete 2>/dev/null || true
  find /var/log -type f -name '*.1' -delete 2>/dev/null || true
  find /var/log -type f -name '*.old' -delete 2>/dev/null || true
  truncate -s 0 /var/log/syslog 2>/dev/null || true
  truncate -s 0 /var/log/auth.log 2>/dev/null || true
  truncate -s 0 /var/log/kern.log 2>/dev/null || true
  truncate -s 0 /var/log/dpkg.log 2>/dev/null || true

  # Clear bash history
  for user_home in /root /home/*; do
    truncate -s 0 "$user_home/.bash_history" 2>/dev/null || true
  done

  # Clear tmp
  rm -rf /tmp/* /var/tmp/* 2>/dev/null || true

  # Clear apt cache
  apt clean
  rm -rf /var/cache/apt/archives/*.deb 2>/dev/null || true

  # Remove desktop remnants
  rm -rf /usr/share/pixmaps/* 2>/dev/null || true
  rm -rf /usr/share/backgrounds/* 2>/dev/null || true
  rm -rf /usr/share/themes/* 2>/dev/null || true

  log "Cleanup complete"
fi

# ============================================================
# SUMMARY
# ============================================================
AFTER_DISK=$(df -h / | awk 'NR==2 {print $3}')

log ""
log "============================================"
log "  PicoCluster Claw Orin Nano Golden Image Build Complete"
log "============================================"
log ""
log "  Disk before: $BEFORE_DISK"
log "  Disk after:  $AFTER_DISK"
log "  Hostname:    $HOSTNAME_DEFAULT"
log "  User:        $PICOCLUSTER_USER"
log "  SSH:         Key-only, no root, no password"
log "  Firewall:    UFW active, SSH allowed"
log "  fail2ban:    Active on SSH"
log "  CUDA:        $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo 'check manually')"
log "  NVMe:        $NVME_MOUNT (nofail in fstab)"
log "  Power mode:  MAXN (persisted)"
log "  Boot target: $(systemctl get-default)"
log ""
log "  Next steps:"
log "    1. Add SSH keys to /home/${PICOCLUSTER_USER}/.ssh/authorized_keys"
log "    2. Reboot and verify headless boot + CUDA"
log "    3. dd capture → jetson-shrink.sh → gzip for distribution"
log "    4. Run configure-pair.sh to set IPs before deployment"
log "============================================"
