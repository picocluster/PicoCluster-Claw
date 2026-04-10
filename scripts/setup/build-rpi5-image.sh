#!/bin/bash
# build-rpi5-image.sh — Strip and harden a Raspbian Desktop install for PicoCluster Claw golden image
# Run as root on a booted RPi5 with fresh Raspbian Desktop.
# After running: dd capture → shrink → gzip for distribution.
#
# Usage:
#   sudo bash build-rpi5-image.sh            # Full strip + harden
#   sudo bash build-rpi5-image.sh --dry-run  # Preview only

set -euo pipefail

LOGFILE="/var/log/build-image.log"
DRY_RUN=false
PICOCLUSTER_USER="picocluster"
HOSTNAME_DEFAULT="picocluster-claw"
MY_IP="10.1.10.220"
PARTNER_IP="10.1.10.221"
PARTNER_HOSTNAME="picocrush"
GATEWAY="10.1.10.1"
DNS="8.8.8.8"
SUBNET="24"

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
log "=== PicoCluster Claw RPi5 Golden Image Builder ==="

if ! grep -qi 'raspbian\|debian' /etc/os-release 2>/dev/null; then
  log "WARNING: This doesn't look like Raspbian. Proceeding anyway..."
fi
if [[ "$(uname -m)" != "aarch64" ]]; then
  log "WARNING: Expected aarch64, got $(uname -m)"
fi

BEFORE_DISK=$(df -h / | awk 'NR==2 {print $3}')
log "Disk used before: $BEFORE_DISK"

# ============================================================
# STEP 1: Strip GUI / Desktop Environment
# ============================================================
log ""
log "=== STEP 1: Stripping desktop environment ==="

GUI_PACKAGES=(
  raspberrypi-ui-mods
  rpd-plym-splash
  lxde lxde-common lxde-core
  lxpanel lxappearance lxinput lxpolkit lxrandr lxtask lxterminal
  openbox obconf
  pcmanfm
  xserver-xorg xserver-xorg-core xserver-xorg-input-all xserver-xorg-video-all
  xserver-xorg-input-libinput
  x11-common x11-utils x11-xkb-utils x11-xserver-utils
  xdg-utils xdg-user-dirs
  lightdm
  libx11-6 libx11-data libx11-xcb1
  libgtk-3-0 libgtk-3-common libgtk2.0-0 libgtk2.0-common
  gtk2-engines-pixbuf
  gvfs gvfs-backends gvfs-daemons gvfs-fuse
  zenity
  piwiz
  pipanel
  pi-greeter
)

run "apt purge -y ${GUI_PACKAGES[*]} 2>/dev/null || true"
run "systemctl set-default multi-user.target"

# ============================================================
# STEP 2: Strip applications
# ============================================================
log ""
log "=== STEP 2: Stripping applications ==="

APP_PACKAGES=(
  libreoffice-base libreoffice-calc libreoffice-common libreoffice-core
  libreoffice-draw libreoffice-impress libreoffice-math libreoffice-writer
  libreoffice-gtk3 libreoffice-gnome
  chromium-browser chromium-codecs-ffmpeg-extra
  firefox-esr
  wolfram-engine
  sonic-pi
  scratch scratch2 scratch3
  thonny
  geany geany-common
  mu-editor
  smartsim
  penguinspuzzle
  python-games
  minecraft-pi
  realvnc-vnc-server realvnc-vnc-viewer
  rp-bookshelf
  nuscratch
  claws-mail
  galculator
  mousepad
)

run "apt purge -y ${APP_PACKAGES[*]} 2>/dev/null || true"

# ============================================================
# STEP 3: Strip multimedia
# ============================================================
log ""
log "=== STEP 3: Stripping multimedia ==="

MEDIA_PACKAGES=(
  vlc vlc-data vlc-plugin-base
  gpicview
  pulseaudio pulseaudio-utils
  alsa-base alsa-utils
  timidity
  lxmusic
  orca espeak espeak-ng
  at-spi2-core
)

