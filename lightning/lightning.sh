#!/bin/bash

set -o pipefail

TMPDIR="/dev/shm/glm_roi"
mkdir -p "$TMPDIR"
mkdir -p "$HOME/radar_dashboard"

LAST_FRAME_CHANGE=""
LAST_FRAME_CHANGE_TIME="Never"

RAW="$TMPDIR/glm.gif"
ROI="$TMPDIR/roi.gif"
PREV_ROI="$TMPDIR/prev_roi.gif"

STATUS="$HOME/radar_dashboard/glm_roi_status.txt"
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

ROI_W=300
ROI_H=300

THRESHOLD=5
MAX_DISTANCE=200

UPDATE_INTERVAL=300   # internal loop step (5 min)
RESTART_INTERVAL=600  # full restart (10 min)

log() {
    echo "[$(date '+%F %T')] $*" >> "$LOG"
}

pixel_to_latlon() {
    local px="$1"
    local py="$2"

    LAT=$(awk -v py="$py" -v h="$IMG_H" -v top="$LAT_TOP" -v bot="$LAT_BOTTOM" \
        'BEGIN{print top-(py/h)*(top-bot)}')

    LON=$(awk -v px="$px" -v w="$IMG_W" -v left="$LON_LEFT" -v right="$LON_RIGHT" \
        'BEGIN{print left+(px/w)*(right-left)}')

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
    curl -s -L --fail --max-time 20 \
        -H "Cache-Control: no-cache" \
        -H "Pragma: no-cache" \
        -o "$RAW" \
        "${GLM_URL}?t=$(date +%s)"
}

calculate_roi() {
    ST_X=$(awk -v lon="$ST_LON" -v left="$LON_LEFT" -v right="$LON_RIGHT" -v w="$IMG_W" \
        'BEGIN{print int((lon-left)/(right-left)*w)}')

    ST_Y=$(awk -v lat="$ST_LAT" -v top="$LAT_TOP" -v bot="$LAT_BOTTOM" -v h="$IMG_H" \
        'BEGIN{print int((top-lat)/(top-bot)*h)}')

    ROI_X=$((ST_X - ROI_W/2))
    ROI_Y=$((ST_Y - ROI_H/2))

    (( ROI_X < 0 )) && ROI_X=0
    (( ROI_Y < 0 )) && ROI_Y=0
    (( ROI_X + ROI_W > IMG_W )) && ROI_X=$((IMG_W-ROI_W))
    (( ROI_Y + ROI_H > IMG_H )) && ROI_Y=$((IMG_H-ROI_H))
}

crop_roi() {
    convert "$RAW[0]" -crop ${ROI_W}x${ROI_H}+${ROI_X}+${ROI_Y} +repage "$ROI"
}

get_roi_intensity() {
    convert "$ROI[0]" -colorspace Gray -format "%[mean]" info: 2>/dev/null || echo 0
}

frame_activity_score() {
    if [[ ! -f "$PREV_ROI" ]]; then
        cp "$ROI" "$PREV_ROI"
        echo "0"
        return
    fi

    DIFF=$(compare -metric AE "$PREV_ROI" "$ROI" null: 2>&1 || true)
    cp "$ROI" "$PREV_ROI"
    echo "$DIFF"
}

find_nearest_flash() {
    local CLOSEST=9999
    local BEST_DIR="Lightning beyond 200 mile scope"
    local FOUND=0

    while read -r X Y VAL; do
        [[ -z "$VAL" ]] && continue
        (( VAL < THRESHOLD )) && continue

        FOUND=1

        PX=$((ROI_X + X))
        PY=$((ROI_Y + Y))

        read LAT LON <<< "$(pixel_to_latlon "$PX" "$PY")"
        DIST=$(distance_miles "$ST_LAT" "$ST_LON" "$LAT" "$LON")

        if awk -v d1="$DIST" -v d2="$CLOSEST" 'BEGIN{exit !(d1<d2)}'; then
            CLOSEST="$DIST"
            BEST_DIR=$(bearing_dir "$ST_LAT" "$ST_LON" "$LAT" "$LON")
        fi
    done < <(
        convert "$ROI[0]" -colorspace Gray txt:- 2>/dev/null |
        sed -n 's/^\([0-9]*\),\([0-9]*\):.*gray(\([0-9]*\)).*/\1 \2 \3/p'
    )

    if (( FOUND == 0 )); then
        echo ">200|Lightning beyond 200 mile scope"
    elif awk -v d="$CLOSEST" -v m="$MAX_DISTANCE" 'BEGIN{exit !(d<=m)}'; then
        printf "%.1f|%s\n" "$CLOSEST" "$BEST_DIR"
    else
        echo ">200|Lightning beyond 200 mile scope"
    fi
}

