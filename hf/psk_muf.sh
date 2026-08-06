#!/bin/bash

BROKER="mqtt.pskreporter.info"
PORT="1883"
TOPIC="pskr/filter/v2raw/#"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "/var/www/html/data/hf"

clear
echo "=========================================="
echo " High-Performance FT8 Propagation Engine  "
echo "=========================================="
echo "Data streams managed completely in RAM..."
echo "------------------------------------------"

# --- PIPELINE SELECTION ---
# Option A: Dual-run mode (Runs both your original worker and the new propagation engine).
# Option B: Fail-safe mode (Comments out pskr_engine.py to run only your original worker).

mosquitto_sub -h "$BROKER" -p "$PORT" -t "$TOPIC" -q 0 -v | \
  tee >(python3 -u "$SCRIPT_DIR/pskr_engine.py") | \
  python3 -u "$SCRIPT_DIR/pskr_worker.py"

# ==============================================================================
# FAIL-SAFE BACKUP (In case of issues with pskr_engine.py):
# If you ever need to disable the engine script completely, comment out the 3 lines 
# above and uncomment the original single-stream line below:
# ==============================================================================
# mosquitto_sub -h "$BROKER" -p "$PORT" -t "$TOPIC" -q 0 -v | python3 -u "$SCRIPT_DIR/pskr_worker.py"
