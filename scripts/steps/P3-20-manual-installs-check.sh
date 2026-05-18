#!/usr/bin/env bash
set -euo pipefail

# Step: P3-20-manual-installs-check
# Probe: per-entry detection block, dispatching on `detection.kind`:
#   app      -> mac_manual_detect_app <bundle_id>
#   command  -> mac_manual_detect_command <command>
#   file     -> mac_manual_detect_file <path>
#   launchd  -> mac_manual_detect_launchd <label>
#
# Read-only: NEVER writes, NEVER installs, NEVER prompts for sudo.
# Same code path under PHASE1_DRY_RUN=1 as a real run.
#
# Output (per Discovery PRD §9):
#   ok:   <name>             # detected
#   warn: <name> — missing   # not detected, plus reason: and docs_url:
#
# This step ALWAYS exits 0 — manual installs are out of the bootstrap's
# control by definition, and surfacing them must never block the run.
# The doctor (P3-40) reports them as [missing] and exits non-zero, which
# is the formal mechanism for CI-style flagging.
#
# Tolerates inventory/manual.yaml being absent — logs `warn` and exits 0.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
# shellcheck source=../lib/log.sh
. "$LIB_DIR/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$LIB_DIR/idempotent.sh"
# shellcheck source=../lib/macos.sh
. "$LIB_DIR/macos.sh"

step_name="P3-20-manual-installs-check"

REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
INVENTORIES=(
  "$REPO_ROOT/inventory/manual.yaml"
  "$HOME/.local/share/chezmoi-private/inventory/manual-personal.yaml"
  "$HOME/.local/share/chezmoi-enersis/inventory/manual-enersis.yaml"
)
__any=0
for f in "${INVENTORIES[@]}"; do [ -r "$f" ] && __any=1; done
if [ "$__any" -eq 0 ]; then
  warn "$step_name: no manual inventory found; skipping P3-20"
  exit 0
fi

if ! command -v yq >/dev/null 2>&1; then
  # yq is part of the Phase 1 Brewfile; if it's missing, this step is
  # informational so we just warn and exit 0 rather than failing the run.
  warn "$step_name: yq not on PATH; cannot parse manual inventories — skipping"
  exit 0
fi

# Project each entry to a US-separated row (ASCII 0x1f):
#   name<US>reason<US>docs_url<US>kind<US>arg
# `arg` is the kind-specific payload: bundle_id / command / path / label.
# We can't use @tsv here because IFS=$'\t' collapses consecutive tabs
# (tab is whitespace in IFS), which shifts fields when docs_url is empty.
__US=$'\x1f'
__yq_query='.manual[] | [
    .name,
    (.reason // ""),
    (.docs_url // ""),
    .detection.kind,
    (.detection.bundle_id // .detection.command // .detection.path // .detection.label // "")
  ] | join("'"$__US"'")'

info "Manual installs check:"

count_missing=0
count_ok=0

for INVENTORY_FILE in "${INVENTORIES[@]}"; do
  [ -r "$INVENTORY_FILE" ] || continue
  entries="$(yq '[.manual[]] | length' "$INVENTORY_FILE" 2>/dev/null || echo 0)"
  [ "$entries" -gt 0 ] || continue
  info "$step_name: walking $(basename "$INVENTORY_FILE") ($entries entries)"

  while IFS=$'\x1f' read -r name reason docs_url kind arg; do
    [ -n "$name" ] || continue

    detected=1
    case "$kind" in
      app)     mac_manual_detect_app     "$arg" && detected=0 || detected=1 ;;
      command) mac_manual_detect_command "$arg" && detected=0 || detected=1 ;;
      file)    mac_manual_detect_file    "$arg" && detected=0 || detected=1 ;;
      launchd) mac_manual_detect_launchd "$arg" && detected=0 || detected=1 ;;
      *)
        warn "$name — unsupported detection.kind \"$kind\""
        count_missing=$((count_missing + 1))
        continue
        ;;
    esac

    if [ "$detected" -eq 0 ]; then
      ok "$name"
      count_ok=$((count_ok + 1))
    else
      warn "$name — missing"
      [ -n "$reason" ]   && info "    reason:   $reason"
      [ -n "$docs_url" ] && info "    docs_url: $docs_url"
      count_missing=$((count_missing + 1))
    fi
  done < <(yq eval "$__yq_query" "$INVENTORY_FILE" 2>/dev/null || true)
done

info "$step_name: $count_ok present, $count_missing missing (read-only check)"

# Always exit 0 — see header comment.
exit 0
