#!/bin/bash
# stress-test-orin.sh — PicoClaw Orin Nano (picocrush) in-case thermal/power testing
# Run as root on the Orin Nano
# Compares in-case temps vs previous out-of-case benchmarks
set -euo pipefail

RESULTS_DIR="$HOME/results-incase"
IPERF_SERVER="10.1.10.207"
DURATION=120
SOAK_DURATION=300
MODEL_DIR="/mnt/nvme/models"
LLAMA_BENCH="/mnt/nvme/llama.cpp/build/bin/llama-bench"
mkdir -p "$RESULTS_DIR"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- Install dependencies ---
install_deps() {
  log "Installing stress tools..."
  apt update -qq
  apt install -y -qq stress-ng fio iperf3 > /dev/null 2>&1
  log "Dependencies installed."
}

# --- Tegrastats helpers ---
read_power() {
  # Read VDD_IN (total SoC power) from tegrastats
  tegrastats --interval 100 2>/dev/null | head -1 | grep -oP 'VDD_IN \K[0-9]+' || echo "0"
}

read_temp() {
  # Read tj (junction temp)
  cat /sys/devices/virtual/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f", $1/1000}' || echo "0"
}

read_gpu_clock() {
  cat /sys/devices/gpu.0/devfreq/17000000.ga10b/cur_freq 2>/dev/null | awk '{printf "%d", $1/1000000}' || echo "0"
}

# --- Tegrastats monitor (runs in background) ---
monitor_tegrastats() {
  local label="$1"
  local duration="$2"
  tegrastats --interval 2000 --logfile "$RESULTS_DIR/${label}_tegrastats.log" &
  TEGRA_PID=$!
}

stop_tegrastats() {
  kill $TEGRA_PID 2>/dev/null || true
  wait $TEGRA_PID 2>/dev/null || true
}

# --- Parse tegrastats log for summary ---
summarize_tegrastats() {
  local logfile="$1"
  local label="$2"

  if [[ ! -f "$logfile" ]]; then
    log "No tegrastats log found: $logfile"
    return
  fi

  # Extract VDD_IN values
  local powers=$(grep -oP 'VDD_IN \K[0-9]+' "$logfile")
  if [[ -n "$powers" ]]; then
    local min=$(echo "$powers" | sort -n | head -1)
    local max=$(echo "$powers" | sort -n | tail -1)
    local avg=$(echo "$powers" | awk '{s+=$1; n++} END {printf "%d", s/n}')
    log "$label power — min: ${min}mW  avg: ${avg}mW  max: ${max}mW"
  fi

  # Extract temps
  local temps=$(grep -oP 'tj@\K[0-9.]+' "$logfile" 2>/dev/null || grep -oP 'CPU@\K[0-9.]+' "$logfile")
  if [[ -n "$temps" ]]; then
    local tmin=$(echo "$temps" | sort -n | head -1)
    local tmax=$(echo "$temps" | sort -n | tail -1)
    log "$label temp — min: ${tmin}C  max: ${tmax}C"
  fi
}

# --- Tests ---

test_idle() {
  log "=== IDLE BASELINE (60s, MAXN, in-case) ==="
  monitor_tegrastats "idle" 60
  sleep 60
  stop_tegrastats
  summarize_tegrastats "$RESULTS_DIR/idle_tegrastats.log" "Idle"
  log ">>> READ KILL-A-WATT NOW (Orin idle, RPi5 idle) <<<"
  read -p "Enter Kill-A-Watt cluster reading (watts): " watts
  echo "orin_idle,$watts" >> "$RESULTS_DIR/killawatt.csv"
}

test_cpu() {
  log "=== CPU STRESS (${DURATION}s, $(nproc) cores, MAXN, in-case) ==="
  monitor_tegrastats "cpu_stress" ${DURATION}
  stress-ng --cpu $(nproc) --cpu-method all --timeout ${DURATION}s --metrics-brief 2>&1 | tee "$RESULTS_DIR/cpu_stress.txt"
  stop_tegrastats
  summarize_tegrastats "$RESULTS_DIR/cpu_stress_tegrastats.log" "CPU stress"
  log ">>> READ KILL-A-WATT NOW (Orin CPU stress) <<<"
  read -p "Enter Kill-A-Watt cluster reading (watts): " watts
  echo "orin_cpu_stress,$watts" >> "$RESULTS_DIR/killawatt.csv"
  log "Cooling down 30s..."
  sleep 30
}

test_inference() {
  local model_file="$1"
  local model_name=$(basename "$model_file" .gguf)
  log "=== INFERENCE: $model_name (MAXN, in-case) ==="
  monitor_tegrastats "inference_${model_name}" 120

  # Run llama-bench
  $LLAMA_BENCH \
    -m "$model_file" \
    -p 512 -n 128 -ngl 99 \
    -t $(nproc) \
    2>&1 | tee "$RESULTS_DIR/inference_${model_name}.txt"

  stop_tegrastats
  summarize_tegrastats "$RESULTS_DIR/inference_${model_name}_tegrastats.log" "$model_name inference"
  log ">>> READ KILL-A-WATT NOW ($model_name inference) <<<"
  read -p "Enter Kill-A-Watt cluster reading (watts): " watts
  echo "orin_inference_${model_name},$watts" >> "$RESULTS_DIR/killawatt.csv"
  log "Cooling down 30s..."
  sleep 30
}

