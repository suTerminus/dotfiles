#!/usr/bin/env bash
set -euo pipefail

# scripts/revert-macos-defaults.sh
#
# Inverse of P3-00: iterates inventory/macos-defaults.yaml and runs
# `defaults delete <domain> <key>` for each entry, then killalls the
# affected processes (Dock, Finder, SystemUIServer, etc.) so the
# changes take effect immediately. After this, macOS falls back to
# system defaults for every key the inventory managed — useful for
# comparing your tweaked setup against the OOTB experience.
#
# Re-applying the inventory: just run `./scripts/setup.sh --only P3-00`
# or `./scripts/setup.sh --phase 3`.
#
# Usage:
#   ./scripts/revert-macos-defaults.sh           # interactive confirm
#   ./scripts/revert-macos-defaults.sh --yes     # skip confirm
#   ./scripts/revert-macos-defaults.sh --dry-run # print, don't run
#
# Exit codes:
#   0 — every entry's defaults delete returned 0 (or was already absent).
#   1 — user declined / inventory missing / yq missing.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
. "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/idempotent.sh
. "$SCRIPT_DIR/lib/idempotent.sh"
# shellcheck source=lib/prompt.sh
. "$SCRIPT_DIR/lib/prompt.sh"

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/code/personal/dotfiles}"
INVENTORY="$DOTFILES_DIR/inventory/macos-defaults.yaml"

YES=0
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)   YES=1; shift ;;
    --dry-run)  DRY=1; shift ;;
    -h|--help)
      sed -n '/^# Usage:/,/^# Exit codes:/p' "$0" | sed 's/^# //;s/^#$//'
      exit 0
      ;;
    *) error "unknown flag: $1"; exit 2 ;;
  esac
done

if [ ! -f "$INVENTORY" ]; then
  error "inventory not found: $INVENTORY"
  exit 1
fi
if ! command -v yq >/dev/null 2>&1; then
  error "yq not on PATH; install via Phase 1 brew bundle"
  exit 1
fi

count="$(yq '[.defaults[]] | length' "$INVENTORY")"
info "about to revert $count macOS defaults entries from $INVENTORY"

if [ "$YES" -ne 1 ] && [ "$DRY" -ne 1 ]; then
  if ! command -v confirm >/dev/null 2>&1 && ! type confirm >/dev/null 2>&1; then
    error "confirm helper missing — run with --yes to skip the prompt"
    exit 1
  fi
  if ! confirm "Revert $count defaults entries (run defaults delete + killall)?" "n"; then
    info "aborted"; exit 1
  fi
fi

killall_targets=()

for ((i=0; i<count; i++)); do
  domain="$(yq -r ".defaults[$i].domain" "$INVENTORY")"
  key="$(yq -r ".defaults[$i].key" "$INVENTORY")"
  killall="$(yq -r ".defaults[$i].killall // \"\"" "$INVENTORY")"

  if [ "$DRY" -eq 1 ]; then
    info "would: defaults delete $domain $key"
  else
    if defaults delete "$domain" "$key" 2>/dev/null; then
      ok "deleted $domain $key"
    else
      info "skip (already absent): $domain $key"
    fi
  fi

  if [ -n "$killall" ] && [ "$killall" != "null" ]; then
    # Dedup
    found=0
    for t in "${killall_targets[@]+"${killall_targets[@]}"}"; do
      [ "$t" = "$killall" ] && { found=1; break; }
    done
    [ "$found" -eq 0 ] && killall_targets+=("$killall")
  fi
done

# Flush killalls.
for t in "${killall_targets[@]+"${killall_targets[@]}"}"; do
  if [ "$DRY" -eq 1 ]; then
    info "would: killall $t"
  else
    info "killall $t"
    killall "$t" 2>/dev/null || true
  fi
done

ok "revert complete; macOS will use system defaults for these keys until P3-00 re-applies"
