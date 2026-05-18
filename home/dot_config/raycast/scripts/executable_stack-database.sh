#!/usr/bin/env bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Stack — Database
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 🗄️
# @raycast.packageName Stacks
# @raycast.description Opens DB-development apps. Customise the list below.

DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
"$DIR/dev-default.sh"

# Add DB-specific tools below:
# open -a "DataGrip" 2>/dev/null || true