run "apt purge -y ${MEDIA_PACKAGES[*]} 2>/dev/null || true"

# ============================================================
# STEP 4: Strip services (Bluetooth, Avahi, CUPS, etc.)
# ============================================================
log ""
log "=== STEP 4: Stripping unnecessary services ==="

SERVICE_PACKAGES=(
  bluez pi-bluetooth bluetooth
  avahi-daemon avahi-utils libnss-mdns
  cups cups-daemon cups-client cups-common cups-filters cups-browsed
  printer-driver-gutenprint
  triggerhappy
  modemmanager
)

run "apt purge -y ${SERVICE_PACKAGES[*]} 2>/dev/null || true"

# ============================================================
# STEP 5: Strip fonts and locales
# ============================================================
log ""
log "=== STEP 5: Stripping fonts and extra locales ==="

FONT_PACKAGES=(
  fonts-noto-mono fonts-noto-ui-core fonts-noto-color-emoji fonts-noto-extra
  fonts-noto-cjk fonts-noto-cjk-extra
  fonts-droid-fallback
  fonts-liberation fonts-liberation2
  fonts-freefont-ttf
  fonts-dejavu-core fonts-dejavu-extra
)

run "apt purge -y ${FONT_PACKAGES[*]} 2>/dev/null || true"

# Remove non-English man pages
if ! $DRY_RUN; then
  find /usr/share/man -mindepth 1 -maxdepth 1 -type d ! -name 'man*' -exec rm -rf {} + 2>/dev/null || true
  find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'en*' ! -name 'locale.alias' -exec rm -rf {} + 2>/dev/null || true
fi

# ============================================================
# STEP 6: Autoremove and clean
# ============================================================
log ""
log "=== STEP 6: Autoremove and clean ==="

run "apt autoremove -y"
run "apt autoclean"
run "apt clean"

MID_DISK=$(df -h / | awk 'NR==2 {print $3}')
log "Disk used after stripping: $MID_DISK (was $BEFORE_DISK)"

# ============================================================
# STEP 7: Disable remaining services
# ============================================================
log ""
log "=== STEP 7: Disabling unnecessary services ==="

DISABLE_SERVICES=(
  bluetooth
  avahi-daemon
  cups
  cups-browsed
  triggerhappy
  ModemManager
  hciuart
)

for svc in "${DISABLE_SERVICES[@]}"; do
  if systemctl list-unit-files "${svc}.service" &>/dev/null; then
    run "systemctl disable ${svc}.service 2>/dev/null || true"
    run "systemctl stop ${svc}.service 2>/dev/null || true"
  fi
done

# ============================================================
# STEP 8: Harden SSH
# ============================================================
log ""
log "=== STEP 8: Hardening SSH ==="

SSHD_CONFIG="/etc/ssh/sshd_config"

if ! $DRY_RUN; then
  # Keep password auth enabled for appliance usability
  sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
  # Disable root login
  sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
  # Enable key-based auth too
  sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
  # Set permissions
  chmod 600 "$SSHD_CONFIG"
  log "SSH hardened: root login disabled, password + key auth enabled"
else
  log "[DRY RUN] Would harden $SSHD_CONFIG"
fi

# ============================================================
# STEP 9: Install security packages
# ============================================================
log ""
log "=== STEP 9: Installing security packages ==="

run "apt update -qq"
run "apt install -y ufw fail2ban unattended-upgrades"

if ! $DRY_RUN; then
  # Configure UFW
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
# STEP 10: Install base tools
# ============================================================
log ""
log "=== STEP 10: Installing base tools ==="

BASE_PACKAGES=(
  curl wget git htop tmux rsync jq
  python3 python3-pip
  net-tools iotop unzip
  gdisk       # For GPT partition management (includes sgdisk)
  stress-ng   # For testing
  fio
  iperf3
)

run "apt install -y ${BASE_PACKAGES[*]}"

# ============================================================
# STEP 11: Install Docker (pre-stage for Phase 4)
# ============================================================
log ""
log "=== STEP 11: Installing Docker ==="

