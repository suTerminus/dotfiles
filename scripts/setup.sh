#!/usr/bin/env bash
# scripts/setup.sh
# Multi-phase orchestrator for macbook-setup (Phase 1+).
# Iterates scripts/steps/P<N>-*.sh in lexical order, captures per-step
# status, duration, and prints a summary table. Idempotent.
#
# Usage:
#   ./scripts/setup.sh --phase 1
#   ./scripts/setup.sh --only P1-20,P1-30
#   ./scripts/setup.sh --doctor
#
# See macbook-setup-phase1-prd.md §4 for the full flag contract.

set -euo pipefail

# --------------------------------------------------------------------
# Resolve SCRIPT_DIR using BASH_SOURCE so the script works whether
# invoked by absolute path, relative path, or symlink.
# --------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------
# Inline log helpers. Defined unconditionally so they're available
# before lib/log.sh is sourced (e.g. if libs are missing during
# early-test scenarios). lib/log.sh defines identical helpers under a
# source guard, so sourcing it later is a no-op.
# --------------------------------------------------------------------
info()  { printf '[INFO] %s\n' "$*" >&2; }
ok()    { printf '[OK]   %s\n' "$*" >&2; }
skip()  { printf '[SKIP] %s\n' "$*" >&2; }
warn()  { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERR]  %s\n' "$*" >&2; }

# --------------------------------------------------------------------
# Source library helpers if reachable. They may not exist yet during
# parallel authoring; the script must still parse --help and exit
# cleanly in that case. Real runs require all three.
# --------------------------------------------------------------------
__source_libs() {
  local missing=0
  if [ -r "$SCRIPT_DIR/lib/log.sh" ]; then
    # shellcheck source=lib/log.sh
    . "$SCRIPT_DIR/lib/log.sh"
  else
    missing=1
  fi
  if [ -r "$SCRIPT_DIR/lib/idempotent.sh" ]; then
    # shellcheck source=lib/idempotent.sh
    . "$SCRIPT_DIR/lib/idempotent.sh"
  else
    missing=1
  fi
  if [ -r "$SCRIPT_DIR/lib/prompt.sh" ]; then
    # shellcheck source=lib/prompt.sh
    . "$SCRIPT_DIR/lib/prompt.sh"
  else
    missing=1
  fi
  return "$missing"
}

# Source lazily — best-effort. If anything is missing we proceed; --help
# still works, and a real run will fail cleanly when steps reference
# helpers that aren't there.
__source_libs || true

# --------------------------------------------------------------------
# Flag parsing.
# --------------------------------------------------------------------
print_usage() {
  cat <<'USAGE'
Usage: scripts/setup.sh [flags]

Multi-phase orchestrator. Selects and runs scripts/steps/P<N>-*.sh in
lexical order, capturing per-step status and duration.

Flags:
  --phase N             Run every step matching P<N>-*. Selects the
                        whole phase in lexical order.
  --only STEP[,STEP..]  Run only the listed step IDs (e.g. P1-20,P1-30).
                        Repeatable; values accumulate.
  --skip STEP[,STEP..]  Skip the listed step IDs. Repeatable. Wins over
                        --only and --phase.
  --include-tag TAG     Activate the named tag bucket (e.g. gis).
                        Repeatable; exported as PHASE1_INCLUDE_TAGS as
                        a comma-separated list for steps to read.
  --update-repos        Pull existing clones in P1-50, in addition to
                        cloning missing ones. Exports PHASE1_UPDATE_REPOS=1.
  --dry-run             Run every probe; print what would happen; do not
                        execute modifying commands. Exports PHASE1_DRY_RUN=1.
  --doctor              Alias for --dry-run --phase 1.
  --fail-fast           Stop on the first non-zero step exit.
  --force               Steps that probe-then-act will skip their probe
                        and re-apply (exports PHASE1_FORCE=1). Currently
                        honoured by P3-00 and P3-10; safe to pass to others
                        (ignored).
  -h, --help            Print this message and exit 0.

Marker file:
  On a fully successful --phase N run, writes
  ~/.local/state/macbook-setup/.phase<N>-complete with a timestamp.

Logs:
  Full output is tee'd to ~/.local/state/macbook-setup/run-phase<N>-<ts>.log
  (or run-<ts>.log when no --phase is given).

Exit codes:
  0  all selected steps ok (or skipped)
  1  one or more steps failed
  2  invalid flag usage
USAGE
}