# =====================================================
# MAIN RESTART LOOP (FULL RESET EVERY 10 MINUTES)
# =====================================================
while true; do

    LOOP_START=$(date +%s)
    LOOP_END=$((LOOP_START + RESTART_INTERVAL))

    echo "Starting 10-minute GLM cycle: $(date)"

    # reset state each cycle
    PREV_ROI="$TMPDIR/prev_roi_$LOOP_START.gif"

    while [[ $(date +%s) -lt $LOOP_END ]]; do

        download_glm || { log "DOWNLOAD FAILED"; sleep 20; continue; }

        calculate_roi
        crop_roi || { log "CROP FAILED"; sleep 20; continue; }

        INTENSITY=$(get_roi_intensity)
        [[ -z "$INTENSITY" ]] && INTENSITY=0

        ACTIVITY=$(frame_activity_score)

        if [[ "$ACTIVITY" -gt 0 ]]; then
            LAST_FRAME_CHANGE_TIME=$(date '+%F %T')
            LAST_FRAME_CHANGE=$ACTIVITY
        fi

        RESULT=$(find_nearest_flash)
        IFS="|" read DIST DIR <<< "$RESULT"

        INSIDE=$(awk -v d="$DIST" -v m="$MAX_DISTANCE" 'BEGIN{print(d<=m && d>0)}')

        if (( $(echo "$INTENSITY < 0.05" | bc -l) )); then
            LEVEL="MINIMAL"
            MESSAGE="No significant lightning activity"
        elif [[ "$INSIDE" == "1" ]]; then
            if (( $(echo "$INTENSITY < 0.1" | bc -l) )); then
                LEVEL="LOW"
            elif (( $(echo "$INTENSITY < 0.2" | bc -l) )); then
                LEVEL="MODERATE"
            else
                LEVEL="HIGH"
            fi
            MESSAGE="Lightning detected within 200 miles"
        else
            LEVEL="DISTANT"
            MESSAGE="Lightning activity beyond 200 miles"
        fi

        cat > "$STATUS" <<EOF
GLM_LEVEL=$LEVEL
GLM_MESSAGE=$MESSAGE
ROI_INTENSITY=$INTENSITY
FRAME_DIFF=$ACTIVITY
LAST_FRAME_CHANGE=$LAST_FRAME_CHANGE
LAST_FRAME_CHANGE_TIME=$LAST_FRAME_CHANGE_TIME
NEAREST_FLASH_MILES=$DIST
FLASH_BEARING=$DIR
LAST_UPDATE=$(date)
EOF

        clear
        echo "================================================="
        echo " KD4K GLM LIGHTNING DETECTOR (10 MIN CYCLE)"
        echo "================================================="
        echo "LEVEL: $LEVEL"
        echo "MESSAGE: $MESSAGE"
        echo "DIST: $DIST miles"
        echo "BEARING: $DIR"
        echo "INTENSITY: $INTENSITY"
        echo "FRAME CHANGE: $ACTIVITY pixels"
        echo "UPDATED: $(date)"
        echo "================================================="

        log "$LEVEL | DIST=$DIST | DIR=$DIR | INT=$INTENSITY | DIFF=$ACTIVITY"

        sleep "$UPDATE_INTERVAL"
    done

    echo "Restarting cycle (fresh data reset)..."
done
