#!/bin/bash
# ========================================================
# KD4K WEATHER SYSTEM - WEATHER FORECAST INGEST WATCHDOG
# ========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="/var/www/html/data"
ZONES=("scz058" "scz054")
BASE_URL="https://tgftp.nws.noaa.gov/data/forecasts/zone/sc"

# Ensure target web data workspace path exists
mkdir -p "$TARGET_DIR"

echo "========================================================"
# This line identifies the script in your 'pgrep' engine checks
echo "Starting KD4K Forecast Launcher Loop..." 
echo "========================================================"

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] Running forecast update cycle..."

    for ZONE in "${ZONES[@]}"; do
        # Pull directly with absolute no-cache directives
        curl -s \
             -H "Cache-Control: no-cache" \
             -H "Pragma: no-cache" \
             -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
             "$BASE_URL/${ZONE}.txt" > "$TARGET_DIR/${ZONE}.txt"
    done

    # Sleep window (Forecasts change slowly, so a 10 to 15-minute loop is ideal)
    # 900 seconds = 15 minutes
    sleep 900
done
