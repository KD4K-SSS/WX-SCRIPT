#!/bin/bash

OUTPUT_RAW="/tmp/atis_raw.wav"
OUTPUT_FINAL="/tmp/atis.wav"

OBS_URL="https://api.weather.gov/stations/KMYR/observations/latest"
ALERT_URL="https://api.weather.gov/alerts/active?point=33.68,-78.89"
METAR_URL="https://tgftp.nws.noaa.gov/data/observations/metar/stations/KMYR.TXT"

# -------------------------
# ATIS LETTER SYSTEM (FIXED)
# -------------------------
ATIS_STATE_FILE="/tmp/atis_state.txt"
TODAY=$(date +"%Y-%m-%d")

LETTERS=(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z)

# Load state
if [ -f "$ATIS_STATE_FILE" ]; then
  source "$ATIS_STATE_FILE"
else
  INDEX=0
  LAST_DATE="$TODAY"
fi

# Reset daily
if [ "$LAST_DATE" != "$TODAY" ]; then
  INDEX=0
  LAST_DATE="$TODAY"
fi

# Ensure INDEX exists
INDEX=${INDEX:-0}

# Cycle index safely
INDEX=$(( (INDEX + 1) % 26 ))
ATIS_LETTER=${LETTERS[$INDEX]}

# Save state
echo "INDEX=$INDEX" > "$ATIS_STATE_FILE"
echo "LAST_DATE=$LAST_DATE" >> "$ATIS_STATE_FILE"

# Convert to spoken ICAO name
case "$ATIS_LETTER" in
  A) ATIS_NAME="Information Alpha" ;;
  B) ATIS_NAME="Information Bravo" ;;
  C) ATIS_NAME="Information Charlie" ;;
  D) ATIS_NAME="Information Delta" ;;
  E) ATIS_NAME="Information Echo" ;;
  F) ATIS_NAME="Information Foxtrot" ;;
  G) ATIS_NAME="Information Golf" ;;
  H) ATIS_NAME="Information Hotel" ;;
  I) ATIS_NAME="Information India" ;;
  J) ATIS_NAME="Information Juliet" ;;
  K) ATIS_NAME="Information Kilo" ;;
  L) ATIS_NAME="Information Lima" ;;
  M) ATIS_NAME="Information Mike" ;;
  N) ATIS_NAME="Information November" ;;
  O) ATIS_NAME="Information Oscar" ;;
  P) ATIS_NAME="Information Papa" ;;
  Q) ATIS_NAME="Information Quebec" ;;
  R) ATIS_NAME="Information Romeo" ;;
  S) ATIS_NAME="Information Sierra" ;;
  T) ATIS_NAME="Information Tango" ;;
  U) ATIS_NAME="Information Uniform" ;;
  V) ATIS_NAME="Information Victor" ;;
  W) ATIS_NAME="Information Whiskey" ;;
  X) ATIS_NAME="Information X-ray" ;;
  Y) ATIS_NAME="Information Yankee" ;;
  Z) ATIS_NAME="Information Zulu" ;;
esac

# -------------------------
# HELPERS
# -------------------------
say_digits() { echo "$1" | sed 's/./& /g'; }
say_number() { echo "$1"; }
capitalize_sentences() { echo "$1" | sed -E 's/(^|\. )([a-z])/\1\U\2/g'; }

convert_direction() {
  DEG=$1
  if [ "$DEG" -ge 338 ] || [ "$DEG" -lt 23 ]; then echo "north"
  elif [ "$DEG" -lt 68 ]; then echo "northeast"
  elif [ "$DEG" -lt 113 ]; then echo "east"
  elif [ "$DEG" -lt 158 ]; then echo "southeast"
  elif [ "$DEG" -lt 203 ]; then echo "south"
  elif [ "$DEG" -lt 248 ]; then echo "southwest"
  elif [ "$DEG" -lt 293 ]; then echo "west"
  else echo "northwest"
  fi
}

# -------------------------
# FETCH DATA
# -------------------------
OBS_JSON=$(curl -s "$OBS_URL")
ALERTS_JSON=$(curl -s "$ALERT_URL")
METAR=$(curl -s "$METAR_URL" | tail -1)

# -------------------------
# ALERTS
# -------------------------
EVENTS=$(echo "$ALERTS_JSON" | jq -r '.features[].properties.event' | sort -u)

ALERT_PHRASE="No advisories"
LIGHTNING_PHRASE="Lightning chance low in the area"

if [ -n "$EVENTS" ]; then
  ALERT_PHRASE=""
  while read -r event; do
    ALERT_PHRASE="${ALERT_PHRASE} ${event} in effect."
  done <<< "$EVENTS"
fi

echo "$ALERTS_JSON" | grep -qi "lightning" && LIGHTNING_PHRASE="Lightning detected in the vicinity"
echo "$ALERTS_JSON" | grep -qi "thunderstorm" && LIGHTNING_PHRASE="Thunderstorms with lightning likely"
echo "$ALERTS_JSON" | grep -qi "severe" && LIGHTNING_PHRASE="Severe weather warning in effect"

