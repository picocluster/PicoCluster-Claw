#!/bin/bash
# stress-test-rpi5.sh — PicoCluster Claw RPi5 (clusterclaw) power/thermal stress testing
# Run as root on the RPi5
set -euo pipefail

RESULTS_DIR="$HOME/results"
IPERF_SERVER="10.1.10.207"
DURATION=120  # seconds per test
mkdir -p "$RESULTS_DIR"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- Install dependencies ---
install_deps() {
  log "Installing stress tools..."
  apt update -qq
  apt install -y -qq stress-ng fio iperf3 sysbench > /dev/null 2>&1
  log "Dependencies installed."
}

# --- Temperature and power reading ---
read_temps() {
  local temp=$(vcgencmd measure_temp | grep -oP '[0-9.]+')
  echo "$temp"
}

read_pmic() {
  # RPi5 PMIC rail voltages and currents
  vcgencmd pmic_read_adc 2>/dev/null || echo "pmic_read_adc not available"
}

# --- Thermal/power monitor (runs in background) ---
monitor() {
  local label="$1"
  local outfile="$RESULTS_DIR/${label}_thermal.csv"
  echo "timestamp,temp_c" > "$outfile"
  while true; do
    local t=$(read_temps)
    echo "$(date '+%H:%M:%S'),$t" >> "$outfile"
    sleep 2
  done
}

start_monitor() {
  monitor "$1" &
  MONITOR_PID=$!
}

stop_monitor() {
  kill $MONITOR_PID 2>/dev/null || true
  wait $MONITOR_PID 2>/dev/null || true
}

# --- Capture PMIC snapshot ---
capture_pmic() {
  local label="$1"
  log "PMIC snapshot ($label):"
  read_pmic | tee "$RESULTS_DIR/${label}_pmic.txt"
}

# --- Tests ---

test_idle() {
  log "=== IDLE BASELINE (60s) ==="
  start_monitor "idle"
  capture_pmic "idle_start"
  sleep 60
  capture_pmic "idle_end"
  stop_monitor
  local temp=$(read_temps)
  log "Idle temp: ${temp}C"
  log ">>> READ KILL-A-WATT NOW (idle) <<<"
  read -p "Enter Kill-A-Watt reading (watts): " watts
  echo "idle,$watts" >> "$RESULTS_DIR/killawatt.csv"
}

test_cpu() {
  log "=== CPU STRESS (${DURATION}s, $(nproc) cores) ==="
  start_monitor "cpu_stress"
  capture_pmic "cpu_stress_start"
  stress-ng --cpu $(nproc) --cpu-method all --timeout ${DURATION}s --metrics-brief 2>&1 | tee "$RESULTS_DIR/cpu_stress.txt"
  capture_pmic "cpu_stress_end"
  stop_monitor
  local temp=$(read_temps)
  log "Post CPU stress temp: ${temp}C"
  log ">>> READ KILL-A-WATT NOW (CPU stress) <<<"
  read -p "Enter Kill-A-Watt reading (watts): " watts
  echo "cpu_stress,$watts" >> "$RESULTS_DIR/killawatt.csv"
  log "Cooling down 30s..."
  sleep 30
}

test_gpu() {
  log "=== GPU STRESS (${DURATION}s) ==="
  # RPi5 GPU stress via OpenGL (if available) or memory-heavy workload
  start_monitor "gpu_stress"
  capture_pmic "gpu_stress_start"
  # Use stress-ng matrix operations which exercise NEON/memory heavily
  stress-ng --matrix $(nproc) --timeout ${DURATION}s --metrics-brief 2>&1 | tee "$RESULTS_DIR/gpu_stress.txt"
  capture_pmic "gpu_stress_end"
  stop_monitor
  local temp=$(read_temps)
  log "Post GPU/matrix stress temp: ${temp}C"
  log ">>> READ KILL-A-WATT NOW (GPU/matrix stress) <<<"
  read -p "Enter Kill-A-Watt reading (watts): " watts
  echo "gpu_stress,$watts" >> "$RESULTS_DIR/killawatt.csv"
  log "Cooling down 30s..."
  sleep 30
}

test_storage() {
  log "=== STORAGE I/O STRESS (${DURATION}s, microSD) ==="
  start_monitor "storage_stress"
  capture_pmic "storage_stress_start"

  # Sequential read/write
  fio --name=seq_rw --rw=readwrite --bs=1M --size=512M \
    --runtime=${DURATION} --time_based --numjobs=2 \
    --directory=/tmp --output="$RESULTS_DIR/fio_seq.txt" --output-format=normal

  # Random 4K read/write
  fio --name=rand_rw --rw=randrw --bs=4k --size=256M \
    --runtime=60 --time_based --numjobs=4 \
    --directory=/tmp --output="$RESULTS_DIR/fio_rand.txt" --output-format=normal

  capture_pmic "storage_stress_end"
  stop_monitor
  local temp=$(read_temps)
  log "Post storage stress temp: ${temp}C"
  log ">>> READ KILL-A-WATT NOW (storage stress) <<<"
  read -p "Enter Kill-A-Watt reading (watts): " watts
  echo "storage_stress,$watts" >> "$RESULTS_DIR/killawatt.csv"
  log "Cooling down 30s..."
  sleep 30
}

