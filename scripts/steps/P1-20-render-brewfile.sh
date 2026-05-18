#!/usr/bin/env bash
# scripts/steps/P1-20-render-brewfile.sh
# Phase 1 step: render home/dot_config/brew/Brewfile.tmpl from
# inventory/brew.yaml via scripts/render-brewfile.sh.
#
# Probe: Brewfile.tmpl exists AND its mtime ≥ brew.yaml mtime.
# If PHASE1_INCLUDE_TAGS is set non-empty, the probe is bypassed
# (we always re-render to honour the requested opt-ins).
#
# Standalone-runnable: sources lib/log.sh and lib/idempotent.sh via
# SCRIPT_DIR so it works without the orchestrator.

set -euo pipefail

# Anchor every relative path to the repo root.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../lib/log.sh
. "${REPO_ROOT}/scripts/lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "${REPO_ROOT}/scripts/lib/idempotent.sh"

# Hard paths the step operates on.
SOURCE_YAML="${REPO_ROOT}/inventory/brew.yaml"
OUTPUT_TMPL="${REPO_ROOT}/home/dot_config/brew/Brewfile.tmpl"
RENDERER="${REPO_ROOT}/scripts/render-brewfile.sh"

info "P1-20 render-brewfile"

if [ ! -f "$SOURCE_YAML" ]; then
  error "P1-20: inventory missing: $SOURCE_YAML"
  exit 1
fi

if [ ! -x "$RENDERER" ]; then
  error "P1-20: renderer not executable: $RENDERER"
  exit 1
fi

# Build the --include-tag arg vector from PHASE1_INCLUDE_TAGS (space- or
# comma-separated). Conservative simplification per orders: any non-empty
# value forces a re-render.
INCLUDE_ARGS=()
if [ -n "${PHASE1_INCLUDE_TAGS:-}" ]; then
  # Replace commas with spaces, then word-split.
  __pi_normalised="${PHASE1_INCLUDE_TAGS//,/ }"
  # shellcheck disable=SC2206
  __pi_arr=($__pi_normalised)
  for __pi_t in "${__pi_arr[@]}"; do
    [ -n "$__pi_t" ] || continue
    INCLUDE_ARGS+=("--include-tag" "$__pi_t")
  done
fi

# Probe: mtime check. Returns 0 if Brewfile.tmpl is fresh enough.
probe_brewfile_tmpl_fresh() {
  [ -f "$OUTPUT_TMPL" ] || return 1
  # stat -f '%m' on macOS / BSD; -c '%Y' on Linux. Phase 1 is macOS-only
  # but keep this portable for anyone running tests on Linux.
  local out_mt src_mt
  if out_mt="$(stat -f '%m' "$OUTPUT_TMPL" 2>/dev/null)" \
     && src_mt="$(stat -f '%m' "$SOURCE_YAML" 2>/dev/null)"; then
    :
  else
    out_mt="$(stat -c '%Y' "$OUTPUT_TMPL")"
    src_mt="$(stat -c '%Y' "$SOURCE_YAML")"
  fi
  [ "$out_mt" -ge "$src_mt" ]
}

# If include-tags were requested, conservatively re-render (we cannot
# tell from mtime alone whether the requested set differs from what was
# baked in last time).
if [ "${#INCLUDE_ARGS[@]}" -eq 0 ] && probe_brewfile_tmpl_fresh; then
  if is_dry_run; then
    info "P1-20: would skip (Brewfile.tmpl up to date)"
  else
    skip "P1-20: Brewfile.tmpl up to date"
  fi
  exit 0
fi

# Dry-run path: invoke the renderer with --dry-run; pipe its output
# through info/warn so we never touch the target.
if is_dry_run; then
  info "P1-20: dry-run — invoking renderer with --dry-run"
  if "$RENDERER" --dry-run "${INCLUDE_ARGS[@]+"${INCLUDE_ARGS[@]}"}" 2>&1 | while IFS= read -r line; do
       case "$line" in
         *"would change"*|*"does not exist"*) warn "$line" ;;
         *) info "$line" ;;
       esac
     done; then
    :
  fi
  exit 0
fi

# Real run: render, then refresh the rendered ~/.config/brew/Brewfile
# via chezmoi if available.
info "P1-20: rendering Brewfile.tmpl"
if ! "$RENDERER" "${INCLUDE_ARGS[@]+"${INCLUDE_ARGS[@]}"}"; then
  error "P1-20: renderer failed"
  exit 1
fi
ok "P1-20: Brewfile.tmpl rendered"

# Refresh the apply-time target if chezmoi is on PATH. P1-10 will pick
# this up on its next pass otherwise.
if command -v chezmoi >/dev/null 2>&1; then
  info "P1-20: refreshing ~/.config/brew/Brewfile via chezmoi"
  if chezmoi apply --force --include=files dot_config/brew/Brewfile; then
    ok "P1-20: chezmoi apply complete"
  else
    warn "P1-20: chezmoi apply failed; P1-10 next pass will retry"
  fi
else
  warn "P1-20: chezmoi not on PATH; rendered Brewfile will be applied by P1-10"
fi

exit 0
