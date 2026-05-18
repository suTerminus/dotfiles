# phase0/lib/idempotent.sh
# Generic probe-then-act wrappers.
# Source after lib/log.sh so the log helpers are available.
# Safe to source multiple times.

if [ -n "${__PHASE0_IDEMPOTENT_SH:-}" ]; then
  return 0
fi
__PHASE0_IDEMPOTENT_SH=1

# Source companion log.sh from the same directory so callers do not
# have to source both manually.
__phase0_idem_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=log.sh
. "${__phase0_idem_dir}/log.sh"

# Ensure Homebrew is visible to this step's subprocess. After step 20
# (20-homebrew) installs brew, its `eval "$(brew shellenv)"` only
# affects step 20's own shell — by the time the orchestrator launches
# step 30 in a fresh subprocess, /opt/homebrew/bin is no longer on PATH.
# Every step sources this lib, so the eval below makes brew visible
# downstream without coupling the orchestrator to step semantics.
if [ -x /opt/homebrew/bin/brew ] && ! command -v brew >/dev/null 2>&1; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# probe_then_act NAME PROBE_CMD ACT_CMD
# Run PROBE_CMD; if it exits 0, log skip and return 0.
# Otherwise run ACT_CMD. Re-probe; if probe still fails, log error
# and return non-zero.
#
# Usage:
#   probe_then_act "homebrew" \
#     "command -v brew >/dev/null" \
#     "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
probe_then_act() {
  local name="$1"; shift
  local probe="$1"; shift
  local act="$1"; shift

  if eval "$probe" >/dev/null 2>&1; then
    skip "$name: already satisfied"
    return 0
  fi

  info "$name: probe failed, applying remediation"
  if ! eval "$act"; then
    error "$name: remediation command exited non-zero"
    return 1
  fi

  if eval "$probe" >/dev/null 2>&1; then
    ok "$name: now satisfied"
    return 0
  fi

  error "$name: probe still fails after remediation"
  return 2
}

# is_dry_run -- returns 0 if PHASE0_DRY_RUN env var is set to a truthy value.
# Steps consult this and short-circuit any state-changing command.
is_dry_run() {
  case "${PHASE0_DRY_RUN:-0}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# require_command CMD MESSAGE
# Hard-fails the step if CMD is not on PATH.
require_command() {
  local cmd="$1"
  local msg="${2:-required command \"$cmd\" not found on PATH}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "$msg"
    return 1
  fi
  return 0
}

# require_tty_stdin MESSAGE
# Hard-fails the step if stdin is not a TTY. Use before any interactive
# command that silently misbehaves on piped or closed stdin: gh's
# `auth login` SSH-key prompt is skipped over non-TTY (so no key is
# generated or uploaded), and `read -p` returns immediately on EOF (so
# "Press Enter to continue" pauses don't actually pause). The
# orchestrator hands /dev/tty to each step when it's available; this
# guard catches the case where it isn't (e.g. piped stdin in CI, or a
# step invoked manually with `< /dev/null`).
require_tty_stdin() {
  local msg="${1:-stdin is not a TTY; this step requires an interactive terminal}"
  if [ ! -t 0 ]; then
    error "$msg"
    return 1
  fi
  return 0
}
