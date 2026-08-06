#!/bin/bash

TEMPLATE_FILE="template.html"
OUTPUT_DIR="/var/www/html/data/hf"
OUTPUT_FILE="$OUTPUT_DIR/index.html"
JSON_OUT_FILE="$OUTPUT_DIR/muf.json"
URL_HAMQSL="https://www.hamqsl.com/solarxml.php"
URL_FORECAST="https://services.swpc.noaa.gov/text/3-day-forecast.txt"
URL_MUF_API="https://prop.kc2g.com/api/stations.json"
SLEEP_INTERVAL=900
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Safari/537.36"

mkdir -p "$OUTPUT_DIR"

parse_tag() { echo "$XML_DATA" | grep -oP "<$1>\K[^<]+" | head -n 1; }
parse_band() { echo "$XML_DATA" | grep -oP "<band name=\"$1\" time=\"$2\">\K[^<]+" | head -n 1; }
get_status_cls() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

echo "Starting Stable Propagation Loop..."

while true; do
    echo "[$(date)] Syncing active environmental matrices..."
    
    XML_DATA=$(curl -sL -A "$USER_AGENT" --max-time 15 "$URL_HAMQSL" | tr -d '\r')
    RAW_FCST=$(curl -sL -A "$USER_AGENT" --max-time 15 "$URL_FORECAST" | tr -d '\r')
    curl -sL -A "$USER_AGENT" --max-time 15 "$URL_MUF_API" -o "$JSON_OUT_FILE"

    if [ -n "$XML_DATA" ] && [[ "$XML_DATA" == *"<solarflux>"* ]]; then
        SFI=$(parse_tag "solarflux"); SFI=${SFI:-N/A}
        SUNSPOTS=$(parse_tag "sunspots"); SUNSPOTS=${SUNSPOTS:-N/A}
        A_INDEX=$(parse_tag "aindex"); A_INDEX=${A_INDEX:-N/A}
        K_INDEX=$(parse_tag "kindex"); K_INDEX=${K_INDEX:-N/A}
        XRAY=$(parse_tag "xray"); XRAY=${XRAY:-N/A}
        SIGNAL_NOISE=$(parse_tag "signalnoise"); SIGNAL_NOISE=${SIGNAL_NOISE:-N/A}
        echo "$SIGNAL_NOISE" > /var/www/html/data/hf/noise_level.txt
        UPDATED=$(parse_tag "updated"); UPDATED=${UPDATED:-$(date)}
        WIND=$(parse_tag "solarwind"); WIND=${WIND:-N/A}
        IMF=$(parse_tag "magneticfield"); IMF=${IMF:-N/A}

        TEXT_FORECAST_CLEAN=$(echo "$RAW_FCST" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        [ -z "$TEXT_FORECAST_CLEAN" ] && TEXT_FORECAST_CLEAN="No updates found."

        B40_D=$(parse_band "80m-40m" "day");   B40_D=${B40_D:-N/A}
        B40_N=$(parse_band "80m-40m" "night"); B40_N=${B40_N:-N/A}
        B20_D=$(parse_band "30m-20m" "day");   B20_D=${B20_D:-N/A}
        B20_N=$(parse_band "30m-20m" "night"); B20_N=${B20_N:-N/A}
        B15_D=$(parse_band "17m-15m" "day");   B15_D=${B15_D:-N/A}
        B15_N=$(parse_band "17m-15m" "night"); B15_N=${B15_N:-N/A}
        B10_D=$(parse_band "12m-10m" "day");   B10_D=${B10_D:-N/A}
        B10_N=$(parse_band "12m-10m" "night"); B10_N=${B10_N:-N/A}

        B40_D_CLS=$(get_status_cls "$B40_D"); B40_N_CLS=$(get_status_cls "$B40_N")
        B20_D_CLS=$(get_status_cls "$B20_D"); B20_N_CLS=$(get_status_cls "$B20_N")
        B15_D_CLS=$(get_status_cls "$B15_D"); B15_N_CLS=$(get_status_cls "$B15_N")
        B10_D_CLS=$(get_status_cls "$B10_D"); B10_N_CLS=$(get_status_cls "$B10_N")

        [ "$SFI" != "N/A" ] && [ "$SFI" -lt 90 ] && { SFI_EVAL="Poor"; SFI_CLASS="poor"; } || { [ "$SFI" != "N/A" ] && [ "$SFI" -lt 140 ] && { SFI_EVAL="Fair"; SFI_CLASS="fair"; } || { SFI_EVAL="Good"; SFI_CLASS="good"; }; }
        [ "$SUNSPOTS" != "N/A" ] && [ "$SUNSPOTS" -lt 40 ] && { SS_EVAL="Poor"; SS_CLASS="poor"; } || { [ "$SUNSPOTS" != "N/A" ] && [ "$SUNSPOTS" -lt 100 ] && { SS_EVAL="Fair"; SS_CLASS="fair"; } || { SS_EVAL="Good"; SS_CLASS="good"; }; }
        [[ "$XRAY" == A* ]] || [[ "$XRAY" == B* ]] && { X_EVAL="Good"; X_CLASS="good"; } || { [[ "$XRAY" == C* ]] && { X_EVAL="Fair"; X_CLASS="fair"; } || { X_EVAL="Poor"; X_CLASS="poor"; }; }
        
        WIND_INT=${WIND%.*}; WIND_INT=${WIND_INT:-0}
        [ "$WIND" = "N/A" ] && { WIND_EVAL="Unknown"; WIND_CLASS="unknown"; } || { [ "$WIND_INT" -lt 400 ] && { WIND_EVAL="Good"; WIND_CLASS="good"; } || { [ "$WIND_INT" -lt 550 ] && { WIND_EVAL="Fair"; WIND_CLASS="fair"; } || { WIND_EVAL="Poor"; WIND_CLASS="poor"; }; }; }
        [ "$K_INDEX" = "N/A" ] && { K_EVAL="Unknown"; K_CLASS="unknown"; } || { [ "$K_INDEX" -le 2 ] && { K_EVAL="Good"; K_CLASS="good"; } || { [ "$K_INDEX" -le 4 ] && { K_EVAL="Fair"; K_CLASS="fair"; } || { K_EVAL="Poor"; K_CLASS="poor"; }; }; }
        [ "$A_INDEX" = "N/A" ] && { A_EVAL="Unknown"; A_CLASS="unknown"; } || { [ "$A_INDEX" -lt 10 ] && { A_EVAL="Good"; A_CLASS="good"; } || { [ "$A_INDEX" -lt 20 ] && { A_EVAL="Fair"; A_CLASS="fair"; } || { A_EVAL="Poor"; A_CLASS="poor"; }; }; }
        [ "$IMF" = "N/A" ] && { IMF_EVAL="Unknown"; IMF_CLASS="unknown"; } || { [[ "$IMF" == -* ]] && { IMF_EVAL="Poor"; IMF_CLASS="poor"; } || { IMF_EVAL="Good"; IMF_CLASS="good"; }; }
        [[ "$SIGNAL_NOISE" == *"S0"* ]] || [[ "$SIGNAL_NOISE" == *"S1"* ]] || [[ "$SIGNAL_NOISE" == *"S2"* ]] && { NOISE_EVAL="Good"; NOISE_CLASS="good"; } || { [[ "$SIGNAL_NOISE" == *"S3"* ]] || [[ "$SIGNAL_NOISE" == *"S4"* ]] || [[ "$SIGNAL_NOISE" == *"S5"* ]] && { NOISE_EVAL="Fair"; NOISE_CLASS="fair"; } || { NOISE_EVAL="Poor"; NOISE_CLASS="poor"; }; }

        T="$OUTPUT_FILE.tmp"
        cp "$TEMPLATE_FILE" "$T"

        sed -i "s|TARGET_UPDATED|$UPDATED|g" "$T"
        sed -i "s|TARGET_SFI|$SFI \&rarr; $SFI_EVAL|g" "$T"
        sed -i "s|id=\"val-sfi\" class=\"card-value\"|id=\"val-sfi\" class=\"card-value $SFI_CLASS\"|g" "$T"
        sed -i "s|TARGET_SUNSPOTS|$SUNSPOTS \&rarr; $SS_EVAL|g" "$T"
        sed -i "s|id=\"val-ss\" class=\"card-value\"|id=\"val-ss\" class=\"card-value $SS_CLASS\"|g" "$T"
        sed -i "s|TARGET_XRAY|$XRAY \&rarr; $X_EVAL|g" "$T"
        sed -i "s|id=\"val-xray\" class=\"card-value\"|id=\"val-xray\" class=\"card-value $X_CLASS\"|g" "$T"
        sed -i "s|TARGET_WIND|$WIND|g" "$T"
        sed -i "s|id=\"val-wind\" class=\"card-value\"|id=\"val-wind\" class=\"card-value $WIND_CLASS\"|g" "$T"
        sed -i "s|TARGET_KINDEX|$K_INDEX \&rarr; $K_EVAL|g" "$T"
        sed -i "s|id=\"val-k\" class=\"card-value\"|id=\"val-k\" class=\"card-value $K_CLASS\"|g" "$T"
        sed -i "s|TARGET_AINDEX|$A_INDEX \&rarr; $A_EVAL|g" "$T"
        sed -i "s|id=\"val-a\" class=\"card-value\"|id=\"val-a\" class=\"card-value $A_CLASS\"|g" "$T"
        sed -i "s|TARGET_IMF|$IMF|g" "$T"
        sed -i "s|id=\"val-imf\" class=\"card-value\"|id=\"val-imf\" class=\"card-value $IMF_CLASS\"|g" "$T"
        sed -i "s|TARGET_SIGNAL_NOISE|$SIGNAL_NOISE \&rarr; $NOISE_EVAL|g" "$T"
        sed -i "s|id=\"val-noise\" class=\"card-value\"|id=\"val-noise\" class=\"card-value $NOISE_CLASS\"|g" "$T"

        sed -i "s|TARGET_B40_D|$B40_D|g" "$T"
        sed -i "s|id=\"b40d\"|id=\"b40d\" class=\"band-status $B40_D_CLS\"|g" "$T"
        sed -i "s|TARGET_B40_N|$B40_N|g" "$T"
        sed -i "s|id=\"b40n\"|id=\"b40n\" class=\"band-status $B40_N_CLS\"|g" "$T"
        sed -i "s|TARGET_B20_D|$B20_D|g" "$T"
        sed -i "s|id=\"b20d\"|id=\"b20d\" class=\"band-status $B20_D_CLS\"|g" "$T"
        sed -i "s|TARGET_B20_N|$B20_N|g" "$T"
        sed -i "s|id=\"b20n\"|id=\"b20n\" class=\"band-status $B20_N_CLS\"|g" "$T"
        sed -i "s|TARGET_B15_D|$B15_D|g" "$T"
        sed -i "s|id=\"b15d\"|id=\"b15d\" class=\"band-status $B15_D_CLS\"|g" "$T"
        sed -i "s|TARGET_B15_N|$B15_N|g" "$T"
        sed -i "s|id=\"b15n\"|id=\"b15n\" class=\"band-status $B15_N_CLS\"|g" "$T"
        sed -i "s|TARGET_B10_D|$B10_D|g" "$T"
        sed -i "s|id=\"b10d\"|id=\"b10d\" class=\"band-status $B10_D_CLS\"|g" "$T"
        sed -i "s|TARGET_B10_N|$B10_N|g" "$T"
        sed -i "s|id=\"b10n\"|id=\"b10n\" class=\"band-status $B10_N_CLS\"|g" "$T"

        export TEXT_FORECAST_CLEAN
        awk '{gsub(/TARGET_TEXT_FORECAST/, ENVIRON["TEXT_FORECAST_CLEAN"])}1' "$T" > "$OUTPUT_FILE"
        rm -f "$T"
        echo "[$(date)] Render sequence clear."
    fi
    sleep $SLEEP_INTERVAL
done
EOF
