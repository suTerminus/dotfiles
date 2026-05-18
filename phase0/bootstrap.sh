#!/usr/bin/env bash
# phase0/bootstrap.sh
# Phase 0 orchestrator: curl|bash entry point for a fresh MacBook.
# Iterates phase0/steps/*.sh in numeric order, capturing per-step
# status, duration, and a summary table. Idempotent and standalone.
#
# Usage:
#   bash phase0/bootstrap.sh [flags]
#   curl -fsSL <raw-url>/phase0/bootstrap.sh | bash
#
# See PRD section 4 for the full contract.

set -euo pipefail

# --------------------------------------------------------------------
# Resolve SCRIPT_DIR. When invoked via `curl | bash`, BASH_SOURCE[0]
# may be empty or unreadable. In that case we fall back to a sensible
# default (the canonical clone location) if it exists, otherwise a
# tmp path that callers can ignore.
# --------------------------------------------------------------------
__resolve_script_dir() {
  local src="${BASH_SOURCE[0]:-}"
  if [ -n "$src" ] && [ -f "$src" ]; then
    cd -- "$(dirname -- "$src")" && pwd
    return 0
  fi
  # Fallback: stdin pipeline. Prefer the canonical clone if present.
  local canonical="$HOME/code/personal/dotfiles/phase0"
  if [ -d "$canonical" ]; then
    printf '%s\n' "$canonical"
    return 0
  fi
  printf '%s\n' "/tmp"
  return 0
}

SCRIPT_DIR="$(__resolve_script_dir)"
SCRIPT_PATH="${BASH_SOURCE[0]:-}"

# --------------------------------------------------------------------
# Inline log helpers. Defined unconditionally so they are available
# before lib/log.sh is sourced (e.g. during the stdin-mode fetch below).
# lib/log.sh defines identical helpers under a source guard, so sourcing
# it later is a no-op.
# --------------------------------------------------------------------
info()  { printf '[INFO] %s\n' "$*" >&2; }
ok()    { printf '[OK]   %s\n' "$*" >&2; }
skip()  { printf '[SKIP] %s\n' "$*" >&2; }
warn()  { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERR]  %s\n' "$*" >&2; }

# Source library helpers if reachable. In stdin mode without a local
# clone they will not be — the fetch path below pulls them in, and we
# re-source after. The inline helpers above cover the gap.
if [ -r "$SCRIPT_DIR/lib/log.sh" ]; then
  # shellcheck source=lib/log.sh
  . "$SCRIPT_DIR/lib/log.sh"
fi
if [ -r "$SCRIPT_DIR/lib/idempotent.sh" ]; then
  # shellcheck source=lib/idempotent.sh
  . "$SCRIPT_DIR/lib/idempotent.sh"
fi

# --------------------------------------------------------------------
# Stdin-mode fetch. When invoked via `curl … | bash` on a fresh machine,
# only bootstrap.sh arrives over the wire — the rest of phase0/ does not
# exist yet. Pull lib/, Brewfile, claude-settings, and steps/* from the
# raw GitHub URL into a tempdir, then point SCRIPT_DIR at it so the
# orchestrator runs against real files. Override the source via
# PHASE0_RAW_URL_BASE for forks/branches.
# --------------------------------------------------------------------
PHASE0_RAW_URL_BASE="${PHASE0_RAW_URL_BASE:-https://raw.githubusercontent.com/suTerminus/dotfiles/main/phase0}"

__stdin_fetch_files() {
  if ! command -v curl >/dev/null 2>&1; then
    error "stdin mode: curl not on PATH; cannot fetch phase0 files"
    return 1
  fi
  local tmpdir
  tmpdir="$(mktemp -d -t phase0-XXXXXX)" || return 1
  mkdir -p "$tmpdir/lib" "$tmpdir/steps" || { rm -rf "$tmpdir"; return 1; }

  local files=(
    lib/log.sh
    lib/idempotent.sh
    Brewfile
    claude-settings-bootstrap.json
    steps/00-preflight.sh
    steps/10-xcode-clt.sh
    steps/20-homebrew.sh
    steps/30-phase0-brew.sh
    steps/40-github-auth.sh
    steps/50-claude-code.sh
    steps/60-clone-self.sh
  )

  info "stdin mode: fetching phase0 files from $PHASE0_RAW_URL_BASE"
  local f
  for f in "${files[@]}"; do
    if ! curl -fsSL --max-time 30 -o "$tmpdir/$f" "$PHASE0_RAW_URL_BASE/$f"; then
      error "failed to fetch $PHASE0_RAW_URL_BASE/$f"
      rm -rf "$tmpdir"
      return 1
    fi
  done
  chmod +x "$tmpdir/steps/"*.sh 2>/dev/null || true
  SCRIPT_DIR="$tmpdir"
  return 0
}

