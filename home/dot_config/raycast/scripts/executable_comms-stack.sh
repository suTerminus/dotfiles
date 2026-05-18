#!/usr/bin/env bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Comms Stack
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 💬
# @raycast.packageName Stacks
# @raycast.description Opens Teams, Outlook, Slack, WhatsApp, Spotify. Hammerspoon snaps each to Display 1 via its windowCreated watcher.

# Prefer Hammerspoon's commApps() — it uses bundle-IDs (more reliable than
# localized app names) and the same `hs` process that runs the placement
# watcher, so launch + snap stay tightly coordinated. Fall back to `open -a`
# if `hs` CLI isn't on PATH yet (e.g. fresh install before init.lua loaded).
if command -v hs >/dev/null 2>&1; then
  hs -c 'commApps()'
else
  for app in "Microsoft Teams" "Microsoft Outlook" "Slack" "WhatsApp" "Spotify"; do
    open -a "$app" 2>/dev/null || true
  done
fi
