#!/usr/bin/env bash
set -euo pipefail

# Step: P3-00-macos-defaults
# Idempotency probe (per-entry):
#   For every entry in inventory/macos-defaults.yaml, the current
#   `defaults read <domain> <key>` value compares equal under its declared
#   `type:` to the declared `value:`. If every entry matches, the step
#   logs `skip: macOS defaults already applied` and exits 0 with zero
#   `defaults write` calls and zero `killall` invocations.
#
# Acts in two passes:
#   Pass 1 (compute drift): probe every entry, collect the drift entries
#     and their `killall:` targets into a deduplicated queue.
#   Pass 2 (apply): run `mac_default_set` per drift entry, then
#     `mac_killall_queue_flush` once at the end. A pair of writes to
#     com.apple.dock yields exactly one `killall Dock`.
#
# Under PHASE1_DRY_RUN=1: log `would: defaults write ...` per drift
# entry; mutate nothing. The queue is intentionally not flushed in
# dry-run mode.
#
# Tolerates inventory/macos-defaults.yaml being absent (HMS Faithful
# authors it in parallel) — logs `warn` and exits 0.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
# shellcheck source=../lib/log.sh
. "$LIB_DIR/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$LIB_DIR/idempotent.sh"
# shellcheck source=../lib/macos.sh
. "$LIB_DIR/macos.sh"

step_name="P3-00-macos-defaults"

# Resolve the repo-root inventory dir relative to this step file.
# scripts/steps/P3-00-... -> ../../inventory.
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
INVENTORY_FILE="$REPO_ROOT/inventory/macos-defaults.yaml"

# Flags. Also honour PHASE1_FORCE from the orchestrator's --force flag.
FORCE="${PHASE1_FORCE:-0}"
KEY_FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force|-f) FORCE=1; shift ;;
    --key)      KEY_FILTER="$2"; shift 2 ;;
    --key=*)    KEY_FILTER="${1#--key=}"; shift ;;
    -h|--help)
      cat <<EOF
Usage: $step_name [flags]
  --force, -f         Re-apply every entry (skip the probe-then-act guard).
  --key <name>        Only act on entries whose key equals <name>. Useful
                      after editing one row in inventory/macos-defaults.yaml.
                      Combine with --force to also bypass the probe.
EOF
      exit 0 ;;
    *) error "$step_name: unknown flag: $1"; exit 2 ;;
  esac
done

if [ ! -r "$INVENTORY_FILE" ]; then
  warn "$step_name: inventory/macos-defaults.yaml not found; skipping P3-00"
  exit 0
fi

if ! require_command yq "$step_name: yq required to parse inventory/macos-defaults.yaml"; then
  exit 1
fi

# --------------------------------------------------------------------
# Read the inventory into parallel arrays. We use yq's tab-separated
# output and read line-by-line so values containing spaces survive.
# --------------------------------------------------------------------
DOMAINS=()
KEYS=()
TYPES=()
VALUES=()
KILLALLS=()

# Each YAML entry becomes one tab-separated line:
#   domain<TAB>key<TAB>type<TAB>value<TAB>killall
# Missing `killall:` is rendered as the literal string "null" by yq;
# we map that to empty before queueing.
__yq_query='.defaults[] | [.domain, .key, .type, (.value | @json), (.killall // "")] | @tsv'

while IFS=$'\t' read -r d k t v ka; do
  [ -n "$d" ] || continue
  # `value` is JSON-encoded by yq; strip surrounding quotes for scalars.
  # For arrays/dicts we keep the JSON form for the comparator. This keeps
  # whitespace inside string values intact.
  case "$v" in
    \"*\")
      # Strip leading/trailing quote and unescape \" and \\.
      v="${v#\"}"; v="${v%\"}"
      v="${v//\\\"/\"}"
      v="${v//\\\\/\\}"
      ;;
  esac
  DOMAINS+=("$d")
  KEYS+=("$k")
  TYPES+=("$t")
  VALUES+=("$v")
  KILLALLS+=("$ka")
done < <(yq eval "$__yq_query" "$INVENTORY_FILE" 2>/dev/null || true)

n="${#DOMAINS[@]}"
if [ "$n" -eq 0 ]; then
  info "$step_name: inventory has zero entries; nothing to do"
  exit 0
fi

# --------------------------------------------------------------------
# Pass 1: compute drift (and honour --force / --key filters).
# --------------------------------------------------------------------
DRIFT_IDX=()
i=0
while [ "$i" -lt "$n" ]; do
  domain="${DOMAINS[$i]}"
  key="${KEYS[$i]}"
  type="${TYPES[$i]}"
  expected="${VALUES[$i]}"

  # --key narrows the action to one entry by key name.
  if [ -n "$KEY_FILTER" ] && [ "$key" != "$KEY_FILTER" ]; then
    i=$((i + 1))
    continue
  fi

  # --force bypasses the probe and treats every (filtered) entry as drift.
  if [ "$FORCE" -eq 1 ]; then
    DRIFT_IDX+=("$i")
    i=$((i + 1))
    continue
  fi

  current=""
  if current_raw="$(mac_default_get "$domain" "$key" 2>/dev/null)"; then
    current="$current_raw"
    if mac_default_compare "$type" "$current" "$expected"; then
      i=$((i + 1))
      continue
    fi
  fi
  DRIFT_IDX+=("$i")
  i=$((i + 1))
done

drift_n="${#DRIFT_IDX[@]}"
if [ "$drift_n" -eq 0 ]; then
  if [ -n "$KEY_FILTER" ]; then
    warn "$step_name: --key '$KEY_FILTER' matched nothing in inventory"
  else
    skip "$step_name: macOS defaults already applied"
  fi
  exit 0
fi

# --------------------------------------------------------------------
# Pass 2: apply (or, under dry-run, log would-actions).
# --------------------------------------------------------------------
if is_dry_run; then
  for j in "${DRIFT_IDX[@]}"; do
    info "would: defaults write ${DOMAINS[$j]} ${KEYS[$j]} -${TYPES[$j]} ${VALUES[$j]}"
  done
  info "$step_name: dry-run; $drift_n drift entr$([ "$drift_n" -eq 1 ] && printf 'y' || printf 'ies')"
  exit 0
fi

failures=0
for j in "${DRIFT_IDX[@]}"; do
  domain="${DOMAINS[$j]}"
  key="${KEYS[$j]}"
  type="${TYPES[$j]}"
  value="${VALUES[$j]}"
  ka="${KILLALLS[$j]}"
  if mac_default_set "$domain" "$key" "$type" "$value"; then
    ok "$step_name: $domain $key set"
    if [ -n "$ka" ] && [ "$ka" != "null" ]; then
      mac_killall_queue_add "$ka"
    fi
  else
    error "$step_name: $domain $key write failed"
    failures=$((failures + 1))
  fi
done

mac_killall_queue_flush

if [ "$failures" -gt 0 ]; then
  error "$step_name: $failures write(s) failed"
  exit 1
fi

ok "$step_name: applied $drift_n macOS default(s)"
exit 0
