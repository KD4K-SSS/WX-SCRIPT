#!/bin/bash

#################################################
# KD4K HF MUF SYSTEM MASTER LAUNCHER
#################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER_LOG="/mnt/ssbwx_tmp/master_muf_launcher.log"

LAUNCHERS=(
    "psk_muf.sh"
    "wspr_muf.sh"
    "propagation.sh"
    "muf.sh"
    "psk_gif.sh"
    "omiss_engine.py"
)

DELAY_BETWEEN_LAUNCHES=3

#################################################
# LOGGING
#################################################

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LAUNCHER_LOG"
}

#################################################
# PREVENT MULTIPLE COPIES
#################################################

LOCKFILE="/tmp/muf_launcher.lock"

if ! mkdir "$LOCKFILE" 2>/dev/null; then
    echo "Another MUF launcher instance is already running."
    exit 1
fi

#################################################
# CLEAN SHUTDOWN
#################################################

cleanup() {

    echo

    log_message "Shutdown requested. Stopping all MUF services..."

    for TARGET_SCRIPT in "${LAUNCHERS[@]}"
    do
        pkill -f "$TARGET_SCRIPT" 2>/dev/null
    done

    rm -rf "$LOCKFILE"

    log_message "All MUF services terminated."

    exit 0
}

trap cleanup INT TERM EXIT

#################################################
# BANNER
#################################################

clear

echo "=========================================="
echo "        KD4K HF MUF SYSTEM LAUNCHER       "
echo "=========================================="

log_message "HF MUF Boot Sequence Initiated"

#################################################
# SCRIPT LAUNCH LOOP
#################################################

for i in "${!LAUNCHERS[@]}"
do
    TARGET_SCRIPT="${LAUNCHERS[$i]}"
    FULL_PATH="$SCRIPT_DIR/$TARGET_SCRIPT"

    if [[ ! -f "$FULL_PATH" ]]; then
        log_message "ERROR: Missing $TARGET_SCRIPT"
        continue
    fi

    if [[ ! -x "$FULL_PATH" ]]; then
        chmod +x "$FULL_PATH"
    fi

    if pgrep -f "$TARGET_SCRIPT" >/dev/null 2>&1; then
        log_message "$TARGET_SCRIPT already running. Skipping."
        continue
    fi

    # Strip .sh or .py to create log name (e.g. omiss_engine.log)
    LOG_NAME="${TARGET_SCRIPT%.*}.log"

    log_message "Starting $TARGET_SCRIPT..."

    # Determine command based on file extension
    if [[ "$TARGET_SCRIPT" == *.py ]]; then
        CMD=(python3 "$FULL_PATH")
    else
        CMD=("$FULL_PATH")
    fi

    nohup "${CMD[@]}" \
        > "$SCRIPT_DIR/$LOG_NAME" \
        2>&1 &

    PID=$!

    sleep 2

    if kill -0 "$PID" 2>/dev/null; then
        log_message "$TARGET_SCRIPT running with PID: $PID"
    else
        log_message "ERROR: $TARGET_SCRIPT exited immediately"
    fi

    sleep "$DELAY_BETWEEN_LAUNCHES"

done

#################################################
# VERIFY STATUS
#################################################

echo
echo "=========================================="
echo "      MUF SYSTEM STATUS VERIFICATION      "
echo "=========================================="

ALL_ONLINE=true

for TARGET_SCRIPT in "${LAUNCHERS[@]}"
do
    if pgrep -f "$TARGET_SCRIPT" >/dev/null 2>&1; then
        echo "  [ONLINE ] $TARGET_SCRIPT"
    else
        echo "  [OFFLINE] $TARGET_SCRIPT"
        ALL_ONLINE=false
    fi
done

echo "------------------------------------------"

if [[ "$ALL_ONLINE" == true ]]; then
    log_message "SUCCESS: All MUF services online."
else
    log_message "WARNING: One or more services offline."
fi

echo "=========================================="
echo
echo "All MUF Services Running"
echo "Press CTRL+C to Stop Everything"
echo "=========================================="
echo

#################################################
# KEEP SUPERVISOR RUNNING
#################################################

while true
do
    sleep 5
done
