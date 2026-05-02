#!/bin/bash

OUTPUT_RAW="/tmp/atis_raw.wav"
OUTPUT_FINAL="atis.wav"

METAR_URL=https://tgftp.nws.noaa.gov/data/observations/metar/stations/KMYR.TXT
ALERT_URL=https://api.weather.gov/alerts/active?point=33.68,-78.89

# -------------------------
# DIGIT SPEECH (ONLY TIME + ALT)
# -------------------------
say_digits() {
  echo "$1" | sed 's/./& /g'
}

# -------------------------
# NORMAL NUMBER SPEECH (ALL OTHER VALUES)
# -------------------------
say_number() {
  echo "$1"
}

# -------------------------
# CAPITALIZE
# -------------------------
capitalize_sentences() {
  echo "$1" | sed -E 's/(^|\. )([a-z])/\1\U\2/g'
}

# -------------------------
# SAFE DECIMAL
# -------------------------
to_dec() {
  echo $((10#$1))
}

# -------------------------
# WIND CONVERSION (MPH)
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
# VISIBILITY
# -------------------------
decode_visibility() {
  VIS="$1"
  case "$VIS" in
    P6SM) echo "visibility greater than six miles" ;;
    M1/4SM) echo "visibility less than one quarter mile" ;;
    1/4SM) echo "visibility one quarter mile" ;;
    1/2SM) echo "visibility one half mile" ;;
    3/4SM) echo "visibility three quarters mile" ;;
    *SM)
      NUM=$(echo "$VIS" | tr -d 'SM')
      echo "visibility ${NUM} miles"
      ;;
    *) echo "visibility not available" ;;
  esac
}

# -------------------------
# CLOUDS
# -------------------------
decode_clouds() {
  CLOUDS=$(echo "$1" | grep -oE '(FEW|SCT|BKN|OVC|VV)[0-9]{3}' | head -n3)
  RESULT=""

  for c in $CLOUDS; do
    TYPE=${c:0:3}
    HEIGHT_RAW=${c:3:3}
    HEIGHT=$(to_dec "$HEIGHT_RAW")
    FEET=$((HEIGHT * 100))

    case "$TYPE" in
      FEW) DESC="few clouds at" ;;
      SCT) DESC="scattered clouds at" ;;
      BKN) DESC="broken ceiling at" ;;
      OVC) DESC="overcast ceiling at" ;;
      VV) DESC="vertical visibility at" ;;
    esac

    RESULT="$RESULT ${DESC} $(say_number "$FEET") feet,"
  done

  RESULT=$(echo "$RESULT" | sed 's/^ //')
  RESULT=$(echo "$RESULT" | sed 's/,$//')

  [ -z "$RESULT" ] && RESULT="clear skies"

  echo "$RESULT"
}

# -------------------------
# FETCH METAR
# -------------------------
METAR=$(curl -s "$METAR_URL" | tail -n 1)

# -------------------------
# ALERTS
# -------------------------
ALERTS=$(curl -s "$ALERT_URL")
LIGHTNING_PHRASE="no significant weather hazards"
echo "$ALERTS" | grep -qi "thunderstorm" && LIGHTNING_PHRASE="thunderstorm activity in the area"
echo "$ALERTS" | grep -qi "lightning" && LIGHTNING_PHRASE="lightning detected in the vicinity"
echo "$ALERTS" | grep -qi "severe" && LIGHTNING_PHRASE="severe weather warning in effect"

# -------------------------
# WIND (MPH + FAA STYLE)
# -------------------------
WIND_BLOCK=$(echo "$METAR" | grep -oE '[0-9]{5,6}(G[0-9]{2})?KT' | head -n1)

