#!/bin/bash

#################################
# PART 1 - SETUP
#################################

WORKDIR="$HOME/goes19"
FILE="$WORKDIR/latest.nc"

RING_FILE="$WORKDIR/ring_history.txt"
JSON_FILE="/var/www/html/data/group_data.json"
LOG_FILE="$WORKDIR/group_event_log.csv"

# Ensure log and ring files exist cleanly
if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
    echo "timestamp,count10,count25,count50,count100,rate10,rate25,rate50,rate100,nearest,lat,lon,score" > "$LOG_FILE"
fi

touch "$RING_FILE"

MY_LAT=33.621
MY_LON=-78.964
INTERVAL=120

while true; do
    clear

    echo "GOES-19 GROUP LIGHTNING RADAR"
    echo "Time (EDT): $(TZ="America/New_York" date '+%Y-%m-%d %H:%M:%S')"
    echo "Location: Surfside Beach SC"
    echo "------------------------------------"

    #################################
    # PART 1A - FILE CHECK
    #################################

    if [ ! -f "$FILE" ]; then
        echo "GLM Data Failed"
        sleep "$INTERVAL"
        continue
    fi

    PROCESS_FILE="$WORKDIR/processing.nc"
    cp "$FILE" "$PROCESS_FILE"
    echo "GLM Data Updated"

    #################################
    # PART 1B - EXTRACT & COUNT TOTAL GROUPS
    #################################

    RAW_GROUPS=$(paste <(ncks -C -H -v group_lat "$PROCESS_FILE" 2>/dev/null | grep -Eo '[-0-9]+\.[0-9]+') \
                       <(ncks -C -H -v group_lon "$PROCESS_FILE" 2>/dev/null | grep -Eo '[-0-9]+\.[0-9]+'))

    TOTAL_GROUPS=$(wc -l <<< "$RAW_GROUPS")
    echo "Total Lightning Groups in File: $TOTAL_GROUPS"

    #################################
    # PART 2 - STREAMED AWK PASS
    #################################

    RESULTS=$(echo "$RAW_GROUPS" | awk -v mylat="$MY_LAT" -v mylon="$MY_LON" '
    BEGIN {
        pi=3.141592653589793
        count10=count25=count50=count100=0
        nearest=999999
        nearlat=nearlon=""
        score=0
    }
    NF==2 {
        lat=$1; lon=$2

        if(lat < 24 || lat > 38 || lon < -90 || lon > -70) next

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

        score += exp(-dist/20)
    }
    END {
        printf "%.6f|%.6f|%.6f|%d|%d|%d|%d|%.6f\n", nearest, nearlat, nearlon, count10, count25, count50, count100, score
    }')

    IFS='|' read -r NEAREST NEAR_LAT NEAR_LON COUNT10 COUNT25 COUNT50 COUNT100 SCORE <<< "$RESULTS"

    #################################
    # PART 2A - NO LIGHTNING PROTECTION
    #################################

    if [ "$NEAREST" = "999999.000000" ]; then
        NEAR_LAT="N/A"
        NEAR_LON="N/A"
        DISPLAY_DIST="N/A"
    else
        DISPLAY_DIST=$(printf "%.1f" "$NEAREST")
    fi

    JSON_SCORE=$(printf "%.3f" "$SCORE")

    #################################
    # PART 3 - SAVE RING HISTORY
    #################################

    echo "$COUNT10 $COUNT25 $COUNT50 $COUNT100" >> "$RING_FILE"
    tail -n 3 "$RING_FILE" > "${RING_FILE}.tmp" && mv "${RING_FILE}.tmp" "$RING_FILE"

    #################################
    # PART 3A - COMPUTE 6-MINUTE TOTALS
    #################################

    read -r SUM10 SUM25 SUM50 SUM100 <<< $(awk '{ s10 += $1; s25 += $2; s50 += $3; s100 += $4 } END { print s10, s25, s50, s100 }' "$RING_FILE")

    [ -z "$SUM10" ] && SUM10=0
    [ -z "$SUM25" ] && SUM25=0
    [ -z "$SUM50" ] && SUM50=0
    [ -z "$SUM100" ] && SUM100=0

    # Group Rates over a 6-minute history frame
    RATE10=$(awk -v s="$SUM10" 'BEGIN{printf "%.1f", s/6}')
    RATE25=$(awk -v s="$SUM25" 'BEGIN{printf "%.1f", s/6}')
    RATE50=$(awk -v s="$SUM50" 'BEGIN{printf "%.1f", s/6}')
    RATE100=$(awk -v s="$SUM100" 'BEGIN{printf "%.1f", s/6}')

    #################################
    # PART 3D - HISTORICAL EVENT LOG
    #################################

    if [ "$COUNT100" -gt 0 ]; then
        echo "$(TZ="America/New_York" date '+%Y-%m-%d %H:%M:%S'),$COUNT10,$COUNT25,$COUNT50,$COUNT100,$RATE10,$RATE25,$RATE50,$RATE100,$NEAREST,$NEAR_LAT,$NEAR_LON,$SCORE" >> "$LOG_FILE"
    fi

    # Safe prune tool to keep header record intact
    if [ $(wc -l < "$LOG_FILE") -gt 10005 ]; then
        head -n 1 "$LOG_FILE" > "${LOG_FILE}.tmp"
        tail -n 10000 "$LOG_FILE" >> "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi

    #################################
    # PART 4 - DISPLAY TERMINAL WINDOW
    #################################

    echo "------------------------------------"
    echo "Closest lightning group:"
    if [ "$DISPLAY_DIST" != "N/A" ]; then
        echo "  Lat: $NEAR_LAT"
        echo "  Lon: $NEAR_LON"
        echo "  Distance: $DISPLAY_DIST miles"
    else
        echo "  None"
    fi

    echo ""
    echo "Group Activity Metrics:"
    printf "  Group Score: %.3f\n" "$SCORE"

    echo ""
    echo "Groups within radius (6-min accumulation):"
    echo "   10 mi : $SUM10"
    echo "   25 mi : $SUM25"
    echo "   50 mi : $SUM50"
    echo "  100 mi : $SUM100"

    echo ""
    echo "Group Strike Frequency Rate:"
    echo "   10 mi : ${RATE10}/min"
    echo "   25 mi : ${RATE25}/min"
    echo "   50 mi : ${RATE50}/min"
    echo "  100 mi : ${RATE100}/min"
    echo "------------------------------------"

    #################################
    # PART 4A - WRITE ATOMIC JSON (With full group data)
    #################################

    GROUP_ARRAY_JSON=$(echo "$RAW_GROUPS" | awk -v mylat="$MY_LAT" -v mylon="$MY_LON" '
    BEGIN {
        pi=3.141592653589793
        printf "["
        first=1
    }
    NF==2 {
        lat=$1; lon=$2
        if(lat < 24 || lat > 38 || lon < -90 || lon > -70) next

        dlat=(lat-mylat)*pi/180
        dlon=(lon-mylon)*pi/180

        a=sin(dlat/2)^2 + cos(mylat*pi/180)*cos(lat*pi/180)*sin(dlon/2)^2
        if (a > 1) a = 1
        c=2*atan2(sqrt(a),sqrt(1-a))
        dist=c*3958.8

        if (dist <= 100) {
            y_coord = sin(dlon) * cos(lat*pi/180)
            x_coord = cos(mylat*pi/180) * sin(lat*pi/180) - sin(mylat*pi/180) * cos(lat*pi/180) * cos(dlon)
            bearing = (atan2(y_coord, x_coord) * 180 / pi + 360) % 360

            if (!first) printf ","
            printf "{\"distance\":%.2f,\"bearing\":%.2f}", dist, bearing
            first=0
        }
    }
    END {
        printf "]"
    }')

    cat > "$JSON_FILE" << EOF
{
  "timestamp":"$(TZ="America/New_York" date '+%Y-%m-%d %H:%M:%S')",
  "nearest_lat":"$NEAR_LAT",
  "nearest_lon":"$NEAR_LON",
  "nearest_distance":"$DISPLAY_DIST",
  "group_score":"$JSON_SCORE",
  "count10":$SUM10,
  "count25":$SUM25,
  "count50":$SUM50,
  "count100":$SUM100,
  "rate10":"$RATE10",
  "rate25":"$RATE25",
  "rate50":"$RATE50",
  "rate100":"$RATE100",
  "total_file_groups":${TOTAL_GROUPS:-0},
  "groups": $GROUP_ARRAY_JSON
}
EOF

    rm -f "$PROCESS_FILE"

    #################################
    # PART 4B - COUNTDOWN TIMERS
    #################################
    for ((sec=INTERVAL; sec>0; sec--)); do
        printf "\rRefreshing in %02d:%02d " $((sec/60)) $((sec%60))
        sleep 1
    done
    echo ""
done
