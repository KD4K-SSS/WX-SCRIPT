#!/bin/bash

OUTPUT_RAW="/tmp/atis_raw.wav"
OUTPUT_FINAL="atis.wav"

OBS_URL="https://api.weather.gov/stations/KMYR/observations/latest"
ALERT_URL="https://api.weather.gov/alerts/active?point=33.68,-78.89"
METAR_URL="https://tgftp.nws.noaa.gov/data/observations/metar/stations/KMYR.TXT"

# -------------------------
# DIGIT SPEECH
# -------------------------
say_digits() { echo "$1" | sed 's/./& /g'; }
say_number() { echo "$1"; }
capitalize_sentences() { echo "$1" | sed -E 's/(^|\. )([a-z])/\1\U\2/g'; }

# -------------------------
# WIND DIRECTION
# -------------------------
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
if [ -n "$EVENTS" ]; then
  ALERT_PHRASE=""
  while read -r event; do
    case "$event" in
      *Thunderstorm*) ALERT_PHRASE="${ALERT_PHRASE} Thunderstorm warning in effect." ;;
      *Tornado*) ALERT_PHRASE="${ALERT_PHRASE} Tornado warning in effect." ;;
      *Flood*) ALERT_PHRASE="${ALERT_PHRASE} Flood warning in effect." ;;
      *Wind*) ALERT_PHRASE="${ALERT_PHRASE} Wind advisory in effect." ;;
      *Fog*) ALERT_PHRASE="${ALERT_PHRASE} Fog advisory in effect." ;;
      *Heat*) ALERT_PHRASE="${ALERT_PHRASE} Heat advisory in effect." ;;
      *) ALERT_PHRASE="${ALERT_PHRASE} ${event,,} in effect." ;;
    esac
  done <<< "$EVENTS"
fi

# -------------------------
# LIGHTNING PHRASE
# -------------------------
LIGHTNING_PHRASE="Lightning chance low in the area"
echo "$EVENTS" | grep -qi "Thunderstorm" && LIGHTNING_PHRASE="Thunderstorms with lightning likely"
echo "$ALERTS_JSON" | grep -qi "lightning" && LIGHTNING_PHRASE="Lightning detected in the vicinity"
echo "$ALERTS_JSON" | grep -qi "severe" && LIGHTNING_PHRASE="Severe weather warning in effect, lightning probable"

# -------------------------
# WIND FROM METAR
# -------------------------
if [[ "$METAR" =~ ([0-9]{3})([0-9]{2})G?([0-9]{2})?KT ]]; then
    WIND_DIR_NUM=${BASH_REMATCH[1]}
    WIND_SPEED=${BASH_REMATCH[2]}
    WIND_GUST=${BASH_REMATCH[3]:-0}
else
    WIND_DIR_NUM=0
    WIND_SPEED=0
    WIND_GUST=0
fi

WIND_DIR_WORD=$(convert_direction "$WIND_DIR_NUM")
if [ "$WIND_SPEED" -le 2 ]; then
    WIND_PHRASE="Wind calm"
else
    if [ "$WIND_GUST" -gt 0 ]; then
        WIND_PHRASE="Wind from the ${WIND_DIR_WORD} at ${WIND_SPEED} miles per hour gusting to ${WIND_GUST} miles per hour"
    else
        WIND_PHRASE="Wind from the ${WIND_DIR_WORD} at ${WIND_SPEED} miles per hour"
    fi
fi

# -------------------------
# VISIBILITY
# -------------------------
if [[ "$METAR" =~ ([0-9]{4})\s?SM ]]; then
    VIS_MILES=${BASH_REMATCH[1]}
else
    VIS_METERS=$(echo "$OBS_JSON" | jq '.properties.visibility.value // 0')
    VIS_MILES=$(echo "$VIS_METERS / 1609.34" | bc -l)
    VIS_MILES=$(printf "%.0f" "$VIS_MILES")
fi

