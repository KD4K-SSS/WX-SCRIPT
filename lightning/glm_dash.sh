#!/bin/bash
set -e

WORKDIR="$HOME/goes19"
FILE="$WORKDIR/latest.nc"

# Your location (Surfside Beach SC)
MY_LAT=33.621
MY_LON=-78.964

INTERVAL=300  # 5 minutes

while true; do
    clear

    echo "GOES-19 LIGHTNING DASHBOARD"
    echo "Time (EDT): $(TZ="America/New_York" date '+%Y-%m-%d %H:%M:%S')"
    echo "Location: Surfside Beach SC"
    echo "------------------------------------"

    if [ ! -f "$FILE" ]; then
        echo "Waiting for latest.nc..."
        sleep $INTERVAL
        continue
    fi

    # Extract clean arrays
    mapfile -t LATS < <(ncks -C -H -v flash_lat "$FILE" | grep -Eo '[-0-9]+\.[0-9]+')
    mapfile -t LONS < <(ncks -C -H -v flash_lon "$FILE" | grep -Eo '[-0-9]+\.[0-9]+')

    FLASH_COUNT=${#LATS[@]}
    echo "Total flashes: $FLASH_COUNT"
    echo "------------------------------------"

    # Closest flash calculation
    MIN_DIST=999999
    CLOSEST_LAT=""
    CLOSEST_LON=""

    for i in "${!LATS[@]}"; do
        LAT="${LATS[$i]}"
        LON="${LONS[$i]}"

        DIST=$(awk -v lat1="$MY_LAT" -v lon1="$MY_LON" -v lat2="$LAT" -v lon2="$LON" 'BEGIN{
            pi=3.141592653589793
            dlat=(lat2-lat1)*pi/180
            dlon=(lon2-lon1)*pi/180
            a = sin(dlat/2)^2 + cos(lat1*pi/180)*cos(lat2*pi/180)*sin(dlon/2)^2
            c = 2 * atan2(sqrt(a), sqrt(1-a))
            r = 3958.8
            print c*r
        }')

        if (( $(echo "$DIST < $MIN_DIST" | bc -l) )); then
            MIN_DIST=$DIST
            CLOSEST_LAT=$LAT
            CLOSEST_LON=$LON
        fi
    done

    echo "Closest lightning flash:"
    echo "  Lat: $CLOSEST_LAT"
    echo "  Lon: $CLOSEST_LON"
    printf "  Distance: %.2f miles\n" "$MIN_DIST"

    echo "------------------------------------"
    echo "Refreshing in $(($INTERVAL/60)) minutes..."
    sleep $INTERVAL
done