test_network() {
  log "=== NETWORK STRESS (60s, iperf3 to $IPERF_SERVER) ==="
  start_monitor "network_stress"
  capture_pmic "network_stress_start"

  log "Upload (4 streams)..."
  iperf3 -c "$IPERF_SERVER" -t 30 -P 4 2>&1 | tee "$RESULTS_DIR/iperf3_upload.txt"

  log "Download (4 streams)..."
  iperf3 -c "$IPERF_SERVER" -t 30 -P 4 -R 2>&1 | tee "$RESULTS_DIR/iperf3_download.txt"

  capture_pmic "network_stress_end"
  stop_monitor
  local temp=$(read_temps)
  log "Post network stress temp: ${temp}C"
  log ">>> READ KILL-A-WATT NOW (network stress) <<<"
  read -p "Enter Kill-A-Watt reading (watts): " watts
  echo "network_stress,$watts" >> "$RESULTS_DIR/killawatt.csv"
  log "Cooling down 30s..."
  sleep 30
}

test_kitchen_sink() {
  log "=== KITCHEN SINK — ALL SUBSYSTEMS (${DURATION}s) ==="
  start_monitor "kitchen_sink"
  capture_pmic "kitchen_sink_start"

  # CPU stress
  stress-ng --cpu $(nproc) --cpu-method all --timeout ${DURATION}s &
  CPU_PID=$!

  # Matrix/memory stress
  stress-ng --matrix 2 --timeout ${DURATION}s &
  MATRIX_PID=$!

  # Storage I/O
  fio --name=kitchen_io --rw=randrw --bs=4k --size=256M \
    --runtime=${DURATION} --time_based --numjobs=2 \
    --directory=/tmp --output="$RESULTS_DIR/fio_kitchen.txt" --output-format=normal &
  FIO_PID=$!

  # Network
  iperf3 -c "$IPERF_SERVER" -t ${DURATION} -P 4 > "$RESULTS_DIR/iperf3_kitchen.txt" 2>&1 &
  IPERF_PID=$!

  log "All subsystems running. Monitoring for ${DURATION}s..."
  sleep ${DURATION}

  kill $CPU_PID $MATRIX_PID $FIO_PID $IPERF_PID 2>/dev/null || true
  wait $CPU_PID $MATRIX_PID $FIO_PID $IPERF_PID 2>/dev/null || true

  capture_pmic "kitchen_sink_end"
  stop_monitor
  local temp=$(read_temps)
  log "Post kitchen sink temp: ${temp}C"
  log ">>> READ KILL-A-WATT NOW (kitchen sink) <<<"
  read -p "Enter Kill-A-Watt reading (watts): " watts
  echo "kitchen_sink,$watts" >> "$RESULTS_DIR/killawatt.csv"
}

test_sustained_soak() {
  log "=== 5-MINUTE SUSTAINED SOAK — ALL SUBSYSTEMS ==="
  local soak_duration=300
  start_monitor "sustained_soak"
  capture_pmic "sustained_soak_start"

  stress-ng --cpu $(nproc) --cpu-method all --timeout ${soak_duration}s &
  stress-ng --matrix 2 --timeout ${soak_duration}s &
  fio --name=soak_io --rw=randrw --bs=4k --size=256M \
    --runtime=${soak_duration} --time_based --numjobs=2 \
    --directory=/tmp --output="$RESULTS_DIR/fio_soak.txt" --output-format=normal &

  log "Sustained soak running for 5 minutes..."
  log ">>> WATCH KILL-A-WATT FOR PEAK READING <<<"

  # Sample temps every 30s
  for i in $(seq 1 10); do
    sleep 30
    local t=$(read_temps)
    log "  ${i}/10 — Temp: ${t}C"
  done

  wait

  capture_pmic "sustained_soak_end"
  stop_monitor
  local temp=$(read_temps)
  log "Post 5-min soak temp: ${temp}C"
  read -p "Enter Kill-A-Watt peak reading (watts): " watts
  echo "sustained_soak_peak,$watts" >> "$RESULTS_DIR/killawatt.csv"
  read -p "Enter Kill-A-Watt sustained avg reading (watts): " watts_avg
  echo "sustained_soak_avg,$watts_avg" >> "$RESULTS_DIR/killawatt.csv"
}

# --- Main ---
if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 1
fi

echo "test,watts" > "$RESULTS_DIR/killawatt.csv"

log "=== PicoCluster Claw RPi5 Stress Test Suite ==="
log "Results: $RESULTS_DIR"
log "iperf3 server: $IPERF_SERVER"
log "CPU cores: $(nproc)"
log "Current temp: $(read_temps)C"
echo ""

install_deps

test_idle
test_cpu
test_gpu
test_storage
test_network
test_kitchen_sink
test_sustained_soak

log ""
log "=== ALL TESTS COMPLETE ==="
log "Results saved to $RESULTS_DIR/"
log ""
log "Kill-A-Watt readings:"
cat "$RESULTS_DIR/killawatt.csv"
