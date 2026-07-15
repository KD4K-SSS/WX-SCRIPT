#!/bin/bash

set -euo pipefail

# ---------------- USB-BASED TMP DIRECTORY ----------------
TMPDIR="/mnt/ssbwx_tmp"
mkdir -p "$TMPDIR"

OUTPUT_FINAL="$TMPDIR/atis.wav"
TEMP_OUTPUT="$TMPDIR/atis_new.wav"
RAW_AUDIO="$TMPDIR/atis_raw.wav"
BEEP_FILE="$TMPDIR/atis_beep.wav"

# Verify dependencies
for cmd in jq awk sox pico2wave cvlc curl aplay; do
    command -v "$cmd" >/dev/null || { echo "$cmd not installed"; exit 1; }
done

trap "echo 'Stopping ATIS'; kill 0; exit 0" SIGINT

math() { awk "BEGIN { print $* }"; }

# ---------------- AIRPORT PROFILES ----------------
declare -A STATION_NAME OBS_URL ALERT_URL METAR_URL FORECAST_GRID_URL

STATION_NAME[HYW]="Conway, South Carolina"
OBS_URL[HYW]="https://api.weather.gov/stations/KHYW/observations/latest"
ALERT_URL[HYW]="https://api.weather.gov/alerts/active?point=33.80,-79.04"
METAR_URL[HYW]="https://tgftp.nws.noaa.gov/data/observations/metar/stations/KHYW.TXT"
FORECAST_GRID_URL[HYW]="https://api.weather.gov/gridpoints/ILM/90,60/forecast"

STATION_NAME[MYR]="Surfside Beach, South Carolina"
OBS_URL[MYR]="https://api.weather.gov/stations/KMYR/observations/latest"
ALERT_URL[MYR]="https://api.weather.gov/alerts/active?point=33.68,-78.89"
METAR_URL[MYR]="https://tgftp.nws.noaa.gov/data/observations/metar/stations/KMYR.TXT"
FORECAST_GRID_URL[MYR]="https://api.weather.gov/gridpoints/ILM/89,64/forecast"

# ---------------- VERBOSE SYSTEM (ROUTED TO USB) ----------------
# Moving the high-write state tracking file to the USB drive
VERBOSE_FILE="$TMPDIR/atis_verbose_state.txt"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE_LOG_DIR="$SCRIPT_DIR" # Long term log history files remain on primary disk

CURRENT_DAY=$(date +%F)
VERBOSE_HISTORY_FILE="$VERBOSE_LOG_DIR/atis_verbose_$CURRENT_DAY.log"

declare -A VERBOSE_PREV

if [ -f "$VERBOSE_FILE" ]; then
    while IFS="=" read -r k v; do
        VERBOSE_PREV["$k"]="$v"
    done < "$VERBOSE_FILE"
fi

VERBOSE_LOG() {
    local name="$1" value="$2" timestamp day_now msg
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    day_now=$(date +%F)

    if [ "$day_now" != "$CURRENT_DAY" ]; then
        CURRENT_DAY="$day_now"
        VERBOSE_HISTORY_FILE="$VERBOSE_LOG_DIR/atis_verbose_$CURRENT_DAY.log"
    fi

    if [ "${VERBOSE_PREV[$name]+set}" ] && [ "${VERBOSE_PREV[$name]}" != "$value" ]; then
        msg="[VERBOSE] $timestamp $name changed: '${VERBOSE_PREV[$name]}' → '$value'"
    elif [ -z "${VERBOSE_PREV[$name]+set}" ]; then
        msg="[VERBOSE] $timestamp $name initialized: '$value'"
    else
        msg="[VERBOSE] $timestamp $name unchanged: '$value'"
    fi

    echo "$msg" >&2
    echo "$msg" >> "$VERBOSE_HISTORY_FILE"
    VERBOSE_PREV["$name"]="$value"
}

SAVE_VERBOSE() {
    : > "$VERBOSE_FILE"
    for k in "${!VERBOSE_PREV[@]}"; do
        echo "$k=${VERBOSE_PREV[$k]}" >> "$VERBOSE_FILE"
    done
}

speak_aviation_time() {
    local t="$1"
    digit_word() {
        case "$1" in
            0) echo "zero" ;; 1) echo "one" ;; 2) echo "two" ;; 3) echo "three" ;;
            4) echo "four" ;; 5) echo "five" ;; 6) echo "six" ;; 7) echo "seven" ;;
            8) echo "eight" ;; 9) echo "niner" ;;
        esac
    }
    echo "$(digit_word "${t:0:1}") $(digit_word "${t:1:1}") $(digit_word "${t:2:1}") $(digit_word "${t:3:1}")"
}

