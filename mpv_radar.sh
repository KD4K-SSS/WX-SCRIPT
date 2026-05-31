#!/bin/bash

set -eo pipefail

DIR="$HOME/radar_dashboard"
mkdir -p "$DIR"
cd "$DIR"

HTML="index.html"
STATUS="$HOME/radar_dashboard/glm_roi_status.txt"

KLTX_URL="https://radar.weather.gov/ridge/standard/KLTX_loop.gif"
KCAE_URL="https://radar.weather.gov/ridge/standard/KCAE_loop.gif"
GLM_URL="https://cdn.star.nesdis.noaa.gov/GOES19/GLM/SECTOR/se/EXTENT3/GOES19-SE-EXTENT3-600x600.gif"

KLTX="kltx.gif"
KCAE="kcae.gif"
GLM_IMG="glm.gif"

# =========================================================
# DASHBOARD
# =========================================================

cat > "$HTML" <<'EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>KD4K Radar Dashboard</title>

<style>

html, body {
    margin: 0;
    height: 100%;
    background: black;
    color: white;
    font-family: Arial;
    overflow: hidden;
}

#container {
    display: flex;
    height: 100vh;
}

/* LEFT: SINGLE ROTATING IMAGE */
#left {
    flex: 0 0 auto;
    background: black;
    display: flex;
    align-items: center;
    justify-content: center;
}

#radarImg {
    height: 100vh;
    width: auto;
}

/* RIGHT: TEXT PANEL */
#right {
    flex: 1;
    background: #111;
    padding: 12px;
    font-family: monospace;
    overflow-y: auto;
}

.title {
    color: white;
    font-weight: bold;
    margin-bottom: 10px;
}

pre {
    white-space: pre-wrap;
}

</style>
</head>

<body>

<div id="container">

    <div id="left">
        <img id="radarImg">
    </div>

    <div id="right">

        <div class="title">⚡ GLM / WEATHER DATA</div>
        <pre id="glmText">Loading...</pre>

    </div>

</div>

<script>

// ==========================
// ROTATING LEFT IMAGE
// ==========================

const images = [
    "kltx.gif",
    "kcae.gif",
    "glm.gif"
];

let index = 0;

function rotateRadar() {
    document.getElementById("radarImg").src =
        images[index] + "?t=" + Date.now();

    index = (index + 1) % images.length;
}

setInterval(rotateRadar, 20000);
rotateRadar();

// ==========================
// RIGHT PANEL LIVE TEXT
// ==========================

async function loadText() {
    try {
        const res = await fetch("glm_roi_status.txt?t=" + Date.now(), {
            cache: "no-store"
        });
        const text = await res.text();
        document.getElementById("glmText").innerText = text;
    } catch (e) {
        document.getElementById("glmText").innerText =
            "ERROR LOADING DATA";
    }
}

setInterval(loadText, 5000);
loadText();

</script>

</body>
</html>
EOF

# =========================================================
# DOWNLOAD LOOP
# =========================================================

download_data() {

    curl -s -L --fail --max-time 20 \
        -o "$KLTX" "${KLTX_URL}?t=$(date +%s)"

    curl -s -L --fail --max-time 20 \
        -o "$KCAE" "${KCAE_URL}?t=$(date +%s)"

    curl -s -L --fail --max-time 20 \
        -o "$GLM_IMG" "${GLM_URL}?t=$(date +%s)"
}

# =========================================================
# START
# =========================================================

download_data

if command -v xdg-open >/dev/null; then
    xdg-open "$HTML" >/dev/null 2>&1 &
elif command -v open >/dev/null; then
    open "$HTML"
fi

while true; do
    sleep 300
    download_data
done
