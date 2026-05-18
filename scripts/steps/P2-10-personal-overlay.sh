#!/usr/bin/env bash
set -euo pipefail

# Step: P2-10-personal-overlay
# Idempotency probe (all of):
#   1. ~/.local/share/chezmoi-private/.git exists.
#   2. `chezmoi diff --source ~/.local/share/chezmoi-private` returns empty.
#
# Behaviour:
#   - probe passes -> skip.
#   - clone missing -> git clone git@github.com:suTerminus/dotfiles-private.git
#     ~/.local/share/chezmoi-private (under dry-run: log `would:`).
#     Hard-fail with a clear message if clone fails (admiral creates the
#     repo at integration time).
#   - apply overlay -> chezmoi apply --source <PRIVATE>. Requires
#     BW_SESSION (P2-00 sets it; we source the persisted session file as
#     a fallback for standalone-runs).
#   - re-probe diff -> non-empty: warn (don't fail).
#
# Depends on: P2-00 having unlocked Bitwarden. Standalone-runnable;
# sources lib/log.sh, lib/idempotent.sh, lib/phase2.sh via SCRIPT_DIR.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"
# shellcheck source=../lib/phase2.sh
. "$SCRIPT_DIR/../lib/phase2.sh"

step_name="P2-10-personal-overlay"

PRIVATE_SOURCE="$HOME/.local/share/chezmoi-private"
PRIVATE_REPO_URL="git@github.com:suTerminus/dotfiles-private.git"

probe_personal_overlay_clean() {
  [ -d "$PRIVATE_SOURCE/.git" ] || return 1
  command -v chezmoi >/dev/null 2>&1 || return 1
  local diff_out
  if ! diff_out="$(chezmoi diff --source "$PRIVATE_SOURCE" 2>/dev/null)"; then
    return 1
  fi
  [ -z "$diff_out" ]
}

if ! command -v git >/dev/null 2>&1; then
  if is_dry_run; then info "P2-10: would: git clone (git not on PATH yet)"; exit 0; fi
  error "git not on PATH"; exit 1
fi

if ! command -v chezmoi >/dev/null 2>&1; then
  if is_dry_run; then info "P2-10: would: chezmoi apply --source dotfiles-private (chezmoi not yet on PATH; Phase 1 installs it)"; exit 0; fi
  error "chezmoi not on PATH; Phase 1 should have installed it"; exit 1
fi

if probe_personal_overlay_clean; then
  skip "$step_name: personal overlay clean"
  exit 0
fi

# Ensure BW_SESSION is in env -- chezmoi templates with bitwardenFields
# need it. Tolerate missing session under dry-run; warn under real run.
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
if [ ! -d "$PRIVATE_SOURCE/.git" ]; then
  if [ -e "$PRIVATE_SOURCE" ]; then
    error "$step_name: $PRIVATE_SOURCE exists but is not a git repo; refusing to overwrite"
    exit 1
  fi
  if is_dry_run; then
    info "$step_name: dry-run; would: git clone $PRIVATE_REPO_URL $PRIVATE_SOURCE"
  else
    info "$step_name: cloning $PRIVATE_REPO_URL -> $PRIVATE_SOURCE"
    mkdir -p "$(dirname -- "$PRIVATE_SOURCE")"
    if ! git clone "$PRIVATE_REPO_URL" "$PRIVATE_SOURCE"; then
      error "$step_name: clone failed for $PRIVATE_REPO_URL"
      error "$step_name: re-run after admiral creates the dotfiles-private repo"
      exit 1
    fi
    ok "$step_name: cloned dotfiles-private"
  fi
else
  # Existing clone: ff-pull so the source state matches origin before
  # apply. Skip silently under dry-run.
  if ! is_dry_run; then
    if git -C "$PRIVATE_SOURCE" pull --ff-only --quiet 2>/dev/null; then
      info "$step_name: pulled latest dotfiles-private (origin/main)"
    else
      warn "$step_name: git pull --ff-only failed for $PRIVATE_SOURCE (local diverged or offline); applying as-is"
    fi
  fi
fi

# State 2: apply overlay.
if is_dry_run; then
  info "$step_name: dry-run; running chezmoi diff (read-only) against personal source"
  if [ -d "$PRIVATE_SOURCE/.git" ]; then
    if diff_out="$(chezmoi diff --source "$PRIVATE_SOURCE" 2>&1)"; then
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
    info "$step_name: dry-run; would: chezmoi apply --source $PRIVATE_SOURCE (after clone)"
  fi
  exit 0
fi

info "$step_name: applying personal overlay via chezmoi apply --source $PRIVATE_SOURCE"
if ! chezmoi apply --source "$PRIVATE_SOURCE"; then
  error "$step_name: chezmoi apply failed against personal overlay"
  exit 1
fi

# Re-probe.
if probe_personal_overlay_clean; then
  ok "$step_name: personal overlay applied; diff clean"
  exit 0
fi

# Diff non-empty after apply -- warn but don't fail. This can happen when
# templates produce machine-conditional content the diff display flags
# as drift on first apply.
diff_out="$(chezmoi diff --source "$PRIVATE_SOURCE" 2>&1 || true)"
warn "$step_name: chezmoi diff non-empty after apply (continuing):"
printf '%s\n' "$diff_out" | while IFS= read -r line; do
  warn "  $line"
done
exit 0
