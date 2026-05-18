#!/usr/bin/env bash
set -euo pipefail

# Step: P2-00-bitwarden-unlock
# Idempotency probe: `bw status` reports `.status == "unlocked"`.
#
# Behaviour:
#   - probe passes -> skip.
#   - bw missing   -> hard-fail (Phase 1 Brewfile installs it).
#   - unauthenticated -> require_tty_stdin; under dry-run log `would: bw login`;
#     else `bw login`. After bw login the user must re-run the step to unlock.
#   - locked       -> require_tty_stdin; under dry-run log `would: bw unlock --raw`;
#     else `bw unlock --raw` -> capture session token to a 0600-mode file at
#     ~/.local/state/macbook-setup/bw-session, export BW_SESSION, register a
#     cleanup trap on EXIT/SIGINT/SIGTERM that unlinks the file.
#
# Security:
#   - Session token is NEVER written to stdout, log, or exported via printf.
#   - The token is captured into a local with bw unlock --raw, then redirected
#     into the session file with `printf '%s' "$session" > "$file"` after
#     the file is pre-created with mode 0600 so no race exposes it.
#   - Trap unlinks the file on step exit. Note: this fires when *this step*
#     exits, not when the orchestrator/setup.sh exits, so the session file
#     may persist for the life of the orchestrator. This is intentional --
#     downstream Phase 2 steps (P2-10, P2-12) need to source it. The
#     orchestrator-level trap is a future improvement; for now we accept
#     that the session file may persist for the life of `setup.sh`.
#
# Re-running: if the session file exists and `bw status` (with that session
# in env) reports unlocked, the step skips without prompting. If the
# session is stale, the file is unlinked and the step falls through to
# unlock again.
#
# Depends on: bw installed by Phase 1 public Brewfile (`bitwarden-cli` cask).
#
# Standalone-runnable: sources lib/log.sh, lib/idempotent.sh, lib/phase2.sh
# via SCRIPT_DIR so it works without the orchestrator.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"
# shellcheck source=../lib/phase2.sh
. "$SCRIPT_DIR/../lib/phase2.sh"

step_name="P2-00-bitwarden-unlock"

STATE_DIR="$HOME/.local/state/macbook-setup"
SESSION_FILE="$STATE_DIR/bw-session"

# probe_bw_unlocked
# Returns 0 iff `bw status` says `unlocked`. Honors $BW_SESSION when set
# (so we can validate a session loaded from the session file).
probe_bw_unlocked() {
  command -v bw >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local raw status
  raw="$(bw status 2>/dev/null || true)"
  [ -n "$raw" ] || return 1
  status="$(printf '%s' "$raw" | jq -r '.status // empty' 2>/dev/null || true)"
  [ "$status" = "unlocked" ]
}

# probe_bw_status_field
# Echo the .status field from `bw status` (unauthenticated|locked|unlocked|"").
probe_bw_status_field() {
  command -v bw >/dev/null 2>&1 || { printf ''; return 1; }
  command -v jq >/dev/null 2>&1 || { printf ''; return 1; }
  bw status 2>/dev/null | jq -r '.status // empty' 2>/dev/null || true
}

# write_session_file SESSION
# Pre-create the session file with mode 0600, then write the session
# value with printf (no echo, no logging of the value).
write_session_file() {
  local session="$1"
  mkdir -p "$STATE_DIR"
  # Use a strict umask while creating the file so it can't briefly exist
  # world-readable. Restore umask in a subshell.
  (
    umask 077
    : > "$SESSION_FILE"
  )
  chmod 600 "$SESSION_FILE" 2>/dev/null || true
  printf '%s' "$session" > "$SESSION_FILE"
  chmod 600 "$SESSION_FILE" 2>/dev/null || true
}

# cleanup trap. Unlinks the session file on step exit. We register early
# (before any path that writes the file) so a SIGINT mid-write still
# triggers cleanup. The trap is a no-op if the file doesn't exist.
cleanup_session_file() {
  if [ -f "$SESSION_FILE" ]; then
    rm -f "$SESSION_FILE" 2>/dev/null || true
  fi
}

# Hook the trap up front. Using ERR is intentionally omitted so a probe
# failure doesn't drop the session file the user just unlocked.
trap cleanup_session_file EXIT
trap 'cleanup_session_file; exit 130' INT
trap 'cleanup_session_file; exit 143' TERM

