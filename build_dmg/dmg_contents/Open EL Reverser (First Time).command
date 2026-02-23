#!/bin/bash
# This script removes macOS quarantine so EL Reverser can open.
# You only need to run this once after dragging the app to Applications.

APP="/Applications/EL Reverser.app"

if [ ! -d "$APP" ]; then
    echo ""
    echo "⚠️  Please drag 'EL Reverser' into Applications first, then run this again."
    echo ""
    read -p "Press Enter to close..."
    exit 1
fi

echo ""
echo "🔓 Removing quarantine from EL Reverser..."
xattr -cr "$APP"
echo "✅ Done! Opening EL Reverser now..."
echo ""
open "$APP"
