#!/bin/bash

# ==========================================
# KD4K GOES-19 WEATHER SYSTEM FLEET CONTROLLER
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MASTER_LAUNCHER="$SCRIPT_DIR/ssbwx_master.sh" # Path to your main launcher

# Array of your specific scripts to target for shutdown
LAUNCHERS=(
    "nc_runner.sh"
    "atis_runner.sh"
    "strike_launcher.sh"
    "flashes_launcher.sh"
    "glmdash_launcher.sh"
    "plot_launcher.sh"
)

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

stop_fleet() {
    echo "=========================================="
    log_message "Initiating Fleet Shutdown..."
    echo "=========================================="
    
    local found_any=false
    for TARGET_SCRIPT in "${LAUNCHERS[@]}"; do
        # Find all process IDs (PIDs) matching the exact script name
        PIDS=$(pgrep -f "$TARGET_SCRIPT")
        
        if [ ! -z "$PIDS" ]; then
            log_message "Stopping $TARGET_SCRIPT (PIDs: $PIDS)..."
            # Send standard terminate signal (SIGTERM)
            kill $PIDS
            found_any=true
        else
            echo "   [ OFFLINE ] $TARGET_SCRIPT is already stopped."
        fi
    done
    
    # Give the OS a moment to clean up process tables
    sleep 1
    
    if [ "$found_any" = true ]; then
        log_message "SUCCESS: All active weather engine subsystems have been stopped."
    else
        log_message "No active subsystems were found running."
    fi
}

status_fleet() {
    echo "=========================================="
    echo "       CURRENT FLEET STATUS CHECK         "
    echo "=========================================="
    local all_online=true

    for TARGET_SCRIPT in "${LAUNCHERS[@]}"; do
        if pgrep -f "$TARGET_SCRIPT" > /dev/null; then
            echo -e "   [\e[32m ONLINE \e[0m] $TARGET_SCRIPT"
        else
            echo -e "   [\e[31m OFFLINE \e[0m] $TARGET_SCRIPT"
            all_online=false
        fi
    done
    echo "------------------------------------------"
}

# --- MAIN CONTROLLER ROUTER ---
case "$1" in
    stop)
        stop_fleet
        ;;
    status)
        status_fleet
        ;;
    restart)
        stop_fleet
        
        # --- CLEAN LOGS SECTION ---
        echo "=========================================="
        log_message "Purging old runtime logs to prepare for clean boot..."
        # Safely remove individual subsystem logs and the master log if desired
        rm -f "$SCRIPT_DIR"/*.log
        echo "   [ CLEANED ] Old log captures deleted."
        echo "=========================================="
        
        echo -e "\nWaiting 3 seconds before spinning up the engine..."
        sleep 3
        
        if [ -f "$MASTER_LAUNCHER" ]; then
            exec "$MASTER_LAUNCHER"
        else
            log_message "ERROR: Cannot find master launcher script at $MASTER_LAUNCHER"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {status|stop|restart}"
        exit 1
        ;;
esac
