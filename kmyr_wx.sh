#!/bin/bash

set -euo pipefail

OUTPUT_FINAL="/tmp/atis.wav"
TEMP_OUTPUT="/tmp/atis_new.wav"
RAW_AUDIO="/tmp/atis_raw.wav"
BEEP_FILE="/tmp/atis_beep.wav"

OBS_URL="https://api.weather.gov/stations/KMYR/observations/latest"
ALERT_URL="https://api.weather.gov/alerts/active?point=33.68,-78.89"
METAR_URL="https://tgftp.nws.noaa.gov/data/observations/metar/stations/KMYR.TXT"
FORECAST_URL="https://wttr.in/MYR?format=%t+↑%w+%p"

# -------------------------
# DEPENDENCIES
# -------------------------
for cmd in jq awk sox pico2wave cvlc curl aplay; do
  command -v "$cmd" >/dev/null || { echo "$cmd not installed"; exit 1; }
done

trap "echo 'Stopping ATIS'; kill 0; exit 0" SIGINT

math() { awk "BEGIN { print $* }"; }

# -------------------------
# VERBOSE STATE
# -------------------------
VERBOSE_FILE="/tmp/atis_verbose_state.txt"

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

    echo "$msg"
    echo "$msg" >> "$VERBOSE_HISTORY_FILE"

    VERBOSE_PREV["$name"]="$value"
}

# -------------------------
# CLEANUP
# -------------------------
cleanup_logs() {
  find "$VERBOSE_LOG_DIR" -name "atis_verbose_*.log" -type f -mtime +10 -delete 2>/dev/null
}

SAVE_VERBOSE() {
    : > "$VERBOSE_FILE"
    for k in "${!VERBOSE_PREV[@]}"; do
        echo "$k=${VERBOSE_PREV[$k]}" >> "$VERBOSE_FILE"
    done
}

say_digits() { echo "$1" | sed 's/./& /g'; }

# -------------------------
# AVIATION TIME SPEAKING
# -------------------------
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

  echo "$(digit_word "$h1") \
$(digit_word "$h2") \
$(digit_word "$m1") \
$(digit_word "$m2")"
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

# -------------------------
# CREATE BEEP FILE
# -------------------------
if [ ! -f "$BEEP_FILE" ]; then
  sox -n -r 44100 -c 1 "$BEEP_FILE" synth 0.15 sine 1000 vol 0.08
fi

