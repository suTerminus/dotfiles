#!/usr/bin/env bash
set -euo pipefail

# Step: P1-70-krew-plugins
# Idempotency probe: every entry in inventory/krew.yaml whose tags pass
# the machine + include-tag filter is reported by `kubectl krew list`.
#
# Behaviour:
#   - require_command kubectl + krew. If krew is missing, point at the
#     Brewfile entry that ships it (currently in dotfiles-enersis since
#     all krew plugins are work-tagged).
#   - For each plugin entry that passes the tag filter, install via
#     `kubectl krew install <name>`. Idempotent at krew's layer too.
#
# Tag filter: identical to P1-60 (work-only plugins respect machine type).
#
# Dry-run: log `would: kubectl krew install <name>` per missing entry.
#
# Exit codes:
#   0 — every required plugin installed (or skip).
#   1 — kubectl/krew/yq missing, or one or more installs failed.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="P1-70-krew-plugins"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/code/personal/dotfiles}"

INVENTORIES=(
  "$DOTFILES_DIR/inventory/krew.yaml"
  "$HOME/.local/share/chezmoi-private/inventory/krew-personal.yaml"
  "$HOME/.local/share/chezmoi-enersis/inventory/krew-enersis.yaml"
)
__any=0
for f in "${INVENTORIES[@]}"; do [ -f "$f" ] && __any=1; done
if [ "$__any" -eq 0 ]; then
  info "$step_name: no krew inventory found; skipping"
  exit 0
fi

if ! command -v kubectl >/dev/null 2>&1; then
  if is_dry_run; then
    info "$step_name: would: per-plugin kubectl krew install (kubectl not yet on PATH; P1-30 installs kubernetes-cli first)"
    exit 0
  fi
  error "$step_name: kubectl not on PATH; ensure kubernetes-cli is in the Brewfile"
  exit 1
fi

# krew lives at ~/.krew/bin/kubectl-krew once installed via brew. brew's
# krew formula puts a symlink/binary that kubectl picks up as a plugin.
# Add ~/.krew/bin to PATH if needed (zshrc already does this).
[ -d "$HOME/.krew/bin" ] && export PATH="$PATH:$HOME/.krew/bin"

if ! kubectl krew version >/dev/null 2>&1; then
  if is_dry_run; then
    info "$step_name: would: per-plugin install (krew not yet bootstrapped; P1-30 installs the formula, then it self-bootstraps on first kubectl-krew invocation)"
    exit 0
  fi
  error "$step_name: krew not on PATH; ensure 'krew' formula is in the Brewfile (currently in dotfiles-enersis/inventory/brew-enersis.yaml)"
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  error "$step_name: yq not on PATH"
  exit 1
fi

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

listed="$(kubectl krew list 2>/dev/null || true)"

for INVENTORY in "${INVENTORIES[@]}"; do
  [ -f "$INVENTORY" ] || continue
  count="$(yq '[.plugins[]] | length' "$INVENTORY" 2>/dev/null || echo 0)"
  [ "$count" -gt 0 ] || continue
  info "$step_name: walking $(basename "$INVENTORY") ($count plugins)"

  for ((i=0; i<count; i++)); do
    name="$(yq -r ".plugins[$i].name" "$INVENTORY" 2>/dev/null || echo "")"
    tags="$(yq -r ".plugins[$i].tags // [] | join(\" \")" "$INVENTORY" 2>/dev/null || echo "")"
    [ -n "$name" ] || continue

    decision=0
    _select_tags "$tags" "$machine" || decision=$?

    case "$decision" in
      1)
        skipped=$((skipped + 1))
        continue
        ;;
      2)
        warn "$step_name: $name is manual; skipping (warn-not-fail)"
        skipped=$((skipped + 1))
        continue
        ;;
    esac

    if printf '%s\n' "$listed" | awk '{print $1}' | grep -qx "$name"; then
      skipped=$((skipped + 1))
      continue
    fi

    if is_dry_run; then
      info "$step_name: would: kubectl krew install $name"
      continue
    fi

    info "$step_name: installing $name"
    if ! kubectl krew install "$name" >/dev/null 2>&1; then
      error "$step_name: kubectl krew install $name failed"
      errors=$((errors + 1))
      continue
    fi
    installed=$((installed + 1))
  done
done

info "$step_name: installed: $installed; skipped: $skipped; errors: $errors"
[ "$errors" -eq 0 ] && exit 0 || exit 1
