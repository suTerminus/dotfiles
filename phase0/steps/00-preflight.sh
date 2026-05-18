#!/usr/bin/env bash
set -euo pipefail

# Step: 00-preflight
# Idempotency probe: N/A. This step is the gate that runs unconditionally
# at the start of phase0 and validates host preconditions:
#   - macOS major version >= 15 (Sequoia)
#   - Apple Silicon (arm64) -- Intel is a soft warning, not a fail
#   - Internet reachable (curl https://github.com within 5s)
#   - Not running as root (EUID != 0)
#   - ~/code/personal is writable, or does not yet exist (will be created)
# Action: collect every check result; emit per-check log lines; exit
# non-zero if any HARD fail occurred. No state-changing operations.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="00-preflight"
hard_fails=0

if is_dry_run; then
  info "$step_name: dry-run; would validate macOS>=15, arm64, internet, non-root, ~/code/personal writable"
  exit 0
fi

# Check 1: macOS version >= 15 (Sequoia)
if ! command -v sw_vers >/dev/null 2>&1; then
  error "$step_name: sw_vers not found; this does not look like macOS"
  hard_fails=$((hard_fails + 1))
else
  macos_version="$(sw_vers -productVersion 2>/dev/null || echo "")"
  macos_major="${macos_version%%.*}"
  if [ -z "$macos_major" ]; then
    error "$step_name: could not parse macOS version from sw_vers output"
    hard_fails=$((hard_fails + 1))
  elif [ "$macos_major" -lt 15 ] 2>/dev/null; then
    error "$step_name: macOS $macos_version detected; require >= 15 (Sequoia)"
    hard_fails=$((hard_fails + 1))
  else
    ok "$step_name: macOS version $macos_version (>= 15)"
  fi
fi

# Check 2: Apple Silicon (arm64). Intel is a soft warning only.
arch_name="$(uname -m 2>/dev/null || echo unknown)"
if [ "$arch_name" = "arm64" ]; then
  ok "$step_name: architecture arm64 (Apple Silicon)"
else
  warn "$step_name: architecture $arch_name; phase0 is untested on non-arm64 hosts"
fi

# Check 3: Internet reachability via github.com (5s timeout).
if ! command -v curl >/dev/null 2>&1; then
  error "$step_name: curl not found on PATH"
  hard_fails=$((hard_fails + 1))
else
  if curl -fsS --max-time 5 -o /dev/null https://github.com; then
    ok "$step_name: internet reachable (https://github.com)"
  else
    error "$step_name: cannot reach https://github.com within 5s"
    hard_fails=$((hard_fails + 1))
  fi
fi

# Check 4: Not running as root.
current_uid="${EUID:-$(id -u)}"
if [ "$current_uid" -eq 0 ]; then
  error "$step_name: running as root (EUID=0); rerun as a regular user"
  hard_fails=$((hard_fails + 1))
else
  ok "$step_name: not running as root (uid=$current_uid)"
fi

# Check 5: ~/code/personal writable (or absent; will be created later).
code_personal="$HOME/code/personal"
if [ -e "$code_personal" ]; then
  if [ -d "$code_personal" ] && [ -w "$code_personal" ]; then
    ok "$step_name: $code_personal exists and is writable"
  else
    error "$step_name: $code_personal exists but is not a writable directory"
    hard_fails=$((hard_fails + 1))
  fi
else
  info "$step_name: $code_personal does not exist yet; will be created in a later step"
fi

# Check 6: current user is in the macOS admin group. Homebrew's installer
# (step 20) calls sudo internally; without admin membership it aborts with
# a confusing message. Catching it here gives an actionable error up front.
if ! command -v dseditgroup >/dev/null 2>&1; then
  warn "$step_name: dseditgroup not found; skipping admin-group check"
else
  current_user="${USER:-$(id -un)}"
  if dseditgroup -o checkmember -m "$current_user" admin >/dev/null 2>&1; then
    ok "$step_name: $current_user is in the admin group"
  else
    error "$step_name: $current_user is not in the admin group; Homebrew installer requires sudo"
    error "$step_name: grant admin in System Settings > Users & Groups, log out/in, then rerun"
    hard_fails=$((hard_fails + 1))
  fi
fi

# Summary.
if [ "$hard_fails" -gt 0 ]; then
  error "$step_name: $hard_fails hard check(s) failed; aborting"
  exit 1
fi

ok "$step_name: all preflight checks passed"
exit 0
