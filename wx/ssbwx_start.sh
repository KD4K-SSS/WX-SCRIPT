#!/bin/bash

# ==========================================
# KD4K GOES-19 WEATHER SYSTEM MASTER LAUNCHER
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER_LOG="$SCRIPT_DIR/master_fleet_launcher.log"

# Array of your specific watchdog launcher scripts in recommended startup order
LAUNCHERS=(
    "nc_runner.sh"          # 1. Ingests raw data first
    "atis_runner.sh"        # 2. Base weather components
    "strike_launcher.sh"    # 3. Core lightning engine
    "flashes_launcher.sh"   # 4. Flash compiler loop
    "glmdash_launcher.sh"   # 5. Dashboard engine analytics
    "plot_launcher.sh"      # 6. Generates the map outputs last
    "forecast_launcher.sh"  # 7. Forecast Launcher
)

DELAY_BETWEEN_LAUNCHES=4      # Seconds to wait between launching each subsystem

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LAUNCHER_LOG"
}

echo "=========================================="
echo "    STARTING GOES-19 WEATHER ENGINE FLEET   "
echo "=========================================="
echo "This script requires sudo privileges to prime background watchdogs & mount storage."

# 1. Prime the sudo cache right here
sudo -v

# 2. Background keep-alive loop. Refreshes sudo every 10 minutes.
while true; do sudo -n true; sleep 600; kill -0 "$$" || exit; done 2>/dev/null &

# ==========================================
# USB MOUNT & STORAGE VERIFICATION SECTION
# ==========================================
TARGET_DEV="/dev/sdb2"
MOUNT_POINT="/mnt/ssbwx_tmp"

# Ensure the new mount point directory exists on the host OS
if [ ! -d "$MOUNT_POINT" ]; then
    log_message "Mount directory $MOUNT_POINT missing. Creating it..."
    sudo mkdir -p "$MOUNT_POINT"
fi

# Check if the USB drive is already mounted to our target; if not, mount it
if ! mountpoint -q "$MOUNT_POINT"; then
    log_message "USB drive not mounted to $MOUNT_POINT. Attempting to mount $TARGET_DEV..."
    
    # Verify the hardware block device actually exists before mounting
    if [ -b "$TARGET_DEV" ]; then
        sudo mount "$TARGET_DEV" "$MOUNT_POINT"
    else
        log_message "CRITICAL ERROR: Hardware device $TARGET_DEV not found! USB unplugged?"
        exit 1
    fi
else
    log_message "USB drive is already safely mounted to $MOUNT_POINT."
fi

# Double check that our USB destination path is fully functional
if mountpoint -q "$MOUNT_POINT"; then
    sudo chmod 777 "$MOUNT_POINT"
    mkdir -p "$MOUNT_POINT/glm_scratch"
else
    log_message "CRITICAL ERROR: Failed to mount storage. Aborting launch sequence to protect local disk."
    exit 1
fi
# ==========================================

echo "==========================================" | tee -a "$LAUNCHER_LOG"
log_message "Master Fleet Boot Sequence Initiated"
echo "==========================================" | tee -a "$LAUNCHER_LOG"

for i in "${!LAUNCHERS[@]}"; do
    TARGET_SCRIPT="${LAUNCHERS[$i]}"
    FULL_PATH="$SCRIPT_DIR/$TARGET_SCRIPT"

    # Step 1: Ensure the script actually exists
    if [ ! -f "$FULL_PATH" ]; then
        log_message "ERROR: Cannot find launcher: $TARGET_SCRIPT. Skipping..."
        continue
    fi

    # Step 2: Ensure executable bits are set
    if [ ! -x "$FULL_PATH" ]; then
        log_message "Fixing permissions for $TARGET_SCRIPT..."
        chmod +x "$FULL_PATH"
    fi

  # Step 3: Spin up the watchdog inside a detached background session
    log_message "Launching Subsystem [$((i+1))/${#LAUNCHERS[@]}]: $TARGET_SCRIPT"
    
    # Strip the ".sh" extension to create a clean log name (e.g., nc_runner.log)
    LOG_NAME="${TARGET_SCRIPT%.sh}.log"
    
    # Redirect standard output and errors to the script's individual log file
    nohup "$FULL_PATH" > "$SCRIPT_DIR/$LOG_NAME" 2>&1 &
done

echo "==========================================" | tee -a "$LAUNCHER_LOG"
log_message "All subsystems deployed. Verifying background process states..."
echo "==========================================" | tee -a "$LAUNCHER_LOG"

sleep 2 # Brief pause to allow processes to register in OS table

# --- REAL-TIME PROCESS VERIFICATION CHECKLIST ---
echo -e "\n--- ONLINE WATCHDOG STATUS CHECK ---"
ALL_ONLINE=true

for TARGET_SCRIPT in "${LAUNCHERS[@]}"; do
    # Check if the process name is actively registered in the system process tree
    if pgrep -f "$TARGET_SCRIPT" > /dev/null; then
        echo -e "   [\e[32m ONLINE \e[0m] $TARGET_SCRIPT"
    else
        echo -e "   [\e[31m OFFLINE \e[0m] $TARGET_SCRIPT (Check individual script logs!)"
        ALL_ONLINE=false
    fi
done

echo "-------------------------------------"
if [ "$ALL_ONLINE" = true ]; then
    log_message "SUCCESS: Full weather stack is verified ONLINE and running silently."
else
    log_message "WARNING: One or more processes failed to stay online. Check master_fleet_launcher.log"
fi
echo "=========================================="
