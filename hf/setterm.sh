#!/usr/bin/env bash

# Ensure the script is running in a true Linux native TTY console.
# setterm will throw an error if executed inside a graphical terminal emulator (like xterm or alacritty).
if [ "$TERM" = "xterm" ] || [ "$TERM" = "xterm-256color" ]; then
    echo "Warning: This script must be run directly inside a native TTY console." >&2
    echo "It will not function correctly inside a desktop environment terminal." >&2
fi

echo "Configuring TTY power savings..."
echo "-> Screen will blank after 5 minutes of inactivity."
echo "-> Monitor will power down completely via DPMS after 5 minutes."
echo "-> Any keypress or mouse movement will wake the display."

# Apply settings to the current terminal
setterm --blank 5 --powerdown 5

# Optional: Redirect settings to ensure it targets the active TTY console interface 
# even if executed from a background task or SSH session.
# setterm --blank 5 --powerdown 5 > /dev/tty1

echo "TTY power management initialized successfully."
