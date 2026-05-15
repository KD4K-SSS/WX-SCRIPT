#!/bin/bash
set -euo pipefail

WORKDIR="/tmp/radar_ws"
mkdir -p "$WORKDIR"

SE="$WORKDIR/se.gif"
KLTX="$WORKDIR/kltx.gif"

SE_URL="https://radar.weather.gov/ridge/standard/SE/SE_loop.gif"
KLTX_URL="https://radar.weather.gov/ridge/standard/KLTX/KLTX_loop.gif"

echo "Starting radar workstation..."

# Download initial frames BEFORE launching mpv
curl -s -o "$SE" "$SE_URL"
curl -s -o "$KLTX" "$KLTX_URL"

# Start mpv properly (THIS is the critical fix)
mpv \
  --fs \
  --no-border \
  --force-window=yes \
  --loop-file=inf \
  --geometry=100%x100% \
  "$SE" "$KLTX" &
MPV_PID=$!

echo "mpv started: $MPV_PID"

while true; do
    sleep 600

    echo "Refreshing radar data..."

    curl -s -o "$SE" "$SE_URL"
    curl -s -o "$KLTX" "$KLTX_URL"

    # Restart mpv to force reload (reliable method)
    kill $MPV_PID 2>/dev/null || true
    wait $MPV_PID 2>/dev/null || true

    mpv \
      --fs \
      --no-border \
      --force-window=yes \
      --loop-file=inf \
      --geometry=100%x100% \
      "$SE" "$KLTX" &
    MPV_PID=$!

done
