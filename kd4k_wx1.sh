#!/bin/bash

set -euo pipefail

TMPDIR="/dev/shm/atis"
mkdir -p "$TMPDIR"

OUTPUT_FINAL="$TMPDIR/atis.wav"
TEMP_OUTPUT="$TMPDIR/atis_new.wav"
RAW_AUDIO="$TMPDIR/atis_raw.wav"
BEEP_FILE="$TMPDIR/atis_beep.wav"

for cmd in jq awk sox pico2wave cvlc curl aplay; do
  command -v "$cmd" >/dev/null || { echo "$cmd not installed"; exit 1; }
done

trap "echo 'Stopping ATIS'; kill 0; exit 0" SIGINT

math() { awk "BEGIN { print $* }"; }

# ---------------- AIRPORT PROFILES ----------------
declare -A STATION_NAME OBS_URL ALERT_URL METAR_URL FORECAST_URL FORECAST_GRID_URL

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

# ---------------- VERBOSE SYSTEM ----------------
VERBOSE_FILE="/home/sss/Downloads/atis_verbose_state.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE_LOG_DIR="$SCRIPT_DIR"

CURRENT_DAY=$(date +%F)
VERBOSE_HISTORY_FILE="$VERBOSE_LOG_DIR/atis_verbose_$CURRENT_DAY.log"

declare -A VERBOSE_PREV

if [ -f "$VERBOSE_FILE" ]; then
  while IFS="=" read -r k v; do
    VERBOSE_PREV["$k"]="$v"
  done < "$VERBOSE_FILE"
fi

VERBOSE_LOG() {
    local name="$1"
    local value="$2"
    local timestamp day_now msg

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

say_digits() { echo "$1" | sed 's/./& /g'; }

speak_aviation_time() {
  local t="$1"
  local h1=${t:0:1}
  local h2=${t:1:1}
  local m1=${t:2:1}
  local m2=${t:3:1}

  digit_word() {
    case "$1" in
      0) echo "zero" ;;
      1) echo "one" ;;
      2) echo "two" ;;
      3) echo "three" ;;
      4) echo "four" ;;
      5) echo "five" ;;
      6) echo "six" ;;
      7) echo "seven" ;;
      8) echo "eight" ;;
      9) echo "niner" ;;
    esac
  }

  echo "$(digit_word "$h1") $(digit_word "$h2") $(digit_word "$m1") $(digit_word "$m2")"
}

