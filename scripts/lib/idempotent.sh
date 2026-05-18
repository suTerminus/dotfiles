# scripts/lib/idempotent.sh
# Generic probe-then-act wrappers, plus Phase 1 per-tool / per-repo probes.
# Source after lib/log.sh so the log helpers are available.
# Safe to source multiple times.

if [ -n "${__PHASE1_IDEMPOTENT_SH:-}" ]; then
  return 0
fi
__PHASE1_IDEMPOTENT_SH=1

# Source companion log.sh from the same directory so callers do not
# have to source both manually.
__phase1_idem_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=log.sh
. "${__phase1_idem_dir}/log.sh"

# Ensure Homebrew is visible to this step's subprocess. After Phase 0's
# 20-homebrew step installs brew, its `eval "$(brew shellenv)"` only
# affects that step's own shell — by the time the orchestrator launches
# a Phase 1 step in a fresh subprocess, /opt/homebrew/bin is no longer
# on PATH. Every step sources this lib, so the eval below makes brew
# visible downstream without coupling the orchestrator to step semantics.
if [ -x /opt/homebrew/bin/brew ] && ! command -v brew >/dev/null 2>&1; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# probe_then_act NAME PROBE_CMD ACT_CMD
# Run PROBE_CMD; if it exits 0, log skip and return 0.
# Otherwise run ACT_CMD. Re-probe; if probe still fails, log error
# and return non-zero.
#
# Usage:
#   probe_then_act "brew bundle" \
#     "brew bundle check --file=$HOME/.config/brew/Brewfile" \
#     "brew bundle --file=$HOME/.config/brew/Brewfile"
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

# is_dry_run -- returns 0 if PHASE1_DRY_RUN env var is set to a truthy value.
# Steps consult this and short-circuit any state-changing command.
is_dry_run() {
  case "${PHASE1_DRY_RUN:-0}" in
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

# ---------------------------------------------------------------------------
# Phase 1 extension probes
# ---------------------------------------------------------------------------
# These wrap the per-tool / per-repo idempotency checks listed in
# Phase 1 PRD §8 and §9. They are intentionally quiet on the "not
# installed" path (no log output) so callers can compose them inside
# probe_then_act without producing duplicate `[INFO]` lines.

# probe_mise_tool TOOL EXPECTED_VERSION
# Returns 0 iff `mise current <tool>` reports a version string containing
# EXPECTED_VERSION. Tolerates mise being absent from PATH (returns 1
# quietly) so callers can use this as the probe in probe_then_act.
probe_mise_tool() {
  local tool="$1"
  local expected="$2"
  if ! command -v mise >/dev/null 2>&1; then
    return 1
  fi
  local current
  if ! current="$(mise current "$tool" 2>/dev/null)"; then
    return 1
  fi
  case "$current" in
    *"$expected"*) return 0 ;;
    *)             return 1 ;;
  esac
}

# probe_uv_tool PKG
# Returns 0 iff `uv tool list` mentions PKG. Tolerates uv being absent
# from PATH (returns 1 quietly).
probe_uv_tool() {
  local pkg="$1"
  if ! command -v uv >/dev/null 2>&1; then
    return 1
  fi
  uv tool list 2>/dev/null | grep -qi -E "(^|[[:space:]])${pkg}([[:space:]]|$)"
}

# probe_repo_at_path PATH EXPECTED_URL
# Returns 0 iff PATH is a directory containing .git and its origin
# remote URL matches EXPECTED_URL. Tolerates trailing slashes and the
# .git suffix; comparison is case-insensitive (GitHub URLs are
# case-insensitive on the host portion and we treat the whole URL the
# same way for simplicity).
probe_repo_at_path() {
  local path="$1"
  local expected="$2"
  [ -d "$path" ] || return 1
  [ -d "$path/.git" ] || return 1
  command -v git >/dev/null 2>&1 || return 1
  local actual
  if ! actual="$(git -C "$path" remote get-url origin 2>/dev/null)"; then
    return 1
  fi
  # Normalize: lowercase, strip trailing slash, strip trailing .git
  local na ne
  na="$(printf '%s' "$actual"   | tr '[:upper:]' '[:lower:]')"
  ne="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"
  na="${na%/}"; na="${na%.git}"
  ne="${ne%/}"; ne="${ne%.git}"
  [ "$na" = "$ne" ]
}
