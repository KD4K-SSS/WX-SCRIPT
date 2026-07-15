#!/bin/bash
# ========================================================
# NWS TEXT FORECAST INGEST ENGINE - NO CACHE STREAM
# ========================================================

TARGET_DIR="/var/www/html/data"
ZONES=("scz058" "scz054")
BASE_URL="https://tgftp.nws.noaa.gov/data/forecasts/zone/sc"

# 1. Ensure the web directory exists
mkdir -p "$TARGET_DIR"

# 2. Iterate and download each zone layout
for ZONE in "${ZONES[@]}"; do
    echo "Downloading fresh text forecast for $ZONE..."
    
    # -H adds headers forcing the proxy/server to bypass cash pipelines
    # -A forces a clean browser user-agent string to prevent empty block rejections
    curl -s \
         -H "Cache-Control: no-cache" \
         -H "Pragma: no-cache" \
         -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
         "$BASE_URL/${ZONE}.txt" > "$TARGET_DIR/${ZONE}.txt"
         
    # Quick execution sanity validation check
    if [ $? -eq 0 ] && [ -s "$TARGET_DIR/${ZONE}.txt" ]; then
        echo "  Successfully saved to: $TARGET_DIR/${ZONE}.txt"
    else
        echo "  ERROR: Failed to pull a valid file for $ZONE"
    fi
done
