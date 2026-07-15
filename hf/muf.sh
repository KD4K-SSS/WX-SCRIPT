#!/bin/bash

# Configuration
INPUT_URL="https://prop.kc2g.com/api/stations.json"
OUTPUT_FILE="/var/www/html/data/hf/clean_stations.json"
MAX_AGE_HOURS=4
INTERVAL=900 # 15 minutes in seconds

echo "KD4K Station Cleaner Engine Started. Running loop background sequence..."

while true; do
    echo "[$(date -u)] Initiating download and filter cycle..."

    # 1. Grab the raw data feed
    RAW_JSON=$(curl -s --connect-timeout 8 -H "User-Agent: KD4K-Dashboard-Bot/1.0" "$INPUT_URL")

    if [ -z "$RAW_JSON" ]; then
        echo "Error: Failed to download source data. Retrying next cycle."
    else
        # 2. Parse, drop empty MUF/Coordinates, and drop records older than MAX_AGE_HOURS
        CLEAN_JSON=$(echo "$RAW_JSON" | jq --argjson hours "$MAX_AGE_HOURS" '
          [
            .[] | 
            select(
              .mufd != null and 
              .station.latitude != null and 
              .station.longitude != null and
              ((now - (.time + "Z" | fromdateiso8601)) / 3600) < $hours
            )
          ]
        ' 2>/dev/null)

        # 3. Verify and save atomically
        if [ ! -z "$CLEAN_JSON" ] && [ "$CLEAN_JSON" != "[]" ]; then
            echo "$CLEAN_JSON" > "${OUTPUT_FILE}.tmp"
            mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
            COUNT=$(echo "$CLEAN_JSON" | jq '. | length')
            echo "Success! Saved $COUNT active, real-time stations to $OUTPUT_FILE"
        else
            echo "Error: Filter resulted in empty or invalid dataset. Keeping old file."
        fi
    fi

    # Sleep loop execution sequence for 15 minutes
    echo "Sleeping for $((INTERVAL / 60)) minutes..."
    sleep $INTERVAL
done
