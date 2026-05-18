#!/usr/bin/env bash
set -euo pipefail

# Step: P1-80-mas-apps
# Idempotency probe: every entry in inventory/mas.yaml whose tags pass
# the machine + include-tag filter is reported by `mas list` (matching
# on appid in column 1).
#
# Behaviour:
#   - require_command mas (in public Brewfile via brew formula `mas`).
#   - Pre-check `mas account`: if the user is NOT signed into the App
#     Store, warn-not-fail and exit 0 (matches P1-30's MAS posture).
#   - For each app entry that passes the tag filter, install via
#     `mas install <appid>`.
#
# Tag filter: same as P1-60 / P1-70.
#
# Dry-run: log `would: mas install <appid> # <name>` per missing entry.
#
# Exit codes:
#   0 — every required app installed (or skip/warn on App Store auth).
#   1 — mas/yq missing, or one or more installs failed for a non-auth
#       reason.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="P1-80-mas-apps"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/code/personal/dotfiles}"

INVENTORIES=(
  "$DOTFILES_DIR/inventory/mas.yaml"
  "$HOME/.local/share/chezmoi-private/inventory/mas-personal.yaml"
  "$HOME/.local/share/chezmoi-enersis/inventory/mas-enersis.yaml"
)
__any=0
for f in "${INVENTORIES[@]}"; do [ -f "$f" ] && __any=1; done
if [ "$__any" -eq 0 ]; then
  info "$step_name: no mas inventory found; skipping"
  exit 0
fi

if ! command -v mas >/dev/null 2>&1; then
  if is_dry_run; then
    info "$step_name: would: per-app mas install (mas not yet on PATH; P1-30 installs the formula first)"
    exit 0
  fi
  error "$step_name: mas not on PATH; ensure 'mas' formula is in the Brewfile"
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  error "$step_name: yq not on PATH"
  exit 1
fi

# No pre-flight sign-in probe: macOS Sequoia removed the `mas account`
# API, so it always exits non-zero even when the user IS signed in,
# producing a false-positive warning on every Phase 1 run. Defer the
# diagnosis to the per-install loop below — `mas install` returns a
# non-zero exit when auth is missing, and that path already warn-not-
# fails with a remediation hint.

# --- Helpers (mirror P1-60) -------------------------------------------------

_detect_machine() {
  if [ -r "$HOME/.config/chezmoi/chezmoi.toml" ]; then
    grep -E '^[[:space:]]*machine[[:space:]]*=' "$HOME/.config/chezmoi/chezmoi.toml" 2>/dev/null \
      | sed 's/.*=[[:space:]]*//;s/^"//;s/"$//;s/^[[:space:]]*//;s/[[:space:]]*$//' \
      | head -n1
  else
    printf '%s\n' "${MACHINE_TYPE:-personal}"
  fi
}

_tag_in_include() {
  case ",${PHASE1_INCLUDE_TAGS:-}," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

_select_tags() {
  local tags="$1" machine="$2"
  local t has_optional=0 buckets="" has_work=0 has_personal=0
  for t in $tags; do
    case "$t" in
      manual)   return 2 ;;
      optional) has_optional=1 ;;
      work)     has_work=1 ;;
      personal) has_personal=1 ;;
      *)        buckets="$buckets $t" ;;
    esac
  done
  if [ "$has_work" -eq 1 ] && [ "$machine" != "work" ]; then
    return 1
  fi
  if [ "$has_optional" -eq 1 ]; then
    local b opted=1
    for b in $buckets; do
      if _tag_in_include "$b"; then opted=0; break; fi
    done
    [ "$opted" -eq 0 ] || return 1
  fi
  return 0
}

# --- Walk inventory ---------------------------------------------------------

machine="$(_detect_machine)"
info "$step_name: machine=$machine include_tags=\"${PHASE1_INCLUDE_TAGS:-}\""

installed=0
skipped=0
errors=0

listed="$(mas list 2>/dev/null || true)"

for INVENTORY in "${INVENTORIES[@]}"; do
  [ -f "$INVENTORY" ] || continue
  count="$(yq '[.apps[]] | length' "$INVENTORY" 2>/dev/null || echo 0)"
  [ "$count" -gt 0 ] || continue
  info "$step_name: walking $(basename "$INVENTORY") ($count apps)"

  for ((i=0; i<count; i++)); do
    name="$(yq -r ".apps[$i].name" "$INVENTORY" 2>/dev/null || echo "")"
    appid="$(yq -r ".apps[$i].appid" "$INVENTORY" 2>/dev/null || echo "")"
    tags="$(yq -r ".apps[$i].tags // [] | join(\" \")" "$INVENTORY" 2>/dev/null || echo "")"
    [ -n "$appid" ] || continue

    decision=0
    _select_tags "$tags" "$machine" || decision=$?

    case "$decision" in
      1) skipped=$((skipped + 1)); continue ;;
      2) warn "$step_name: $name ($appid) is manual; skipping"; skipped=$((skipped + 1)); continue ;;
    esac

    if printf '%s\n' "$listed" | awk '{print $1}' | grep -qx "$appid"; then
      skipped=$((skipped + 1))
      continue
    fi

    if is_dry_run; then
      info "$step_name: would: mas install $appid  # $name"
      continue
    fi

    info "$step_name: installing $name ($appid)"
    if ! mas install "$appid" 2>&1; then
      warn "$step_name: mas install $appid failed (likely App Store auth or already-installed-by-other-means); continuing"
      errors=$((errors + 1))
      continue
    fi
    installed=$((installed + 1))
  done
done

info "$step_name: installed: $installed; skipped: $skipped; errors: $errors"
# MAS errors are warn-not-fail at the step level (consistent with P1-30
# treatment of MAS).
exit 0
