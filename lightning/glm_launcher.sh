#!/bin/bash

# ==========================================
# GOES-19 RADAR WATCHDOG LAUNCHER
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Main radar script
RADAR_SCRIPT="$SCRIPT_DIR/test.sh"

# Launcher log
LAUNCHER_LOG="$SCRIPT_DIR/radar_launcher.log"

RESTART_DELAY=5
MAX_RESTARTS=1000

RESTART_COUNT=0

# ==========================================
# CTRL+C HANDLING
# ==========================================
cleanup() {
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launcher stopped by user" \
        | tee -a "$LAUNCHER_LOG"

    pkill -f "$RADAR_SCRIPT" 2>/dev/null || true

    exit 0
}

trap cleanup SIGINT SIGTERM

# ==========================================
# STARTUP CHECKS
# ==========================================
if [ ! -f "$RADAR_SCRIPT" ]; then
    echo "ERROR: Cannot find radar script:"
    echo "$RADAR_SCRIPT"
    exit 1
fi

if [ ! -x "$RADAR_SCRIPT" ]; then
    echo "Making radar script executable..."
    chmod +x "$RADAR_SCRIPT"
fi

# ==========================================
# HEADER
# ==========================================
echo "==========================================" | tee -a "$LAUNCHER_LOG"
echo "GOES-19 Radar Launcher Started" | tee -a "$LAUNCHER_LOG"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LAUNCHER_LOG"
echo "Radar Script: $RADAR_SCRIPT" | tee -a "$LAUNCHER_LOG"
echo "==========================================" | tee -a "$LAUNCHER_LOG"

# ==========================================
# MAIN WATCHDOG LOOP
# ==========================================
while true; do

    RESTART_COUNT=$((RESTART_COUNT + 1))

    echo "" | tee -a "$LAUNCHER_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting radar (restart #$RESTART_COUNT)" \
        | tee -a "$LAUNCHER_LOG"

    # --------------------------------------
    # RUN RADAR SCRIPT
    # --------------------------------------
    /bin/bash "$RADAR_SCRIPT"

    EXIT_CODE=$?

    echo "" | tee -a "$LAUNCHER_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Radar exited with code: $EXIT_CODE" \
        | tee -a "$LAUNCHER_LOG"

    # --------------------------------------
    # EXCESSIVE RESTART PROTECTION
    # --------------------------------------
    if [ "$RESTART_COUNT" -ge "$MAX_RESTARTS" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Maximum restart limit reached." \
            | tee -a "$LAUNCHER_LOG"

        echo "Stopping launcher." | tee -a "$LAUNCHER_LOG"
        exit 1
    fi

    # --------------------------------------
    # RESTART COUNTDOWN
    # --------------------------------------
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Radar stopped. Restarting..." \
        | tee -a "$LAUNCHER_LOG"

    for ((sec=RESTART_DELAY; sec>0; sec--)); do
        printf "\rRestarting in %d seconds... " "$sec"
        sleep 1
    done

    echo
done
