#!/usr/bin/env bash
set -euo pipefail

# Step: 30-phase0-brew
# Idempotency probe: `brew bundle check --file=phase0/Brewfile` exits 0,
# meaning every brew/cask entry in the Phase 0 Brewfile is already
# installed on this host. If the probe passes we skip; otherwise we run
# `brew bundle install` against the same Brewfile, then re-probe.
#
# Depends on step 20 (Homebrew installed and on PATH).
#
# Note: the Phase 0 Brewfile contains `cask "claude"` (Claude Desktop).
# The first time that cask installs it may trigger a sudo prompt -- per
# the PRD this is "the first sudo prompt" the user will see in phase 0.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="30-phase0-brew"
BREWFILE_PATH="$SCRIPT_DIR/../Brewfile"

if ! require_command brew "brew not on PATH; run 20-homebrew.sh first"; then
  exit 1
fi

if [ ! -f "$BREWFILE_PATH" ]; then
  error "$step_name: Brewfile not found at $BREWFILE_PATH"
  exit 1
fi

probe_brewfile() {
  brew bundle check --file="$BREWFILE_PATH" >/dev/null 2>&1
}

if is_dry_run; then
  if probe_brewfile; then
    info "$step_name: dry-run; probe passes, would skip (all phase0 packages installed)"
  else
    info "$step_name: dry-run; would install missing entries from $BREWFILE_PATH"
    info "$step_name: dry-run; command would be: brew bundle install --file=\"$BREWFILE_PATH\""
  fi
  exit 0
fi

if probe_brewfile; then
  skip "$step_name: all phase0 packages installed"
  exit 0
fi

info "$step_name: probe failed; running brew bundle install against $BREWFILE_PATH"
if ! brew bundle install --file="$BREWFILE_PATH"; then
  error "$step_name: brew bundle install exited non-zero"
  exit 1
fi

if probe_brewfile; then
  ok "$step_name: phase0 Brewfile satisfied"
  exit 0
fi

error "$step_name: brew bundle install completed but probe still fails -- package may have failed to install"
exit 2
