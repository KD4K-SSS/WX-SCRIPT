#!/bin/bash

############################################################
# PSKReporter FT8 North America HF Propagation Collector
############################################################

##############################
# USER CONFIGURATION
##############################
BROKER="mqtt.pskreporter.info"
PORT="1883"
TOPIC="pskr/filter/v2raw_1pc/+/FT8/#"     # 1% Sampled Stream
MODE="FT8"
WINDOW_MINUTES=15                      # 15minute window in 5-minute bins
WRITE_INTERVAL=300                      # 5-minute throttled disk writes

# Web outputs
OUTPUT="/var/www/html/data/hf/pskr.json"
IMG_OUTPUT="/var/www/html/data/hf/pskr_heatmap.png"

# Temporary storage
TMPDIR="/mnt/ssbwx_tmp"

##############################
# INITIALIZATION
##############################
mkdir -p "$(dirname "$OUTPUT")"
mkdir -p "$TMPDIR"

# Establish a Linux FIFO named pipe for multiplexing the stream and timer
FIFO="$TMPDIR/pskr_propagation.fifo"
rm -f "$FIFO"
mkfifo "$FIFO"

# Comprehensive North American Grid Prefixes
NA_PREFIXES="CM CN DM DN EM EN FM FN AO AP BO BP BK BL CP DP EP FP DK DL EK EL FK FL"

# Map frequencies/bands to distinct Y-axis rows (0=Highest freq, 9=Lowest freq)
declare -A BAND_MAP

for b in 28 28M 28MHz 10m; do BAND_MAP[$b]=0; done
for b in 24 24M 24MHz 12m; do BAND_MAP[$b]=1; done
for b in 21 21M 21MHz 15m; do BAND_MAP[$b]=2; done
for b in 18 18M 18MHz 17m; do BAND_MAP[$b]=3; done
for b in 14 14M 14MHz 20m; do BAND_MAP[$b]=4; done
for b in 10 10M 10MHz 30m; do BAND_MAP[$b]=5; done
for b in 7 7M 7MHz 40m; do BAND_MAP[$b]=6; done
for b in 3 3M 3.5MHz 80m; do BAND_MAP[$b]=7; done
for b in 1 1M 1.8MHz 160m; do BAND_MAP[$b]=8; done

declare -a SPOTS
TOTAL=0
ACCEPTED=0

##############################
# FUNCTIONS
##############################
is_na_grid() {
    local GRID="$1"
    local PREFIX="${GRID:0:2}"
    [[ " $NA_PREFIXES " =~ " $PREFIX " ]]
}

cleanup_old() {
    local NOW KEEP NEW
    NOW=$(date +%s)
    KEEP=$((WINDOW_MINUTES * 60))
    NEW=()

    for spot in "${SPOTS[@]}"; do
        TS="${spot%%|*}"
        if (( NOW - TS <= KEEP )); then
            NEW+=("$spot")
        fi
    done
    SPOTS=("${NEW[@]}")
}
echo "$BAND" >> /tmp/pskr_bands.log

write_json() {
    local NOW
    NOW=$(date '+%Y-%m-%d %H:%M:%S')

    declare -A COUNT TOTAL_SNR BEST_SNR LAST

    for spot in "${SPOTS[@]}"; do
        IFS="|" read -r TS TX RX BAND SNR <<< "$spot"
        KEY="${TX}|${RX}|${BAND}"

        COUNT[$KEY]=$(( ${COUNT[$KEY]:-0} + 1 ))
        TOTAL_SNR[$KEY]=$(( ${TOTAL_SNR[$KEY]:-0} + SNR ))

        if [[ -z "${BEST_SNR[$KEY]}" ]] || (( SNR > BEST_SNR[$KEY] )); then
            BEST_SNR[$KEY]=$SNR
        fi
        LAST[$KEY]=$TS
    done

    {
        echo "{"
        echo "  \"timestamp\":\"$NOW\","
        echo "  \"window_minutes\":$WINDOW_MINUTES,"
        echo "  \"total_spots\":${#SPOTS[@]},"
        echo "  \"paths\":["

        local FIRST=1
        for KEY in "${!COUNT[@]}"; do
            IFS="|" read -r TX RX BAND <<< "$KEY"
             
            local AVG=0
            if (( COUNT[$KEY] > 0 )); then
                AVG=$(( TOTAL_SNR[$KEY] / COUNT[$KEY] ))
            fi

            if (( FIRST == 0 )); then
                echo ","
            fi
            FIRST=0

            cat <<EOF
    {
      "tx":"$TX",
      "rx":"$RX",
      "band":"$BAND",
      "count":${COUNT[$KEY]},
      "avg_snr":$AVG,
      "best_snr":${BEST_SNR[$KEY]},
      "last_seen":${LAST[$KEY]}
    }
EOF
        done
        echo "  ]"
        echo "}"
    } > "$OUTPUT"
}

