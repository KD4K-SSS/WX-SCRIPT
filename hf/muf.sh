#!/bin/bash

# Configuration
INPUT_URL="https://prop.kc2g.com/api/stations.json"
OUTPUT_FILE="/var/www/html/data/hf/clean_stations.json"
TEMPLATE_FILE="/var/www/html/template.html"
MAX_AGE_HOURS=4
INTERVAL=900 # 15 minutes in seconds

echo "KD4K Station Cleaner & HTML Engine Started. Running loop sequence..."

while true; do
    echo "[$(date -u)] Initiating download and propagation update cycle..."

    # 1. Grab the raw station data feed
    RAW_JSON=$(curl -s --connect-timeout 8 -H "User-Agent: KD4K-Dashboard-Bot/1.0" "$INPUT_URL")

    if [ -z "$RAW_JSON" ]; then
        echo "Error: Failed to download source station data. Retrying next cycle."
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

        # 3. Verify and save clean JSON atomically
        if [ ! -z "$CLEAN_JSON" ] && [ "$CLEAN_JSON" != "[]" ]; then
            echo "$CLEAN_JSON" > "${OUTPUT_FILE}.tmp"
            mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
            COUNT=$(echo "$CLEAN_JSON" | jq '. | length')
            echo "Success! Saved $COUNT active, real-time stations to $OUTPUT_FILE"
        else
            echo "Error: Filter resulted in empty or invalid dataset. Keeping old file."
        fi
    fi

    # 4. Check for 6m (VHF / 50MHz) Sporadic-E / Active Propagation in cleaned data
    B6_DAY="Poor"
    B6_NIGHT="Poor"

    if [ -f "$OUTPUT_FILE" ]; then
        # Check if any station in clean_stations.json detected foEs / MUF >= 50 MHz
        ACTIVE_6M=$(jq '[.[] | select(.foes >= 10.0 or .mufd >= 50.0)] | length' "$OUTPUT_FILE" 2>/dev/null)
        
        if [ ! -z "$ACTIVE_6M" ] && [ "$ACTIVE_6M" -gt 0 ]; then
            B6_DAY="Fair (Es)"
            B6_NIGHT="Fair (Es)"
            echo "6M VHF Activity Detected! ($ACTIVE_6M nodes reporting open conditions)"
        fi
    fi

    # 5. Inject 6M parameters directly into template.html
    if [ -f "$TEMPLATE_FILE" ]; then
        sed -i "s/TARGET_B6_D/$B6_DAY/g" "$TEMPLATE_FILE"
        sed -i "s/TARGET_B6_N/$B6_NIGHT/g" "$TEMPLATE_FILE"
        echo "Updated $TEMPLATE_FILE with live 6M band status ($B6_DAY / $B6_NIGHT)."
    fi

    # Sleep loop execution sequence for 15 minutes
    echo "Sleeping for $((INTERVAL / 60)) minutes..."
    sleep $INTERVAL
done
