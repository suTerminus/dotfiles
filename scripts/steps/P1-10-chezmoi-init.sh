#!/usr/bin/env bash
set -euo pipefail

# Step: P1-10-chezmoi-init
# Idempotency probe (all of):
#   1. `chezmoi` is on PATH.
#   2. `chezmoi source-path` exits 0 and (after realpath normalisation)
#      its output equals ~/code/personal/dotfiles/home — i.e. chezmoi is
#      pointed at THIS working repo, not the default ~/.local/share/chezmoi.
#
# Behaviour:
#   - If chezmoi is missing, eager-install via `brew install chezmoi`.
#     (chezmoi is also in inventory/brew.yaml but P1-30 runs after P1-10,
#     so we install eagerly here.)
#   - If the probe passes: run `chezmoi apply` (idempotent re-render of
#     every templated file under home/) and skip-log.
#   - If the probe fails: require_tty_stdin, then
#     `chezmoi init --apply --source ~/code/personal/dotfiles`. This
#     triggers the prompts in home/.chezmoi.toml.tmpl (machine, name,
#     email) and renders every template.
#   - After apply, run `chezmoi diff`. If non-empty, warn with the diff
#     content (do NOT fail — the user may have local edits to surface).
#
# Dry-run: log `would: brew install chezmoi` (if missing) and
# `would: chezmoi init --apply ...` (or `would: chezmoi apply` if already
# initialised), but never execute.
#
# Exit codes:
#   0 — chezmoi initialised and applied (or skip).
#   1 — chezmoi install failed, or post-apply probe still fails.
#   2 — interactive init required but stdin is not a TTY.
#
# Depends on: P1-00 preflight, Phase 0 Homebrew.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"
# shellcheck source=../lib/prompt.sh
. "$SCRIPT_DIR/../lib/prompt.sh"

step_name="P1-10-chezmoi-init"

DOTFILES_DIR="$HOME/code/personal/dotfiles"
# chezmoi source-path returns the .chezmoiroot-resolved source root
# (i.e., DOTFILES_DIR/home given .chezmoiroot at the repo root with
# content "home"). The probe checks for that resolved path.
EXPECTED_SOURCE="$DOTFILES_DIR/home"

# Normalise a path via realpath-ish; fall back to as-given if it doesn't
# yet exist (e.g. fresh machine where home/ hasn't been created).
_normalise_path() {
  local p="$1"
  if [ -z "$p" ]; then
    printf ''
    return 0
  fi
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p" 2>/dev/null || printf '%s' "$p"
  else
    (cd "$p" 2>/dev/null && pwd -P) || printf '%s' "$p"
  fi
}

probe_chezmoi_initialised() {
  command -v chezmoi >/dev/null 2>&1 || return 1
  local source_path
  source_path="$(chezmoi source-path 2>/dev/null)" || return 1
  [ -n "$source_path" ] || return 1
  local got want
  got="$(_normalise_path "$source_path")"
  want="$(_normalise_path "$EXPECTED_SOURCE")"
  [ "$got" = "$want" ]
}

# 1. Eager-install chezmoi if missing.
if ! command -v chezmoi >/dev/null 2>&1; then
  if is_dry_run; then
    info "$step_name: would: brew install chezmoi"
  else
    if ! command -v brew >/dev/null 2>&1; then
      error "$step_name: brew not on PATH; cannot install chezmoi (re-run phase0/steps/20-homebrew.sh)"
      exit 1
    fi
    info "$step_name: chezmoi missing; running: brew install chezmoi"
    if ! brew install chezmoi; then
      error "$step_name: brew install chezmoi failed"
      exit 1
    fi
    ok "$step_name: chezmoi installed"
  fi
else
  info "$step_name: chezmoi already on PATH"
fi

# 2. Probe — is chezmoi already initialised against THIS repo?
if probe_chezmoi_initialised; then
  if is_dry_run; then
    info "$step_name: would: chezmoi apply (already initialised)"
    exit 0
  fi
  info "$step_name: chezmoi already initialised; running chezmoi apply --force"
  # --force: overwrite local drift without prompting. The step subprocess
  # can't service chezmoi's interactive "file has changed since chezmoi
  # last wrote it" prompt (no /dev/tty), and the dotfiles repo is the
  # source of truth — drift in live files is expected to lose.
  if ! chezmoi apply --force; then
    error "$step_name: chezmoi apply failed"
    exit 1
  fi
  skip "$step_name: chezmoi already initialized; applied"
  # Post-apply diff for visibility.
  if diff_out="$(chezmoi diff 2>&1)" && [ -n "$diff_out" ]; then
    warn "$step_name: chezmoi diff non-empty after apply:"
    while IFS= read -r line; do
      warn "$step_name: $line"
    done <<EOF
$diff_out
EOF
  fi
  exit 0
fi

# 3. First-run init. chezmoi will prompt for machine / name / email.
if is_dry_run; then
  # If chezmoi isn't installed yet (we logged the would: above), there's
  # nothing more we can faithfully describe; if it IS installed but not
  # pointed at this repo, the action is init.
  info "$step_name: would: chezmoi init --apply --source $DOTFILES_DIR"
  exit 0
fi

# Pre-set chezmoi config short-circuits the prompts: if the user already
# has ~/.config/chezmoi/chezmoi.toml populated with [data] machine, name,
# email, then chezmoi's promptStringOnce returns the existing values and
# never reads from stdin. In that case we don't need a TTY.
chezmoi_config="$HOME/.config/chezmoi/chezmoi.toml"
prompts_will_fire=1
if [ -f "$chezmoi_config" ] \
   && grep -qE '^[[:space:]]*machine[[:space:]]*=' "$chezmoi_config" \
   && grep -qE '^[[:space:]]*name[[:space:]]*='    "$chezmoi_config" \
   && grep -qE '^[[:space:]]*email[[:space:]]*='   "$chezmoi_config"; then
  prompts_will_fire=0
  info "$step_name: chezmoi config already populated; init will not prompt"
fi

if [ "$prompts_will_fire" -eq 1 ]; then
  if ! require_tty_stdin "$step_name: stdin is not a TTY; chezmoi init prompts for machine/name/email -- re-run from an interactive terminal"; then
    exit 2
  fi
fi

info "$step_name: running chezmoi init --apply --source $DOTFILES_DIR"
if ! chezmoi init --apply --source "$DOTFILES_DIR"; then
  error "$step_name: chezmoi init --apply failed"
  exit 1
fi

if ! probe_chezmoi_initialised; then
  error "$step_name: chezmoi init completed but probe still fails (source-path mismatch)"
  exit 1
fi

ok "$step_name: chezmoi initialised and applied"

# Post-apply diff for visibility (warn-not-fail).
if diff_out="$(chezmoi diff 2>&1)" && [ -n "$diff_out" ]; then
  warn "$step_name: chezmoi diff non-empty after apply:"
  while IFS= read -r line; do
    warn "$step_name: $line"
  done <<EOF
$diff_out
EOF
fi

exit 0
