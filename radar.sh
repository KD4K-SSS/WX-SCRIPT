#!/bin/bash
set -euo pipefail

WORKDIR="/tmp/radar_lightning"
SE_DIR="$WORKDIR/se"
KLTX_DIR="$WORKDIR/kltx"
LTG_DIR="$WORKDIR/lightning"
FRAME_DIR="$WORKDIR/frames"
OUT="$WORKDIR/final_radar_lightning.gif"

mkdir -p "$SE_DIR" "$KLTX_DIR" "$LTG_DIR" "$FRAME_DIR"

# Radar loops
SE_URL="https://radar.weather.gov/ridge/standard/SE/SE_loop.gif"
KLTX_URL="https://radar.weather.gov/ridge/standard/KLTX/KLTX_loop.gif"

# MRMS lightning (CONUS lightning density composite PNG style feed)
# If this endpoint changes, swap to NOAA MRMS tile server or lightning density product feed
LIGHTNING_URL="https://mrms.ncep.noaa.gov/data/2D/MultiSensor_QPE_01H_Pass2/CONUS/latest_conus_lightning.png"

echo "Starting radar + lightning overlay system..."

while true; do
    echo "Downloading radar loops..."
    curl -s -o "$WORKDIR/se.gif" "$SE_URL"
    curl -s -o "$WORKDIR/kltx.gif" "$KLTX_URL"

    echo "Downloading lightning overlay..."
    curl -s -o "$WORKDIR/lightning.png" "$LIGHTNING_URL"

    echo "Extracting frames..."
    rm -rf "$SE_DIR"/* "$KLTX_DIR"/* "$LTG_DIR"/* "$FRAME_DIR"/*

    ffmpeg -y -i "$WORKDIR/se.gif" "$SE_DIR/%03d.png" >/dev/null 2>&1
    ffmpeg -y -i "$WORKDIR/kltx.gif" "$KLTX_DIR/%03d.png" >/dev/null 2>&1

    SE_COUNT=$(ls "$SE_DIR" | wc -l)
    KLTX_COUNT=$(ls "$KLTX_DIR" | wc -l)

    FRAMES=$(( SE_COUNT < KLTX_COUNT ? SE_COUNT : KLTX_COUNT ))

    echo "Building $FRAMES combined frames with lightning overlay..."

    i=0
    for idx in $(seq -w 0 $((FRAMES-1))); do
        SE_FRAME="$SE_DIR/$idx.png"
        KLTX_FRAME="$KLTX_DIR/$idx.png"

        if [[ ! -f "$SE_FRAME" || ! -f "$KLTX_FRAME" ]]; then
            continue
        fi

        COMBO="$FRAME_DIR/frame_$(printf "%03d" $i).png"

        # Build side-by-side radar
        ffmpeg -y -i "$SE_FRAME" -i "$KLTX_FRAME" \
            -filter_complex "hstack=inputs=2" \
            "$FRAME_DIR/base.png" >/dev/null 2>&1

        # Overlay lightning (semi-transparent)
        ffmpeg -y -i "$FRAME_DIR/base.png" -i "$WORKDIR/lightning.png" \
            -filter_complex "overlay=0:0:format=auto:alpha=0.35" \
            "$COMBO" >/dev/null 2>&1

        i=$((i+1))
    done

    echo "Encoding final GIF..."

    ffmpeg -y \
        -framerate 10 \
        -i "$FRAME_DIR/frame_%03d.png" \
        -vf "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
        -loop 0 \
        "$OUT" >/dev/null 2>&1

    echo "Updated radar feed:"
    echo "$OUT"

    sleep 600
done