convert_direction() {
    local DEG=$1
    if (( DEG >= 338 || DEG < 23 )); then echo "north"
    elif (( DEG < 68 )); then echo "northeast"
    elif (( DEG < 113 )); then echo "east"
    elif (( DEG < 158 )); then echo "southeast"
    elif (( DEG < 203 )); then echo "south"
    elif (( DEG < 248 )); then echo "southwest"
    elif (( DEG < 293 )); then echo "west"
    else echo "northwest"
    fi
}

capitalize_sentences() {
    echo "$1" | sed -E 's/(^|\. )([a-z])/\1\U\2/g'
}

# ---------------- AUDIO BEEP SETUP ----------------
if [ ! -f "$BEEP_FILE" ]; then
    sox -n -r 44100 -c 1 "$BEEP_FILE" synth 0.15 sine 1000 vol 0.08
fi

# ---------------- ATIS ENGINE ----------------
generate_atis() {
    STATION="$1"
    STATION_LOWER="${STATION,,}"

    # Safe network fetches using || true to defend set -e
    OBS_JSON=$(curl -s --max-time 10 "${OBS_URL[$STATION]}" || echo "{}")
    ALERTS_JSON=$(curl -s --max-time 10 "${ALERT_URL[$STATION]}" || echo "{}")
    METAR=$(curl -s --max-time 10 "${METAR_URL[$STATION]}" | tail -1 || echo "")
    FORECAST_JSON=$(curl -s --max-time 10 "${FORECAST_GRID_URL[$STATION]}" || echo "{}")

    # ---------------- FORECAST ----------------
    HIGH_TEMP=$(echo "$FORECAST_JSON" | jq -r '.properties.periods[]? | select(.isDaytime==true) | .temperature' | head -1 || echo "")
    LOW_TEMP=$(echo "$FORECAST_JSON" | jq -r '.properties.periods[]? | select(.isDaytime==false) | .temperature' | head -1 || echo "")
    FORECAST_WIND=$(echo "$FORECAST_JSON" | jq -r '.properties.periods[]? | select(.isDaytime==true) | .windSpeed' | head -1 || echo "")

    if [[ -n "$HIGH_TEMP" && -n "$LOW_TEMP" ]]; then
        FORECAST_PHRASE="Forecast high ${HIGH_TEMP} degrees, low ${LOW_TEMP} degrees, air speed ${FORECAST_WIND}"
    else
        FORECAST_PHRASE="Forecast unavailable"
    fi
    VERBOSE_LOG "Forecast" "$FORECAST_PHRASE"

    # ---------------- PRECIPITATION ----------------
    RAIN_CHANCE=$(echo "$FORECAST_JSON" | jq -r '.properties.periods[0].probabilityOfPrecipitation.value // 0' 2>/dev/null || echo "0")
    [[ "$RAIN_CHANCE" == "null" || -z "$RAIN_CHANCE" ]] && RAIN_CHANCE=0
    RAIN_PHRASE="Chance of precipitation ${RAIN_CHANCE} percent"
    VERBOSE_LOG "Rain Chance" "$RAIN_PHRASE"

    # ---------------- ALERTS ----------------
    EVENTS=$(echo "$ALERTS_JSON" | jq -r '.features[].properties.event? // empty' 2>/dev/null | sort -u || echo "")
    ALERT_PHRASE="No advisories"
    if [ -n "$EVENTS" ]; then
        ALERT_PHRASE=""
        while read -r event; do
            ALERT_PHRASE+=" $event in effect."
        done <<< "$EVENTS"
    fi
    VERBOSE_LOG "Alerts" "$ALERT_PHRASE"

    # ---------------- LIGHTNING ----------------
    FORECAST_TEXT=$(echo "$FORECAST_JSON" | jq -r '.properties.periods[0].detailedForecast // empty' 2>/dev/null || echo "")
    SHORT_FORECAST=$(echo "$FORECAST_JSON" | jq -r '.properties.periods[0].shortForecast // empty' 2>/dev/null || echo "")
    FORECAST_TEXT_LOWER=$(echo "$FORECAST_TEXT $SHORT_FORECAST" | tr '[:upper:]' '[:lower:]')

    LIGHTNING_PHRASE="Lightning chance low in the area"
    LIGHTNING_PERCENT=5

    # Native Bash string evaluation skips grep exit failure risks
    if [[ "$ALERTS_JSON" =~ (Severe|Thunderstorm|Tornado|Special) ]]; then
        LIGHTNING_PERCENT=95
        LIGHTNING_PHRASE="Severe thunderstorms with dangerous lightning in the area"
    elif [[ "$FORECAST_TEXT_LOWER" =~ "thunderstorm" ]]; then
        RAIN_CHANCE_NUM=$(echo "$RAIN_CHANCE" | sed 's/[^0-9]//g')
        : "${RAIN_CHANCE_NUM:=0}"

        if (( RAIN_CHANCE_NUM >= 80 )); then
            LIGHTNING_PERCENT=85; LIGHTNING_PHRASE="Thunderstorms with frequent lightning likely"
        elif (( RAIN_CHANCE_NUM >= 60 )); then
            LIGHTNING_PERCENT=65; LIGHTNING_PHRASE="Scattered thunderstorms with lightning possible"
        elif (( RAIN_CHANCE_NUM >= 40 )); then
            LIGHTNING_PERCENT=45; LIGHTNING_PHRASE="Isolated thunderstorms possible"
        elif (( RAIN_CHANCE_NUM >= 20 )); then
            LIGHTNING_PERCENT=25; LIGHTNING_PHRASE="Slight chance of thunderstorms"
        else
            LIGHTNING_PERCENT=15; LIGHTNING_PHRASE="Minimal lightning threat"
        fi
    fi
    LIGHTNING_PERCENT_PHRASE="Chance of lightning ${LIGHTNING_PERCENT} percent"
    VERBOSE_LOG "Lightning" "$LIGHTNING_PHRASE"

    # ---------------- WIND ----------------
    WIND_DIR=0; WIND_SPEED=0
    if [[ "$METAR" =~ ([0-9]{3})([0-9]{2})KT ]]; then
        WIND_DIR=${BASH_REMATCH[1]}
        WIND_SPEED=${BASH_REMATCH[2]}
    fi
    WIND_DIR_WORD=$(convert_direction "$WIND_DIR")
    WIND_MPH=$(math "int(($WIND_SPEED * 1.15078) + 0.5)")
    WIND_PHRASE=$([ "$WIND_SPEED" -le 2 ] && echo "Wind calm" || echo "Wind from the ${WIND_DIR_WORD} at ${WIND_MPH} miles per hour")
    VERBOSE_LOG "Wind" "$WIND_PHRASE"

    # ---------------- VISIBILITY ----------------
    VIS_METERS=$(echo "$OBS_JSON" | jq -r '.properties.visibility.value // 16093' 2>/dev/null || echo "16093")
    VIS_MILES=$(math "int(($VIS_METERS / 1609.34) + 0.5)")
    VIS_PHRASE="Visibility ${VIS_MILES} miles"
    VERBOSE_LOG "Visibility" "$VIS_PHRASE"

    # ---------------- TEMP / DEWPOINT / HUMIDITY ----------------
    TEMP_C=0; DP_C=0
    if [[ "$METAR" =~ ([M]?[0-9]{2})/([M]?[0-9]{2}) ]]; then
        TEMP_C=$(echo "${BASH_REMATCH[1]}" | sed 's/M/-/')
        DP_C=$(echo "${BASH_REMATCH[2]}" | sed 's/M/-/')
    fi
    TEMP=$(math "int((($TEMP_C * 9 / 5) + 32) + 0.5)")
    DP=$(math "int((($DP_C * 9 / 5) + 32) + 0.5)")
    HUMIDITY=$(awk -v T="$TEMP_C" -v DP="$DP_C" 'BEGIN{RH = 100 * (exp((17.625*DP)/(243.04+DP)) / exp((17.625*T)/(243.04+T))); print int(RH+0.5)}')
    VERBOSE_LOG "Humidity" "${HUMIDITY}%"

    # ---------------- HEAT INDEX ----------------
    HEAT_INDEX=$(awk -v T="$TEMP" -v RH="$HUMIDITY" 'BEGIN{if(T >= 75 && RH >= 40){HI = -42.379 + 2.04901523*T + 10.14333127*RH - 0.22475541*T*RH - 0.00683783*T*T - 0.05481717*RH*RH + 0.00122874*T*T*RH + 0.00085282*T*RH*RH - 0.00000199*T*T*RH*RH; print int(HI+0.5)} else { print T }}')
    VERBOSE_LOG "Heat Index" "${HEAT_INDEX}F"

    # ---------------- CLOUDS ----------------
    CLOUD_PHRASE=""
    NWS_CLOUDS=$(echo "$OBS_JSON" | jq -r '.properties.cloudLayers[]? | if .amount=="FEW" then " few clouds at, \(.base.value * 3.28084 | floor) feet" elif .amount=="SCT" then " scattered clouds at, \(.base.value * 3.28084 | floor) feet" elif .amount=="BKN" then " broken ceiling at, \(.base.value * 3.28084 | floor) feet" elif .amount=="OVC" then " overcast ceiling at, \(.base.value * 3.28084 | floor) feet" else empty end' 2>/dev/null | paste -sd ", " - || echo "")

    if [[ -n "$NWS_CLOUDS" ]]; then
        CLOUD_PHRASE="$NWS_CLOUDS"
    else
        SKY_CODE=$(echo "$METAR" | grep -oE 'SKC|CLR|FEW[0-9]{3}|SCT[0-9]{3}|BKN[0-9]{3}|OVC[0-9]{3}' | head -1 || echo "CLR")
        case "$SKY_CODE" in
            SKC|CLR) CLOUD_PHRASE="clear skies" ;;
            FEW*) CLOUD_PHRASE="few clouds" ;;
            SCT*) CLOUD_PHRASE="scattered clouds" ;;
            BKN*) CLOUD_PHRASE="broken ceiling" ;;
            OVC*) CLOUD_PHRASE="overcast ceiling" ;;
            *) CLOUD_PHRASE="clear skies" ;;
        esac
    fi
    VERBOSE_LOG "Clouds" "$CLOUD_PHRASE"

    # ---------------- COMPILING DATA ----------------
    TIME=$(date +"%H%M")
    TIME_SPOKEN=$(speak_aviation_time "$TIME")
    ATIS="${STATION_NAME[$STATION]} Weather Update. Time ${TIME_SPOKEN} local. ${WIND_PHRASE}. ${VIS_PHRASE}. Sky conditions ${CLOUD_PHRASE}. Temperature ${TEMP} degrees. Dewpoint ${DP} degrees. Humidity ${HUMIDITY} percent. Heat index ${HEAT_INDEX} degrees. ${ALERT_PHRASE}. ${LIGHTNING_PHRASE}. ${LIGHTNING_PERCENT_PHRASE}. ${FORECAST_PHRASE}. ${RAIN_PHRASE}. End transmission. Kilo Delta Four Kilo."
    ATIS_FORMATTED=$(capitalize_sentences "$ATIS")

    # Explicitly print to standard error stream so it groups with the verbose terminal view
    echo "" >&2
    echo "KD4K WEATHER STATION ($STATION)" >&2
    echo "==============================" >&2
    echo "$ATIS_FORMATTED" >&2
    echo "==============================" >&2
    echo "" >&2

    # ---------------- OUTPUT WRITES ----------------
    DASHBOARD_DIR="$HOME/radar_dashboard"
    mkdir -p "$DASHBOARD_DIR"

    # Intermediate plain-text blocks go to the USB drive
    TEXT_REPORT_USB="$TMPDIR/atis_${STATION_LOWER}.txt"

    cat > "$TEXT_REPORT_USB" <<EOF