write_heatmap() {

    local IM
    command -v magick >/dev/null 2>&1 && IM="magick" || IM="convert"

    ####################################################
    # HIGH-RES CANVAS
    ####################################################

    local CANVAS_W=2200
    local CANVAS_H=1100

    local LEFT=200
    local BOTTOM=800

    local BAR_W=140
    local GAP=70

    declare -A BAND_COUNT

    BANDS=("160m" "80m" "40m" "30m" "20m" "17m" "15m" "12m" "10m")

    for spot in "${SPOTS[@]}"; do

        IFS="|" read -r TS TX RX BAND SNR <<< "$spot"

        case "$BAND" in
            "160m"|"80m"|"40m"|"30m"|"20m"|"17m"|"15m"|"12m"|"10m")
                BAND_COUNT[$BAND]=$(( ${BAND_COUNT[$BAND]:-0} + 1 ))
                ;;
        esac

    done

    MAX=1

    for B in "${BANDS[@]}"; do
        V=${BAND_COUNT[$B]:-0}
        (( V > MAX )) && MAX=$V
    done

    (( MAX < 1 )) && MAX=1

    TOTAL_SPOTS=${#SPOTS[@]}

    ####################################################
    # FRAME COUNTER + UTC TIMESTAMP
    ####################################################

    ZTIME=$(date -u '+%d %b %Y %H:%MZ')

    FRAME_FILE="$TMPDIR/frame_counter"

    if [[ ! -f "$FRAME_FILE" ]]; then
        echo 1 > "$FRAME_FILE"
    fi

    FRAME=$(cat "$FRAME_FILE")
    echo $((FRAME + 1)) > "$FRAME_FILE"

    FRAMESTAMP="Frame $FRAME | $ZTIME"

    ####################################################
    # CREATE BLANK CANVAS
    ####################################################

    "$IM" -size ${CANVAS_W}x${CANVAS_H} xc:"#101010" "$IMG_OUTPUT"

    ####################################################
    # REFERENCE LINES
    ####################################################

    "$IM" "$IMG_OUTPUT" \
        -stroke "#303030" \
        -strokewidth 2 \
        -draw "line 160,240 2000,240" \
        -draw "line 160,440 2000,440" \
        -draw "line 160,640 2000,640" \
        -draw "line 160,800 2000,800" \
        "$IMG_OUTPUT"

    ####################################################
    # TITLE AND LABELS
    ####################################################

    "$IM" "$IMG_OUTPUT" \
        -font DejaVu-Sans-Bold \
        -fill white \
        -pointsize 48 \
        -draw "text 280,80 'North America FT8 Activity Monitor'" \
        -draw "text 1680,80 'Spots: $TOTAL_SPOTS'" \
        -pointsize 36 \
        -draw "text 1200,140 '$FRAMESTAMP'" \
        -pointsize 40 \
        -draw "text 20,250 'GOOD'" \
        -draw "text 20,450 'WEAK'" \
        -draw "text 20,650 'POOR'" \
        "$IMG_OUTPUT"

    # --------------------------------------------------
    # DRAW BARS
    # --------------------------------------------------
    local IDX=0
    for B in "${BANDS[@]}"; do
        local COUNT=${BAND_COUNT[$B]:-0}
        local COLOR="#101010"
        local STATUS="Closed"

        if [ "$COUNT" -gt 0 ] && [ "$COUNT" -lt 25 ]; then
            COLOR="#ff0000"
            STATUS="Poor"
        elif [ "$COUNT" -ge 25 ] && [ "$COUNT" -lt 150 ]; then
            COLOR="#ffff00"
            STATUS="Weak"
        elif [ "$COUNT" -ge 150 ]; then
            COLOR="#00ff00"
            STATUS="Good"
        fi

        local HEIGHT=$((100 + (COUNT * 500 / MAX)))
        if [ "$HEIGHT" -gt 600 ]; then
            HEIGHT=600
        fi

        local X0=$((LEFT + IDX*(BAR_W+GAP)))
        local X1=$((X0 + BAR_W))
        local Y0=$((BOTTOM - HEIGHT))
        local COUNT_Y=$((Y0 - 24))

        # 1. Draw the Column Box with the Gray Border Outline
        "$IM" "$IMG_OUTPUT" \
            -stroke "#505050" \
            -strokewidth 3 \
            -fill "$COLOR" \
            -draw "rectangle $X0,$Y0 $X1,$BOTTOM" \
            "$IMG_OUTPUT"

        # 2. Draw the Labels (Turn OFF stroke, force crisp White fill)
        "$IM" "$IMG_OUTPUT" \
            -stroke none \
            -fill white \
            -pointsize 40 \
            -draw "text $((X0+10)),$COUNT_Y '$COUNT'" \
            -pointsize 48 \
            -draw "text $((X0+5)),950 '$B'" \
            -pointsize 28 \
            -draw "text $((X0+5)),1010 '$STATUS'" \
            "$IMG_OUTPUT"

        IDX=$((IDX + 1))
    done
    ####################################################
    # DOWNSAMPLE FOR BETTER ANTIALIASING
    ####################################################

    "$IM" "$IMG_OUTPUT" \
        -filter Lanczos \
        -resize 1100x550 \
        "$IMG_OUTPUT"

    echo "$(date '+%F %T') Saved $IMG_OUTPUT"
}
##############################
# BACKGROUND WORKERS
##############################