PHASE=""
ONLY_LIST=()
SKIP_LIST=()
INCLUDE_TAGS=()
UPDATE_REPOS=0
DRY_RUN=0
DOCTOR=0
FAIL_FAST=0
FORCE=0

# Add comma-separated values from a single argument to the named array.
# Bash 3.2-compatible: uses tr to split on commas. Note the trailing `\n`
# in the printf — without it, `read` never sees a terminated line and the
# loop body never executes, leaving the target array silently empty.
__split_csv_into() {
  local arrname="$1"; shift
  local raw="$1"; shift
  local item
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    eval "$arrname+=(\"\$item\")"
  done < <(printf '%s\n' "$raw" | tr ',' '\n')
}

while [ $# -gt 0 ]; do
  case "$1" in
    --phase)
      [ $# -ge 2 ] || { error "--phase requires an argument"; print_usage >&2; exit 2; }
      PHASE="$2"
      shift 2
      ;;
    --phase=*)
      PHASE="${1#--phase=}"
      shift
      ;;
    --only)
      [ $# -ge 2 ] || { error "--only requires an argument"; print_usage >&2; exit 2; }
      __split_csv_into ONLY_LIST "$2"
      shift 2
      ;;
    --only=*)
      __split_csv_into ONLY_LIST "${1#--only=}"
      shift
      ;;
    --skip)
      [ $# -ge 2 ] || { error "--skip requires an argument"; print_usage >&2; exit 2; }
      __split_csv_into SKIP_LIST "$2"
      shift 2
      ;;
    --skip=*)
      __split_csv_into SKIP_LIST "${1#--skip=}"
      shift
      ;;
    --include-tag)
      [ $# -ge 2 ] || { error "--include-tag requires an argument"; print_usage >&2; exit 2; }
      INCLUDE_TAGS+=("$2")
      shift 2
      ;;
    --include-tag=*)
      INCLUDE_TAGS+=("${1#--include-tag=}")
      shift
      ;;
    --update-repos)
      UPDATE_REPOS=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --doctor)
      DOCTOR=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --fail-fast)
      FAIL_FAST=1
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

# --doctor expands to --dry-run --phase 1 (PRD §4).
if [ "$DOCTOR" -eq 1 ]; then
  DRY_RUN=1
  if [ -z "$PHASE" ]; then
    PHASE="1"
  fi
fi

# Validate --phase value (digits only).
if [ -n "$PHASE" ]; then
  case "$PHASE" in
    ''|*[!0-9]*)
      error "--phase requires a numeric argument (e.g. --phase 1)"
      exit 2
      ;;
  esac
fi

# Export env for downstream steps.
if [ "$DRY_RUN" -eq 1 ]; then
  export PHASE1_DRY_RUN=1
fi
if [ "$UPDATE_REPOS" -eq 1 ]; then
  export PHASE1_UPDATE_REPOS=1
fi
if [ "$FORCE" -eq 1 ]; then
  export PHASE1_FORCE=1
fi
# Merge CLI --include-tag flags with machine-default tags from chezmoi
# data. Per-machine defaults live in ~/.config/chezmoi/chezmoi.toml
# under `[data] include_tags = ["..."]`. CLI flags take precedence in
# ordering but both end up in PHASE1_INCLUDE_TAGS.
__chezmoi_default_tags=""
if command -v chezmoi >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  __chezmoi_default_tags="$(chezmoi data 2>/dev/null \
    | jq -r '.include_tags // [] | join(",")' 2>/dev/null || true)"
fi

__cli_tag_csv=""
for t in "${INCLUDE_TAGS[@]+"${INCLUDE_TAGS[@]}"}"; do
  if [ -z "$__cli_tag_csv" ]; then
    __cli_tag_csv="$t"
  else
    __cli_tag_csv="$__cli_tag_csv,$t"
  fi
done

# Combine: chezmoi defaults first, then CLI; deduped via awk pass.
__combined_csv=""
for csv in "$__chezmoi_default_tags" "$__cli_tag_csv"; do
  [ -n "$csv" ] || continue
  if [ -z "$__combined_csv" ]; then
    __combined_csv="$csv"
  else
    __combined_csv="$__combined_csv,$csv"
  fi
done

if [ -n "$__combined_csv" ]; then
  # Dedup while preserving first-seen order.
  __combined_csv="$(printf '%s' "$__combined_csv" | tr ',' '\n' \
    | awk '!seen[$0]++' | paste -sd ',' -)"
  export PHASE1_INCLUDE_TAGS="$__combined_csv"
