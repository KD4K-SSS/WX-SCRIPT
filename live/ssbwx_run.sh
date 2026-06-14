#!/bin/bash
#set +e

WORKDIR="$HOME/goes19"
FILE="$WORKDIR/latest.nc"
STATE_FILE="$WORKDIR/radar_state.txt"
TREND_FILE="$WORKDIR/nearest_history.txt"

touch "$TREND_FILE"

HISTORY_JSON="/var/www/html/data/history.jsonl"

touch "$HISTORY_JSON"

FLASHES_JSON="/var/www/html/data/flashes.json"

# Surfside Beach SC
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
    # LOAD PREVIOUS STATE
    #########################################

    PREV_NEAREST=999999
    OLD_SCORE=0
    OLD_10=0
    OLD_25=0
    OLD_50=0
    OLD_100=0

    if [ -f "$STATE_FILE" ]; then
        read OLD_SCORE PREV_NEAREST OLD_10 OLD_25 OLD_50 OLD_100 < "$STATE_FILE"
    fi

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
    # EXTRACT DATA
    #########################################

    mapfile -t LATS < <(
        ncks -C -H -v flash_lat "$PROCESS_FILE" |
        grep -Eo '[-0-9]+\.[0-9]+'
    )

    mapfile -t LONS < <(
        ncks -C -H -v flash_lon "$PROCESS_FILE" |
        grep -Eo '[-0-9]+\.[0-9]+'
    )

    #########################################
    # VALIDATE ARRAYS
    #########################################

    if [ "${#LATS[@]}" -ne "${#LONS[@]}" ]; then
        echo "ERROR: Latitude/Longitude mismatch"
        sleep "$INTERVAL"
        continue
    fi

    FLASH_COUNT=${#LATS[@]}

    echo "Total strikes: $FLASH_COUNT"

    #########################################
    # DEFAULT TREND VALUES
    #########################################

    SMOOTHED_DIST=""
    TREND_CHANGE="0.0"

    #########################################
    # NO LIGHTNING CASE
    #########################################

    if [ "$FLASH_COUNT" -eq 0 ]; then

        TOTAL_SCORE=0

        COUNT10=0
        COUNT25=0
        COUNT50=0
        COUNT100=0

        NEAREST_DIST=""
        CLOSEST_LAT=""
        CLOSEST_LON=""
        HEADING=""
        DIR=""

        MOVE_STATUS="NO LIGHTNING"

    else

        TOTAL_SCORE=0

        COUNT10=0
        COUNT25=0
        COUNT50=0
        COUNT100=0

        NEAREST_DIST=999999
        CLOSEST_LAT=""
        CLOSEST_LON=""

        #########################################
        # PROCESS FLASHES
        #########################################

        for i in "${!LATS[@]}"; do

            LAT="${LATS[$i]}"
            LON="${LONS[$i]}"

            read DIST SCORE <<< "$(awk \
                -v lat1="$MY_LAT" \
                -v lon1="$MY_LON" \
                -v lat2="$LAT" \
                -v lon2="$LON" '
            BEGIN{
                pi=3.141592653589793

                dlat=(lat2-lat1)*pi/180
                dlon=(lon2-lon1)*pi/180

                a=sin(dlat/2)^2 + cos(lat1*pi/180)*cos(lat2*pi/180)*sin(dlon/2)^2
                c=2*atan2(sqrt(a),sqrt(1-a))

                dist=c*3958.8

                score=exp(-dist/20)

                print dist, score
            }')"

            [ -z "$DIST" ] && continue

            awk -v d="$DIST" 'BEGIN{exit !(d<=10)}' && ((COUNT10++))
            awk -v d="$DIST" 'BEGIN{exit !(d<=25)}' && ((COUNT25++))
            awk -v d="$DIST" 'BEGIN{exit !(d<=50)}' && ((COUNT50++))
            awk -v d="$DIST" 'BEGIN{exit !(d<=100)}' && ((COUNT100++))

            if awk -v d="$DIST" -v n="$NEAREST_DIST" 'BEGIN{exit !(d<n)}'; then
                NEAREST_DIST="$DIST"
                CLOSEST_LAT="$LAT"
                CLOSEST_LON="$LON"
            fi

            TOTAL_SCORE=$(awk -v a="$TOTAL_SCORE" -v b="$SCORE" '
            BEGIN{
                if(a=="") a=0
                if(b=="") b=0
                print a+b
            }')

        done

#########################################
# HEADING TO CLOSEST STRIKE
#########################################

HEADING=""
DIR=""

if [ -n "$CLOSEST_LAT" ] && [ -n "$CLOSEST_LON" ]; then

    HEADING=$(awk \
        -v lat1="$MY_LAT" \
        -v lon1="$MY_LON" \
        -v lat2="$CLOSEST_LAT" \
        -v lon2="$CLOSEST_LON" '
    BEGIN{
        pi=3.141592653589793

        lat1*=pi/180
        lon1*=pi/180
        lat2*=pi/180
        lon2*=pi/180

        dlon=lon2-lon1

        y=sin(dlon)*cos(lat2)
        x=cos(lat1)*sin(lat2)-sin(lat1)*cos(lat2)*cos(dlon)

        brng=atan2(y,x)*180/pi

        if(brng<0)
            brng+=360

        printf "%.1f", brng
    }')

    case $(awk -v h="$HEADING" '
    BEGIN{
        print int((h+22.5)/45)%8
    }') in
        0) DIR="N" ;;
        1) DIR="NE" ;;
        2) DIR="E" ;;
        3) DIR="SE" ;;
        4) DIR="S" ;;
        5) DIR="SW" ;;
        6) DIR="W" ;;
        7) DIR="NW" ;;
    esac

