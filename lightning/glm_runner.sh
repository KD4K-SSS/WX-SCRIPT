#!/bin/bash

# ==========================================
# GOES-19 GLM INGESTOR WATCHDOG
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INGESTOR_SCRIPT="$SCRIPT_DIR/nc_glm.sh"
LAUNCHER_LOG="$SCRIPT_DIR/glm_ingestor_launcher.log"

RESTART_DELAY=5
MAX_RESTARTS=1000

RESTART_COUNT=0

# ==========================================
# CTRL+C HANDLING
# ==========================================
cleanup() {
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] GLM Launcher stopped by user" \
        | tee -a "$LAUNCHER_LOG"

    pkill -f "$INGESTOR_SCRIPT" 2>/dev/null || true

    exit 0
}

trap cleanup SIGINT SIGTERM

# ==========================================
# STARTUP CHECKS
# ==========================================
if [ ! -f "$INGESTOR_SCRIPT" ]; then
    echo "ERROR: Cannot find ingestor script:"
    echo "$INGESTOR_SCRIPT"
    exit 1
fi

if [ ! -x "$INGESTOR_SCRIPT" ]; then
    echo "Making ingestor executable..."
    chmod +x "$INGESTOR_SCRIPT"
fi

# ==========================================
# HEADER
# ==========================================
echo "==========================================" | tee -a "$LAUNCHER_LOG"
echo "GLM Ingestor Launcher Started" | tee -a "$LAUNCHER_LOG"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LAUNCHER_LOG"
echo "Script: $INGESTOR_SCRIPT" | tee -a "$LAUNCHER_LOG"
echo "==========================================" | tee -a "$LAUNCHER_LOG"

# ==========================================
# MAIN WATCHDOG LOOP
# ==========================================
while true; do

    RESTART_COUNT=$((RESTART_COUNT + 1))

    echo "" | tee -a "$LAUNCHER_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting GLM ingestor (restart #$RESTART_COUNT)" \
        | tee -a "$LAUNCHER_LOG"

    /bin/bash "$INGESTOR_SCRIPT"

    EXIT_CODE=$?

    echo "" | tee -a "$LAUNCHER_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ingestor exited with code: $EXIT_CODE" \
        | tee -a "$LAUNCHER_LOG"

    if [ "$RESTART_COUNT" -ge "$MAX_RESTARTS" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Maximum restart limit reached." \
            | tee -a "$LAUNCHER_LOG"
        exit 1
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restarting in $RESTART_DELAY seconds..." \
        | tee -a "$LAUNCHER_LOG"

    for ((sec=RESTART_DELAY; sec>0; sec--)); do
        printf "\rRestarting in %d seconds... " "$sec"
        sleep 1
    done

    echo
done
