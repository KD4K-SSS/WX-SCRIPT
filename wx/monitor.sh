#!/bin/bash
# ========================================================
# SSBWX WEATHER SYSTEM HEARTBEAT MONITOR
# ========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_FILE="/var/www/html/data/status.txt"

# Define your tracked launcher scripts
LAUNCHERS=(
    "nc_runner.sh"
    "atis_runner.sh"
    "strike_launcher.sh"
    "flashes_launcher.sh"
    "glmdash_launcher.sh"
    "plot_launcher.sh"
    "forecast_launcher.sh"
)

# Target directory for storage verification
MOUNT_POINT="/mnt/ssbwx_tmp"

# Centralized dashboard rendering engine (Pure Text Only)
run_monitor() {
    echo "========================================================"
    echo "       SSBWX SERVER MONITOR   "
    echo "========================================================"
    echo "  DATE -TIME: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 1. Check Host Storage Health
    echo -e "\n[ STORAGE SUBSYSTEM ]"
    if mountpoint -q "$MOUNT_POINT"; then
        # Grab disk usage percentage for your target mount
        DISK_USAGE=$(df -h "$MOUNT_POINT" | awk 'NR==2 {print $5}')
        echo -e " MOUNT POINT: [ MOUNTED ] $MOUNT_POINT ($DISK_USAGE USED)"
    else
        echo -e " MOUNT POINT: [ CRITICAL OFFLINE ] $MOUNT_POINT (USB disconnected?)"
    fi

    # 2. Check Active Watchdogs via Process Tree
    echo -e "\n[ PROCESS TELEMETRY ]"
    for TARGET_SCRIPT in "${LAUNCHERS[@]}"; do
        # Extract PID if it exists
        PID=$(pgrep -f "$TARGET_SCRIPT")
        
        if [ -n "$PID" ]; then
            # Print ONLINE status with its native PID
            echo -e "  [ ONLINE ] (PID: $(echo $PID | awk '{print $1}')) -> $TARGET_SCRIPT"
        else
            # Print OFFLINE status
            echo -e "  [ OFFLINE ] -------------------> $TARGET_SCRIPT"
        fi
    done
    
    # 3. Quick Peek at recent log activities (Hides countdown spam)
    echo -e "\n[ RECENT ERROR ALERT LOGS ]"
    if [ -f "$SCRIPT_DIR/master_fleet_launcher.log" ]; then
        tail -n 3 "$SCRIPT_DIR/master_fleet_launcher.log" | sed 's/^/  /'
    else
        echo "  No master log file found yet."
    fi
    
    # 4. Check Global System Load & Network Metrics
    echo -e "\n[ SYSTEM INFO ]"
    CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    RAM_USAGE=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    echo -e "  CPU:    $CPU_LOAD%"
    echo -e "  MEMORY (RAM): $RAM_USAGE"

    # --- wlo1 Network Telemetry Addition ---
    if grep -q "wlo1:" /proc/net/dev; then
        # Parse total received (RX) and transmitted (TX) bytes into Megabytes
        NET_STATS=$(awk '/wlo1:/ {printf "RX: %.1f MB | TX: %.1f MB", $2/1024/1024, $10/1024/1024}' /proc/net/dev)
        echo -e "  NETWORK: $NET_STATS"
    else
        echo -e "  NETWORK: [ INTERFACE NOT FOUND / OFFLINE ]"
    fi
}

# Execution Route handling
if [ "$1" == "--txt" ]; then
    run_monitor
else
    # Automatically verify web data directory exists
    mkdir -p "$(dirname "$STATUS_FILE")"

    while true; do
        # 1. Clear ONLY the active terminal screen
        tput clear > /dev/tty
        
        # 2. Render real-time data cleanly to the screen
        run_monitor
        echo -e "\n========================================================"
        echo "END SCAN - RELOAD IN 2 MINUTES"
        
        # 3. Simultaneously dump a 100% pure text capture to the web status file
        run_monitor > "$STATUS_FILE"
        
        # Short sleep window for responsive real-time state tracking
        sleep 120
    done
fi
