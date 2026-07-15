#!/bin/bash

###########################################################
# FT8 Equalizer GIF Generator
###########################################################

TMPDIR="/mnt/ssbwx_tmp"
FRAME_DIR="$TMPDIR/pskr_frames"

SOURCE_IMG="/var/www/html/data/hf/pskr_heatmap.png"
OUT_GIF="/var/www/html/data/hf/pskr_history.gif"

MAX_FRAMES=72
SLEEP_TIME=300

mkdir -p "$FRAME_DIR"

echo "========================================"
echo " FT8 GIF Generator Started"
echo "========================================"

while true; do

    #######################################################
    # Verify source image exists
    #######################################################

    if [[ ! -f "$SOURCE_IMG" ]]; then
        echo "$(date '+%F %T') Source image missing."
        sleep "$SLEEP_TIME"
        continue
    fi

    #######################################################
    # Save frame
    #######################################################

    STAMP=$(date -u '+%Y%m%d_%H%MZ')

    cp "$SOURCE_IMG" \
       "$FRAME_DIR/${STAMP}.png"

    #######################################################
    # Keep 6 hours of frames
    #######################################################

    ls -1t "$FRAME_DIR"/*.png \
        2>/dev/null \
        | tail -n +$((MAX_FRAMES + 1)) \
        | xargs -r rm -f

    #######################################################
    # Rebuild GIF
    #######################################################

    COUNT=$(find "$FRAME_DIR" -name "*.png" | wc -l)

    if (( COUNT > 1 )); then

        if command -v magick >/dev/null 2>&1; then

            magick \
                -delay 40 \
                -loop 0 \
                "$FRAME_DIR"/*.png \
                "$OUT_GIF"

        else

            convert \
                -delay 40 \
                -loop 0 \
                "$FRAME_DIR"/*.png \
                "$OUT_GIF"

        fi

        echo "$(date '+%F %T') Updated GIF ($COUNT frames)"

    fi

    sleep "$SLEEP_TIME"

done
