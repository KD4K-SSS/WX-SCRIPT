#!/bin/bash
set -e

WORKDIR="$HOME/goes19"
FILE="$WORKDIR/latest.nc"
OUT="/var/www/html/data/flashes.json"
TRACK_FILE="/var/www/html/data/storm_track.csv"

touch "$TRACK_FILE"

# Surfside Beach SC Reference
MY_LAT=33.621
MY_LON=-78.964
MAX_MILES=100
INTERVAL=120 # 2 minutes execution cycle

while true; do
    echo "=========================================="
    echo "Starting Flashes Pass: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="

    if [ ! -f "$FILE" ]; then
        echo "[]" > "$OUT"
        echo "No latest.nc found this cycle. Skipping..."
        
        # Countdown sleep before continuing to next loop pass
        for ((sec=INTERVAL; sec>0; sec--)); do
            printf "\rNext flashes pass in %02d:%02d   " $((sec/60)) $((sec%60))
            sleep 1
        done
        echo ""
        continue
    fi

    PROCESS_FILE="$WORKDIR/processing_flashes.nc"
    cp "$FILE" "$PROCESS_FILE"

    echo "=== Processing GOES-19 Lightning Array ==?"

    # 1. Stream values side-by-side directly into a single optimized awk pipeline
    RAW_FLASHES=$(paste <(ncks -C -H -v flash_lat "$PROCESS_FILE" 2>/dev/null | grep -Eo '[-0-9]+\.[0-9]+') \
                        <(ncks -C -H -v flash_lon "$PROCESS_FILE" 2>/dev/null | grep -Eo '[-0-9]+\.[0-9]+'))

    # 2. Process all math operations and compile structured JSON in one pass
    # Using double quotes on awk to bypass the single-quote syntax parser completely
    jq_input=$(echo "$RAW_FLASHES" | awk -v mylat="$MY_LAT" -v mylon="$MY_LON" -v max_m="$MAX_MILES" "
    BEGIN {
        pi = 3.141592653589793
        print \"[\"
        first = 1
        count = 0
    }
    NF==2 {
        lat = \$1; lon = \$2

        # Calculate Distance (Haversine)
        dlat = (lat - mylat) * pi / 180
        dlon = (lon - mylon) * pi / 180
        a = sin(dlat/2)^2 + cos(mylat * pi / 180) * cos(lat * pi / 180) * sin(dlon/2)^2
        if (a > 1) a = 1
        c = 2 * atan2(sqrt(a), sqrt(1-a))
        dist = c * 3958.8

        # Filter out strikes outside radius
        if (dist > max_m) next

        # Calculate Bearing
        rad_mylat = mylat * pi / 180
        rad_mylon = mylon * pi / 180
        rad_lat = lat * pi / 180
        rad_lon = lon * pi / 180
        
        y = sin(rad_lon - rad_mylon) * cos(rad_lat)
        x = cos(rad_mylat) * sin(rad_lat) - sin(rad_mylat) * cos(rad_lat) * cos(rad_lon - rad_mylon)
        brng = atan2(y, x) * 180 / pi
        if (brng < 0) brng += 360

        if (!first) print \",\"
        first = 0
        count++

        printf \"  {\\n    \\\"lat\\\": %.5f,\\n    \\\"lon\\\": %.5f,\\n    \\\"distance\\\": %.1f,\\n    \\\"bearing\\\": %.1f,\\n    \\\"age_minutes\\\": 0\\n  }\", lat, lon, dist, brng
    }
    END {
        print \"]\"
    }")

    # Write atomic file cleanly to eliminate web server race-conditions
    echo "$jq_input" > "$OUT"

    # 3. Update the rolling storm track logs using lightning arrays
    COUNT=$(jq length "$OUT" 2>/dev/null || echo 0)

    if [ "$COUNT" -eq 0 ]; then
        # Completely clean out flashes array if jq had rendering errors or empty string
        echo "[]" > "$OUT"
        COUNT=0
    fi

    if [ "$COUNT" -ge 5 ]; then
        # Protect against zero division by validating count length inside jq environment natively
        AVG_LAT=$(jq 'if length > 0 then ([.[].lat] | add / length) else 0 end' "$OUT")
        AVG_LON=$(jq 'if length > 0 then ([.[].lon] | add / length) else 0 end' "$OUT")
        NOW=$(date +%s)

        if [ "$AVG_LAT" != "0" ]; then
            echo "$NOW,$AVG_LAT,$AVG_LON" >> "$TRACK_FILE"
            # Keep only the last 3 track histories
            tail -n 3 "$TRACK_FILE" > "${TRACK_FILE}.tmp" && mv "${TRACK_FILE}.tmp" "$TRACK_FILE"
        fi
    fi

    echo "Created $OUT"
    echo "Flashes within ${MAX_MILES} miles: $COUNT"
    rm -f "$PROCESS_FILE"

    # Loop countdown delay block
    echo "Flashes calculation pass finished."
    for ((sec=INTERVAL; sec>0; sec--)); do
        printf "\rNext flashes pass in %02d:%02d   " $((sec/60)) $((sec%60))
        sleep 1
    done
    echo ""
done
