#!/usr/bin/env bash
set -euo pipefail

# Step: 40-github-auth
# Idempotency probe (all of):
#   1. `gh auth status --hostname github.com` exits 0 (authenticated).
#   2. `gh auth status` reports the git operations protocol as ssh
#      (we grep for "protocol: ssh" case-insensitively, which matches
#       gh's "Git operations protocol: ssh" line across recent versions).
#   3. `gh ssh-key list` returns at least one row, confirming an SSH
#      key is registered with the authenticated GitHub account.
#
# If any of those fail we run `gh auth login --git-protocol ssh --web`,
# which is the magic combination per PRD: it sets the git remote
# protocol to SSH, drives a browser-based device-code flow, and offers
# to upload (or generate + upload) an SSH key in one shot.
#
# Depends on step 30 (gh installed via phase0 Brewfile).

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="40-github-auth"

if ! require_command gh "gh not on PATH; run 30-phase0-brew.sh first"; then
  exit 1
fi

probe_github_auth() {
  if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    return 1
  fi
  if ! gh auth status --hostname github.com 2>&1 | grep -qiE 'protocol:[[:space:]]*ssh'; then
    return 2
  fi
  local key_count
  key_count="$(gh ssh-key list 2>/dev/null | grep -c '.' || true)"
  if [ "${key_count:-0}" -lt 1 ]; then
    return 3
  fi
  return 0
}

if is_dry_run; then
  if probe_github_auth; then
    info "$step_name: dry-run; probe passes, would skip (gh authenticated with SSH)"
  else
    info "$step_name: dry-run; would run gh auth login --git-protocol ssh --web"
  fi
  exit 0
fi

if probe_github_auth; then
  skip "$step_name: gh authenticated with SSH"
  exit 0
fi

if ! require_tty_stdin "$step_name: stdin is not a TTY; gh auth login needs a terminal for the SSH-key generation/upload prompt -- re-run from an interactive terminal session"; then
  exit 2
fi

info "$step_name: probe failed; launching interactive gh auth login"
info "$step_name: follow the browser device-code prompt, and accept the SSH key upload offer"
if ! gh auth login --git-protocol ssh --web; then
  error "$step_name: gh auth login exited non-zero"
  exit 1
fi

if probe_github_auth; then
  ok "$step_name: gh authenticated with SSH and at least one SSH key registered"
  exit 0
fi

error "$step_name: gh auth login completed but probe still fails -- please re-run interactively"
exit 2
