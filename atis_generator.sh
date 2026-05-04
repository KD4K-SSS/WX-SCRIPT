#!/bin/bash

OUTPUT_RAW="/tmp/atis_raw.wav"
OUTPUT_FINAL="/tmp/atis.wav"

METAR_URL="https://tgftp.nws.noaa.gov/data/observations/metar/stations/KMYR.TXT"
ALERT_URL="https://api.weather.gov/alerts/active?point=33.68,-78.89"

LAST_RUN=""

# -------------------------
# FUNCTIONS
# -------------------------
say_digits() { echo "$1" | sed 's/./& /g'; }
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

decode_visibility() {
  VIS="$1"
  case "$VIS" in
    P6SM) echo "visibility greater than six miles" ;;
    *) echo "visibility $(echo "$VIS" | tr -d 'SM') miles" ;;
  esac
}

decode_clouds() {
  CLOUDS=$(echo "$1" | grep -oE '(FEW|SCT|BKN|OVC)[0-9]{3}' | head -n2)
  [ -z "$CLOUDS" ] && echo "clear skies" && return
  for c in $CLOUDS; do
    TYPE=${c:0:3}
    HEIGHT=$((10#${c:3:3} * 100))
    case "$TYPE" in
      FEW) echo -n "few clouds at $HEIGHT feet, " ;;
      SCT) echo -n "scattered clouds at $HEIGHT feet, " ;;
      BKN) echo -n "broken ceiling at $HEIGHT feet, " ;;
      OVC) echo -n "overcast ceiling at $HEIGHT feet, " ;;
    esac
  done | sed 's/, $//'
}

# -------------------------
# MAIN LOOP
# -------------------------
while true; do
  MIN=$(date +"%M")
  NOW=$(date +"%H%M")

  if [[ "$MIN" == "10" || "$MIN" == "40" ]]; then
    if [[ "$NOW" != "$LAST_RUN" ]]; then

      echo "Updating ATIS at $(date)"

      METAR=$(curl -s "$METAR_URL" | tail -n 1)
      ALERTS=$(curl -s "$ALERT_URL")

      # WIND
      WIND_BLOCK=$(echo "$METAR" | grep -oE '[0-9]{5}KT')
      DIR=${WIND_BLOCK:0:3}
      SPD=$((10#${WIND_BLOCK:3:2}))
      MPH=$((SPD * 115 / 100))
      DIR_WORD=$(convert_direction "$DIR")

      if [ "$SPD" -le 2 ]; then
        WIND="wind calm"
      else
        WIND="wind from the ${DIR_WORD} at ${MPH} miles per hour"
      fi

      # VIS
      VIS=$(decode_visibility "$(echo "$METAR" | grep -oE 'P?[0-9]+SM')")

      # TEMP
      TEMP_DP=$(echo "$METAR" | grep -oE ' [0-9]{2}/[0-9]{2}')
      TEMP_C=$(echo "$TEMP_DP" | cut -d/ -f1)
      TEMP=$((TEMP_C * 9 / 5 + 32))

      # CLOUDS
      CLOUDS=$(decode_clouds "$METAR")

      # ALT
      ALT=$(echo "$METAR" | grep -oE 'A[0-9]{4}' | tr -d 'A')
      ALT_SPOKEN=$(say_digits "$ALT")

      # TIME
      TIME_SPOKEN=$(say_digits "$NOW")

      # ALERTS
      HAZARD="no significant weather hazards"
      echo "$ALERTS" | grep -qi "thunderstorm" && HAZARD="thunderstorm activity in the area"

      # BUILD
      ATIS="Myrtle Beach International Airport information.
Time ${TIME_SPOKEN} local.
${WIND}.
${VIS}.
Sky conditions ${CLOUDS}.
Temperature ${TEMP} degrees Fahrenheit.
Altimeter ${ALT_SPOKEN}.
${HAZARD}."

      ATIS=$(capitalize_sentences "$ATIS")

      echo "$ATIS"

      pico2wave -w "$OUTPUT_RAW" "$ATIS"
      sox "$OUTPUT_RAW" "$OUTPUT_FINAL" gain -n -6

      LAST_RUN="$NOW"
    fi
  fi

  sleep 20
done
