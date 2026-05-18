#!/usr/bin/env bash
set -euo pipefail

# Step: P2-12-enersis-overlay
# Idempotency probe (machine == work AND all of):
#   1. ~/.local/share/chezmoi-enersis/.git exists.
#   2. `chezmoi diff --source ~/.local/share/chezmoi-enersis` returns empty.
#
# Behaviour:
#   - machine != work -> skip entirely. Also verify
#     ~/.local/share/chezmoi-enersis does NOT exist on a personal machine;
#     warn (don't fail) if it does (drift).
#   - probe passes -> skip.
#   - clone missing -> git clone git@github.com:suTerminus/dotfiles-enersis.git
#     ~/.local/share/chezmoi-enersis. Hard-fail with a clear message if
#     clone fails (admiral creates the repo at integration time).
#   - apply overlay -> chezmoi apply --source <ENERSIS>. Requires
#     BW_SESSION (P2-00 sets it; we source the session file as fallback).
#   - re-probe diff -> non-empty: warn (don't fail).
#
# Depends on: P2-00 (BW_SESSION) and P2-10 (personal overlay applied
# first, so layers compose in the correct order).
#
# Standalone-runnable: sources lib/log.sh, lib/idempotent.sh, lib/phase2.sh
# via SCRIPT_DIR.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"
# shellcheck source=../lib/phase2.sh
. "$SCRIPT_DIR/../lib/phase2.sh"

step_name="P2-12-enersis-overlay"

ENERSIS_SOURCE="$HOME/.local/share/chezmoi-enersis"
ENERSIS_REPO_URL="git@github.com:suTerminus/dotfiles-enersis.git"

# Machine-type guard. On personal machines this step is a no-op except
# for a drift check.
machine="$(phase2_machine_type || true)"
if [ "$machine" != "work" ]; then
  if [ -e "$ENERSIS_SOURCE" ]; then
    warn "$step_name: enersis overlay present on non-work machine (machine='$machine'); see $ENERSIS_SOURCE"
  fi
  skip "$step_name: not a work machine (machine='${machine:-unset}')"
  exit 0
fi

probe_enersis_overlay_clean() {
  [ -d "$ENERSIS_SOURCE/.git" ] || return 1
  command -v chezmoi >/dev/null 2>&1 || return 1
  local diff_out
  if ! diff_out="$(chezmoi diff --source "$ENERSIS_SOURCE" 2>/dev/null)"; then
    return 1
  fi
  [ -z "$diff_out" ]
}

if ! command -v git >/dev/null 2>&1; then
  if is_dry_run; then info "P2-12: would: git clone enersis overlay"; exit 0; fi
  error "git not on PATH"; exit 1
fi

if ! command -v chezmoi >/dev/null 2>&1; then
  if is_dry_run; then info "P2-12: would: chezmoi apply --source dotfiles-enersis (Phase 1 installs chezmoi)"; exit 0; fi
  error "chezmoi not on PATH; Phase 1 should have installed it"; exit 1
fi

if probe_enersis_overlay_clean; then
  skip "$step_name: enersis overlay clean"
  exit 0
fi

# Ensure BW_SESSION available (same pattern as P2-10).
if [ -z "${BW_SESSION:-}" ]; then
  if phase2_load_bw_session; then
    info "$step_name: loaded BW_SESSION from session file"
  elif is_dry_run; then
    info "$step_name: dry-run; BW_SESSION not set (would be required for apply)"
  else
    warn "$step_name: BW_SESSION not set; chezmoi apply will fail on bitwardenFields templates -- run P2-00 first"
  fi
fi

# State 1: clone missing OR pull existing.
if [ ! -d "$ENERSIS_SOURCE/.git" ]; then
  if [ -e "$ENERSIS_SOURCE" ]; then
    error "$step_name: $ENERSIS_SOURCE exists but is not a git repo; refusing to overwrite"
    exit 1
  fi
  if is_dry_run; then
    info "$step_name: dry-run; would: git clone $ENERSIS_REPO_URL $ENERSIS_SOURCE"
  else
    info "$step_name: cloning $ENERSIS_REPO_URL -> $ENERSIS_SOURCE"
    mkdir -p "$(dirname -- "$ENERSIS_SOURCE")"
    if ! git clone "$ENERSIS_REPO_URL" "$ENERSIS_SOURCE"; then
      error "$step_name: clone failed for $ENERSIS_REPO_URL"
      error "$step_name: re-run after admiral creates the dotfiles-enersis repo"
      exit 1
    fi
    ok "$step_name: cloned dotfiles-enersis"
  fi
else
  if ! is_dry_run; then
    if git -C "$ENERSIS_SOURCE" pull --ff-only --quiet 2>/dev/null; then
      info "$step_name: pulled latest dotfiles-enersis (origin/main)"
    else
      warn "$step_name: git pull --ff-only failed for $ENERSIS_SOURCE; applying as-is"
    fi
  fi
fi

# State 2: apply overlay.
if is_dry_run; then
  info "$step_name: dry-run; running chezmoi diff against enersis source"
  if [ -d "$ENERSIS_SOURCE/.git" ]; then
    if diff_out="$(chezmoi diff --source "$ENERSIS_SOURCE" 2>&1)"; then
      if [ -n "$diff_out" ]; then
        info "$step_name: dry-run; chezmoi would apply changes:"
        printf '%s\n' "$diff_out" | while IFS= read -r line; do
          info "  $line"
        done
      else
        info "$step_name: dry-run; chezmoi diff is empty"
      fi
    else
      warn "$step_name: dry-run; chezmoi diff exited non-zero"
    fi
  else
    info "$step_name: dry-run; would: chezmoi apply --source $ENERSIS_SOURCE (after clone)"
  fi
  exit 0
fi

info "$step_name: applying enersis overlay via chezmoi apply --source $ENERSIS_SOURCE"
if ! chezmoi apply --source "$ENERSIS_SOURCE"; then
  error "$step_name: chezmoi apply failed against enersis overlay"
  exit 1
fi

if probe_enersis_overlay_clean; then
  ok "$step_name: enersis overlay applied; diff clean"
  exit 0
fi

diff_out="$(chezmoi diff --source "$ENERSIS_SOURCE" 2>&1 || true)"
warn "$step_name: chezmoi diff non-empty after apply (continuing):"
printf '%s\n' "$diff_out" | while IFS= read -r line; do
  warn "  $line"
done
exit 0
