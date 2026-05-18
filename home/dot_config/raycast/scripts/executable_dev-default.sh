#!/usr/bin/env bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Dev Stack — Default
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 🚀
# @raycast.packageName Stacks
# @raycast.description Opens dev apps scaled to screen count: 1 screen = single Arc+Ghostty; 2 = 2 Arc; 3 = 3 Arc + 2 Ghostty.

# Count active displays via CoreGraphics (fast, no external tools needed).
SCREENS=$(python3 -c "import Quartz; _,d,_=Quartz.CGGetActiveDisplayList(32,None,None); print(len(d))" 2>/dev/null || echo 1)

# Single-instance apps — always one window regardless of screen count.
for app in "Visual Studio Code" "Obsidian" "Spotify"; do
  open -a "$app" 2>/dev/null || true
done

# Arc: 1 on laptop, 2 on minimal (1 ext), 3 on office (2+ ext).
if   [ "$SCREENS" -ge 3 ]; then ARC_COUNT=3
elif [ "$SCREENS" -ge 2 ]; then ARC_COUNT=2
else                             ARC_COUNT=1
fi

# Ghostty: 1 on laptop/minimal, 2 on office.
if [ "$SCREENS" -ge 3 ]; then GHOSTTY_COUNT=2; else GHOSTTY_COUNT=1; fi

open -a "Arc" 2>/dev/null || true
for i in $(seq 2 "$ARC_COUNT"); do
  osascript -e 'tell application "Arc" to make new window' 2>/dev/null || true
done

open -a "Ghostty" 2>/dev/null || true
for i in $(seq 2 "$GHOSTTY_COUNT"); do open -n -a "Ghostty" 2>/dev/null || true; done
