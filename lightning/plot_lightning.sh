#!/bin/bash

TARGET="/var/www/html/data/target.png"
DATA_JSON="/var/www/html/data/data.json"
FLASH_JSON="/var/www/html/data/flashes.json"
OUTPUT="/var/www/html/data/lightning_map.png"

#########################################
# TARGET IMAGE CALIBRATION
#########################################

# target.png is 1254 x 1254
CENTER_X=627
CENTER_Y=627

# Scaled from previous 600px image:
# 280 px @ 600px image ≈ 585 px @ 1254px image
MAX_RADIUS_PIXELS=585

MAX_MILES=100

PIXELS_PER_MILE=$(awk "BEGIN {print $MAX_RADIUS_PIXELS/$MAX_MILES}")

#########################################
# VERIFY FILES EXIST
#########################################

for FILE in "$TARGET" "$DATA_JSON" "$FLASH_JSON"
do
    if [ ! -f "$FILE" ]; then
        echo "Error: Missing file: $FILE"
        exit 1
    fi
done

#########################################
# DETERMINE SCOPE STATUS
#########################################

COUNT100=$(jq -r '.count100 // 0' "$DATA_JSON")

if [[ "$COUNT100" =~ ^[0-9]+$ ]] && (( COUNT100 > 0 )); then
    STATUS="LIGHTNING DETECTED"
    STATUS_COLOR="red"
else
    STATUS="SCOPE CLEAR"
    STATUS_COLOR="lime"
fi

#########################################
# BUILD STRIKE OVERLAYS
#########################################

DRAW=""

while read -r flash
do
    DIST=$(echo "$flash" | jq -r '.distance')
    BEARING=$(echo "$flash" | jq -r '.bearing')

    [ "$DIST" = "null" ] && continue
    [ "$BEARING" = "null" ] && continue

    #########################################
    # Bearing → radians
    #########################################

    RAD=$(awk "BEGIN {print $BEARING * 3.141592653589793 / 180}")

    #########################################
    # Distance → pixels
    #########################################

    RP=$(awk "BEGIN {print $DIST * $PIXELS_PER_MILE}")

    #########################################
    # Compute image coordinates
    #########################################

    X=$(awk "BEGIN {printf \"%d\", $CENTER_X + $RP*sin($RAD)}")
    Y=$(awk "BEGIN {printf \"%d\", $CENTER_Y - $RP*cos($RAD)}")

    #########################################
    # Optional debug output
    #########################################

    echo "Plotting: ${DIST} mi @ ${BEARING}° -> X=${X} Y=${Y}"

    #########################################
    # Larger strike marker
    #########################################

    DRAW="$DRAW \
    -stroke yellow \
    -strokewidth 4 \
    -draw \"line $((X-12)),$Y $((X+12)),$Y\" \
    -draw \"line $X,$((Y-12)) $X,$((Y+12))\""

done < <(jq -c '.[]' "$FLASH_JSON")

#########################################
# CREATE IMAGE
#########################################

eval convert "\"$TARGET\"" \
    $DRAW \
    -fill "$STATUS_COLOR" \
    -pointsize 28 \
    -gravity southeast \
    -annotate +15+15 "\"$STATUS\"" \
    "\"$OUTPUT\""

echo
echo "Created $OUTPUT"
echo "Status: $STATUS"
echo "Lightning within 100 miles: $COUNT100"
echo "Plotted strikes: $(jq length "$FLASH_JSON")"
