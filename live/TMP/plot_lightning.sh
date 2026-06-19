#!/bin/bash
set -e

TARGET="/var/www/html/data/target.png"
DATA_JSON="/var/www/html/data/group_data.json"
OUTPUT="/var/www/html/data/lightning_map.png"

CENTER_X=627
CENTER_Y=627
MAX_RADIUS_PIXELS=585
MAX_MILES=100
PIXELS_PER_MILE=$(awk "BEGIN {print $MAX_RADIUS_PIXELS/$MAX_MILES}")

MY_LAT=33.6211836
MY_LON=-78.9648714

echo "=== CHECKPOINT 1: VERIFYING FILES ==="
for FILE in "$TARGET" "$DATA_JSON"
do
    if [ ! -f "$FILE" ]; then
        echo "ERROR: Missing file: $FILE"
        exit 1
    fi
done

# Read metrics from the unified group json
COUNT100=$(jq -r '.count100 // 0' "$DATA_JSON")
TIMESTAMP=$(jq -r '.timestamp // empty' "$DATA_JSON")

if [[ "$COUNT100" =~ ^[0-9]+$ ]] && (( COUNT100 > 0 )); then
    STATUS="LIGHTNING DETECTED"
    STATUS_COLOR="red"
else
    STATUS="SCOPE CLEAR"
    STATUS_COLOR="lime"
fi

echo "=== CHECKPOINT 2: GENERATING MVG IN MEMORY ==="
MVG_STREAM=""

# 1. Single Outer Blue Ring (100 miles)
RADIUS_PIXELS=$(awk "BEGIN {printf \"%d\", 100 * $PIXELS_PER_MILE}")
PERIMETER_Y=$((CENTER_Y + RADIUS_PIXELS))
TEXT_Y=$((CENTER_Y - RADIUS_PIXELS + 15))

MVG_STREAM="${MVG_STREAM}stroke-dasharray none stroke cyan fill none stroke-width 1 circle $CENTER_X,$CENTER_Y $CENTER_X,$PERIMETER_Y"$'\n'
MVG_STREAM="${MVG_STREAM}stroke-dasharray none fill cyan stroke black stroke-width 1 font DejaVu-Sans font-size 14 text $((CENTER_X + 5)),$TEXT_Y '100 mi'"$'\n'

# 2. Compass Heading Labels
for DIR in "N 0" "NE 45" "E 90" "SE 135" "S 180" "SW 225" "W 270" "NW 315"; do
    read -r LABEL ANGLE <<< "$DIR"
    RAD=$(awk "BEGIN {print $ANGLE * 3.141592653589793 / 180}")
    RP=$((MAX_RADIUS_PIXELS + 25))
    X=$(awk "BEGIN {printf \"%d\", $CENTER_X + $RP*sin($RAD)}")
    Y=$(awk "BEGIN {printf \"%d\", $CENTER_Y - $RP*cos($RAD)}")
    MVG_STREAM="${MVG_STREAM}stroke-dasharray none font DejaVu-Sans-Bold fill cyan stroke black stroke-width 2 font-size 38 text $X,$Y '$LABEL'"$'\n'
done

# 3. Reference Cities
declare -a CITIES_ARR=(
    "LCTY,33.89138,-79.75758"
    "CON,33.83600,-79.04780"
    "NMB,33.81600,-78.68000"
    "GTN,33.37680,-79.29450"
    "CHS,32.89261,-80.02204"
    "ILM,34.22570,-77.94470"
    "FLO,34.19540,-79.76260"
    "KIN,33.66710,-79.83060"
    "LOR,34.05600,-78.89000"
    "WHI,34.33880,-78.70310"
    "DIL,34.41274,-79.37831"
)

for C in "${CITIES_ARR[@]}"; do
    IFS=',' read -r C_NAME C_LAT C_LON <<< "$C"
    
    # We pass 'q' as a single quote parameter down to awk to avoid breaking the shell parser
    CITY_MVG=$(awk -v ml="$MY_LAT" -v mo="$MY_LON" -v cl="$C_LAT" -v co="$C_LON" \
        -v max_m="$MAX_MILES" -v cx="$CENTER_X" -v cy="$CENTER_Y" -v ppm="$PIXELS_PER_MILE" \
        -v name="$C_NAME" -v q="'" 'BEGIN {
        pi = 3.141592653589793
        r1 = ml * pi / 180; o1 = mo * pi / 180
        r2 = cl * pi / 180; o2 = co * pi / 180
        dl = r2 - r1; do_l = o2 - o1
        a = sin(dl/2)^2 + cos(r1) * cos(r2) * sin(do_l/2)^2
        d = 3959 * 2 * atan2(sqrt(a), sqrt(1-a))
        if (d <= max_m) {
            y_coord = sin(do_l) * cos(r2)
            x_coord = cos(r1) * sin(r2) - sin(r1) * cos(r2) * cos(do_l)
            b = (atan2(y_coord, x_coord) * 180 / pi + 360) % 360
            rad = b * pi / 180
            rp = d * ppm
            px = int(cx + rp * sin(rad) + 0.5)
            py = int(cy - rp * cos(rad) + 0.5)
            printf "stroke-dasharray none fill lime stroke white stroke-width 2 circle %d,%d %d,%d\n", px, py, px+5, py
            printf "fill white stroke black stroke-width 1 font DejaVu-Sans-Bold font-size 24 text %d,%d %s%s%s\n", px+14, py+8, q, name, q
        }
    }')
    if [ ! -z "$CITY_MVG" ]; then
        MVG_STREAM="${MVG_STREAM}${CITY_MVG}"$'\n'
    fi
done

# 4. High-Precision Lightning Groups (Pulls straight from the new .groups array)
STRIKES_RAW=$(jq -r '.groups[]? // empty | "\(.distance) \(.bearing)"' "$DATA_JSON" || echo "")

if [ ! -z "$STRIKES_RAW" ]; then
    STRIKES_MVG=$(awk -v cx="$CENTER_X" -v cy="$CENTER_Y" -v ppm="$PIXELS_PER_MILE" 'BEGIN { pi = 3.141592653589793 }
    {
        dist = $1; bearing = $2
        rad = bearing * pi / 180
        rp = dist * ppm
        x = int(cx + rp * sin(rad) + 0.5)
        y = int(cy - rp * cos(rad) + 0.5)
        
        color = "yellow"
        sz = 6
        printf "stroke-dasharray none stroke %s stroke-width 3 line %d,%d %d,%d line %d,%d %d,%d\n", \
            color, x - sz, y, x + sz, y, x, y - sz, x, y + sz
    }' <<< "$STRIKES_RAW")
    
    if [ ! -z "$STRIKES_MVG" ]; then
        MVG_STREAM="${MVG_STREAM}${STRIKES_MVG}"$'\n'
    fi
fi

echo "=== CHECKPOINT 3: RUNNING IMAGEMAGICK ==="
convert "$TARGET" -coalesce -draw "$MVG_STREAM" \
    -font DejaVu-Sans-Bold -fill deepskyblue -stroke black -strokewidth 1 -pointsize 24 -draw "text 950,1100 'ATLANTIC OCEAN'" \
    -font DejaVu-Sans-Bold -fill white -stroke black -strokewidth 1 -pointsize 24 -gravity southwest -annotate +15+15 "$TIMESTAMP" \
    -font DejaVu-Sans-Bold -fill "$STATUS_COLOR" -stroke black -strokewidth 1 -pointsize 28 -gravity southeast -annotate +15+15 "$STATUS" \
    "$OUTPUT"

echo "SUCCESS! Map updated using precision groups."
