#!/bin/bash

# ==========================================
# GOES-19 GLM DASHBOARD WATCHDOG LAUNCHER
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASH_SCRIPT="$SCRIPT_DIR/glm_dash.sh" # Assumes your dashboard script name
LAUNCHER_LOG="$SCRIPT_DIR/glm_dash_launcher.log"

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
    log_message "GLM Dashboard Launcher stopped by user"
    pkill -f "$DASH_SCRIPT" 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM

# ==========================================
# STARTUP CHECKS & USB ENVIRONMENT SETUP
# ==========================================
echo "This script requires sudo privileges to confirm the USB mount status."
# Force a sudo refresh up front. This will ask for your password right here.
sudo -v

# Ensure your ssbwx_tmp mount path is fully valid and active
if [ -d "/mnt/ssbwx_tmp" ]; then
    mkdir -p "/mnt/ssbwx_tmp/glm_scratch"
    sudo chmod 777 /mnt/ssbwx_tmp
    sudo chmod 777 /mnt/ssbwx_tmp/glm_scratch
else
    echo "WARNING: /mnt/ssbwx_tmp not found. Make sure your USB drive launcher mounted it first." | tee -a "$LAUNCHER_LOG"
fi

if [ ! -f "$DASH_SCRIPT" ]; then
    echo "ERROR: Cannot find dashboard script:"
    echo "$DASH_SCRIPT"
    exit 1
fi

if [ ! -x "$DASH_SCRIPT" ]; then
    echo "Making dashboard script executable..."
    chmod +x "$DASH_SCRIPT"
fi

# ==========================================
# HEADER
# ==========================================
echo "==========================================" | tee -a "$LAUNCHER_LOG"
log_message "GLM Dashboard Launcher Started"
log_message "Target Script: $DASH_SCRIPT"
echo "==========================================" | tee -a "$LAUNCHER_LOG"

# ==========================================
# MAIN WATCHDOG LOOP
# ==========================================
while true; do

    RESTART_COUNT=$((RESTART_COUNT + 1))
    START_TIME=$(date +%s)

    echo "" | tee -a "$LAUNCHER_LOG"
    log_message "Starting GLM Dashboard Loop (restart #$RESTART_COUNT)"

    # Execute your dashboard core
    "$DASH_SCRIPT"
    EXIT_CODE=$?

    log_message "Dashboard engine exited with code: $EXIT_CODE"

    # Crash loop protection: If it ran successfully for more than 60 seconds, reset restart count
    END_TIME=$(date +%s)
    RUN_DURATION=$((END_TIME - START_TIME))
    if [ "$RUN_DURATION" -gt 60 ]; then
        log_message "Stable dashboard runtime detected ($RUN_DURATION seconds). Resetting metrics."
        RESTART_COUNT=0
    fi

    # Excess restart check
    if [ "$RESTART_COUNT" -ge "$MAX_RESTARTS" ]; then
        log_message "Maximum rapid restart limit reached for dashboard. Stopping launcher."
        exit 1
    fi

    log_message "Restarting dashboard in $RESTART_DELAY seconds..."
    
    for ((sec=RESTART_DELAY; sec>0; sec--)); do
        printf "\rRestarting in %d seconds... " "$sec"
        sleep 1
    done

    echo
done
