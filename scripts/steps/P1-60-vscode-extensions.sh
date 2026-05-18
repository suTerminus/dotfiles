#!/usr/bin/env bash
set -euo pipefail

# Step: P1-60-vscode-extensions
# Idempotency probe: every entry in inventory/vscode-extensions.yaml whose
# tags pass the machine + include-tag filter is reported by
# `code --list-extensions`.
#
# Behaviour:
#   - require_command code (installed by P1-30 brew bundle as visual-studio-code).
#   - require_command yq.
#   - For each extension entry that passes the tag filter, probe with
#     `code --list-extensions | grep -qi -F -x <id>`. If missing AND
#     not dry-run, run `code --install-extension <id>`.
#
# Tag filter: same conventions as P1-50 / render-brewfile.
#   tags: []                   -> always include.
#   tags: [optional, BUCKET]   -> include iff PHASE1_INCLUDE_TAGS lists BUCKET.
#   tags: [work]               -> include only on work machine.
#   tags: [personal]           -> always (personal scope, machine-agnostic).
#   tags: [manual]             -> warn-skip.
#
# Dry-run: log `would: code --install-extension <id>` per missing entry.
#
# Exit codes:
#   0 — every required extension installed (or skip).
#   1 — code/yq missing, or one or more installs failed.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="P1-60-vscode-extensions"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/code/personal/dotfiles}"

# Walk public + both overlay sources. Each file iterated independently;
# overlays may not exist yet (Phase 2 clones them).
INVENTORIES=(
  "$DOTFILES_DIR/inventory/vscode-extensions.yaml"
  "$HOME/.local/share/chezmoi-private/inventory/vscode-extensions-personal.yaml"
  "$HOME/.local/share/chezmoi-enersis/inventory/vscode-extensions-enersis.yaml"
)

# At least one must exist.
__any=0
for f in "${INVENTORIES[@]}"; do [ -f "$f" ] && __any=1; done
if [ "$__any" -eq 0 ]; then
  warn "$step_name: no vscode-extensions inventory found; nothing to do"
  exit 0
fi

if ! command -v code >/dev/null 2>&1; then
  if is_dry_run; then
    info "$step_name: would: per-extension code --install-extension (code not on PATH; P1-30 installs Visual Studio Code first)"
    exit 0
  fi
  error "$step_name: code not on PATH; ensure visual-studio-code is in the Brewfile"
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  error "$step_name: yq not on PATH"
  exit 1
fi

# --- Helpers (shared shape with P1-50) ---------------------------------------

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
  local needle="$1"
  case ",${PHASE1_INCLUDE_TAGS:-}," in
    *",${needle},"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Returns 0=include, 1=exclude, 2=manual-warn-skip.
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
  # Layering: [personal] always; [work] only on work; untagged always.
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

# Cache the current extensions list once.
listed="$(code --list-extensions 2>/dev/null || true)"

for INVENTORY in "${INVENTORIES[@]}"; do
  [ -f "$INVENTORY" ] || continue
  count="$(yq '[.extensions[]] | length' "$INVENTORY" 2>/dev/null || echo 0)"
  [ "$count" -gt 0 ] || continue
  info "$step_name: walking $(basename "$INVENTORY") ($count entries)"

  for ((i=0; i<count; i++)); do
    id="$(yq -r ".extensions[$i].id" "$INVENTORY" 2>/dev/null || echo "")"
    tags="$(yq -r ".extensions[$i].tags // [] | join(\" \")" "$INVENTORY" 2>/dev/null || echo "")"
    [ -n "$id" ] || continue

    decision=0
    _select_tags "$tags" "$machine" || decision=$?

    case "$decision" in
      1)
        skipped=$((skipped + 1))
        continue
        ;;
      2)
        warn "$step_name: $id is manual; skipping (warn-not-fail)"
        skipped=$((skipped + 1))
        continue
        ;;
    esac

    # Probe — case-insensitive exact match (vscode normalises ids to lowercase).
    if printf '%s\n' "$listed" | grep -qix -F "$id"; then
      skipped=$((skipped + 1))
      continue
    fi

    if is_dry_run; then
      info "$step_name: would: code --install-extension $id"
      continue
    fi

    info "$step_name: installing $id"
    if ! code --install-extension "$id" --force >/dev/null 2>&1; then
      error "$step_name: code --install-extension $id failed"
      errors=$((errors + 1))
      continue
    fi
    installed=$((installed + 1))
  done
done

info "$step_name: installed: $installed; skipped: $skipped; errors: $errors"
[ "$errors" -eq 0 ] && exit 0 || exit 1