convert_direction() {
  DEG=$1
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

# ---------------- AUDIO BEEP ----------------
if [ ! -f "$BEEP_FILE" ]; then
  sox -n -r 44100 -c 1 "$BEEP_FILE" synth 0.15 sine 1000 vol 0.08
fi

# ---------------- ATIS ENGINE ----------------
generate_atis() {

STATION="$1"

OBS_JSON=$(curl -s --max-time 10 "${OBS_URL[$STATION]}")
ALERTS_JSON=$(curl -s --max-time 10 "${ALERT_URL[$STATION]}")
METAR=$(curl -s --max-time 10 "${METAR_URL[$STATION]}" | tail -1)

FORECAST_JSON=$(curl -s --max-time 10 "${FORECAST_GRID_URL[$STATION]}")

# ---------------- FORECAST FIX (TEMP + WIND RESTORED) ----------------
# ---------------- FORECAST FIX (TEMP + WIND RESTORED) ----------------
HIGH_TEMP=$(echo "$FORECAST_JSON" | jq -r '
.properties.periods[]
| select(.isDaytime==true)
| .temperature
' | head -1)

LOW_TEMP=$(echo "$FORECAST_JSON" | jq -r '
.properties.periods[]
| select(.isDaytime==false)
| .temperature
' | head -1)

FORECAST_WIND=$(echo "$FORECAST_JSON" | jq -r '
.properties.periods[]
| select(.isDaytime==true)
| .windSpeed
' | head -1)

if [[ -n "$HIGH_TEMP" && -n "$LOW_TEMP" ]]; then
  FORECAST_PHRASE="Forecast high ${HIGH_TEMP} degrees, low ${LOW_TEMP} degrees, air speed ${FORECAST_WIND}"
else
  FORECAST_PHRASE="Forecast unavailable"
fi

VERBOSE_LOG "Forecast" "$FORECAST_PHRASE"

# ---------------- CHANCE OF PRECIPITATION ----------------
RAIN_CHANCE=$(echo "$FORECAST_JSON" | jq -r '
.properties.periods[0].probabilityOfPrecipitation.value // 0
')

if [[ "$RAIN_CHANCE" == "null" || -z "$RAIN_CHANCE" ]]; then
  RAIN_CHANCE=0
fi

RAIN_PHRASE="Chance of precipitation ${RAIN_CHANCE} percent"

VERBOSE_LOG "Rain Chance" "$RAIN_PHRASE"

VERBOSE_LOG "Forecast" "$FORECAST_PHRASE"

# ---------------- ALERTS ----------------
EVENTS=$(echo "$ALERTS_JSON" | jq -r '.features[].properties.event? // empty' | sort -u)
ALERT_PHRASE="No advisories"

if [ -n "$EVENTS" ]; then
  ALERT_PHRASE=""
  while read -r event; do
    ALERT_PHRASE+=" $event in effect."
  done <<< "$EVENTS"
fi

VERBOSE_LOG "Alerts" "$ALERT_PHRASE"

# ---------------- LIGHTNING (HYBRID NOAA SYSTEM + PERCENT) ----------------

FORECAST_TEXT=$(echo "$FORECAST_JSON" | jq -r '
.properties.periods[0].detailedForecast // empty
')

SHORT_FORECAST=$(echo "$FORECAST_JSON" | jq -r '
.properties.periods[0].shortForecast // empty
')

FORECAST_TEXT_LOWER=$(echo "$FORECAST_TEXT $SHORT_FORECAST" | tr '[:upper:]' '[:lower:]')

LIGHTNING_PHRASE="Lightning chance low in the area"
LIGHTNING_PERCENT=5

# --- Highest Priority: Severe Alerts ---
if echo "$ALERTS_JSON" | grep -qiE \
'Severe Thunderstorm Warning|Tornado Warning|Special Marine Warning'; then

  LIGHTNING_PERCENT=95
  LIGHTNING_PHRASE="Severe thunderstorms with dangerous lightning in the area"

# --- Thunderstorms Mentioned In Forecast ---
elif echo "$FORECAST_TEXT_LOWER" | grep -qi "thunderstorm"; then

  RAIN_CHANCE_NUM=$(echo "$RAIN_CHANCE" | sed 's/[^0-9]//g')

  if [[ -z "$RAIN_CHANCE_NUM" ]]; then
    RAIN_CHANCE_NUM=0
  fi

  # Lightning probability estimate
  if (( RAIN_CHANCE_NUM >= 80 )); then
    LIGHTNING_PERCENT=85
    LIGHTNING_PHRASE="Thunderstorms with frequent lightning likely"

  elif (( RAIN_CHANCE_NUM >= 60 )); then
    LIGHTNING_PERCENT=65
    LIGHTNING_PHRASE="Scattered thunderstorms with lightning possible"

  elif (( RAIN_CHANCE_NUM >= 40 )); then
    LIGHTNING_PERCENT=45
    LIGHTNING_PHRASE="Isolated thunderstorms possible"

  elif (( RAIN_CHANCE_NUM >= 20 )); then
    LIGHTNING_PERCENT=25
    LIGHTNING_PHRASE="Slight chance of thunderstorms"

  else
    LIGHTNING_PERCENT=15
    LIGHTNING_PHRASE="Minimal lightning threat"
  fi
fi

LIGHTNING_PERCENT_PHRASE="Chance of lightning ${LIGHTNING_PERCENT} percent"

VERBOSE_LOG "Lightning" "$LIGHTNING_PHRASE"
VERBOSE_LOG "Lightning Percent" "$LIGHTNING_PERCENT_PHRASE"

# ---------------- WIND ----------------
if [[ "$METAR" =~ ([0-9]{3})([0-9]{2})KT ]]; then
  WIND_DIR=${BASH_REMATCH[1]}
  WIND_SPEED=${BASH_REMATCH[2]}
else
  WIND_DIR=0
  WIND_SPEED=0
fi

WIND_DIR_WORD=$(convert_direction "$WIND_DIR")
WIND_MPH=$(math "int(($WIND_SPEED * 1.15078) + 0.5)")

if [ "$WIND_SPEED" -le 2 ]; then
  WIND_PHRASE="Wind calm"
else
  WIND_PHRASE="Wind from the ${WIND_DIR_WORD} at ${WIND_MPH} miles per hour"
fi
VERBOSE_LOG "Wind" "$WIND_PHRASE"

# ---------------- VISIBILITY ----------------
VIS_METERS=$(echo "$OBS_JSON" | jq -r '.properties.visibility.value // 16093')
VIS_MILES=$(math "int(($VIS_METERS / 1609.34) + 0.5)")
VIS_PHRASE="Visibility ${VIS_MILES} miles"
VERBOSE_LOG "Visibility" "$VIS_PHRASE"

# ---------------- TEMP / DEWPOINT ----------------
TEMP_DP=$(echo "$METAR" | grep -oE '[M]?[0-9]{2}/[M]?[0-9]{2}' | head -1)

if [[ "$TEMP_DP" =~ ([M]?[0-9]{2})/([M]?[0-9]{2}) ]]; then
  T_RAW=${BASH_REMATCH[1]}
  DP_RAW=${BASH_REMATCH[2]}
  TEMP_C=$(echo "$T_RAW" | sed 's/M/-/')
  DP_C=$(echo "$DP_RAW" | sed 's/M/-/')
else
  TEMP_C=0
  DP_C=0
fi

TEMP=$(math "int((($TEMP_C * 9 / 5) + 32) + 0.5)")
DP=$(math "int((($DP_C * 9 / 5) + 32) + 0.5)")

HUMIDITY=$(awk -v T="$TEMP_C" -v DP="$DP_C" 'BEGIN{
  RH = 100 * (exp((17.625*DP)/(243.04+DP)) / exp((17.625*T)/(243.04+T)));
  print int(RH+0.5)
}')
VERBOSE_LOG "Humidity" "${HUMIDITY}%"

# ---------------- HEAT INDEX ----------------
HEAT_INDEX=$(awk -v T="$TEMP" -v RH="$HUMIDITY" 'BEGIN{
  if(T >= 75 && RH >= 40){
    HI = -42.379 + 2.04901523*T + 10.14333127*RH \
         - 0.22475541*T*RH - 0.00683783*T*T \
         - 0.05481717*RH*RH + 0.00122874*T*T*RH \
         + 0.00085282*T*RH*RH - 0.00000199*T*T*RH*RH;
    print int(HI+0.5)
  } else { print T }
}')
VERBOSE_LOG "Heat Index" "${HEAT_INDEX}F"

# ---------------- CLOUDS ----------------
# ---------------- CLOUDS (FIXED + SAFE + METAR FALLBACK) ----------------
CLOUD_PHRASE=""

# Try NWS cloud layers first
NWS_CLOUDS=$(echo "$OBS_JSON" | jq -r '
.properties.cloudLayers[]? |
if .amount=="FEW" then " few clouds at, \(.base.value * 3.28084 | floor) feet"
elif .amount=="SCT" then " scattered clouds at, \(.base.value * 3.28084 | floor) feet"
elif .amount=="BKN" then " broken ceiling at, \(.base.value * 3.28084 | floor) feet"
elif .amount=="OVC" then " overcast ceiling at, \(.base.value * 3.28084 | floor) feet"
else empty end
' 2>/dev/null | paste -sd ", " -)

if [[ -n "$NWS_CLOUDS" ]]; then
  CLOUD_PHRASE="$NWS_CLOUDS"
else
  # METAR fallback (safe parse)
  SKY_CODE=$(echo "$METAR" | grep -oE 'SKC|CLR|FEW[0-9]{3}|SCT[0-9]{3}|BKN[0-9]{3}|OVC[0-9]{3}' | head -1 || true)

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
# ---------------- TIME ----------------
TIME=$(date +"%H%M")
TIME_SPOKEN=$(speak_aviation_time "$TIME")
ATIS="${STATION_NAME[$STATION]} Weather Update.
Time ${TIME_SPOKEN} local.
${WIND_PHRASE}.
${VIS_PHRASE}.
Sky conditions ${CLOUD_PHRASE}.
Temperature ${TEMP} degrees. Dewpoint ${DP} degrees.
Humidity ${HUMIDITY} percent.
Heat index ${HEAT_INDEX} degrees.
${ALERT_PHRASE}.
${LIGHTNING_PHRASE}.
${LIGHTNING_PERCENT_PHRASE}.
${FORECAST_PHRASE}.
${RAIN_PHRASE}.
End transmission. Kilo Delta Four Kilo."

ATIS_FORMATTED=$(capitalize_sentences "$ATIS")


echo ""
echo "KD4K WEATHER STATION"
echo "=============================="
echo "$ATIS_FORMATTED"
echo "=============================="
echo ""

# --------------------------------------------------
# WRITE TO DASHBOARD ATIS FILE
# --------------------------------------------------

DASHBOARD_DIR="$HOME/radar_dashboard"
mkdir -p "$DASHBOARD_DIR"

cat > "$DASHBOARD_DIR/atis.txt" <<EOF
KD4K WEATHER STATION
==============================

$ATIS_FORMATTED

==============================

Last Updated: $(date)
EOF

SAVE_VERBOSE

cat > "$DASHBOARD_DIR/weather.html" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta http-equiv="refresh" content="30">
<title>KD4K Weather Station</title>

<style>
body {
    background: black;
    color: #00ff00;
    font-family: monospace;
    padding: 20px;
    white-space: pre-wrap;
}
</style>
</head>

<body>
<pre>
$(cat "$DASHBOARD_DIR/atis.txt")
</pre>
</body>
</html>
EOF

pico2wave -w "$RAW_AUDIO" "$ATIS_FORMATTED"
sox "$RAW_AUDIO" "$TEMP_OUTPUT" gain -n -6 pad 0.35 0.35 highpass 70 lowpass 6500 pitch -100 tempo 0.94
mv "$TEMP_OUTPUT" "$OUTPUT_FINAL"
}

# ---------------- MAIN LOOP ----------------
while true; do
  generate_atis HYW
  cvlc --play-and-exit --quiet "$OUTPUT_FINAL" >/dev/null 2>&1

  for i in 1 2 3 4 5; do
    cvlc --play-and-exit --quiet "$BEEP_FILE" >/dev/null 2>&1
    sleep 1
  done

  generate_atis MYR
  cvlc --play-and-exit --quiet "$OUTPUT_FINAL" >/dev/null 2>&1

  for i in 1 2 3 4 5; do
    cvlc --play-and-exit --quiet "$BEEP_FILE" >/dev/null 2>&1
    sleep 1
  done

done