WIND_DIR=${WIND_BLOCK:0:3}
WIND_DIR_NUM=$((10#$WIND_DIR))

WIND_SPEED=$((10#${WIND_BLOCK:3:2}))
WIND_MPH=$(( (WIND_SPEED * 115) / 100 ))

if echo "$WIND_BLOCK" | grep -q "G"; then
  WIND_GUST=$(echo "$WIND_BLOCK" | grep -oE 'G[0-9]{2}' | tr -d 'G')
  WIND_GUST=$((10#$WIND_GUST))
  GUST_MPH=$(( (WIND_GUST * 115) / 100 ))
fi

WIND_DIR_WORD=$(convert_direction "$WIND_DIR_NUM")

if [ "$WIND_SPEED" -le 2 ]; then
  WIND_PHRASE="wind calm"
else
  if [ -n "$WIND_GUST" ]; then
    WIND_PHRASE="wind from the ${WIND_DIR_WORD} at ${WIND_MPH} miles per hour gusting to ${GUST_MPH} miles per hour"
  else
    WIND_PHRASE="wind from the ${WIND_DIR_WORD} at ${WIND_MPH} miles per hour"
  fi
fi

# -------------------------
# VISIBILITY
# -------------------------
VIS_RAW=$(echo "$METAR" | grep -oE 'P?M?[0-9/]+SM' | head -n1)
VIS_PHRASE=$(decode_visibility "$VIS_RAW")

# -------------------------
# TEMP / DEWPOINT
# -------------------------
TEMP_DP=$(echo "$METAR" | grep -oE ' M?[0-9]{1,2}/M?[0-9]{1,2}')
TEMP_C=$(echo "$TEMP_DP" | cut -d/ -f1 | tr -d 'M')
DP_C=$(echo "$TEMP_DP" | cut -d/ -f2 | tr -d 'M')

TEMP=$(( (TEMP_C * 9 / 5) + 32 ))
DP=$(( (DP_C * 9 / 5) + 32 ))

# -------------------------
# HUMIDITY
# -------------------------
HUMIDITY=$(awk -v T="$TEMP" -v DP="$DP" 'BEGIN{
  RH = 100 * (exp((17.625*DP)/(243.04+DP)) / exp((17.625*T)/(243.04+T)));
  print int(RH+0.5)
}')
HUMIDITY_PHRASE="Humidity $(say_number "$HUMIDITY") percent."

# -------------------------
# HEAT INDEX
# -------------------------
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
HEAT_INDEX_PHRASE="Heat index $(say_number "$HEAT_INDEX") degrees Fahrenheit."

# -------------------------
# CLOUDS
# -------------------------
CLOUD_PHRASE=$(decode_clouds "$METAR")

# -------------------------
# ALT (DIGIT SPEECH ONLY)
# -------------------------
ALT=$(echo "$METAR" | grep -oE 'A[0-9]{4}' | tr -d 'A')
ALT_SPOKEN=$(say_digits "$ALT")

# -------------------------
# TIME (DIGIT SPEECH ONLY)
# -------------------------
TIME=$(date +"%H%M")
TIME_SPOKEN=$(say_digits "$TIME")

# -------------------------
# PRESSURE TREND
# -------------------------
ALT_FILE="/tmp/altimeter_history.txt"
if [ -f "$ALT_FILE" ]; then
  read -r ALT1 ALT2 ALT3 < "$ALT_FILE"
else
  ALT1=$ALT
  ALT2=$ALT
  ALT3=$ALT
fi

ALT3="$ALT2"
ALT2="$ALT1"
ALT1="$ALT"

echo "$ALT1 $ALT2 $ALT3" > "$ALT_FILE"

DELTA1=$((ALT1 - ALT2))
DELTA2=$((ALT2 - ALT3))
AVG_DELTA=$(( (DELTA1 + DELTA2) / 2 ))

TREND="steady"
if [ "$AVG_DELTA" -gt 2 ]; then TREND="rising"; fi
if [ "$AVG_DELTA" -lt -2 ]; then TREND="falling"; fi
if [ "$AVG_DELTA" -gt 5 ]; then TREND="rapidly rising"; fi
if [ "$AVG_DELTA" -lt -5 ]; then TREND="rapidly falling"; fi

TREND_PHRASE="Pressure trend ${TREND}."

# -------------------------
# FINAL ATIS
# -------------------------
ATIS="Myrtle Beach International Airport information. 
Time ${TIME_SPOKEN} local. 
${WIND_PHRASE}. 
${VIS_PHRASE}. 
Sky conditions ${CLOUD_PHRASE}. 
Temperature $(say_number "$TEMP") degrees Fahrenheit. Dewpoint $(say_number "$DP") degrees Fahrenheit. 
${HUMIDITY_PHRASE} ${HEAT_INDEX_PHRASE} 
Altimeter ${ALT_SPOKEN}. 
${TREND_PHRASE} 
${LIGHTNING_PHRASE}."

ATIS_FORMATTED=$(capitalize_sentences "$ATIS")
echo "$ATIS_FORMATTED"

# -------------------------
# TTS
# -------------------------
pico2wave -w "$OUTPUT_RAW" "$ATIS_FORMATTED"

# -------------------------
# SOX CLEAN AUDIO
# -------------------------
sox "$OUTPUT_RAW" "$OUTPUT_FINAL" \
  gain -n -6 \
  pad 0.35 0.35 \
  highpass 70 \
  lowpass 6500 \
  tempo 0.98

aplay "$OUTPUT_FINAL"
