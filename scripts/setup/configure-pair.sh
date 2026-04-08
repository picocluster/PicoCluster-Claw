#!/bin/bash
# configure-pair.sh — Configure a PicoClaw node pair (claw/crush) with static IPs
#
# Run on each node with the SAME arguments so both agree on addressing.
#
# Usage:
#   sudo ./configure-pair.sh claw                              # Defaults: claw=10.1.10.220, crush=10.1.10.221
#   sudo ./configure-pair.sh crush                             # Same pair, run on the Orin
#   sudo ./configure-pair.sh claw --start-ip 192.168.1.50     # Custom network
#   sudo ./configure-pair.sh claw --pair 1                    # Pair 1: claw1=10.1.10.222, crush1=10.1.10.223
#   sudo ./configure-pair.sh crush --start-ip 192.168.1.50 --pair 2 --gateway 192.168.1.1 --dns 1.1.1.1

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 <claw|crush> [options]

Arguments:
  claw    This node is the RPi5 (agent orchestrator)
  crush   This node is the Orin Nano (inference)

Options:
  --start-ip IP    Base IP for pair 0, claw node (default: 10.1.10.220)
  --pair N         Pair number (default: 0). Offsets IPs by 2*N from start.
  --gateway IP     Gateway address (default: start-ip network .1)
  --dns IP         DNS server (default: 8.8.8.8)
  --subnet N       Subnet prefix length (default: 24)
  --ansible-dir D  Path to ansible directory (default: ~/ansible)
  --dry-run        Show what would be done without making changes

IP calculation:
  claw_ip  = start_ip + (pair * 2)
  crush_ip = start_ip + (pair * 2) + 1

Examples:
  Pair 0 (default):  claw=10.1.10.220  crush=10.1.10.221
  Pair 1:            claw=10.1.10.222  crush=10.1.10.223
  Pair 2:            claw=10.1.10.224  crush=10.1.10.225
EOF
  exit 1
}

# --- Parse arguments ---
if [[ $# -lt 1 ]]; then
  usage
fi

node_type="$1"
shift

if [[ "$node_type" != "claw" && "$node_type" != "crush" ]]; then
  echo "ERROR: First argument must be 'claw' or 'crush', got '$node_type'"
  usage
fi

start_ip="10.1.10.220"
pair_num=0
gateway=""
dns="8.8.8.8"
subnet=24
ansible_dir="$HOME/ansible"
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start-ip)  start_ip="$2"; shift 2 ;;
    --pair)      pair_num="$2"; shift 2 ;;
    --gateway)   gateway="$2"; shift 2 ;;
    --dns)       dns="$2"; shift 2 ;;
    --subnet)    subnet="$2"; shift 2 ;;
    --ansible-dir) ansible_dir="$2"; shift 2 ;;
    --dry-run)   dry_run=true; shift ;;
    *)           echo "Unknown option: $1"; usage ;;
  esac
done

if (( EUID != 0 )) && ! $dry_run; then
  echo "ERROR: Must run as root (or use --dry-run)"
  exit 1
fi