if ! command -v bw >/dev/null 2>&1; then
  if is_dry_run; then
    info "P2-00: would: bw status / unlock (bw not yet on PATH; Phase 1 brew bundle installs bitwarden-cli first)"
    trap - EXIT INT TERM
    exit 0
  fi
  error "bw not on PATH; ensure Phase 1 Brewfile installed bitwarden-cli"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  if is_dry_run; then
    info "P2-00: would: jq parse of bw status (jq not yet on PATH; Phase 1 installs it)"
    trap - EXIT INT TERM
    exit 0
  fi
  error "jq not on PATH; ensure Phase 1 Brewfile installed jq"
  exit 1
fi

# If a previous step in this run left a session file, prefer reusing it
# rather than re-prompting. Validate by setting BW_SESSION and re-probing.
if [ -f "$SESSION_FILE" ] && [ -z "${BW_SESSION:-}" ]; then
  if phase2_load_bw_session; then
    if probe_bw_unlocked; then
      # Disarm the trap so we don't unlink the still-good file when this
      # step exits; downstream steps need it.
      trap - EXIT INT TERM
      skip "$step_name: existing session valid"
      exit 0
    fi
    # Stale session -- drop it and fall through.
    rm -f "$SESSION_FILE" 2>/dev/null || true
    unset BW_SESSION
  fi
fi

# Fast path: probe without any session in env.
if probe_bw_unlocked; then
  trap - EXIT INT TERM
  skip "$step_name: bw already unlocked"
  exit 0
fi

# Need to act -- examine status and branch.
status_field="$(probe_bw_status_field || true)"

case "$status_field" in
  unauthenticated)
    if is_dry_run; then
      info "$step_name: dry-run; would: bw login"
      trap - EXIT INT TERM
      exit 0
    fi
    if ! require_tty_stdin "$step_name: stdin is not a TTY; bw login needs an interactive terminal -- re-run from one"; then
      exit 2
    fi
    info "$step_name: bw is unauthenticated; running bw login (interactive: email + master password + 2FA)"
    if ! bw login; then
      error "$step_name: bw login failed"
      exit 1
    fi
    info "$step_name: bw login complete; re-run this step to unlock"
    # Disarm trap: there's nothing to clean up, and we want the user to
    # re-run cleanly.
    trap - EXIT INT TERM
    exit 0
    ;;
  locked|"")
    # Treat empty/missing status the same as locked: try to unlock. This
    # also covers the case where bw status itself errored transiently.
    if is_dry_run; then
      info "$step_name: dry-run; would: bw unlock --raw and write session to $SESSION_FILE (mode 0600)"
      trap - EXIT INT TERM
      exit 0
    fi
    if ! require_tty_stdin "$step_name: stdin is not a TTY; bw unlock needs an interactive terminal -- re-run from one"; then
      exit 2
    fi
    info "$step_name: bw is locked; running bw unlock --raw (you will be prompted for the master password)"
    local_session=""
    if ! local_session="$(bw unlock --raw)"; then
      error "$step_name: bw unlock --raw exited non-zero"
      exit 1
    fi
    if [ -z "$local_session" ]; then
      error "$step_name: bw unlock --raw returned empty session"
      exit 1
    fi

    write_session_file "$local_session"
    BW_SESSION="$local_session"
    export BW_SESSION
    # Scrub the local immediately so it's not visible in any later trap
    # context.
    local_session=""
    unset local_session

    if ! probe_bw_unlocked; then
      error "$step_name: bw still reports locked after unlock"
      exit 2
    fi

    # Disarm the cleanup trap so the session persists for downstream
    # Phase 2 steps in the same orchestrator run. The orchestrator (or
    # the user manually) is responsible for unlinking the file at the
    # end of the run; see header comment.
    trap - EXIT INT TERM
    ok "$step_name: bw unlocked; session persisted (mode 0600)"
    exit 0
    ;;
  unlocked)
    # Race: status flipped between probe and case. Re-probe.
    if probe_bw_unlocked; then
      trap - EXIT INT TERM
      skip "$step_name: bw already unlocked"
      exit 0
    fi
    error "$step_name: bw status reported unlocked but probe failed; check bw configuration"
    exit 2
    ;;
  *)
    error "$step_name: unrecognized bw status: $status_field"
    exit 2
    ;;
esac
