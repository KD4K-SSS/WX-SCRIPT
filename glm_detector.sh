#!/bin/bash

set -eo pipefail

TMPDIR="/dev/shm/glm_roi"

mkdir -p "$TMPDIR"
mkdir -p "$HOME"

RAW="$TMPDIR/glm.gif"
ROI="$TMPDIR/roi.gif"

STATUS="$DIR/glm_roi_status.txt"
LOG="$TMPDIR/glm_roi.log"

GLM_URL="https://cdn.star.nesdis.noaa.gov/GOES19/GLM/SECTOR/se/EXTENT3/GOES19-SE-EXTENT3-600x600.gif"

IMG_W=600
IMG_H=600

LAT_TOP=35.5
LAT_BOTTOM=30.0

LON_LEFT=-85.5
LON_RIGHT=-75.0

ST_LAT=33.621
ST_LON=-78.956

ROI_X=200
ROI_Y=200
ROI_W=200
ROI_H=200

THRESHOLD=50
UPDATE_INTERVAL=300

log() {
    echo "[$(date '+%F %T')] $*" >> "$LOG"
}

pixel_to_latlon() {

    local px="$1"
    local py="$2"

    LAT=$(awk -v py="$py" -v h="$IMG_H" -v top="$LAT_TOP" -v bot="$LAT_BOTTOM" 'BEGIN{print top-(py/h)*(top-bot)}')

    LON=$(awk -v px="$px" -v w="$IMG_W" -v left="$LON_LEFT" -v right="$LON_RIGHT" 'BEGIN{print left+(px/w)*(right-left)}')

    echo "$LAT $LON"
}

distance_miles() {

awk -v lat1="$1" -v lon1="$2" -v lat2="$3" -v lon2="$4" '
function rad(x){return x*3.1415926535/180}
BEGIN{
R=3959
dlat=rad(lat2-lat1)
dlon=rad(lon2-lon1)
a=sin(dlat/2)^2+cos(rad(lat1))*cos(rad(lat2))*sin(dlon/2)^2
c=2*atan2(sqrt(a),sqrt(1-a))
print R*c
}'
}

bearing_dir() {

awk -v lat1="$1" -v lon1="$2" -v lat2="$3" -v lon2="$4" '
function rad(x){return x*3.1415926535/180}
BEGIN{
dlon=rad(lon2-lon1)
y=sin(dlon)*cos(rad(lat2))
x=cos(rad(lat1))*sin(rad(lat2))-sin(rad(lat1))*cos(rad(lat2))*cos(dlon)
brng=atan2(y,x)*180/3.1415926535
if(brng<0)brng+=360
dirs="N NE E SE S SW W NW"
split(dirs,a," ")
idx=int((brng+22.5)/45)%8+1
print a[idx]
}'
}

download_glm() {

    curl \
        -s \
        -L \
        --fail \
        --max-time 20 \
        -H "Cache-Control: no-cache" \
        -H "Pragma: no-cache" \
        -o "$RAW" \
        "${GLM_URL}?t=$(date +%s)"
}

crop_roi() {

    convert "$RAW" \
        -crop ${ROI_W}x${ROI_H}+${ROI_X}+${ROI_Y} \
        "$ROI" 2>/dev/null
}

get_roi_intensity() {

    convert "$ROI" \
        -colorspace Gray \
        -format "%[mean]" \
        info: 2>/dev/null
}

find_nearest_flash() {

    local CLOSEST=9999
    local BEST_LAT="N/A"
    local BEST_LON="N/A"
    local BEST_DIR="N/A"

    convert "$ROI" -colorspace Gray -depth 8 txt:- 2>/dev/null | \
    awk -F'[(), ]+' '/gray/ {print $2,$3,$5}' | \
    while read X Y VAL; do

        VAL=$(echo "$VAL" | tr -cd '0-9')

        [ -z "$VAL" ] && continue

        if [ "$VAL" -lt "$THRESHOLD" ]; then
            continue
        fi

        PX=$((ROI_X + X))
        PY=$((ROI_Y + Y))

        read LAT LON <<< "$(pixel_to_latlon "$PX" "$PY")"

        DIST=$(distance_miles "$ST_LAT" "$ST_LON" "$LAT" "$LON")

        BETTER=$(awk -v d1="$DIST" -v d2="$CLOSEST" 'BEGIN{if(d1<d2)print 1; else print 0}')

        if [ "$BETTER" = "1" ]; then

            CLOSEST="$DIST"
            BEST_LAT="$LAT"
            BEST_LON="$LON"

            BEST_DIR=$(bearing_dir "$ST_LAT" "$ST_LON" "$LAT" "$LON")
        fi

    done

    WITHIN=$(awk -v d="$CLOSEST" 'BEGIN{if(d<=50)print 1; else print 0}')

    if [ "$WITHIN" = "1" ]; then

        DIST_OUT=$(printf "%.1f" "$CLOSEST")

        echo "$DIST_OUT|$BEST_DIR|$BEST_LAT|$BEST_LON"

    else

        echo ">50|N/A|N/A|N/A"
    fi
}

while true; do

    if ! download_glm; then
        log "DOWNLOAD FAILED"
        sleep 20
        continue
    fi

    if ! crop_roi; then
        log "ROI CROP FAILED"
        sleep 20
        continue
    fi

    INTENSITY=$(get_roi_intensity)

    [ -z "$INTENSITY" ] && INTENSITY=0

    RESULT=$(find_nearest_flash)

    IFS="|" read DIST DIR FLASH_LAT FLASH_LON <<< "$RESULT"

    LEVEL="MINIMAL"
    MESSAGE="No lightning nearby"

    EXTREME=$(awk -v i="$INTENSITY" 'BEGIN{print(i>40000)}')
    HIGH=$(awk -v i="$INTENSITY" 'BEGIN{print(i>25000)}')
    MOD=$(awk -v i="$INTENSITY" 'BEGIN{print(i>12000)}')

    if [ "$EXTREME" = "1" ]; then

        LEVEL="EXTREME"
        MESSAGE="Strong lightning nearby"

    elif [ "$HIGH" = "1" ]; then

        LEVEL="HIGH"
        MESSAGE="Active lightning nearby"

    elif [ "$MOD" = "1" ]; then

        LEVEL="MODERATE"
        MESSAGE="Weak lightning nearby"
    fi

cat > "$STATUS" <<EOF
GLM_LEVEL=$LEVEL
GLM_MESSAGE=$MESSAGE

ROI_INTENSITY=$INTENSITY

NEAREST_FLASH_MILES=$DIST
FLASH_BEARING=$DIR

FLASH_LAT=$FLASH_LAT
FLASH_LON=$FLASH_LON

LAST_UPDATE=$(date)
EOF

    clear

    echo "================================================="
    echo " KD4K GLM LIGHTNING DETECTOR"
    echo "================================================="
    echo ""
    echo "LEVEL:            $LEVEL"
    echo "MESSAGE:          $MESSAGE"
    echo ""
    echo "NEAREST FLASH:    $DIST miles"
    echo "FLASH BEARING:    $DIR"
    echo ""
    echo "FLASH LATITUDE:   $FLASH_LAT"
    echo "FLASH LONGITUDE:  $FLASH_LON"
    echo ""
    echo "ROI INTENSITY:    $INTENSITY"
    echo ""
    echo "UPDATED:"
    echo "$(date)"
    echo ""

    log "$LEVEL | DIST=$DIST | DIR=$DIR | INT=$INTENSITY"

    sleep "$UPDATE_INTERVAL"

done
