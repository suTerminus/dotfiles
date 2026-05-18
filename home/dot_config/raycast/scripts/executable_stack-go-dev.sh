#!/usr/bin/env bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Stack — Go Dev
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 🐹
# @raycast.packageName Stacks
# @raycast.description Opens Go-development apps. Customise the list below.

DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
"$DIR/dev-default.sh"

# Add Go-specific tools below:
# open -a "GoLand" 2>/dev/null || true
# open -a "Kreya"  2>/dev/null || true
