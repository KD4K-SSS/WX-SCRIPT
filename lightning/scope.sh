#!/bin/bash

WORKDIR="$HOME/goes19"
STATE_FILE="$WORKDIR/radar_state.txt"

draw_radar() {
    local radius=18
    local scale=5

    echo
    echo "               LIGHTNING RADAR SCOPE"
    echo

    for ((y=-radius; y<=radius; y++)); do
        line=""
        for ((x=-radius; x<=radius; x++)); do

            dist=$(awk -v x="$x" -v y="$y" 'BEGIN{print sqrt(x*x + y*y)}')
            miles=$(awk -v d="$dist" -v s="$scale" 'BEGIN{print d*s}')

            char=" "

            # radar rings
            awk "BEGIN {exit !($miles < 100)}" && char="."
            awk "BEGIN {exit !($miles < 50)}" && char=":"
            awk "BEGIN {exit !($miles < 25)}" && char="-"
            awk "BEGIN {exit !($miles < 10)}" && char="+"
            awk "BEGIN {exit !($miles < 2)}" && char="O"

            # center point = YOU
            if [[ $x -eq 0 && $y -eq 0 ]]; then
                char="X"
            fi

            line+="$char"
        done
        echo "$line"
    done

    echo
}

while true; do
    clear

    echo "GOES-19 RADAR DISPLAY"
    echo "Time: $(date)"
    echo "------------------------------------"

    if [[ ! -f "$STATE_FILE" ]]; then
        echo "Waiting for data..."
        sleep 5
        continue
    fi

    read TOTAL_SCORE NEAREST DIST10 DIST25 DIST50 DIST100 < "$STATE_FILE"

    echo "Lightning Activity Score: $TOTAL_SCORE"
    echo "Closest Flash Distance: $NEAREST mi"

    echo
    echo "Radius counts:"
    echo " 10 mi: $DIST10"
    echo " 25 mi: $DIST25"
    echo " 50 mi: $DIST50"
    echo "100 mi: $DIST100"

    draw_radar

    sleep 2
done
