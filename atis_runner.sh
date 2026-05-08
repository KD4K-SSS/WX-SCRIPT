#!/bin/bash

# ==========================================
# ATIS AUTO-RESTART LAUNCHER
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Main ATIS script
ATIS_SCRIPT="$SCRIPT_DIR/kd4k_wx.sh"

# Launcher log
LAUNCHER_LOG="$SCRIPT_DIR/atis_launcher.log"

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

    # kill child ATIS process if running
    pkill -f "$ATIS_SCRIPT" 2>/dev/null || true

    exit 0
}

trap cleanup SIGINT SIGTERM

# ==========================================
# STARTUP CHECKS
# ==========================================
if [ ! -f "$ATIS_SCRIPT" ]; then
    echo "ERROR: Cannot find ATIS script:"
    echo "$ATIS_SCRIPT"
    exit 1
fi

if [ ! -x "$ATIS_SCRIPT" ]; then
    echo "Making ATIS script executable..."
    chmod +x "$ATIS_SCRIPT"
fi

# ==========================================
# HEADER
# ==========================================
echo "==========================================" | tee -a "$LAUNCHER_LOG"
echo "ATIS Launcher Started" | tee -a "$LAUNCHER_LOG"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LAUNCHER_LOG"
echo "ATIS Script: $ATIS_SCRIPT" | tee -a "$LAUNCHER_LOG"
echo "==========================================" | tee -a "$LAUNCHER_LOG"

# ==========================================
# MAIN WATCHDOG LOOP
# ==========================================
while true; do

    RESTART_COUNT=$((RESTART_COUNT + 1))

    echo "" | tee -a "$LAUNCHER_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting ATIS (restart #$RESTART_COUNT)" \
        | tee -a "$LAUNCHER_LOG"

    # --------------------------------------
    # RUN MAIN ATIS SCRIPT
    # --------------------------------------
    /bin/bash "$ATIS_SCRIPT"

    EXIT_CODE=$?

    echo "" | tee -a "$LAUNCHER_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ATIS exited with code: $EXIT_CODE" \
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
    # RESTART TIMER
    # --------------------------------------
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restarting in $RESTART_DELAY seconds..." \
        | tee -a "$LAUNCHER_LOG"

    sleep "$RESTART_DELAY"

done