if [ "$VIS_MILES" -ge 10 ]; then
    VIS_PHRASE="Visibility greater than ten miles"
else
    VIS_PHRASE="Visibility ${VIS_MILES} miles"
fi

# -------------------------
# TEMP / DEWPOINT
# -------------------------
TEMP_C=$(echo "$OBS_JSON" | jq '.properties.temperature.value // 0')
DP_C=$(echo "$OBS_JSON" | jq '.properties.dewpoint.value // 0')
TEMP=$(( ($(printf "%.0f" "$TEMP_C") * 9 / 5) + 32 ))
DP=$(( ($(printf "%.0f" "$DP_C") * 9 / 5) + 32 ))

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
# ALTIMETER & PRESSURE TREND
# -------------------------
# Try JSON
ALT_PASCAL=$(echo "$OBS_JSON" | jq '.properties.barometricPressure.value // empty')
if [[ -n "$ALT_PASCAL" && "$ALT_PASCAL" != "null" && "$ALT_PASCAL" != "0" ]]; then
    ALT_INHG=$(echo "$ALT_PASCAL * 0.0002953" | bc -l)
elif [[ "$METAR" =~ A([0-9]{4}) ]]; then
    ALT_INHG=$(echo "${BASH_REMATCH[1]:0:2}.${BASH_REMATCH[1]:2:2}")
else
    ALT_INHG=29.92
fi

ALT=$(printf "%.2f" "$ALT_INHG")
ALT_SPOKEN=$(say_digits "$(printf "%.0f" "$(echo "$ALT*100" | bc -l)")")

ALT_FILE="/tmp/altimeter_history.txt"
if [ -f "$ALT_FILE" ]; then
    read -r ALT1 ALT2 ALT3 < "$ALT_FILE"
else
    ALT1=$ALT2=$ALT3=$ALT
fi
ALT3="$ALT2"; ALT2="$ALT1"; ALT1="$ALT"
echo "$ALT1 $ALT2 $ALT3" > "$ALT_FILE"

DELTA1=$(echo "$ALT1 - $ALT2" | bc)
DELTA2=$(echo "$ALT2 - $ALT3" | bc)
AVG_DELTA=$(echo "($DELTA1 + $DELTA2)/2" | bc)

TREND="steady"
(( $(echo "$AVG_DELTA > 2" | bc -l) )) && TREND="rising"
(( $(echo "$AVG_DELTA < -2" | bc -l) )) && TREND="falling"
TREND_PHRASE="Pressure trend ${TREND}"

# -------------------------
# TIME
# -------------------------
TIME=$(date +"%H%M")
TIME_SPOKEN=$(say_digits "$TIME")

# -------------------------
# FINAL ATIS
# -------------------------
ATIS="Kilp Delta Four Kilo weather information. 
Time ${TIME_SPOKEN} eastern. 
${WIND_PHRASE}. 
${VIS_PHRASE}. 
Sky conditions ${CLOUD_PHRASE}. 
Temperature $(say_number "$TEMP") degrees Fahrenheit. Dewpoint $(say_number "$DP") degrees Fahrenheit. 
Humidity $(say_number "$HUMIDITY") percent. Heat index $(say_number "$HEAT_INDEX") degrees Fahrenheit. 
Altimeter ${ALT_SPOKEN}. 
${TREND_PHRASE}. 
${ALERT_PHRASE} in effect. 
${LIGHTNING_PHRASE}."

ATIS_FORMATTED=$(capitalize_sentences "$ATIS")
echo "$ATIS_FORMATTED"

# -------------------------
# TTS + AUDIO
# -------------------------
pico2wave -w "$OUTPUT_RAW" "$ATIS_FORMATTED"
sox "$OUTPUT_RAW" "$OUTPUT_FINAL" gain -n -6 pad 0.35 0.35 highpass 70 lowpass 6500 tempo 0.98
aplay "$OUTPUT_FINAL"