# Worker 1: Heartbeat Timer (Injects a forced update token into the pipe every 5 minutes)
(
    while true; do
        sleep "$WRITE_INTERVAL"
        echo "TICK|||"
    done
) > "$FIFO" &
TIMER_PID=$!

# Worker 2: High-Speed Mosquitto Sub Feed
mosquitto_sub -h "$BROKER" -p "$PORT" -t "$TOPIC" -q 0 -v | jq -R --unbuffered -rc '
  capture("^(?<topic>[^ ]+) (?<payload>.*)$") | 
  (.topic | split("/")) as $parts | 
  (.payload | fromjson) as $json |
  $parts[3] as $band |
  $json | select(.md == "FT8" and .sl != null and .rl != null) |
  "\($band)|\(.sl[0:4])|\(.rl[0:4])|\(.rp // 0)"
' > "$FIFO" &
SUB_PID=$!

# Safety trap to kill background tasks when closing or restarting script
cleanup_exit() {
    kill "$TIMER_PID" "$SUB_PID" 2>/dev/null
    rm -f "$FIFO"
    exit 0
}
trap cleanup_exit SIGINT SIGTERM EXIT

##############################
# MAIN PROCESSING ENGINE
##############################
clear
echo "=========================================="
echo " FT8 North America HF Propagation Engine  "
echo "=========================================="
echo "Stream active. Monitoring MQTT feed..."
echo "------------------------------------------"

while IFS="|" read -r BAND TX RX SNR; do
echo "$BAND" >> /tmp/pskr_bands.log
    TS=$(date +%s)

    # Handle the 5-Minute Force-Write Heartbeat Tick
    if [[ "$BAND" == "TICK" ]]; then
        cleanup_old
        write_json
        write_heatmap
        # Print a clean newline so the heartbeat log stays in the terminal history
        echo -e "\n$(date '+%T') [HEARTBEAT] 💾 JSON & Heatmap saved! Active Matrix: ${#SPOTS[@]} tracks."
        continue
    fi

    ((TOTAL++))

    # Validate North American Footprint
    if ! is_na_grid "$TX" && ! is_na_grid "$RX"; then
        # Update the live ticker even for skipped spots so you see the stream is alive
        echo -ne "$(date '+%T') | Raw: $TOTAL | NA Accepted: $ACCEPTED | [Skipped: $TX -> $RX]\r"
        continue
    fi

    SPOTS+=("$TS|$TX|$RX|$BAND|$SNR")
    ((ACCEPTED++))

    # Live rolling ticker for accepted spots (overwrites the line in place)
    echo -ne "$(date '+%T') | Raw: $TOTAL | NA Accepted: $ACCEPTED | [Incoming: $TX -> $RX ($BAND)]\033[K\r"

done < "$FIFO"