KD4K WEATHER STATION ($STATION)
==============================
$ATIS_FORMATTED
==============================
Last Updated: $(date)
EOF

    SAVE_VERBOSE

    # Web output stays on your storage disk untouched
    cat > "$DASHBOARD_DIR/weather_${STATION_LOWER}.html" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta http-equiv="refresh" content="30">
<title>KD4K Weather Station - $STATION</title>
<style>
body { background: black; color: #00ff00; font-family: monospace; padding: 20px; white-space: pre-wrap; }
</style>
</head>
<body>
<pre>$(cat "$TEXT_REPORT_USB")</pre>
</body>
</html>
EOF

    cat > /var/www/html/data/${STATION_LOWER}_weather.json <<EOF
{
  "updated":"$(date '+%Y-%m-%d %H:%M:%S')",
  "station":"${STATION_NAME[$STATION]}",
  "wind":"${WIND_PHRASE}",
  "visibility":"${VIS_PHRASE}",
  "clouds":"${CLOUD_PHRASE}",
  "temperature":${TEMP},
  "dewpoint":${DP},
  "humidity":${HUMIDITY},
  "heat_index":${HEAT_INDEX},
  "lightning_phrase":"${LIGHTNING_PHRASE}",
  "lightning_percent":${LIGHTNING_PERCENT},
  "rain_percent":${RAIN_CHANCE},
  "forecast":"${FORECAST_PHRASE}",
  "alerts":"${ALERT_PHRASE}"
}
EOF

    # Audio compression & manipulation runs completely on the USB drive
    pico2wave -w "$RAW_AUDIO" "$ATIS_FORMATTED"
    sox "$RAW_AUDIO" "$TEMP_OUTPUT" gain -n -6 pad 0.35 0.35 highpass 70 lowpass 6500 pitch -100 tempo 0.94
    mv "$TEMP_OUTPUT" "$TMPDIR/atis_${STATION_LOWER}.wav"
}

# ---------------- MAIN LOOP ----------------
while true; do
    for target_station in HYW MYR; do
        generate_atis "$target_station"
        
        # Stream audio execution from the partition path
        cvlc --play-and-exit --quiet "$TMPDIR/atis_${target_station,,}.wav" >/dev/null 2>&1

        for i in {1..5}; do
            cvlc --play-and-exit --quiet "$BEEP_FILE" >/dev/null 2>&1
            sleep 1
        done
    done
done
