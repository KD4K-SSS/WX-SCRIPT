#!/bin/bash

# Configuration Paths
OUTPUT_FILE="/var/www/html/data/hf/regional_muf.json"
PATHS_FILE="/var/www/html/data/hf/user_paths.json" # TEST MODE TARGET FILE
INTERVAL=900 # 15 minutes

# TARGET SNR: Set to 3 dB to strike a balance between voice copy capacity and data density
WSPR_SNR_THRESHOLD=3

# Define US Regions using optimized grid mappings (Mixing full sectors for low density, sub-grids for high density)
REGIONS=(
    "Northeast_1|FN"         # Reverted to full FN — needs a wider net to capture quiet periods
    "Mid_Atlantic_2|FN2"     # Focuses on PA / NJ (FN20, FN10, etc.)
    "Mid_Atlantic_3|FM"      # Maryland / Virginia / West Virginia
    "Southeast_4|EM8"        # GA / FL / Carolinas / TN
    "South_Central_5|EM"     # Reverted to full EM — captures the entire TX/OK/LA footprint 
    "West_Coast_6|CM"        # California (CM, DM)
    "Pacific_NW_7|CN"        # Washington / Oregon
    "Great_Lakes_8|EN8"      # Michigan / Ohio / West PA
    "Midwest_9|EN5"          # Illinois / Indiana / Wisconsin
    "Plains_0|DN"            # Colorado / Wyoming / Dakotas / Nebraska
)

echo "Regional US WSPR HF MUF Engine Started (Named JSON Engine)..."

while true; do
    echo "[$(date -u)] Fetching last 15 mins of live packet telemetry from wspr.live..."
    
    START_TIME=$(date -u -d "15 minutes ago" +"%Y-%m-%d %H:%M:%S")
    END_TIME=$(date -u +"%Y-%m-%d %H:%M:%S")
    
    TMP_JSON=$(curl -s --connect-timeout 15 -G "https://wspr.live/wspr_downloader.php" \
        --data-urlencode "start=${START_TIME}" \
        --data-urlencode "end=${END_TIME}" \
        --data-urlencode "format=JSON")

    if [ -z "$TMP_JSON" ] || ! echo "$TMP_JSON" | jq -e . >/dev/null 2>&1; then
        echo "Warning: API endpoint returned invalid text structure. Skipping run cycle..."
    else
       # =====================================================================
        # TEST MODE UPGRADE: Compile Grid Map with Transmitting Regions Heard
        # =====================================================================
        echo " -> Processing test mode grid map with path origins..."
        GRID_MAP_JSON=$(echo "$TMP_JSON" | jq --argjson snr_floor "$WSPR_SNR_THRESHOLD" '
            [ .data[]? | 
              select(.rx_loc | strings | length >= 2) |
              select(.tx_loc | strings | length >= 2) |
              select(.snr >= $snr_floor) |
              select(.frequency <= 30000000 and .frequency > 0) |
              { 
                rx: .rx_loc[0:2], 
                freq: (.frequency / 1000000),
                # Map tx_loc prefix to readable call district regions
                tx_region: (
                  if .tx_loc | startswith("FN") then "Northeast/Mid-Atlantic"
                  elif .tx_loc | startswith("FM") then "Mid-Atlantic (3)"
                  elif .tx_loc | startswith("EM") then "Southeast/South-Central"
                  elif .tx_loc | startswith("CM") then "West Coast (6)"
                  elif .tx_loc | startswith("CN") then "Pacific NW (7)"
                  elif .tx_loc | startswith("EN") then "Great Lakes/Midwest"
                  elif .tx_loc | startswith("DN") then "Plains (0)"
                  else ("Grid " + .tx_loc[0:2])
                  end
                )
              }
            ] | group_by(.rx) | map({
                key: .[0].rx,
                value: {
                    muf: (map(.freq) | max | (.*100 | round / 100)),
                    spots: length,
                    # Collect unique list of regions heard by this grid
                    hearing: (map(.tx_region) | unique)
                }
            }) | from_entries
        ')
        
        FINAL_PATHS_JSON=$(jq -n --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" --argjson grids "$GRID_MAP_JSON" '{last_updated: $time, grids: $grids}')
        echo "$FINAL_PATHS_JSON" > "${PATHS_FILE}.tmp"
        mv "${PATHS_FILE}.tmp" "$PATHS_FILE"
        
        # =====================================================================
        # 2. CORE REGIONS ENGINE (Optimized validation)
        # =====================================================================
        JSON_ACCUMULATOR="{}"

        for REGION_DATA in "${REGIONS[@]}"; do
            IFS='|' read -r NAME MATCH_GRID <<< "$REGION_DATA"
            
            STATS=$(echo "$TMP_JSON" | jq --arg grid "$MATCH_GRID" --argjson snr_floor "$WSPR_SNR_THRESHOLD" '
                [ .data[]? | 
                  select(.rx_loc | strings | startswith($grid)) | 
                  select(.snr >= $snr_floor) | 
                  select(.frequency <= 30000000 and .frequency > 0) | 
                  .frequency 
                ] | { count: length, max: max }
            ')

            TOTAL_SPOTS=$(echo "$STATS" | jq '.count')
            MAX_FREQ_HZ=$(echo "$STATS" | jq '.max')

            # Require at least 2 matching spots to protect against anomalous, single-station flukes
            if [ "$TOTAL_SPOTS" -gt 1 ] && [ "$MAX_FREQ_HZ" != "null" ]; then
                CROWD_MUF=$(awk "BEGIN {printf \"%.2f\", $MAX_FREQ_HZ / 1000000}")
            else
                CROWD_MUF="0.00"
            fi

            JSON_ACCUMULATOR=$(echo "$JSON_ACCUMULATOR" | jq \
                --arg name "$NAME" \
                --arg muf "$CROWD_MUF" \
                --argjson spots "$TOTAL_SPOTS" \
                '. + {($name): {muf: ($muf | tonumber), active_spots: $spots}}')
                
            echo " -> Zone: $NAME | Robust MUF: ${CROWD_MUF} MHz (${TOTAL_SPOTS} spots over ${WSPR_SNR_THRESHOLD}dB)"
        done

        FINAL_JSON=$(echo "$JSON_ACCUMULATOR" | jq --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '{last_updated: $time, regions: .}')
        echo "$FINAL_JSON" > "${OUTPUT_FILE}.tmp"
        mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
        echo "Success: Clean dashboard metrics updated."
    fi

    echo "Sleeping 15 minutes..."
    sleep $INTERVAL
done
