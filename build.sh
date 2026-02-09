#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building MicMute..."
mkdir -p MicMute.app/Contents/MacOS
swiftc MicMute.swift -o MicMute.app/Contents/MacOS/MicMute -framework Cocoa -O

echo "Done! Run with: open MicMute.app"
echo "Or install as login item with: ./install.sh"
