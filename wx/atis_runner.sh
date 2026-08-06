#!/bin/bash

# ==========================================
# KD4K AUTO-RESTART LAUNCHER
# ==========================================
# NOTE: Removed sudo sysctl. Recommend adding 'vm.swappiness=10' to /etc/sysctl.conf instead.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATIS_SCRIPT="$SCRIPT_DIR/kd4k_wx1.sh"
LAUNCHER_LOG="/mnt/ssbwx_tmp/atis_launcher.log"

RESTART_DELAY=5
MAX_RESTARTS=1000
RESTART_COUNT=0

# Helper function to log with timestamps easily
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LAUNCHER_LOG"
}

# ==========================================
# CTRL+C HANDLING
# ==========================================
cleanup() {
    echo ""
    log_message "Launcher stopped by user"
    pkill -f "$ATIS_SCRIPT" 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM



# ==========================================
# HEADER
# ==========================================
echo "==========================================" | tee -a "$LAUNCHER_LOG"
log_message "ATIS Launcher Started"
log_message "ATIS Script: $ATIS_SCRIPT"
echo "==========================================" | tee -a "$LAUNCHER_LOG"

# ==========================================
# MAIN WATCHDOG LOOP
# ==========================================
while true; do
    RESTART_COUNT=$((RESTART_COUNT + 1))
    START_TIME=$(date +%s)

    echo "" | tee -a "$LAUNCHER_LOG"
    log_message "Starting ATIS (restart #$RESTART_COUNT)"

    # Run the script directly since it's executable
    "$ATIS_SCRIPT"
    EXIT_CODE=$?

    log_message "ATIS exited with code: $EXIT_CODE"

    # Crash loop protection: If it ran for more than 60 seconds, reset restart count
    END_TIME=$(date +%s)
    RUN_DURATION=$((END_TIME - START_TIME))
    if [ "$RUN_DURATION" -gt 60 ]; then
        RESTART_COUNT=0
    fi

    # Excess restart check
    if [ "$RESTART_COUNT" -ge "$MAX_RESTARTS" ]; then
        log_message "Maximum rapid restart limit reached. Stopping launcher."
        exit 1
    fi

    log_message "Restarting in $RESTART_DELAY seconds..."
    sleep "$RESTART_DELAY"
done
