#!/bin/bash
set -e

WORKDIR="$HOME/goes19"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

BASE="https://noaa-goes19.s3.amazonaws.com"

while true; do
    YEAR=$(date -u +%Y)
    DOY=$(date -u +%j)
    HOUR=$(date -u +%H)

    PREFIX="GLM-L2-LCFA/$YEAR/$DOY/$HOUR/"
    URL="$BASE/?list-type=2&prefix=$PREFIX"

    echo "[$(date -u)] Checking for latest GLM file..."

    XML=$(curl -s "$URL")

    FILES=$(echo "$XML" | grep -oE 'OR_GLM-L2-LCFA_G19_s[0-9]+_e[0-9]+_c[0-9]+\.nc')

    if [ -z "$FILES" ]; then
        echo "No files found this cycle."
        sleep 300
        continue
    fi

    LATEST=$(echo "$FILES" | sort | tail -n 1)

    if [ -f "latest.nc" ] && grep -q "$LATEST" last_download.txt 2>/dev/null; then
        echo "No new file."
    else
        echo "New file found: $LATEST"

        wget -q -O latest.nc "$BASE/$PREFIX$LATEST"
        
        echo "$LATEST" > last_download.txt

        echo "Downloaded and updated latest.nc"

        echo "File converted"
        ncks -H -C -v flash_lat latest.nc 2>/dev/null | grep -c "," || true
    fi

    echo "Sleeping 1 minute..."
    sleep 60
done
