#!/usr/bin/env bash
set -euo pipefail

# Step: 60-clone-self
# Idempotency probe (all of):
#   1. `~/code/personal/dotfiles/.git` is a directory.
#   2. `git -C ~/code/personal/dotfiles remote get-url origin` matches one of:
#        git@github.com:suTerminus/dotfiles.git
#        https://github.com/suTerminus/dotfiles.git
#        https://github.com/suTerminus/dotfiles
#
# Behaviour:
#   - If probe passes: skip. If env PHASE0_UPDATE=1, additionally do
#     `git pull --ff-only` against origin to refresh in-place.
#   - If probe fails: ensure `~/code/personal` exists, then attempt
#     `git clone git@github.com:suTerminus/dotfiles.git`. SSH should be
#     ready because step 40 ran `gh auth login --git-protocol ssh --web`.
#   - If SSH clone fails (common cause: SSH key not yet propagated to
#     GitHub on the remote side), fall back to HTTPS clone. Once that
#     succeeds the user can later swap origin back to SSH:
#       git -C ~/code/personal/dotfiles remote set-url origin \
#         git@github.com:suTerminus/dotfiles.git
#   - Verify the clone contains `phase0/` -- if not, something is wrong
#     with the upstream and we error out.
#   - Write the marker `~/.local/state/macbook-setup/.phase0-complete`
#     so bootstrap.sh and Phase 1 can detect Phase 0 completion.
#
# Depends on step 40 (gh + SSH auth) for the SSH clone path; HTTPS
# fallback works without SSH.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="60-clone-self"

DOTFILES_PARENT="$HOME/code/personal"
DOTFILES_DIR="$DOTFILES_PARENT/dotfiles"
SSH_REMOTE="git@github.com:suTerminus/dotfiles.git"
HTTPS_REMOTE="https://github.com/suTerminus/dotfiles.git"
STATE_DIR="$HOME/.local/state/macbook-setup"
MARKER_FILE="$STATE_DIR/.phase0-complete"

probe_clone_present() {
  [ -d "$DOTFILES_DIR/.git" ] || return 1
  local url
  url="$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || true)"
  case "$url" in
    "git@github.com:suTerminus/dotfiles.git") return 0 ;;
    "https://github.com/suTerminus/dotfiles.git") return 0 ;;
    "https://github.com/suTerminus/dotfiles") return 0 ;;
    *) return 1 ;;
  esac
}

is_update_requested() {
  case "${PHASE0_UPDATE:-0}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

if is_dry_run; then
  if probe_clone_present; then
    info "$step_name: dry-run; clone already present at $DOTFILES_DIR"
    if is_update_requested; then
      info "$step_name: dry-run; would run: git -C \"$DOTFILES_DIR\" pull --ff-only"
    fi
  else
    info "$step_name: dry-run; would mkdir -p \"$DOTFILES_PARENT\""
    info "$step_name: dry-run; would run: git clone $SSH_REMOTE \"$DOTFILES_DIR\""
    info "$step_name: dry-run; on SSH failure would fall back to: git clone $HTTPS_REMOTE \"$DOTFILES_DIR\""
  fi
  info "$step_name: dry-run; would write marker $MARKER_FILE"
  exit 0
fi

if ! require_command git "git not on PATH; install Xcode CLT (step 10) or Brewfile git"; then
  exit 1
fi

if probe_clone_present; then
  skip "$step_name: dotfiles already cloned at $DOTFILES_DIR"
  if is_update_requested; then
    info "$step_name: PHASE0_UPDATE=1 set; running git pull --ff-only"
    if git -C "$DOTFILES_DIR" pull --ff-only; then
      ok "$step_name: dotfiles updated"
    else
      warn "$step_name: git pull --ff-only failed (non-fast-forward or network); leaving as-is"
    fi
  fi
else
  info "$step_name: cloning dotfiles into $DOTFILES_DIR"
  mkdir -p "$DOTFILES_PARENT"

  if git clone "$SSH_REMOTE" "$DOTFILES_DIR"; then
    ok "$step_name: cloned via SSH"
  else
    warn "$step_name: SSH clone failed; falling back to https"
    # Clean up any partial directory the failed SSH clone may have left.
    if [ -d "$DOTFILES_DIR" ] && [ ! -d "$DOTFILES_DIR/.git" ]; then
      rm -rf "$DOTFILES_DIR"
    fi
    if ! git clone "$HTTPS_REMOTE" "$DOTFILES_DIR"; then
      error "$step_name: HTTPS clone also failed -- check network and repo visibility"
      exit 1
    fi
    ok "$step_name: cloned via HTTPS (consider switching origin to SSH later)"
  fi

  if ! probe_clone_present; then
    error "$step_name: clone completed but probe still fails (unexpected origin URL?)"
    exit 2
  fi
fi

# Sanity-check: the clone must contain the phase0 tree we expect.
if [ ! -d "$DOTFILES_DIR/phase0" ]; then
  error "$step_name: clone at $DOTFILES_DIR is missing phase0/ -- repo content unexpected"
  exit 2
fi

# Write the Phase 0 completion marker.
mkdir -p "$STATE_DIR"
touch "$MARKER_FILE"
ok "$step_name: marker written at $MARKER_FILE"

exit 0
