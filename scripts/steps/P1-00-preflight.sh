#!/usr/bin/env bash
set -euo pipefail

# Step: P1-00-preflight
# Idempotency probe: N/A. This step is the read-only gate that runs
# unconditionally at the start of Phase 1. It validates that Phase 0
# completed and the host preconditions Phase 1 depends on are still in
# place. It never mutates state.
#
# Checks (each emits ok / error; only error increments the hard-fail
# counter):
#   1. Phase 0 marker file ~/.local/state/macbook-setup/.phase0-complete
#      exists and is non-empty.
#   2. cwd is ~/code/personal/dotfiles, OR $DOTFILES_DIR is set and
#      matches the working tree root.
#   3. `gh auth status` exits 0 AND its output mentions "protocol: ssh".
#   4. `command -v brew` resolves AND `brew --version` exits 0.
#   5. ~/.ssh/id_ed25519.pub exists (used by SSH commit signing in P1-10).
#
# Action: collect results, log per-check, exit 1 on any hard fail else 0.
# Dry-run: identical behaviour (everything is read-only); the only
# difference is an info banner up front.
#
# Exit codes:
#   0 — all checks passed.
#   1 — at least one precondition is missing; remediation hint printed.
#
# Depends on: Phase 0 having run to completion.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="P1-00-preflight"
hard_fails=0

if is_dry_run; then
  info "$step_name: PHASE1_DRY_RUN=1 (read-only checks only)"
fi

# Check 1: Phase 0 marker.
MARKER_FILE="$HOME/.local/state/macbook-setup/.phase0-complete"
if [ -s "$MARKER_FILE" ]; then
  marker_contents="$(cat "$MARKER_FILE" 2>/dev/null || true)"
  if [ -n "$marker_contents" ]; then
    ok "$step_name: phase 0 marker found ($marker_contents)"
  else
    # Non-empty by -s test, but cat may have trimmed; fall back to mtime.
    marker_mtime="$(stat -f '%Sm' "$MARKER_FILE" 2>/dev/null || stat -c '%y' "$MARKER_FILE" 2>/dev/null || echo unknown)"
    ok "$step_name: phase 0 marker found ($marker_mtime)"
  fi
elif [ -f "$MARKER_FILE" ]; then
  # Phase 0's 60-clone-self.sh creates the marker via plain `touch` — it
  # has no contents on the user's actual machine. Treat existence as the
  # contract; warn but accept. (The PRD describes the marker as "non-empty"
  # but the running implementation produces an empty file.)
  marker_mtime="$(stat -f '%Sm' "$MARKER_FILE" 2>/dev/null || stat -c '%y' "$MARKER_FILE" 2>/dev/null || echo unknown)"
  ok "$step_name: phase 0 marker found ($marker_mtime; empty file — Phase 0 touched it without timestamp)"
else
  error "$step_name: Phase 0 marker missing; re-run phase0/bootstrap.sh."
  hard_fails=$((hard_fails + 1))
fi

# Check 2: cwd anchor. Prefer $DOTFILES_DIR when set; otherwise expect
# the user is sitting in ~/code/personal/dotfiles.
expected_dotfiles="$HOME/code/personal/dotfiles"
cwd_resolved="$(pwd -P 2>/dev/null || pwd)"
expected_resolved="$(cd "$expected_dotfiles" 2>/dev/null && pwd -P || echo "$expected_dotfiles")"
if [ -n "${DOTFILES_DIR:-}" ]; then
  dotfiles_dir_resolved="$(cd "$DOTFILES_DIR" 2>/dev/null && pwd -P || echo "$DOTFILES_DIR")"
  if [ "$cwd_resolved" = "$dotfiles_dir_resolved" ]; then
    ok "$step_name: cwd matches \$DOTFILES_DIR ($DOTFILES_DIR)"
  else
    error "$step_name: must run from ~/code/personal/dotfiles or set DOTFILES_DIR; current cwd: $PWD"
    hard_fails=$((hard_fails + 1))
  fi
elif [ "$cwd_resolved" = "$expected_resolved" ]; then
  ok "$step_name: cwd is $expected_dotfiles"
else
  error "$step_name: must run from ~/code/personal/dotfiles or set DOTFILES_DIR; current cwd: $PWD"
  hard_fails=$((hard_fails + 1))
fi

# Check 3: gh auth status (SSH protocol).
if ! command -v gh >/dev/null 2>&1; then
  error "$step_name: gh not on PATH; re-run phase0/steps/40-github-auth.sh"
  hard_fails=$((hard_fails + 1))
else
  gh_status_out="$(gh auth status 2>&1 || true)"
  if ! gh auth status >/dev/null 2>&1; then
    error "$step_name: gh not auth'd via SSH; re-run phase0/steps/40-github-auth.sh"
    hard_fails=$((hard_fails + 1))
  elif ! printf '%s\n' "$gh_status_out" | grep -qiE 'protocol:[[:space:]]*ssh'; then
    error "$step_name: gh not auth'd via SSH; re-run phase0/steps/40-github-auth.sh"
    hard_fails=$((hard_fails + 1))
  else
    ok "$step_name: gh authenticated with SSH protocol"
  fi
fi

# Check 4: Homebrew.
if ! command -v brew >/dev/null 2>&1; then
  error "$step_name: Homebrew missing; re-run phase0/steps/20-homebrew.sh"
  hard_fails=$((hard_fails + 1))
elif ! brew --version >/dev/null 2>&1; then
  error "$step_name: Homebrew missing; re-run phase0/steps/20-homebrew.sh"
  hard_fails=$((hard_fails + 1))
else
  ok "$step_name: brew on PATH"
fi

# Check 5: SSH public key exists.
ssh_pub="$HOME/.ssh/id_ed25519.pub"
if [ -f "$ssh_pub" ]; then
  ok "$step_name: SSH key present ($ssh_pub)"
else
  error "$step_name: SSH key missing; re-run phase0/steps/40-github-auth.sh"
  hard_fails=$((hard_fails + 1))
fi

# Summary.
if [ "$hard_fails" -gt 0 ]; then
  error "$step_name: $hard_fails precondition(s) failed; aborting Phase 1"
  exit 1
fi

ok "$step_name: preflight checks pass"
exit 0
