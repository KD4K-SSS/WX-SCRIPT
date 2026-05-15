#!/bin/bash
set -euo pipefail

WORKDIR="/tmp/radar_ws"
mkdir -p "$WORKDIR"

SE="$WORKDIR/se.gif"
KLTX="$WORKDIR/kltx.gif"

SE_URL="https://radar.weather.gov/ridge/standard/SE/SE_loop.gif"
KLTX_URL="https://radar.weather.gov/ridge/standard/KLTX/KLTX_loop.gif"

echo "Starting radar workstation..."

# Launch mpv once (it will keep running)
mpv --fs --no-border --geometry=100%x100% \
    --loop-file=inf \
    --title="RADAR WORKSTATION" \
    "$SE" "$KLTX" &
MPV_PID=$!

echo "mpv PID: $MPV_PID"

while true; do
    echo "Updating radar feeds..."

    curl -s -o "$SE" "$SE_URL"
    curl -s -o "$KLTX" "$KLTX_URL"

    # Force mpv to reload files
    kill -HUP "$MPV_PID" 2>/dev/null || true

    echo "Updated. Sleeping 10 minutes..."
    sleep 600
done
