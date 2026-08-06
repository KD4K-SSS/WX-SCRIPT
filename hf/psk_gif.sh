#!/bin/bash

###########################################################
# PSK Reporter Renderer
###########################################################

JSON="/var/www/html/data/hf/pskr_summary.json"

PNG_OUT="/var/www/html/data/hf/pskr_heatmap.png"
GIF_OUT="/var/www/html/data/hf/pskr_history.gif"

FRAME_DIR="/mnt/ssbwx_tmp/pskr_frames"

PNG_INTERVAL=300
GIF_INTERVAL=1800
MAX_FRAMES=48

mkdir -p "$FRAME_DIR"

LAST_GIF=0

echo "========================================"
echo " PSK Reporter Renderer Started"
echo "========================================"

while true
do

    if [[ ! -f "$JSON" ]]; then
        echo "$(date '+%F %T') ERROR: Missing $JSON"
        sleep "$PNG_INTERVAL"
        continue
    fi

    #######################################################
    # Read Summary Data
    #######################################################

    TOTAL=$(jq -r '.total_spots' "$JSON")

    M160=$(jq -r '.bands[] | select(.band=="160m") | .active_spots' "$JSON")
    M80=$(jq -r '.bands[] | select(.band=="80m") | .active_spots' "$JSON")
    M40=$(jq -r '.bands[] | select(.band=="40m") | .active_spots' "$JSON")
    M30=$(jq -r '.bands[] | select(.band=="30m") | .active_spots' "$JSON")
    M20=$(jq -r '.bands[] | select(.band=="20m") | .active_spots' "$JSON")
    M17=$(jq -r '.bands[] | select(.band=="17m") | .active_spots' "$JSON")
    M15=$(jq -r '.bands[] | select(.band=="15m") | .active_spots' "$JSON")
    M12=$(jq -r '.bands[] | select(.band=="12m") | .active_spots' "$JSON")
    M10=$(jq -r '.bands[] | select(.band=="10m") | .active_spots' "$JSON")

    #######################################################
    # Build Heatmap PNG
    #######################################################

    TMPPNG="/tmp/pskr_heatmap.png"

    BANDS=("160m" "80m" "40m" "30m" "20m" "17m" "15m" "12m" "10m")
    VALUES=($M160 $M80 $M40 $M30 $M20 $M17 $M15 $M12 $M10)

    MAX=$M160

    for V in "${VALUES[@]}"
    do
        (( V > MAX )) && MAX=$V
    done

    (( MAX < 1 )) && MAX=1

    CMD="convert -size 2200x1100 xc:black"

    CMD="$CMD \
    -stroke '#303030' \
    -strokewidth 2 \
    -draw 'line 160,240 2000,240' \
    -draw 'line 160,440 2000,440' \
    -draw 'line 160,640 2000,640' \
    -draw 'line 160,800 2000,800' \
    -font DejaVu-Sans-Bold \
    -fill white \
    -stroke none \
    -pointsize 48 \
    -draw \"text 280,80 'North America Digital to SSB Activity Monitor'\" \
    -draw \"text 1650,80 'Paths: $TOTAL'\" \
    -pointsize 30 \
    -draw \"text 1650,130 '$(date -u '+%d %b %Y %H:%MZ')'\" \
    -pointsize 40 \
    -draw \"text 20,250 'GOOD'\" \
    -draw \"text 20,450 'WEAK'\" \
    -draw \"text 20,650 'POOR'\""

    LEFT=200
    BOTTOM=800
    BAR_W=140
    GAP=70

    for IDX in "${!BANDS[@]}"
    do

        COUNT=${VALUES[$IDX]}

        COLOR="#101010"
        STATUS="Closed"

        if (( COUNT > 0 && COUNT < 25 ))
        then
            COLOR="#ff0000"
            STATUS="Poor"

        elif (( COUNT >= 25 && COUNT < 150 ))
        then
            COLOR="#ffff00"
            STATUS="Weak"

        elif (( COUNT >= 150 ))
        then
            COLOR="#00ff00"
            STATUS="Good"
        fi

        HEIGHT=$((100 + (COUNT * 500 / MAX)))

        (( HEIGHT > 600 )) && HEIGHT=600

        X0=$((LEFT + IDX * (BAR_W + GAP)))
        X1=$((X0 + BAR_W))
        Y0=$((BOTTOM - HEIGHT))

        CMD="$CMD \
        -stroke '#505050' \
        -strokewidth 3 \
        -fill '$COLOR' \
        -draw 'rectangle $X0,$Y0 $X1,$BOTTOM' \
        -stroke none \
        -fill white \
        -pointsize 40 \
        -draw \"text $((X0+10)),$((Y0-20)) '$COUNT'\" \
        -pointsize 48 \
        -draw \"text $((X0+5)),950 '${BANDS[$IDX]}'\" \
        -pointsize 28 \
        -draw \"text $((X0+5)),1010 '$STATUS'\""
    done

    CMD="$CMD \
    -filter Lanczos \
    -resize 1100x550 \
    '$TMPPNG'"

    eval "$CMD"

    RC=$?

    if [[ $RC -ne 0 ]]; then
        echo "$(date '+%F %T') Render failed."
        sleep "$PNG_INTERVAL"
        continue
    fi

    mv -f "$TMPPNG" "$PNG_OUT"

    echo "$(date '+%F %T') PNG Updated"

    #######################################################
    # GIF Update Every 30 Minutes
    #######################################################

    NOW=$(date +%s)

    if (( NOW - LAST_GIF >= GIF_INTERVAL ))
    then

        STAMP=$(date -u '+%Y%m%d_%H%MZ')

        cp "$PNG_OUT" "$FRAME_DIR/${STAMP}.png"

        ls -1t "$FRAME_DIR"/*.png 2>/dev/null \
            | tail -n +$((MAX_FRAMES + 1)) \
            | xargs -r rm -f

        COUNT=$(find "$FRAME_DIR" -name "*.png" | wc -l)

        if (( COUNT > 1 ))
        then
            TMPGIF="/tmp/pskr_history.gif"

            convert \
                -delay 80 \
                -loop 0 \
                "$FRAME_DIR"/*.png \
                "$TMPGIF"

            if [[ -f "$TMPGIF" ]]; then
                mv -f "$TMPGIF" "$GIF_OUT"
                echo "$(date '+%F %T') GIF Updated ($COUNT frames)"
            fi
        fi

        LAST_GIF=$NOW
    fi

    sleep "$PNG_INTERVAL"

done
