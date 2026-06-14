#!/bin/bash

set -e

WORKDIR="$HOME/goes19"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Latest GOES-19 GLM directory
BASE="https://noaa-goes19.s3.amazonaws.com/GLM-L2-LCFA"

YEAR=$(date -u +%Y)
DOY=$(date -u +%j)
HOUR=$(date -u +%H)

echo "Searching for latest file..."
INDEX=$(curl -s "$BASE/$YEAR/$DOY/$HOUR/")

FILE=$(echo "$INDEX" \
    | grep -o 'OR_GLM-L2-LCFA_G19[^"]*\.nc' \
    | tail -1)

if [ -z "$FILE" ]; then
    echo "No GLM file found."
    exit 1
fi

echo "Downloading:"
echo "$FILE"

wget -q -O latest.nc \
    "$BASE/$YEAR/$DOY/$HOUR/$FILE"

echo
echo "Variables in file:"
ncdump -h latest.nc | grep flash || true

echo
echo "Flash coordinates:"
ncks -H -C -v flash_lat,flash_lon latest.nc 2>/dev/null