fi
unset __chezmoi_default_tags __cli_tag_csv __combined_csv

# --------------------------------------------------------------------
# Log file setup.
# --------------------------------------------------------------------
LOG_DIR="$HOME/.local/state/macbook-setup"
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
  error "could not create log directory: $LOG_DIR"
  exit 1
fi
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
if [ -n "$PHASE" ]; then
  LOG_FILE="$LOG_DIR/run-phase${PHASE}-${TIMESTAMP}.log"
else
  LOG_FILE="$LOG_DIR/run-${TIMESTAMP}.log"
fi
: > "$LOG_FILE" || { error "could not write to log file: $LOG_FILE"; exit 1; }

info "macbook-setup orchestrator starting"
info "log file: $LOG_FILE"
info "script dir: $SCRIPT_DIR"
[ -n "$PHASE" ]                && info "phase: $PHASE"
[ "$DRY_RUN" -eq 1 ]           && info "DRY RUN mode (PHASE1_DRY_RUN=1)"
[ "$DOCTOR" -eq 1 ]            && info "doctor mode (--dry-run --phase ${PHASE})"
[ "$UPDATE_REPOS" -eq 1 ]      && info "update-repos: PHASE1_UPDATE_REPOS=1"
[ -n "${PHASE1_INCLUDE_TAGS:-}" ] && info "include-tags: ${PHASE1_INCLUDE_TAGS}"

# --------------------------------------------------------------------
# Discover step files.
# - With --phase N, match scripts/steps/P<N>-*.sh.
# - Without --phase, match scripts/steps/P*-*.sh (all phases). The
#   --only/--skip filters then narrow.
# Use LC_ALL=C sort for stable lexical ordering across locales.
# --------------------------------------------------------------------
STEPS_DIR="$SCRIPT_DIR/steps"
STEPS=()
if [ -d "$STEPS_DIR" ]; then
  if [ -n "$PHASE" ]; then
    __glob="P${PHASE}-*.sh"
  else
    __glob="P*-*.sh"
  fi
  while IFS= read -r f; do
    [ -n "$f" ] && STEPS+=("$f")
  done < <(LC_ALL=C find "$STEPS_DIR" -maxdepth 1 -type f -name "$__glob" 2>/dev/null | LC_ALL=C sort)
  unset __glob
fi

if [ "${#STEPS[@]}" -eq 0 ]; then
  if [ -n "$PHASE" ]; then
    warn "no steps found in $STEPS_DIR matching P${PHASE}-*.sh"
  else
    warn "no steps found in $STEPS_DIR"
  fi
  # Empty step set is not an error. The summary table below still
  # renders (with no rows), and we exit 0. This is also what makes
  # `--dry-run --phase 1` exit 0 against an empty steps dir during
  # parallel authoring.
fi

# --------------------------------------------------------------------
# Selection helpers (lifted from phase0/bootstrap.sh, adapted for the
# P<N>-NN-name.sh shape).
#
# Match rules for a needle against a basename:
#   - exact basename (with or without .sh)
#   - the P<N>-NN id prefix, e.g. "P1-20" matches "P1-20-render-brewfile.sh"
# --------------------------------------------------------------------
__step_matches() {
  local needle="$1"
  local base="$2"
  local trimmed="${base%.sh}"
  if [ "$needle" = "$base" ] || [ "$needle" = "$trimmed" ]; then
    return 0
  fi
  case "$base" in
    "${needle}"-*) return 0 ;;
  esac
  return 1
}

