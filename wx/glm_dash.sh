#!/bin/bash

WORKDIR="$HOME/goes19"
FILE="$WORKDIR/latest.nc"
STATE_FILE="$WORKDIR/radar_state.txt"
TREND_FILE="$WORKDIR/nearest_history.txt"
HISTORY_JSON="/var/www/html/data/history.jsonl"
JSON_FILE="/var/www/html/data/data.json"

# Setup initial structural files
touch "$TREND_FILE" "$HISTORY_JSON"

MY_LAT=33.621
MY_LON=-78.964
INTERVAL=300

while true; do
    clear

    echo "GOES-19 SOUTHEAST LIGHTNING RADAR DASHBOARD"
    echo "Time (EDT): $(TZ="America/New_York" date '+%Y-%m-%d %H:%M:%S')"
    echo "Location: Surfside Beach SC"
    echo "------------------------------------"

    #########################################
    # FILE CHECK
    #########################################

    if [ ! -f "$FILE" ]; then
        echo "GLM Data Failed"
        sleep "$INTERVAL"
        continue
    fi
    
    PROCESS_FILE="$WORKDIR/processing.nc"
    cp "$FILE" "$PROCESS_FILE"
    echo "GLM Data Updated"

    #########################################
    # STREAMED EXTRACTION AND UNIFIED CALCULATIONS
    #########################################

    # Stream the values side-by-side cleanly in-memory
    RAW_FLASHES=$(paste <(ncks -C -H -v flash_lat "$PROCESS_FILE" 2>/dev/null | grep -Eo '[-0-9]+\.[0-9]+') \
                        <(ncks -C -H -v flash_lon "$PROCESS_FILE" 2>/dev/null | grep -Eo '[-0-9]+\.[0-9]+'))

    FLASH_COUNT=$(wc -l <<< "$RAW_FLASHES")
    echo "Total strikes in file: $FLASH_COUNT"

    # Process all coordinates in a single ultra-fast pass
    RESULTS=$(echo "$RAW_FLASHES" | awk -v mylat="$MY_LAT" -v mylon="$MY_LON" '
    BEGIN {
        pi=3.141592653589793
        count10=count25=count50=count100=0
        nearest=999999
        nearlat=nearlon=""
        total_score=0
    }
    NF==2 {
        lat=$1; lon=$2

        # Southeast regional filter bounding box
        if (lat < 24 || lat > 38 || lon < -90 || lon > -70) next

        dlat=(lat-mylat)*pi/180
        dlon=(lon-mylon)*pi/180

        a=sin(dlat/2)^2 + cos(mylat*pi/180)*cos(lat*pi/180)*sin(dlon/2)^2
        if (a > 1) a = 1
        c=2*atan2(sqrt(a),sqrt(1-a))
        dist=c*3958.8

        if(dist <= 10)  count10++
        if(dist <= 25)  count25++
        if(dist <= 50)  count50++
        if(dist <= 100) count100++

        if(dist < nearest) {
            nearest=dist
            nearlat=lat
            nearlon=lon
        }
        total_score += exp(-dist/20)
    }
    END {
        # Calculate Heading Bearing Vector if lightning was caught
        brng = ""
        if (nearest != 999999) {
            rad_mylat = mylat*pi/180
            rad_mylon = mylon*pi/180
            rad_nlat = nearlat*pi/180
            rad_nlon = nearlon*pi/180
            
            y = sin(rad_nlon - rad_mylon) * cos(rad_nlat)
            x = cos(rad_mylat) * sin(rad_nlat) - sin(rad_mylat) * cos(rad_nlat) * cos(rad_nlon - rad_mylon)
            brng = atan2(y, x) * 180 / pi
            if (brng < 0) brng += 360
        }
        printf "%d|%d|%d|%d|%.6f|%.6f|%.6f|%.6f|%s\n", 
            count10, count25, count50, count100, nearest, nearlat, nearlon, total_score, brng
    }')

    IFS='|' read -r COUNT10 COUNT25 COUNT50 COUNT100 NEAREST_DIST CLOSEST_LAT CLOSEST_LON TOTAL_SCORE HEADING <<< "$RESULTS"

    #########################################
    # VECTOR AND RADIAL INTERPRETATION
    #########################################

    DIR=""
    if [ "$NEAREST_DIST" != "999999.000000" ]; then
        DIR_IDX=$(awk -v h="$HEADING" 'BEGIN{print int((h+22.5)/45)%8}')
        case "$DIR_IDX" in
            0) DIR="N" ;; 1) DIR="NE" ;; 2) DIR="E" ;; 3) DIR="SE" ;;
            4) DIR="S" ;; 5) DIR="SW" ;; 6) DIR="W" ;; 7) DIR="NW" ;;
        esac
    else
        NEAREST_DIST=""
        HEADING=""
    fi

    # Calculate 5-scan moving window intervals (5 x 5 min = 25 Min window)
    if [ -n "$NEAREST_DIST" ]; then
        echo "$NEAREST_DIST" >> "$TREND_FILE"
    else
        echo "999999" >> "$TREND_FILE"  # Placeholder to maintain continuity when clear
    fi

    tail -n 5 "$TREND_FILE" > "${TREND_FILE}.tmp" && mv "${TREND_FILE}.tmp" "$TREND_FILE"

    # Compute Moving Smoothed Windows (Syntax Bug Fixed Here)
    TREND_RAW=$(awk '
    {
        if ($1 != 999999) { sum += $1; valid++ }
        arr[NR] = $1
    }
    END {
        sm = (valid > 0) ? sum/valid : 0
        diff = 0
        status = "STABLE"
        
        if (NR >= 2 && arr[1] != 999999 && arr[NR] != 999999) {
            diff = arr[NR] - arr[1]
            if (diff <= -2) status = "APPROACHING"
            else if (diff >= 2) status = "MOVING AWAY"
        } else if (valid == 0) {
            status = "NO LIGHTNING"
        }
        printf "%.1f|%.1f|%s\n", sm, diff, status
    }' "$TREND_FILE")

    IFS='|' read -r SMOOTHED_DIST TREND_CHANGE MOVE_STATUS <<< "$TREND_RAW"

    # Compute Flash Rates (/min over the 5 minute file window)
    RATE10=$(awk -v c="$COUNT10" 'BEGIN{printf "%.1f", c/5}')
    RATE25=$(awk -v c="$COUNT25" 'BEGIN{printf "%.1f", c/5}')
    RATE50=$(awk -v c="$COUNT50" 'BEGIN{printf "%.1f", c/5}')
    RATE100=$(awk -v c="$COUNT100" 'BEGIN{printf "%.1f", c/5}')

    #########################################
    # DISPLAY
    #########################################

    echo "------------------------------------"
    echo "Lightning Activity in Surfside Beach Radius:"
    printf "  Strike Score: %.3f\n" "$TOTAL_SCORE"

    STATUS_TXT="Quiet"
    if awk "BEGIN {exit !($TOTAL_SCORE > 5)}"; then STATUS_TXT="VERY ACTIVE (nearby storms)"
    elif awk "BEGIN {exit !($TOTAL_SCORE > 2)}"; then STATUS_TXT="ACTIVE"
    elif awk "BEGIN {exit !($TOTAL_SCORE > 0.5)}"; then STATUS_TXT="LIGHT activity"; fi
    echo "  Status: $STATUS_TXT"
    echo "------------------------------------"

    if [ -n "$CLOSEST_LAT" ]; then
        echo "Closest lightning strike:"
        echo "  Lat: $CLOSEST_LAT"
        echo "  Lon: $CLOSEST_LON"
        printf "  Distance: %.2f miles\n" "$NEAREST_DIST"
        [ -n "$HEADING" ] && echo "  Heading: ${HEADING}° ($DIR)"
    else
        echo "No lightning detected."
    fi

    echo "------------------------------------"
    echo "Storm direction trend: $MOVE_STATUS"
    if [ -n "$CLOSEST_LAT" ]; then
        printf "Smoothed distance (25 min): %s miles\n" "$SMOOTHED_DIST"
        printf "Trend change: %s miles\n" "$TREND_CHANGE"
    fi
    echo "------------------------------------"
    echo "Lightning within radius:"
    printf "  10 mi  : %d\n" "$COUNT10"
    printf "  25 mi  : %d\n" "$COUNT25"
    printf "  50 mi  : %d\n" "$COUNT50"
    printf "  100 mi : %d\n" "$COUNT100"
    echo ""
    echo "Flash rate:"
    printf "  10 mi  : %s/min\n" "$RATE10"
    printf "  25 mi  : %s/min\n" "$RATE25"
    printf "  50 mi  : %s/min\n" "$RATE50"
    printf "  100 mi : %s/min\n" "$RATE100"
    echo "------------------------------------"

    #########################################
    # EXPORTS (JSON & LOG STACKS)
    #########################################

    cat > "$JSON_FILE" << EOF
{
  "timestamp":"$(TZ="America/New_York" date '+%Y-%m-%d %H:%M:%S')",
  "flash_count":$FLASH_COUNT,
  "strike_score":$TOTAL_SCORE,
  "nearest_distance":"$NEAREST_DIST",
  "smoothed_distance":"$SMOOTHED_DIST",
  "trend_change":"$TREND_CHANGE",
  "closest_lat":"$CLOSEST_LAT",
  "closest_lon":"$CLOSEST_LON",
  "heading":"$HEADING",
  "direction":"$DIR",
  "movement":"$MOVE_STATUS",
  "count10":$COUNT10,
  "count25":$COUNT25,
  "count50":$COUNT50,
  "count100":$COUNT100,
  "rate10":"$RATE10",
  "rate25":"$RATE25",
  "rate50":"$RATE50",
  "rate100":"$RATE100"
}
EOF

    echo "{\"timestamp\":\"$(TZ="America/New_York" date '+%Y-%m-%d %H:%M:%S')\",\"nearest\":\"$NEAREST_DIST\",\"smoothed\":\"$SMOOTHED_DIST\",\"score\":\"$TOTAL_SCORE\",\"count10\":$COUNT10,\"count25\":$COUNT25,\"count50\":$COUNT50,\"count100\":$COUNT100,\"rate25\":\"$RATE25\"}" >> "$HISTORY_JSON"
    tail -n 2016 "$HISTORY_JSON" > "${HISTORY_JSON}.tmp" && mv "${HISTORY_JSON}.tmp" "$HISTORY_JSON"

    # Save radar runtime state file
    printf "%s %s %s %s %s %s\n" "$TOTAL_SCORE" "${NEAREST_DIST:-999999}" "$COUNT10" "$COUNT25" "$COUNT50" "$COUNT100" > "$STATE_FILE"

    #########################################
    # REFRESH COUNTDOWN
    #########################################
    for ((sec=INTERVAL; sec>0; sec--)); do
        printf "\rRefreshing in %02d:%02d   " $((sec/60)) $((sec%60))
        sleep 1
    done
    printf "\rRefreshing in 00:00        \n"
done
