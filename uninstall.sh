#!/bin/bash

PLIST_NAME="com.micmute.app"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

launchctl unload "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH"

pkill -f MicMute 2>/dev/null || true

echo "MicMute uninstalled."
