#!/usr/bin/env bash
set -euo pipefail

# Step: P1-30-brew-bundle
# Idempotency probe: `brew bundle check --file=~/.config/brew/Brewfile`
# exits 0 — meaning every formula/cask/mas entry in the rendered
# Brewfile is already installed on this host.
#
# Behaviour:
#   - require_command brew (defence-in-depth; preflight should have caught
#     it).
#   - Verify ~/.config/brew/Brewfile exists. If not, P1-10 hasn't applied
#     yet — error with a hint to run P1-10 first.
#   - If probe passes: skip.
#   - Pre-check `mas account`: if it exits non-zero, warn-not-fail. The
#     bundle command will print per-entry errors for MAS apps; those are
#     not Phase-1-blocking.
#   - Run `brew bundle install --file=~/.config/brew/Brewfile`.
#   - Re-probe. If it still fails, warn with `brew bundle check` output
#     and exit 0 — almost always a MAS auth issue and Phase 1 must not
#     be blocked by App Store sign-in state (PRD §13 Q-PARENT-3).
#
# Dry-run: log `would: brew bundle install --file=...` and exit 0.
#
# Exit codes:
#   0 — bundle satisfied (skip), bundle installed cleanly, or
#       post-install probe failed but only warn-worthy entries (MAS).
#   1 — Brewfile missing, brew missing, or brew bundle install crashed.
#
# Depends on: P1-00 preflight, P1-10 chezmoi-init (renders the Brewfile),
# P1-20 render-brewfile (writes the source template).

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="P1-30-brew-bundle"

BREWFILE_PATH="$HOME/.config/brew/Brewfile"

if ! require_command brew "$step_name: brew not on PATH; re-run phase0/steps/20-homebrew.sh"; then
  exit 1
fi

if [ ! -f "$BREWFILE_PATH" ]; then
  if is_dry_run; then
    info "$step_name: would: brew bundle install --file=$BREWFILE_PATH (Brewfile not yet rendered; P1-10 chezmoi apply runs first in real execution)"
    exit 0
  fi
  error "$step_name: $BREWFILE_PATH missing; re-run P1-10 first"
  exit 1
fi

probe_brew_bundle() {
  brew bundle check --file="$BREWFILE_PATH" >/dev/null 2>&1
}

if probe_brew_bundle; then
  if is_dry_run; then
    info "$step_name: dry-run; probe passes, would skip (brew bundle satisfied)"
  else
    skip "$step_name: brew bundle satisfied"
  fi
  exit 0
fi

# MAS pre-check (warn-not-fail). Run it only if the Brewfile actually
# references mas — otherwise the warning would be noise.
if grep -qE '^[[:space:]]*mas[[:space:]]' "$BREWFILE_PATH" 2>/dev/null; then
  if command -v mas >/dev/null 2>&1; then
    if ! mas account >/dev/null 2>&1; then
      warn "$step_name: not signed in to Mac App Store; mas entries will fail. Continuing."
    else
      info "$step_name: mas account check passed"
    fi
  else
    info "$step_name: mas binary not yet installed; bundle will install it before mas lines run"
  fi
fi

if is_dry_run; then
  info "$step_name: would: brew bundle install --file=$BREWFILE_PATH"
  exit 0
fi

info "$step_name: probe failed; running brew bundle install"
if ! brew bundle install --file="$BREWFILE_PATH"; then
  error "$step_name: brew bundle install exited non-zero"
  exit 1
fi

if probe_brew_bundle; then
  ok "$step_name: brew bundle satisfied"
  exit 0
fi

# Re-probe still failing. Capture and warn — almost always MAS auth.
warn "$step_name: brew bundle check still reports missing entries after install:"
check_out="$(brew bundle check --file="$BREWFILE_PATH" 2>&1 || true)"
if [ -n "$check_out" ]; then
  while IFS= read -r line; do
    warn "$step_name: $line"
  done <<EOF
$check_out
EOF
fi
warn "$step_name: continuing (likely MAS auth — sign in to App Store and re-run P1-30)"
exit 0
