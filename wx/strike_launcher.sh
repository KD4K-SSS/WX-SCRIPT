#!/bin/bash

# ==========================================
# GOES-19 STRIKE DATA WATCHDOG LAUNCHER
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STRIKE_SCRIPT="$SCRIPT_DIR/strike_data.sh"
LAUNCHER_LOG="/mnt/ssbwx_tmp/strike_data_launcher.log"

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
    log_message "Strike Data Launcher stopped by user"
    pkill -f "$STRIKE_SCRIPT" 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM

# ==========================================
# STARTUP CHECKS & USB ENVIRONMENT SETUP
# ==========================================
echo "This script requires sudo privileges to confirm the USB mount status."
# Force a sudo refresh up front. This will ask for your password right here.
sudo -v

# Verify that the USB drive mount path is completely valid and running
if [ -d "/mnt/ssbwx_tmp" ]; then
    mkdir -p "/mnt/ssbwx_tmp/glm_scratch"
    sudo chmod 777 /mnt/ssbwx_tmp
else
    echo "WARNING: /mnt/ssbwx_tmp not found. Ensure your primary USB launcher has run first." | tee -a "$LAUNCHER_LOG"
fi

if [ ! -f "$STRIKE_SCRIPT" ]; then
    echo "ERROR: Cannot find target script:"
    echo "$STRIKE_SCRIPT"
    exit 1
fi

if [ ! -x "$STRIKE_SCRIPT" ]; then
    echo "Making strike data script executable..."
    chmod +x "$STRIKE_SCRIPT"
fi

# ==========================================
# HEADER
# ==========================================
echo "==========================================" | tee -a "$LAUNCHER_LOG"
log_message "Strike Data Launcher Started"
log_message "Target Script: $STRIKE_SCRIPT"
echo "==========================================" | tee -a "$LAUNCHER_LOG"

# ==========================================
# MAIN WATCHDOG LOOP
# ==========================================
while true; do

    RESTART_COUNT=$((RESTART_COUNT + 1))
    START_TIME=$(date +%s)

    echo "" | tee -a "$LAUNCHER_LOG"
    log_message "Starting Strike Data Core Engine (restart #$RESTART_COUNT)"

    # Run the strike data engine directly
    "$STRIKE_SCRIPT"
    EXIT_CODE=$?

    log_message "Strike Data core exited with code: $EXIT_CODE"

    # Crash loop protection: If it ran successfully for more than 60 seconds, reset restart count
    END_TIME=$(date +%s)
    RUN_DURATION=$((END_TIME - START_TIME))
    if [ "$RUN_DURATION" -gt 60 ]; then
        log_message "Stable engine runtime detected ($RUN_DURATION seconds). Resetting metrics."
        RESTART_COUNT=0
    fi

    # Excess restart check
    if [ "$RESTART_COUNT" -ge "$MAX_RESTARTS" ]; then
        log_message "Maximum rapid restart limit reached for strike data. Stopping launcher."
        exit 1
    fi

    log_message "Restarting core engine in $RESTART_DELAY seconds..."
    
    for ((sec=RESTART_DELAY; sec>0; sec--)); do
        printf "\rRestarting in %d seconds... " "$sec"
        sleep 1
    done

    echo
done