# --------------------------------------------------------------------
# Self-rexec optimization (PRD section 4).
# If a local clone exists at ~/code/personal/dotfiles/phase0/bootstrap.sh
# AND its sha256 matches the currently executing script, exec the local
# copy. Skip when we're already running from that path (no infinite
# loop) or when we cannot compute a sha256 of ourselves (e.g. piped).
# --------------------------------------------------------------------
__maybe_self_rexec() {
  local local_copy="$HOME/code/personal/dotfiles/phase0/bootstrap.sh"
  [ -r "$local_copy" ] || return 0
  # Already running from the local copy? Bail out to avoid loops.
  if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
    local self_abs
    self_abs="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)/$(basename -- "$SCRIPT_PATH")"
    if [ "$self_abs" = "$local_copy" ]; then
      return 0
    fi
  fi
  # Need shasum or sha256sum to compare.
  local hasher=""
  if command -v shasum >/dev/null 2>&1; then
    hasher="shasum -a 256"
  elif command -v sha256sum >/dev/null 2>&1; then
    hasher="sha256sum"
  else
    return 0
  fi
  # Hash the local copy.
  local local_hash=""
  local_hash="$($hasher "$local_copy" 2>/dev/null | awk '{print $1}')" || return 0
  [ -n "$local_hash" ] || return 0
  # Hash the currently executing script if we have a real file; otherwise
  # we cannot compare, so just use the local copy (curl|bash case).
  if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
    local self_hash=""
    self_hash="$($hasher "$SCRIPT_PATH" 2>/dev/null | awk '{print $1}')" || return 0
    if [ "$self_hash" = "$local_hash" ]; then
      info "self-rexec: handing off to $local_copy"
      exec bash "$local_copy" "$@"
    fi
    return 0
  fi
  # curl|bash case: no real file to hash. Prefer the local copy.
  info "self-rexec (curl|bash): handing off to $local_copy"
  exec bash "$local_copy" "$@"
}