# --- IP arithmetic ---
ip_to_int() {
  local IFS='.'
  read -r a b c d <<< "$1"
  echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

int_to_ip() {
  local n=$1
  echo "$(( (n >> 24) & 255 )).$(( (n >> 16) & 255 )).$(( (n >> 8) & 255 )).$(( n & 255 ))"
}

base_int=$(ip_to_int "$start_ip")
claw_int=$(( base_int + (pair_num * 2) ))
crush_int=$(( claw_int + 1 ))

claw_ip=$(int_to_ip $claw_int)
crush_ip=$(int_to_ip $crush_int)

# Derive gateway from network if not specified (.1 of the same /24)
if [[ -z "$gateway" ]]; then
  gateway=$(int_to_ip $(( claw_int & 0xFFFFFF00 | 1 )))
fi

# Hostnames
if (( pair_num == 0 )); then
  claw_hostname="claw"
  crush_hostname="crush"
else
  claw_hostname="claw${pair_num}"
  crush_hostname="crush${pair_num}"
fi

# Determine this node's IP and hostname
if [[ "$node_type" == "claw" ]]; then
  my_ip="$claw_ip"
  my_hostname="$claw_hostname"
  partner_ip="$crush_ip"
  partner_hostname="$crush_hostname"
else
  my_ip="$crush_ip"
  my_hostname="$crush_hostname"
  partner_ip="$claw_ip"
  partner_hostname="$claw_hostname"
fi

# --- Display summary ---
echo "=== PicoClaw Node Configuration ==="
echo ""
echo "  This node:    $node_type → $my_hostname ($my_ip/$subnet)"
echo "  Partner node: → $partner_hostname ($partner_ip/$subnet)"
echo "  Gateway:      $gateway"
echo "  DNS:          $dns"
echo "  Pair:         $pair_num"
echo ""

if $dry_run; then
  echo "[DRY RUN] No changes will be made."
  echo ""
fi

# --- Step 1: Set hostname ---
echo "--- Setting hostname to $my_hostname ---"
if ! $dry_run; then
  hostnamectl set-hostname "$my_hostname"
  echo "  Done."
else
  echo "  [dry-run] hostnamectl set-hostname $my_hostname"
fi

# --- Step 2: Configure static IP via NetworkManager ---
echo "--- Configuring static IP ($my_ip/$subnet) via NetworkManager ---"

# Auto-detect primary wired connection
conn=$(nmcli -t -f NAME,TYPE,DEVICE con show --active 2>/dev/null | grep ':802-3-ethernet:' | head -1 | cut -d ':' -f 1)
if [[ -z "$conn" ]]; then
  # Fallback: try inactive wired connections
  conn=$(nmcli -t -f NAME,TYPE con show 2>/dev/null | grep ':802-3-ethernet' | head -1 | cut -d ':' -f 1)
fi
if [[ -z "$conn" ]]; then
  echo "  ERROR: Could not find a wired ethernet connection in NetworkManager"
  exit 2
fi
echo "  Connection: $conn"

if ! $dry_run; then
  nmcli con mod "$conn" ipv4.addresses "$my_ip/$subnet"
  nmcli con mod "$conn" ipv4.gateway "$gateway"
  nmcli con mod "$conn" ipv4.dns "$dns"
  nmcli con mod "$conn" ipv4.method manual
  echo "  Applied. Restarting connection..."
  nmcli con down "$conn" 2>/dev/null || true
  nmcli con up "$conn"
  echo "  Done."
else
  echo "  [dry-run] nmcli con mod \"$conn\" ipv4.addresses $my_ip/$subnet"
  echo "  [dry-run] nmcli con mod \"$conn\" ipv4.gateway $gateway"
  echo "  [dry-run] nmcli con mod \"$conn\" ipv4.dns $dns"
  echo "  [dry-run] nmcli con mod \"$conn\" ipv4.method manual"
fi

# --- Step 3: Update /etc/hosts ---
echo "--- Updating /etc/hosts ---"
hosts_block="$claw_ip  $claw_hostname
$crush_ip  $crush_hostname"

if ! $dry_run; then
  # Remove existing PicoCluster block if present
  sed -i '/^# BEGIN PICOCLUSTER/,/^# END PICOCLUSTER/d' /etc/hosts
  # Append new block
  cat >> /etc/hosts <<EOF

# BEGIN PICOCLUSTER
$hosts_block
# END PICOCLUSTER
EOF
  echo "  Done."
else
  echo "  [dry-run] Would write to /etc/hosts:"
  echo "    $hosts_block"
fi

# --- Step 4: Update Ansible inventory (claw only) ---
if [[ "$node_type" == "claw" ]]; then
  echo "--- Updating Ansible inventory ---"
  inventory_file="$ansible_dir/inventory/cluster.yml"
  if [[ -d "$ansible_dir/inventory" ]]; then
    inventory_content="---
all:
  children:
    rpi5:
      hosts:
        ${claw_hostname}:
          ansible_host: ${claw_ip}
          ansible_user: picocluster
          ansible_connection: local
    orin:
      hosts:
        ${crush_hostname}:
          ansible_host: ${crush_ip}
          ansible_user: picocluster
"
    if ! $dry_run; then
      echo "$inventory_content" > "$inventory_file"
      echo "  Written: $inventory_file"
    else
      echo "  [dry-run] Would write $inventory_file"
    fi
  else
    echo "  Skipped: $ansible_dir/inventory not found"
  fi

  # --- Step 5: Update group_vars/all.yml ---
  echo "--- Updating Ansible group_vars ---"
  allvars_file="$ansible_dir/group_vars/all.yml"
  if [[ -f "$allvars_file" ]]; then
    if ! $dry_run; then
      sed -i "s|^orin_ip:.*|orin_ip: ${crush_ip}|" "$allvars_file"
      echo "  Updated orin_ip in $allvars_file"
    else
      echo "  [dry-run] Would set orin_ip: ${crush_ip} in $allvars_file"
    fi
  else
    echo "  Skipped: $allvars_file not found"
  fi

  # --- Step 6: Update OpenClaw config ---
  echo "--- Updating OpenClaw config ---"
  openclaw_config="$HOME/.config/openclaw/config.json"
  if [[ -f "$openclaw_config" ]]; then
    if ! $dry_run; then
      # Update the baseUrl to point to the new crush IP
      sed -i "s|\"baseUrl\":.*|\"baseUrl\": \"http://${crush_ip}:8080/v1\",|" "$openclaw_config"
      echo "  Updated: $openclaw_config"
    else
      echo "  [dry-run] Would update baseUrl to http://${crush_ip}:8080/v1 in $openclaw_config"
    fi
  else
    echo "  Skipped: $openclaw_config not found (will be created by Ansible)"
  fi
fi

# --- Summary ---
echo ""
echo "=== Configuration Complete ==="
echo ""
echo "  Hostname: $my_hostname"
echo "  IP:       $my_ip/$subnet"
echo "  Gateway:  $gateway"
echo "  DNS:      $dns"
echo ""
if [[ "$node_type" == "claw" ]]; then
  echo "Now run the same command on the Orin Nano (crush):"
  cmd="sudo ./configure-pair.sh crush"
  [[ "$start_ip" != "10.1.10.220" ]] && cmd+=" --start-ip $start_ip"
  (( pair_num != 0 )) && cmd+=" --pair $pair_num"
  [[ "$dns" != "8.8.8.8" ]] && cmd+=" --dns $dns"
  echo "  $cmd"
else
  echo "Now run the same command on the RPi5 (claw):"
  cmd="sudo ./configure-pair.sh claw"
  [[ "$start_ip" != "10.1.10.220" ]] && cmd+=" --start-ip $start_ip"
  (( pair_num != 0 )) && cmd+=" --pair $pair_num"
  [[ "$dns" != "8.8.8.8" ]] && cmd+=" --dns $dns"
  echo "  $cmd"
fi
echo ""
echo "Verify with: ping $partner_hostname"
