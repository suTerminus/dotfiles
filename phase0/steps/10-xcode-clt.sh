#!/usr/bin/env bash
set -euo pipefail

# Step: 10-xcode-clt
# Idempotency probe: `xcode-select -p` exits 0 AND its output points
# to a directory that exists on disk.
# Action: if probe fails, invoke `xcode-select --install` (fire-and-forget;
# opens a system GUI dialog) and then poll the probe every 10s for up
# to 30 minutes. `xcode-select --install` exits 1 when an install is
# already in progress -- that is tolerated, not treated as failure.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="10-xcode-clt"

# Probe: returns 0 when CLT looks installed.
xcode_clt_installed() {
  local clt_path
  if ! clt_path="$(xcode-select -p 2>/dev/null)"; then
    return 1
  fi
  [ -n "$clt_path" ] && [ -d "$clt_path" ]
}

if xcode_clt_installed; then
  skip "$step_name: Xcode Command Line Tools already installed at $(xcode-select -p)"
  exit 0
fi

if is_dry_run; then
  info "$step_name: dry-run; would invoke 'xcode-select --install' and poll until installed"
  exit 0
fi

info "$step_name: Xcode Command Line Tools not detected; triggering installer"
info "$step_name: a system GUI dialog will appear; accept it to start the download"

# `xcode-select --install` returns 1 if an install is already in progress.
# That is fine; we just want to ensure the dialog/process has been kicked off.
if ! xcode-select --install >/dev/null 2>&1; then
  info "$step_name: xcode-select --install exited non-zero (likely already in progress); continuing to poll"
fi

# Poll every 10s, up to 180 iterations (30 minutes).
# Emit a heartbeat every 6 iterations (~ every 60s).
poll_interval=10
max_iterations=180
heartbeat_every=6

i=0
while [ "$i" -lt "$max_iterations" ]; do
  if xcode_clt_installed; then
    ok "$step_name: Xcode Command Line Tools installed at $(xcode-select -p)"
    exit 0
  fi
  if [ $((i % heartbeat_every)) -eq 0 ]; then
    info "$step_name: still waiting for Xcode CLT install (this opens a system dialog)"
  fi
  sleep "$poll_interval"
  i=$((i + 1))
done

error "$step_name: timed out after 30 minutes waiting for Xcode CLT install"
exit 1