fi

#########################################
# 25-MINUTE TREND SMOOTHING
#########################################

MOVE_STATUS="STABLE"

echo "$NEAREST_DIST" >> "$TREND_FILE"

tail -n 5 "$TREND_FILE" > "${TREND_FILE}.tmp"
mv "${TREND_FILE}.tmp" "$TREND_FILE"

HISTORY_COUNT=$(wc -l < "$TREND_FILE")

SMOOTHED_DIST="$NEAREST_DIST"
TREND_CHANGE="0.0"

if [ "$HISTORY_COUNT" -ge 2 ]; then

    SMOOTHED_DIST=$(awk '
    {
        sum += $1
        count++
    }
    END{
        if(count>0)
            printf "%.1f", sum/count
    }' "$TREND_FILE")

    FIRST=$(head -n 1 "$TREND_FILE")
    LAST=$(tail -n 1 "$TREND_FILE")

    TREND_CHANGE=$(awk \
        -v first="$FIRST" \
        -v last="$LAST" '
    BEGIN{
        printf "%.1f", last-first
    }')

    if awk -v c="$TREND_CHANGE" '
    BEGIN{exit !(c<=-2)}'; then

        MOVE_STATUS="APPROACHING"

    elif awk -v c="$TREND_CHANGE" '
    BEGIN{exit !(c>=2)}'; then

        MOVE_STATUS="MOVING AWAY"

    else

        MOVE_STATUS="STABLE"

    fi
fi

#########################################
# SAVE STATE
#########################################

printf "%s %s %s %s %s %s\n" \
    "$TOTAL_SCORE" \
    "$NEAREST_DIST" \
    "$COUNT10" \
    "$COUNT25" \
    "$COUNT50" \
    "$COUNT100" \
    > "$STATE_FILE"

    fi
    
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

if awk "BEGIN {exit !($TOTAL_SCORE > 5)}"; then
    echo "  Status: VERY ACTIVE (nearby storms)"
elif awk "BEGIN {exit !($TOTAL_SCORE > 2)}"; then
    echo "  Status: ACTIVE"
elif awk "BEGIN {exit !($TOTAL_SCORE > 0.5)}"; then
    echo "  Status: LIGHT activity"
else
    echo "  Status: Quiet"
fi

echo "------------------------------------"

if [ "$FLASH_COUNT" -gt 0 ]; then

    echo "Closest lightning strike:"
    echo "  Lat: $CLOSEST_LAT"
    echo "  Lon: $CLOSEST_LON"
    printf "  Distance: %.2f miles\n" "$NEAREST_DIST"

    if [ -n "$HEADING" ]; then
        echo "  Heading: ${HEADING}° ($DIR)"
    fi

else

    echo "No lightning detected."

fi

echo "------------------------------------"

echo "Storm direction trend: $MOVE_STATUS"

if [ "$FLASH_COUNT" -gt 0 ]; then
    printf "Smoothed distance (25 min): %.1f miles\n" "$SMOOTHED_DIST"
    printf "Trend change: %.1f miles\n" "$TREND_CHANGE"
fi

echo "------------------------------------"

echo "Lightning within radius:"
echo "  10 mi : $COUNT10"
echo "  25 mi : $COUNT25"
echo "  50 mi : $COUNT50"
echo " 100 mi : $COUNT100"
echo ""
echo "Flash rate:"
echo "  10 mi : ${RATE10}/min"
echo "  25 mi : ${RATE25}/min"
echo "  50 mi : ${RATE50}/min"
echo " 100 mi : ${RATE100}/min"

echo "------------------------------------"

#########################################
# WRITE JSON NOW
#########################################

JSON_FILE="/var/www/html/data/data.json"

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
echo "{\"timestamp\":\"$(TZ="America/New_York" date '+%Y-%m-%d %H:%M:%S')\",\
\"nearest\":\"$NEAREST_DIST\",\
\"smoothed\":\"$SMOOTHED_DIST\",\
\"score\":\"$TOTAL_SCORE\",\
\"count10\":$COUNT10,\
\"count25\":$COUNT25,\
\"count50\":$COUNT50,\
\"count100\":$COUNT100,\
\"rate25\":\"$RATE25\"}" >> "$HISTORY_JSON"

tail -n 2016 "$HISTORY_JSON" > "${HISTORY_JSON}.tmp"
mv "${HISTORY_JSON}.tmp" "$HISTORY_JSON"

#########################################
# COUNTDOWN
#########################################

for ((sec=INTERVAL; sec>0; sec--)); do
    printf "\rRefreshing in %02d:%02d   " $((sec/60)) $((sec%60))
    sleep 1
done

printf "\rRefreshing in 00:00        \n"

done