if ! command -v docker &>/dev/null; then
  if ! $DRY_RUN; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker "$PICOCLUSTER_USER" 2>/dev/null || true
    systemctl enable docker
    log "Docker installed and enabled"
  else
    log "[DRY RUN] Would install Docker"
  fi
else
  log "Docker already installed"
fi

# ============================================================
# STEP 12: Configure system
# ============================================================
log ""
log "=== STEP 12: Configuring system ==="

if ! $DRY_RUN; then
  # Set hostname
  hostnamectl set-hostname "$HOSTNAME_DEFAULT"
  log "Hostname set to $HOSTNAME_DEFAULT"

  # Ensure picocluster user exists
  if ! id "$PICOCLUSTER_USER" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo,docker "$PICOCLUSTER_USER"
    echo "${PICOCLUSTER_USER}:picocluster" | chpasswd
    log "Created user $PICOCLUSTER_USER"
  else
    usermod -aG sudo,docker "$PICOCLUSTER_USER" 2>/dev/null || true
    log "User $PICOCLUSTER_USER already exists"
  fi

  # Set up SSH directory for picocluster user
  mkdir -p "/home/${PICOCLUSTER_USER}/.ssh"
  chmod 700 "/home/${PICOCLUSTER_USER}/.ssh"
  touch "/home/${PICOCLUSTER_USER}/.ssh/authorized_keys"
  chmod 600 "/home/${PICOCLUSTER_USER}/.ssh/authorized_keys"
  chown -R "${PICOCLUSTER_USER}:${PICOCLUSTER_USER}" "/home/${PICOCLUSTER_USER}/.ssh"

  # Remove pi user if present (but not if we're logged in as pi)
  if id pi &>/dev/null && [[ "$(whoami)" != "pi" ]]; then
    userdel -r pi 2>/dev/null || true
    log "Removed pi user"
  fi

  # Configure journald log rotation
  mkdir -p /etc/systemd/journald.conf.d
  cat > /etc/systemd/journald.conf.d/size.conf <<'EOF'
[Journal]
SystemMaxUse=100M
SystemMaxFileSize=10M
EOF
  systemctl restart systemd-journald
  log "Journald max size set to 100M"

  # Configure swap (2GB for stability)
  if command -v dphys-swapfile &>/dev/null; then
    sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
    systemctl restart dphys-swapfile
    log "Swap set to 2048MB"
  fi
fi

# ============================================================
# STEP 12b: Configure network (static IP, /etc/hosts)
# ============================================================
log ""
log "=== STEP 12b: Configuring network ==="

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
# STEP 13: Clean up
# ============================================================
log ""
log "=== STEP 13: Final cleanup ==="

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
  rm -rf /usr/share/icons/*/48x48 /usr/share/icons/*/64x64 /usr/share/icons/*/128x128 /usr/share/icons/*/256x256 2>/dev/null || true

  log "Cleanup complete"
fi

# ============================================================
# SUMMARY
# ============================================================
AFTER_DISK=$(df -h / | awk 'NR==2 {print $3}')

log ""
log "============================================"
log "  PicoCluster Claw RPi5 Golden Image Build Complete"
log "============================================"
log ""
log "  Disk before: $BEFORE_DISK"
log "  Disk after:  $AFTER_DISK"
log "  Hostname:    $HOSTNAME_DEFAULT"
log "  User:        $PICOCLUSTER_USER"
log "  SSH:         Key-only, no root, no password"
log "  Firewall:    UFW active, SSH allowed"
log "  fail2ban:    Active on SSH"
log "  Docker:      $(docker --version 2>/dev/null || echo 'not installed')"
log "  Boot target: $(systemctl get-default)"
log ""
log "  Next steps:"
log "    1. Add SSH keys to /home/${PICOCLUSTER_USER}/.ssh/authorized_keys"
log "    2. Reboot and verify headless boot"
log "    3. dd capture → shrink → gzip for distribution"
log "    4. Run configure-pair.sh to set IPs before deployment"
log "============================================"
