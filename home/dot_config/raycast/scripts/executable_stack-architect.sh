#!/usr/bin/env bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Stack — Architect
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 📐
# @raycast.packageName Stacks
# @raycast.description Opens architecture / diagramming apps. Customise the list below.

DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
"$DIR/dev-default.sh"

# Add architect-specific tools below. Likely candidates:
# open -a "Obsidian"       2>/dev/null || true   # already in default
# open -a "Mermaid"        2>/dev/null || true
# open -a "GIMP"           2>/dev/null || true
# Structurizr extension is VSCode-based; opens with VSCode (already in default).