# -------------------------
# WIND
# -------------------------
if [[ "$METAR" =~ ([0-9]{3})([0-9]{2})KT ]]; then
  WIND_DIR=${BASH_REMATCH[1]}
  WIND_SPEED=${BASH_REMATCH[2]}
else
  WIND_DIR=0
  WIND_SPEED=0
fi

WIND_DIR_WORD=$(convert_direction "$WIND_DIR")

if [ "$WIND_SPEED" -le 2 ]; then
  WIND_PHRASE="Wind calm"
else
  WIND_PHRASE="Wind from the ${WIND_DIR_WORD} at ${WIND_SPEED} miles per hour"
fi

# -------------------------
# VISIBILITY
# -------------------------
VIS_METERS=$(echo "$OBS_JSON" | jq '.properties.visibility.value // 16093')
VIS_MILES=$(echo "$VIS_METERS / 1609.34" | bc -l)
VIS_MILES=$(printf "%.0f" "$VIS_MILES")
VIS_PHRASE="Visibility ${VIS_MILES} miles"

# -------------------------
# TEMP / DEWPOINT
# -------------------------
TEMP_C=$(echo "$OBS_JSON" | jq '.properties.temperature.value // 0')
DP_C=$(echo "$OBS_JSON" | jq '.properties.dewpoint.value // 0')

TEMP=$(( $(printf "%.0f" "$TEMP_C") * 9 / 5 + 32 ))
DP=$(( $(printf "%.0f" "$DP_C") * 9 / 5 + 32 ))

# -------------------------
# HUMIDITY / HEAT INDEX
# -------------------------
HUMIDITY=$(awk -v T="$TEMP" -v DP="$DP" 'BEGIN{
  RH = 100 * (exp((17.625*DP)/(243.04+DP)) / exp((17.625*T)/(243.04+T)));
  print int(RH+0.5)
}')

HEAT_INDEX=$(awk -v T="$TEMP" -v RH="$HUMIDITY" 'BEGIN{
  if(T >= 80 && RH >= 40){
    HI = -42.379 + 2.04901523*T + 10.14333127*RH \
         - 0.22475541*T*RH - 0.00683783*T*T \
         - 0.05481717*RH*RH + 0.00122874*T*T*RH \
         + 0.00085282*T*RH*RH - 0.00000199*T*T*RH*RH;
    print int(HI+0.5)
  } else { print T }
}')

# -------------------------
# CLOUDS
# -------------------------
CLOUD_PHRASE=$(echo "$OBS_JSON" | jq -r '
.properties.cloudLayers[]? |
if .amount=="FEW" then "few clouds at \(.base.value * 3.28084 | floor) feet"
elif .amount=="SCT" then "scattered clouds at \(.base.value * 3.28084 | floor) feet"
elif .amount=="BKN" then "broken ceiling at \(.base.value * 3.28084 | floor) feet"
elif .amount=="OVC" then "overcast ceiling at \(.base.value * 3.28084 | floor) feet"
else empty end
' | paste -sd ", " -)

[ -z "$CLOUD_PHRASE" ] && CLOUD_PHRASE="clear skies"

# -------------------------
# ALT + TREND
# -------------------------
ALT=$(echo "$METAR" | grep -oE 'A[0-9]{4}' | tr -d 'A')
ALT_SPOKEN=$(say_digits "$ALT")

ALT_FILE="/tmp/alt_history.txt"
read -r A1 A2 A3 < "$ALT_FILE" 2>/dev/null

A3=$A2
A2=$A1
A1=$ALT
echo "$A1 $A2 $A3" > "$ALT_FILE"

DELTA=$(( (A1 - A2 + A2 - A3) / 2 ))

TREND="steady"
[ "$DELTA" -gt 2 ] && TREND="rising"
[ "$DELTA" -lt -2 ] && TREND="falling"

TREND_PHRASE="Pressure trend ${TREND}"

# -------------------------
# TIME
# -------------------------
TIME=$(date +"%H%M")
TIME_SPOKEN=$(say_digits "$TIME")

# -------------------------
# FINAL ATIS
# -------------------------
ATIS="Myrtle Beach International Airport ${ATIS_NAME} weather information.
Time ${TIME_SPOKEN} eastern.
${WIND_PHRASE}.
${VIS_PHRASE}.
Sky conditions ${CLOUD_PHRASE}.
Temperature ${TEMP} degrees Fahrenheit. Dewpoint ${DP} degrees Fahrenheit.
Humidity ${HUMIDITY} percent. Heat index ${HEAT_INDEX} degrees Fahrenheit.
Altimeter ${ALT_SPOKEN}.
${TREND_PHRASE}.
${ALERT_PHRASE}.
${LIGHTNING_PHRASE}."

ATIS_FORMATTED=$(capitalize_sentences "$ATIS")
echo "$ATIS_FORMATTED"

# -------------------------
# AUDIO OUTPUT
# -------------------------
pico2wave -w "$OUTPUT_RAW" "$ATIS_FORMATTED"

sox "$OUTPUT_RAW" "$OUTPUT_FINAL" \
  gain -n -6 pad 0.35 0.35 highpass 70 lowpass 6500 tempo 0.98

aplay "$OUTPUT_FINAL"
