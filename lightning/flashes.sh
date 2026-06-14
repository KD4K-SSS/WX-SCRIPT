#!/bin/bash

WORKDIR="$HOME/goes19"
FILE="$WORKDIR/latest.nc"

OUT="/var/www/html/data/flashes.json"

# Surfside Beach SC
MY_LAT=33.621
MY_LON=-78.964

MAX_MILES=100

#########################################
# VERIFY FILE EXISTS
#########################################

if [ ! -f "$FILE" ]; then
    echo "[]" > "$OUT"
    echo "No latest.nc found"
    exit 1
fi

#########################################
# EXTRACT FLASH POSITIONS
#########################################

mapfile -t LATS < <(
    ncks -C -H -v flash_lat "$FILE" |
    grep -Eo '[-0-9]+\.[0-9]+'
)

mapfile -t LONS < <(
    ncks -C -H -v flash_lon "$FILE" |
    grep -Eo '[-0-9]+\.[0-9]+'
)

#########################################
# VALIDATE ARRAYS
#########################################

if [ "${#LATS[@]}" -ne "${#LONS[@]}" ]; then
    echo "ERROR: Latitude/Longitude mismatch"
    exit 1
fi

#########################################
# BUILD JSON
#########################################

echo "[" > "$OUT"

FIRST=true

for i in "${!LATS[@]}"
do
    LAT="${LATS[$i]}"
    LON="${LONS[$i]}"

    #########################################
    # DISTANCE
    #########################################

    DIST=$(awk \
        -v lat1="$MY_LAT" \
        -v lon1="$MY_LON" \
        -v lat2="$LAT" \
        -v lon2="$LON" '
    BEGIN{
        pi=3.141592653589793

        dlat=(lat2-lat1)*pi/180
        dlon=(lon2-lon1)*pi/180

        a=sin(dlat/2)^2+cos(lat1*pi/180)*cos(lat2*pi/180)*sin(dlon/2)^2
        c=2*atan2(sqrt(a),sqrt(1-a))

        printf "%.1f", c*3958.8
    }')

    #########################################
    # ONLY KEEP FLASHES <= 100 MILES
    #########################################

    if ! awk -v d="$DIST" -v m="$MAX_MILES" \
        'BEGIN{exit !(d<=m)}'
    then
        continue
    fi

    #########################################
    # BEARING
    #########################################

    BEARING=$(awk \
        -v lat1="$MY_LAT" \
        -v lon1="$MY_LON" \
        -v lat2="$LAT" \
        -v lon2="$LON" '
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

    #########################################
    # WRITE JSON ENTRY
    #########################################

    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$OUT"
    fi

    cat >> "$OUT" << EOF
{
  "distance": $DIST,
  "bearing": $BEARING,
  "age_minutes": 0
}
EOF

done

echo "]" >> "$OUT"

COUNT=$(jq length "$OUT")

echo "Created $OUT"
echo "Flashes within ${MAX_MILES} miles: $COUNT"