test_kitchen_sink() {
  log "=== KITCHEN SINK — ALL SUBSYSTEMS (${DURATION}s, MAXN, in-case) ==="
  monitor_tegrastats "kitchen_sink" ${DURATION}

  stress-ng --cpu $(nproc) --cpu-method all --timeout ${DURATION}s &
  CPU_PID=$!

  fio --name=kitchen_io --rw=randrw --bs=4k --size=256M \
    --runtime=${DURATION} --time_based --numjobs=2 \
    --directory=/mnt/nvme --output="$RESULTS_DIR/fio_kitchen.txt" --output-format=normal &
  FIO_PID=$!

  iperf3 -c "$IPERF_SERVER" -t ${DURATION} -P 4 > "$RESULTS_DIR/iperf3_kitchen.txt" 2>&1 &
  IPERF_PID=$!

  # Run inference concurrently
  if [[ -f "$MODEL_DIR/Phi-3.5-mini-instruct-Q4_K_M.gguf" ]]; then
    $LLAMA_BENCH -m "$MODEL_DIR/Phi-3.5-mini-instruct-Q4_K_M.gguf" \
      -p 1024 -n 256 -ngl 99 -r 4 \
      2>&1 | tee "$RESULTS_DIR/inference_kitchen.txt" &
    BENCH_PID=$!
  fi

  log "All subsystems running..."
  sleep ${DURATION}

  kill $CPU_PID $FIO_PID $IPERF_PID ${BENCH_PID:-0} 2>/dev/null || true
  wait 2>/dev/null || true

  stop_tegrastats
  summarize_tegrastats "$RESULTS_DIR/kitchen_sink_tegrastats.log" "Kitchen sink"
  log ">>> READ KILL-A-WATT NOW (kitchen sink) <<<"
  read -p "Enter Kill-A-Watt cluster reading (watts): " watts
  echo "orin_kitchen_sink,$watts" >> "$RESULTS_DIR/killawatt.csv"
  log "Cooling down 60s..."
  sleep 60
}

test_sustained_soak() {
  log "=== 5-MINUTE SUSTAINED SOAK — ALL SUBSYSTEMS (MAXN, in-case) ==="
  monitor_tegrastats "sustained_soak" ${SOAK_DURATION}

  stress-ng --cpu $(nproc) --cpu-method all --timeout ${SOAK_DURATION}s &
  fio --name=soak_io --rw=randrw --bs=4k --size=256M \
    --runtime=${SOAK_DURATION} --time_based --numjobs=2 \
    --directory=/mnt/nvme --output="$RESULTS_DIR/fio_soak.txt" --output-format=normal &

  if [[ -f "$MODEL_DIR/Phi-3.5-mini-instruct-Q4_K_M.gguf" ]]; then
    $LLAMA_BENCH -m "$MODEL_DIR/Phi-3.5-mini-instruct-Q4_K_M.gguf" \
      -p 1024 -n 256 -ngl 99 -r 8 \
      2>&1 | tee "$RESULTS_DIR/inference_soak.txt" &
  fi

  log "Sustained soak running for 5 minutes..."
  log ">>> WATCH KILL-A-WATT FOR PEAK READING <<<"

  for i in $(seq 1 10); do
    sleep 30
    local t=$(read_temp)
    local gpu=$(read_gpu_clock)
    log "  ${i}/10 — Temp: ${t}C  GPU: ${gpu}MHz"
  done

  wait 2>/dev/null || true

  stop_tegrastats
  summarize_tegrastats "$RESULTS_DIR/sustained_soak_tegrastats.log" "Sustained soak"

  read -p "Enter Kill-A-Watt peak reading (watts): " watts
  echo "orin_sustained_peak,$watts" >> "$RESULTS_DIR/killawatt.csv"
  read -p "Enter Kill-A-Watt sustained avg reading (watts): " watts_avg
  echo "orin_sustained_avg,$watts_avg" >> "$RESULTS_DIR/killawatt.csv"
}

# --- Main ---
if (( EUID != 0 )); then
  echo "ERROR: Must run as root"
  exit 1
fi

# Set MAXN power mode
nvpmodel -m 2
jetson_clocks

echo "test,watts" > "$RESULTS_DIR/killawatt.csv"

log "=== PicoClaw Orin Nano In-Case Stress Test Suite ==="
log "Results: $RESULTS_DIR"
log "Previous out-of-case results: ~/results/"
log "iperf3 server: $IPERF_SERVER"
log "CPU cores: $(nproc)"
log "Current temp: $(read_temp)C"
log "GPU clock: $(read_gpu_clock)MHz"
echo ""

install_deps

test_idle
test_cpu

# Inference tests with available models
for model in "$MODEL_DIR"/*.gguf; do
  if [[ -f "$model" ]]; then
    test_inference "$model"
  fi
done

test_kitchen_sink
test_sustained_soak

log ""
log "=== ALL TESTS COMPLETE ==="
log "Results saved to $RESULTS_DIR/"
log ""
log "Kill-A-Watt readings:"
cat "$RESULTS_DIR/killawatt.csv"
log ""
log "Compare in-case vs out-of-case temps:"
log "  Out-of-case peak (5-min soak): 71.0C"
log "  In-case peak (5-min soak): check sustained_soak_tegrastats.log"
