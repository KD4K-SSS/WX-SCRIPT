#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORKDIR="$SCRIPT_DIR/glm_anim"
FRAMES_DIR="$WORKDIR/frames"
HTML="$SCRIPT_DIR/index.html"
GIF="$WORKDIR/glm.gif"

URL="https://cdn.star.nesdis.noaa.gov/GOES19/GLM/SECTOR/se/EXTENT3/2400x2400.jpg"

mkdir -p "$FRAMES_DIR"

MAX_FRAMES=6
INTERVAL=300

# ----------------------------
# HTML (local viewer)
# ----------------------------
cat > "$HTML" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<style>
body { margin:0; background:black; display:flex; justify-content:center; align-items:center; height:100vh; }
img { max-width:100%; max-height:100%; }
</style>
</head>
<body>
<img src="glm_anim/glm.gif?$(date +%s)">
</body>
</html>
EOF

firefox "$HTML" >/dev/null 2>&1 &

# ----------------------------
# MAIN LOOP
# ----------------------------
while true; do

    echo "Downloading latest GLM image..."

    TMP="$WORKDIR/latest.jpg"

    # safe download check (IMPORTANT)
    if ! curl -L --fail --silent --show-error -o "$TMP" "$URL"; then
        echo "Download failed, retrying..."
        sleep 30
        continue
    fi

    # verify it's actually an image
    if ! file "$TMP" | grep -q "JPEG image data"; then
        echo "Invalid file downloaded (not JPEG), skipping..."
        rm -f "$TMP"
        sleep 30
        continue
    fi

    # ----------------------------
    # SHIFT OLD FRAMES (6 MAX)
    # ----------------------------
    for ((i=MAX_FRAMES-1; i>=1; i--)); do
        if [[ -f "$FRAMES_DIR/frame_$((i-1)).jpg" ]]; then
            mv "$FRAMES_DIR/frame_$((i-1)).jpg" "$FRAMES_DIR/frame_$i.jpg"
        fi
    done

    cp "$TMP" "$FRAMES_DIR/frame_0.jpg"

    # ----------------------------
    # BUILD GIF
    # ----------------------------
    echo "Building GIF..."

    if ls "$FRAMES_DIR"/frame_*.jpg 1> /dev/null 2>&1; then
        ffmpeg -y \
            -framerate 1 \
            -i "$FRAMES_DIR/frame_%d.jpg" \
            -vf "scale=800:-1:flags=lanczos" \
            -loop 0 "$GIF" >/dev/null 2>&1
    fi

    echo "Updated GIF at $(date)"

    sleep "$INTERVAL"
done
