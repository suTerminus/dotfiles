#!/usr/bin/env bash
set -euo pipefail

# Step: 20-homebrew
# Idempotency probe: `command -v brew` resolves AND `brew --version`
# exits 0.
# Action: if probe fails, run the official Homebrew installer in
# non-interactive mode. Note that NONINTERACTIVE=1 only suppresses
# the "press enter to continue" prompt; the installer still calls
# sudo internally and will prompt for the user password at runtime.
# Post-install: persist `eval "$(/opt/homebrew/bin/brew shellenv)"`
# in ~/.zprofile (guarded by a marker comment so we never duplicate
# it) and source it for the current shell so subsequent phase0 steps
# see brew on PATH. We deliberately do NOT run `brew update` here --
# that is a maintenance op, not a bootstrap op.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="20-homebrew"
brew_marker="# bootstrap: brew shellenv"
zprofile="$HOME/.zprofile"

brew_installed() {
  command -v brew >/dev/null 2>&1 && brew --version >/dev/null 2>&1
}

ensure_zprofile_shellenv() {
  # Append the shellenv eval line to ~/.zprofile if not already present.
  # Marker-based detection so re-runs are idempotent.
  if [ -f "$zprofile" ] && grep -Fq "$brew_marker" "$zprofile"; then
    info "$step_name: ~/.zprofile already contains brew shellenv marker"
    return 0
  fi
  info "$step_name: appending brew shellenv eval to ~/.zprofile"
  {
    printf '\n%s\n' "$brew_marker"
    printf '%s\n' 'eval "$(/opt/homebrew/bin/brew shellenv)"'
  } >> "$zprofile"
}

source_brew_for_current_shell() {
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}

if brew_installed; then
  skip "$step_name: Homebrew already installed ($(brew --version | head -n1))"
  if is_dry_run; then
    info "$step_name: dry-run; would ensure brew shellenv eval is present in ~/.zprofile"
    info "$step_name: dry-run; would source /opt/homebrew/bin/brew shellenv for current shell"
    exit 0
  fi
  ensure_zprofile_shellenv
  source_brew_for_current_shell
  exit 0
fi

if is_dry_run; then
  info "$step_name: dry-run; would run the official Homebrew installer with NONINTERACTIVE=1"
  info "$step_name: dry-run; would ensure brew shellenv eval is present in ~/.zprofile"
  info "$step_name: dry-run; would source /opt/homebrew/bin/brew shellenv for current shell"
  exit 0
fi

info "$step_name: Homebrew not detected; running official installer (sudo password may be requested)"
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Make brew visible to this shell process before re-probing.
source_brew_for_current_shell

if ! brew_installed; then
  error "$step_name: post-install probe still fails; brew not on PATH or non-functional"
  exit 1
fi

ensure_zprofile_shellenv

ok "$step_name: Homebrew installed ($(brew --version | head -n1))"
exit 0
