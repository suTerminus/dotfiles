#!/usr/bin/env bash
set -euo pipefail

# Step: P1-90-helm-plugins
# Idempotency probe: every entry in inventory/helm-plugins.yaml whose
# tags pass the machine + include-tag filter is reported by
# `helm plugin list` (matching the first column).
#
# Behaviour:
#   - require_command helm. helm is in inventory/brew.yaml as work-only,
#     so this step is effectively a no-op on personal machines unless
#     helm is also installed there.
#   - For each plugin, install via `helm plugin install <url>`.
#
# Tag filter: same as P1-60 / P1-70 / P1-80.
#
# Dry-run: log `would: helm plugin install <url>` per missing entry.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="P1-90-helm-plugins"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/code/personal/dotfiles}"

INVENTORIES=(
  "$DOTFILES_DIR/inventory/helm-plugins.yaml"
  "$HOME/.local/share/chezmoi-private/inventory/helm-plugins-personal.yaml"
  "$HOME/.local/share/chezmoi-enersis/inventory/helm-plugins-enersis.yaml"
)
__any=0
for f in "${INVENTORIES[@]}"; do [ -f "$f" ] && __any=1; done
if [ "$__any" -eq 0 ]; then
  info "$step_name: no helm-plugins inventory found; skipping"
  exit 0
fi

if ! command -v helm >/dev/null 2>&1; then
  if is_dry_run; then
    info "$step_name: would: per-plugin helm plugin install (helm not yet on PATH)"
    exit 0
  fi
  warn "$step_name: helm not on PATH; skipping (helm is work-only in this inventory layout)"
  exit 0
fi

if ! command -v yq >/dev/null 2>&1; then
  error "$step_name: yq not on PATH"
  exit 1
fi

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

machine="$(_detect_machine)"
info "$step_name: machine=$machine include_tags=\"${PHASE1_INCLUDE_TAGS:-}\""

installed=0
skipped=0
errors=0

listed="$(helm plugin list 2>/dev/null | awk 'NR>1{print $1}' || true)"

for INVENTORY in "${INVENTORIES[@]}"; do
  [ -f "$INVENTORY" ] || continue
  count="$(yq '[.plugins[]] | length' "$INVENTORY" 2>/dev/null || echo 0)"
  [ "$count" -gt 0 ] || continue
  info "$step_name: walking $(basename "$INVENTORY") ($count plugins)"

  for ((i=0; i<count; i++)); do
    name="$(yq -r ".plugins[$i].name" "$INVENTORY" 2>/dev/null || echo "")"
    url="$(yq -r ".plugins[$i].url" "$INVENTORY" 2>/dev/null || echo "")"
    tags="$(yq -r ".plugins[$i].tags // [] | join(\" \")" "$INVENTORY" 2>/dev/null || echo "")"
    [ -n "$name" ] && [ -n "$url" ] || continue

    decision=0
    _select_tags "$tags" "$machine" || decision=$?

    case "$decision" in
      1) skipped=$((skipped + 1)); continue ;;
      2) warn "$step_name: $name is manual; skipping"; skipped=$((skipped + 1)); continue ;;
    esac

    if printf '%s\n' "$listed" | grep -qx "$name"; then
      skipped=$((skipped + 1))
      continue
    fi

    if is_dry_run; then
      info "$step_name: would: helm plugin install $url"
      continue
    fi

    info "$step_name: installing $name from $url"
    if ! helm plugin install "$url" >/dev/null 2>&1; then
      error "$step_name: helm plugin install $url failed"
      errors=$((errors + 1))
      continue
    fi
    installed=$((installed + 1))
  done
done

info "$step_name: installed: $installed; skipped: $skipped; errors: $errors"
[ "$errors" -eq 0 ] && exit 0 || exit 1
