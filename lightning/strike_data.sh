#!/bin/bash

#################################
# PART 1 - SETUP
#################################

WORKDIR="$HOME/goes19"
FILE="$WORKDIR/latest.nc"

RING_FILE="$WORKDIR/ring_history.txt"
JSON_FILE="/var/www/html/data/group_data.json"
LOG_FILE="$WORKDIR/group_event_log.csv"

# Ensure log and ring files exist
if [ ! -f "$LOG_FILE" ]
then
    echo "timestamp,count10,count25,count50,count100,rate10,rate25,rate50,rate100,nearest,lat,lon,score" > "$LOG_FILE"
fi

touch "$RING_FILE"

MY_LAT=33.621
MY_LON=-78.964

INTERVAL=120

while true
do

clear

echo "GOES-19 GROUP LIGHTNING RADAR"
echo "Time (EDT): $(TZ="America/New_York" date '+%Y-%m-%d %H:%M:%S')"
echo "Location: Surfside Beach SC"
echo "------------------------------------"

#################################
# PART 1A - FILE CHECK
#################################

if [ ! -f "$FILE" ]
then
    echo "GLM Data Failed"
    sleep "$INTERVAL"
    continue
fi

PROCESS_FILE="$WORKDIR/processing.nc"
cp "$FILE" "$PROCESS_FILE"

echo "GLM Data Updated"

#################################
# PART 1B - EXTRACT & COUNT TOTAL GROUPS (IN-MEMORY)
#################################

# Stream data arrays together side-by-side cleanly into memory
RAW_GROUPS=$(paste <(ncks -C -H -v group_lat "$PROCESS_FILE" 2>/dev/null | grep -Eo '[-0-9]+\.[0-9]+') \
                   <(ncks -C -H -v group_lon "$PROCESS_FILE" 2>/dev/null | grep -Eo '[-0-9]+\.[0-9]+'))

# Count total groups in the file before filtering down by region
TOTAL_GROUPS=$(wc -l <<< "$RAW_GROUPS")
echo "Total Lightning Groups in File: $TOTAL_GROUPS"

#################################
# PART 2 - STREAMED AWK PASS
#################################

RESULTS=$(echo "$RAW_GROUPS" | awk -v mylat="$MY_LAT" -v mylon="$MY_LON" '
BEGIN {
    pi=3.141592653589793
    count10=0
    count25=0
    count50=0
    count100=0
    nearest=999999
    nearlat=""
    nearlon=""
    score=0
}
{
    lat=$1
    lon=$2

    if(lat < 24 || lat > 38) next
    if(lon < -90 || lon > -70) next

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

if [ "$NEAREST" = "999999.000000" ]
then
    NEAR_LAT=""
    NEAR_LON=""
fi

#################################
# PART 3 - SAVE RING HISTORY
#################################

echo "$COUNT10 $COUNT25 $COUNT50 $COUNT100" >> "$RING_FILE"

#################################
# KEEP LAST 3 SCANS
#################################

tail -n 3 "$RING_FILE" > "${RING_FILE}.tmp"
mv "${RING_FILE}.tmp" "$RING_FILE"

#################################
# PART 3A - COMPUTE 6-MINUTE TOTALS
#################################

read -r SUM10 SUM25 SUM50 SUM100 <<< $(awk '{ s10 += $1; s25 += $2; s50 += $3; s100 += $4 } END { print s10, s25, s50, s100 }' "$RING_FILE")

#################################
# PART 3B - PROTECT EMPTY VALUES
#################################

[ -z "$SUM10" ] && SUM10=0
[ -z "$SUM25" ] && SUM25=0
[ -z "$SUM50" ] && SUM50=0
[ -z "$SUM100" ] && SUM100=0

#################################
# PART 3C - GROUP RATE
#################################

RATE10=$(awk -v s="$SUM10" 'BEGIN{printf "%.1f", s/6}')
RATE25=$(awk -v s="$SUM25" 'BEGIN{printf "%.1f", s/6}')
RATE50=$(awk -v s="$SUM50" 'BEGIN{printf "%.1f", s/6}')
RATE100=$(awk -v s="$SUM100" 'BEGIN{printf "%.1f", s/6}')

#################################
# PART 3D - EVENT LOG
#################################

if [ "$COUNT100" -gt 0 ]
then
    echo "$(TZ="America/New_York" date '+%Y-%m-%d %H:%M:%S'),$COUNT10,$COUNT25,$COUNT50,$COUNT100,$RATE10,$RATE25,$RATE50,$RATE100,$NEAREST,$NEAR_LAT,$NEAR_LON,$SCORE" >> "$LOG_FILE"
fi

#################################
# PART 3E - LIMIT LOG SIZE
#################################

tail -n 10000 "$LOG_FILE" > "${LOG_FILE}.tmp"
mv "${LOG_FILE}.tmp" "$LOG_FILE"

#################################
# PART 4 - DISPLAY
#################################

echo
echo "------------------------------------"
echo "Closest lightning group"

if [ "$NEAREST" != "999999.000000" ]
then
    echo " Lat: $NEAR_LAT"
    echo " Lon: $NEAR_LON"
    printf " Distance: %.1f miles\n" "$NEAREST"
else
    echo " None"
fi

echo
echo "Group Activity"
printf "Group Score: %.3f\n" "$SCORE"

echo
echo "Groups within radius (6 min)"
echo " 10 mi : $SUM10"
echo " 25 mi : $SUM25"
echo " 50 mi : $SUM50"
echo "100 mi : $SUM100"

echo
echo "Group Rate"
echo " 10 mi : ${RATE10}/min"
echo " 25 mi : ${RATE25}/min"
echo " 50 mi : ${RATE50}/min"
echo "100 mi : ${RATE100}/min"

echo
printf "6-minute average rate (100 mi): %s groups/min\n" "$RATE100"

#################################
# PART 4A - WRITE JSON
#################################

cat > "$JSON_FILE" << EOF
{
  "timestamp":"$(TZ="America/New_York" date '+%Y-%m-%d %H:%M:%S')",
  "nearest_lat":"$NEAR_LAT",
  "nearest_lon":"$NEAR_LON",
  "nearest_distance":"$(printf "%.1f" "$NEAREST")",
  "group_score":"$(printf "%.3f" "$SCORE")",
  "count10":"$SUM10",
  "count25":"$SUM25",
  "count50":"$SUM50",
  "count100":"$SUM100",
  "rate10":"$RATE10",
  "rate25":"$RATE25",
  "rate50":"$RATE50",
  "rate100":"$RATE100"
}
EOF

#################################
# PART 4B - COUNTDOWN
#################################

echo
echo "------------------------------------"

for ((sec=INTERVAL; sec>0; sec--))
do
    printf "\rRefreshing in %02d:%02d " $((sec/60)) $((sec%60))
    sleep 1
done

echo
done
