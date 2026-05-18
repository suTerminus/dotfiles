#!/usr/bin/env bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Dev Stack + Comms
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 🌐
# @raycast.packageName Stacks
# @raycast.description Full work-day open: Dev Stack — Default + Slack/Teams/Outlook.

DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
run() { local f="$DIR/$1.sh"; [ -x "$f" ] || f="$DIR/executable_$1.sh"; bash "$f"; }
run dev-default
run comms-stack

# After all apps have had time to launch, re-snap every window to its correct space.
(sleep 15 && /opt/homebrew/bin/hs -c "snapAll()" 2>/dev/null) &