# --------------------------------------------------------------------
# Flag parsing.
# --------------------------------------------------------------------
print_usage() {
  cat <<'USAGE'
Usage: bootstrap.sh [flags]

Phase 0 orchestrator. Iterates phase0/steps/*.sh in numeric order.

Flags:
  --only STEP      Run only the given step (basename or numeric prefix).
                   Repeatable.
  --skip STEP      Skip the given step. Repeatable. Wins over --only.
  --dry-run        Set PHASE0_DRY_RUN=1 and propagate to step scripts.
  --fail-fast      Stop on the first failing step (default: continue).
  --update         Passed through to 60-clone-self.sh to re-pull.
  -h, --help       Print this message and exit 0.

Exit codes:
  0  all steps ok (or skipped)
  1  one or more steps failed
  2  invalid flag usage
USAGE
}

ONLY_LIST=()
SKIP_LIST=()
FAIL_FAST=0
UPDATE=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --only)
      [ $# -ge 2 ] || { error "--only requires an argument"; print_usage >&2; exit 2; }
      ONLY_LIST+=("$2")
      shift 2
      ;;
    --only=*)
      ONLY_LIST+=("${1#--only=}")
      shift
      ;;
    --skip)
      [ $# -ge 2 ] || { error "--skip requires an argument"; print_usage >&2; exit 2; }
      SKIP_LIST+=("$2")
      shift 2
      ;;
    --skip=*)
      SKIP_LIST+=("${1#--skip=}")
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --fail-fast)
      FAIL_FAST=1
      shift
      ;;
    --update)
      UPDATE=1
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      error "unknown flag: $1"
      print_usage >&2
      exit 2
      ;;
  esac
done

if [ "$DRY_RUN" -eq 1 ]; then
  export PHASE0_DRY_RUN=1
fi
if [ "$UPDATE" -eq 1 ]; then
  export PHASE0_UPDATE=1
fi

# If we are in stdin mode without a local clone (no steps/ adjacent),
# fetch the rest of phase0/ from the raw URL before going further.
# Done after flag parsing so `--help` short-circuits without network.
if [ ! -d "$SCRIPT_DIR/steps" ]; then
  if ! __stdin_fetch_files; then
    error "phase0 fetch failed; check network and rerun"
    exit 1
  fi
  # Pull in the freshly fetched libs (idempotent due to internal guards
  # — but the inline helpers from the top of this script also work).
  # shellcheck source=lib/log.sh
  . "$SCRIPT_DIR/lib/log.sh"
  # shellcheck source=lib/idempotent.sh
  . "$SCRIPT_DIR/lib/idempotent.sh"
fi

# Run self-rexec only after parsing flags so we can pass them through.
__maybe_self_rexec "$@"

# --------------------------------------------------------------------
# Log file setup.
# --------------------------------------------------------------------
LOG_DIR="$HOME/.local/state/macbook-setup"
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
  error "could not create log directory: $LOG_DIR"
  exit 1
fi
LOG_FILE="$LOG_DIR/phase0-$(date +%Y%m%d_%H%M%S).log"
: > "$LOG_FILE" || { error "could not write to log file: $LOG_FILE"; exit 1; }

info "phase0 bootstrap starting"
info "log file: $LOG_FILE"
info "script dir: $SCRIPT_DIR"
[ "$DRY_RUN" -eq 1 ] && info "DRY RUN mode (PHASE0_DRY_RUN=1)"

# --------------------------------------------------------------------
# Discover steps.
# --------------------------------------------------------------------
STEPS_DIR="$SCRIPT_DIR/steps"
STEPS=()
if [ -d "$STEPS_DIR" ]; then
  # Use LC_ALL=C sort to guarantee numeric-prefix order.
  while IFS= read -r f; do
    [ -n "$f" ] && STEPS+=("$f")
  done < <(LC_ALL=C find "$STEPS_DIR" -maxdepth 1 -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort)
fi

if [ "${#STEPS[@]}" -eq 0 ]; then
  warn "no steps found in phase0/steps/"
  exit 0
fi

# --------------------------------------------------------------------
# Selection helpers.
# --------------------------------------------------------------------
# Return 0 if NEEDLE matches step BASENAME by either:
#   - exact basename match (with or without .sh)
#   - numeric prefix match (e.g. "10" matches "10-homebrew.sh")
__step_matches() {
  local needle="$1"
  local base="$2"
  local trimmed="${base%.sh}"
  if [ "$needle" = "$base" ] || [ "$needle" = "$trimmed" ]; then
    return 0
  fi
  # Numeric prefix?
  case "$needle" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$base" in
    "${needle}"-*|"${needle}"_*) return 0 ;;
  esac
  return 1
}

__should_run() {
  local base="$1"
  # --skip wins.
  local n
  for n in "${SKIP_LIST[@]+"${SKIP_LIST[@]}"}"; do
    if __step_matches "$n" "$base"; then
      return 1
    fi
  done
  # No --only constraints -> run everything not skipped.
  if [ "${#ONLY_LIST[@]}" -eq 0 ]; then
    return 0
  fi
  for n in "${ONLY_LIST[@]+"${ONLY_LIST[@]}"}"; do
    if __step_matches "$n" "$base"; then
      return 0
    fi
  done
  return 1
}

# --------------------------------------------------------------------
# Run steps and collect status.
# --------------------------------------------------------------------
NAMES=()
STATUSES=()
DURATIONS=()
EXITS=()

OVERALL_FAIL=0
TOTAL_DURATION=0

for step in "${STEPS[@]}"; do
  base="$(basename -- "$step")"
  if ! __should_run "$base"; then
    NAMES+=("$base")
    STATUSES+=("skip")
    DURATIONS+=("0")
    EXITS+=("0")
    skip "$base: excluded by --only/--skip"
    continue
  fi

  printf '\n' >&2
  printf '=== Step: %s ===\n' "$base" >&2

  start_ts=$(date +%s)
  rc=0
  # Build args to pass through to the step. --update goes only to clone-self,
  # but it's harmless for steps to ignore unknown env, so we use env vars.
  # Hand /dev/tty to the step's stdin so interactive prompts work even
  # when bootstrap was invoked via `curl | bash` (whose own stdin is the
  # curl pipe, not a TTY). Without this, gh auth login silently skips
  # its SSH-key prompt and `read -p` pauses return instantly on EOF.
  set +e
  if [ -r /dev/tty ]; then
    bash "$step" </dev/tty 2>&1 | tee -a "$LOG_FILE"
  else
    bash "$step" 2>&1 | tee -a "$LOG_FILE"
  fi
  rc=${PIPESTATUS[0]}
  set -e
  end_ts=$(date +%s)
  dur=$((end_ts - start_ts))
  TOTAL_DURATION=$((TOTAL_DURATION + dur))

  NAMES+=("$base")
  DURATIONS+=("$dur")
  EXITS+=("$rc")

  if [ "$rc" -eq 0 ]; then
    STATUSES+=("ok")
    ok "$base: completed in ${dur}s"
  else
    STATUSES+=("fail")
    OVERALL_FAIL=1
    error "$base: exited $rc after ${dur}s"
    if [ "$FAIL_FAST" -eq 1 ]; then
      warn "fail-fast: aborting remaining steps"
      break
    fi
  fi
done

# --------------------------------------------------------------------
# Summary table.
# --------------------------------------------------------------------
printf '\n' >&2
printf '=== Summary ===\n' >&2

# Compute column widths.
name_w=4
for n in "${NAMES[@]+"${NAMES[@]}"}"; do
  [ "${#n}" -gt "$name_w" ] && name_w=${#n}
done
status_w=6
dur_w=8

printf '%-*s  %-*s  %*s\n' "$name_w" "STEP" "$status_w" "STATUS" "$dur_w" "DURATION" >&2
# Separator line built from dashes.
sep=""
total_w=$((name_w + 2 + status_w + 2 + dur_w))
i=0
while [ "$i" -lt "$total_w" ]; do
  sep="${sep}-"
  i=$((i + 1))
done
printf '%s\n' "$sep" >&2

i=0
n_steps=${#NAMES[@]}
while [ "$i" -lt "$n_steps" ]; do
  printf '%-*s  %-*s  %*s\n' \
    "$name_w" "${NAMES[$i]}" \
    "$status_w" "${STATUSES[$i]}" \
    "$dur_w" "${DURATIONS[$i]}s" >&2
  i=$((i + 1))
done

printf '%s\n' "$sep" >&2
printf 'total: %d step(s), %ds\n' "$n_steps" "$TOTAL_DURATION" >&2

# --------------------------------------------------------------------
# Final handoff or failure message.
# --------------------------------------------------------------------
if [ "$OVERALL_FAIL" -eq 0 ]; then
  cat >&2 <<EOF

===============================================================
  [OK] Phase 0 complete

  Installed:
    - Xcode Command Line Tools
    - Homebrew
    - gh, git, node, jq
    - Claude Code CLI (authenticated)
    - Claude Desktop app (authenticated; pairs with CLI for cowork)

  Cloned:
    - github.com/suTerminus/dotfiles -> ~/code/personal/dotfiles

  Next steps:
    1. cd ~/code/personal/dotfiles
    2. cp phase0/claude-settings-bootstrap.json ~/.claude/settings.json
       (pre-allows brew/gh/common reads so Phase 1 doesn't prompt on every command)
    3. claude
    4. Tell Claude: "Help me build Phase 1 from the PRD"

  Phase 1 will set up:
    - chezmoi (dotfile management)
    - Inventory system (brew.yaml, repos.yaml, mise.yaml)
    - Full Brewfile, language runtimes, repo auto-clone

  Logs: $LOG_FILE
===============================================================
EOF
  exit 0
else
  printf '\n' >&2
  error "Phase 0 finished with failures."
  i=0
  while [ "$i" -lt "$n_steps" ]; do
    if [ "${STATUSES[$i]}" = "fail" ]; then
      error "  - ${NAMES[$i]}: exit ${EXITS[$i]}"
    fi
    i=$((i + 1))
  done
  error "Logs: $LOG_FILE"
  exit 1
fi