# -------------------------
# ATIS GENERATOR
# -------------------------
generate_atis() {

OBS_JSON=$(curl -s --max-time 10 "$OBS_URL")
ALERTS_JSON=$(curl -s --max-time 10 "$ALERT_URL")
METAR=$(curl -s --max-time 10 "$METAR_URL" | tail -1)
FORECAST_RAW=$(curl -s --max-time 10 "$FORECAST_URL")

EVENTS=$(echo "$ALERTS_JSON" | jq -r '.features[].properties.event? // empty' | sort -u)
ALERT_PHRASE="No advisories"

if [ -n "$EVENTS" ]; then
  ALERT_PHRASE=""
  while read -r event; do
    ALERT_PHRASE+=" $event in effect."
  done <<< "$EVENTS"
fi

VERBOSE_LOG "Alerts" "$ALERT_PHRASE"

LIGHTNING_PHRASE="Lightning chance low in the area"

if echo "$ALERTS_JSON" | grep -qi "severe"; then
  LIGHTNING_PHRASE="Severe weather warning in effect"
elif echo "$ALERTS_JSON" | grep -qi "thunderstorm"; then
  LIGHTNING_PHRASE="Thunderstorms with lightning likely"
elif echo "$ALERTS_JSON" | grep -qi "lightning"; then
  LIGHTNING_PHRASE="Lightning detected in the vicinity"
fi

VERBOSE_LOG "Lightning" "$LIGHTNING_PHRASE"

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

VIS_METERS=$(echo "$OBS_JSON" | jq -r '.properties.visibility.value // 16093')
VIS_MILES=$(math "int(($VIS_METERS / 1609.34) + 0.5)")
VIS_PHRASE="Visibility ${VIS_MILES} miles"

VERBOSE_LOG "Visibility" "$VIS_PHRASE"

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

VERBOSE_LOG "Temperature" "${TEMP}F / Dewpoint ${DP}F"

HUMIDITY=$(awk -v T="$TEMP_C" -v DP="$DP_C" 'BEGIN{
  RH = 100 * (exp((17.625*DP)/(243.04+DP)) / exp((17.625*T)/(243.04+T)));
  print int(RH+0.5)
}')

VERBOSE_LOG "Humidity" "${HUMIDITY}%"

HEAT_INDEX=$(awk -v T="$TEMP" -v RH="$HUMIDITY" 'BEGIN{
  if(T >= 80 && RH >= 40){
    HI = -42.379 + 2.04901523*T + 10.14333127*RH \
         - 0.22475541*T*RH - 0.00683783*T*T \
         - 0.05481717*RH*RH + 0.00122874*T*T*RH \
         + 0.00085282*T*RH*RH - 0.00000199*T*T*RH*RH;
    print int(HI+0.5)
  } else {
    print T
  }
}')

VERBOSE_LOG "Heat Index" "${HEAT_INDEX}F"

CLOUD_PHRASE=$(echo "$OBS_JSON" | jq -r '
.properties.cloudLayers[]? |
if .amount=="FEW" then "few clouds at \(.base.value * 3.28084 | floor) feet"
elif .amount=="SCT" then "scattered clouds at \(.base.value * 3.28084 | floor) feet"
elif .amount=="BKN" then "broken ceiling at \(.base.value * 3.28084 | floor) feet"
elif .amount=="OVC" then "overcast ceiling at \(.base.value * 3.28084 | floor) feet"
else empty end
' | paste -sd ", " -)

[ -z "$CLOUD_PHRASE" ] && CLOUD_PHRASE="clear skies"

VERBOSE_LOG "Clouds" "$CLOUD_PHRASE"

ALT=$(echo "$METAR" | grep -oE 'A[0-9]{4}' | tr -d 'A')
ALT_SPOKEN=$(say_digits "$ALT")

ALT_FILE="/tmp/atis_alt.txt"
ALT_TREND="steady"

if [ -f "$ALT_FILE" ]; then
  PREV=$(cat "$ALT_FILE")
  if (( ALT > PREV )); then
    ALT_TREND="rising"
  elif (( ALT < PREV )); then
    ALT_TREND="falling"
  fi
fi

echo "$ALT" > "$ALT_FILE"

ALT_PHRASE="Altimeter ${ALT_SPOKEN}, ${ALT_TREND}"

VERBOSE_LOG "Altimeter" "$ALT_PHRASE"

TEMP_F=$(echo "$FORECAST_RAW" | grep -oE '[0-9]+°F' | head -1 | tr -d '°F')
WIND_F=$(echo "$FORECAST_RAW" | grep -oE '[0-9]+mph' | head -1 | tr -d 'mph')
RAIN_F=$(echo "$FORECAST_RAW" | grep -oE '[0-9.]+in' | head -1 | tr -d 'in')

FORECAST_PHRASE="Two hour forecast temperature ${TEMP_F} degrees, wind ${WIND_F} miles per hour, rain chance ${RAIN_F} inches"

VERBOSE_LOG "Forecast" "$FORECAST_PHRASE"

TIME=$(date +"%H%M")
TIME_SPOKEN=$(speak_aviation_time "$TIME")

ATIS="Kilo Delta Four Kilo Weather Update.
Time ${TIME_SPOKEN} local.
${WIND_PHRASE}.
${VIS_PHRASE}.
Sky conditions ${CLOUD_PHRASE}.
Temperature ${TEMP} degrees. Dewpoint ${DP} degrees.
Humidity ${HUMIDITY} percent.
Heat index ${HEAT_INDEX} degrees.
${ALT_PHRASE}.
${ALERT_PHRASE}.
${LIGHTNING_PHRASE}.
${FORECAST_PHRASE}.
End transmission"

ATIS_FORMATTED=$(capitalize_sentences "$ATIS")

echo "$ATIS_FORMATTED"

SAVE_VERBOSE

pico2wave -w "$RAW_AUDIO" "$ATIS_FORMATTED"
sox "$RAW_AUDIO" "$TEMP_OUTPUT" gain -n -6 pad 0.35 0.35 highpass 70 lowpass 6500 tempo 0.98
mv "$TEMP_OUTPUT" "$OUTPUT_FINAL"
}

# -------------------------
# RUN LOOP
# -------------------------
while true; do

  generate_atis

  cleanup_logs

  if [ -f "$OUTPUT_FINAL" ]; then
    cvlc --play-and-exit --quiet "$OUTPUT_FINAL" >/dev/null 2>&1
  fi

  for i in 1 2 3 4 5; do
    cvlc --play-and-exit --quiet "$BEEP_FILE" >/dev/null 2>&1
    sleep 1
  done

done