# --skip wins over --only. With no --only constraint, run everything not
# explicitly skipped.
__should_run() {
  local base="$1"
  local n
  for n in "${SKIP_LIST[@]+"${SKIP_LIST[@]}"}"; do
    if __step_matches "$n" "$base"; then
      return 1
    fi
  done
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
RAN_ANY=0

for step in "${STEPS[@]+"${STEPS[@]}"}"; do
  base="$(basename -- "$step")"
  trimmed="${base%.sh}"
  # Derive the "P1-20" id and the friendly name "render-brewfile" for
  # the header. If the filename doesn't match P<N>-NN-name, fall back
  # to printing the basename only.
  id="$trimmed"
  pretty="$trimmed"
  case "$trimmed" in
    P*-[0-9]*-*)
      id="${trimmed%%-*}-${trimmed#*-}"  # safe no-op when only one '-' deep
      # Cleaner extraction: id = first two dash-segments, pretty = rest.
      id="$(printf '%s' "$trimmed" | awk -F- '{print $1"-"$2}')"
      pretty="$(printf '%s' "$trimmed" | awk -F- '{for(i=3;i<=NF;i++){printf (i==3?"":"-")$i}}')"
      [ -z "$pretty" ] && pretty="$trimmed"
      ;;
  esac

  if ! __should_run "$base"; then
    NAMES+=("$id")
    STATUSES+=("skip")
    DURATIONS+=("0")
    EXITS+=("0")
    skip "$base: excluded by --only/--skip"
    continue
  fi

  RAN_ANY=1

  printf '\n' >&2
  printf '=== %s %s ===\n' "$id" "$pretty" >&2

  start_ts=$(date +%s)
  rc=0
  # Hand /dev/tty to the step's stdin so interactive prompts work even
  # when this orchestrator was invoked via a pipe. TTY redirection is
  # non-negotiable — Phase 0's lesson. The subshell open is the only
  # reliable probe: `[ -r /dev/tty ]` returns true even when the parent
  # has no controlling terminal (macOS) and the redirect then fails.
  set +e
  if (: </dev/tty) 2>/dev/null; then
    bash "$step" </dev/tty 2>&1 | tee -a "$LOG_FILE"
  else
    warn "$base: /dev/tty not openable; running without TTY redirection"
    bash "$step" 2>&1 | tee -a "$LOG_FILE"
  fi
  rc=${PIPESTATUS[0]}
  set -e
  end_ts=$(date +%s)
  dur=$((end_ts - start_ts))
  TOTAL_DURATION=$((TOTAL_DURATION + dur))

  NAMES+=("$id")
  DURATIONS+=("$dur")
  EXITS+=("$rc")

  if [ "$rc" -eq 0 ]; then
    STATUSES+=("ok")
    ok "$id: completed in ${dur}s"
  else
    STATUSES+=("fail")
    OVERALL_FAIL=1
    error "$id: exited $rc after ${dur}s"
    if [ "$FAIL_FAST" -eq 1 ]; then
      warn "fail-fast: aborting remaining steps"
      break
    fi
  fi
done

# --------------------------------------------------------------------
# Summary table. Mirrors phase0/bootstrap.sh format exactly.
# --------------------------------------------------------------------
printf '\n' >&2
printf '=== Summary ===\n' >&2

name_w=4
for n in "${NAMES[@]+"${NAMES[@]}"}"; do
  [ "${#n}" -gt "$name_w" ] && name_w=${#n}
done
status_w=6
dur_w=8

printf '%-*s  %-*s  %*s\n' "$name_w" "STEP" "$status_w" "STATUS" "$dur_w" "DURATION" >&2
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
# Marker file. Written only when:
#   - --phase was used (not --only / --skip alone), AND
#   - every selected step exited 0 (OVERALL_FAIL == 0), AND
#   - at least one step actually ran (RAN_ANY == 1) — so an empty
#     steps dir doesn't claim the phase is complete.
# Format: "phase<N>-complete-at-<ISO-timestamp>\n"
# --------------------------------------------------------------------
if [ "$OVERALL_FAIL" -eq 0 ] && [ -n "$PHASE" ] && [ "$RAN_ANY" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    info "would write marker: $LOG_DIR/.phase${PHASE}-complete (skipped under --dry-run)"
  else
    marker="$LOG_DIR/.phase${PHASE}-complete"
    iso_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if printf 'phase%s-complete-at-%s\n' "$PHASE" "$iso_ts" > "$marker"; then
      ok "wrote marker: $marker"
    else
      warn "failed to write marker: $marker"
    fi
  fi
fi

# --------------------------------------------------------------------
# Final status.
# --------------------------------------------------------------------
if [ "$OVERALL_FAIL" -eq 0 ]; then
  if [ "$n_steps" -eq 0 ]; then
    info "no steps selected; nothing to do"
  else
    ok "all selected steps completed successfully"
  fi
  info "logs: $LOG_FILE"
  exit 0
else
  printf '\n' >&2
  error "orchestrator finished with failures."
  i=0
  while [ "$i" -lt "$n_steps" ]; do
    if [ "${STATUSES[$i]}" = "fail" ]; then
      error "  - ${NAMES[$i]}: exit ${EXITS[$i]}"
    fi
    i=$((i + 1))
  done
  error "logs: $LOG_FILE"
  exit 1
fi
