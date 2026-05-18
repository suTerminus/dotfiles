#!/usr/bin/env bash
set -euo pipefail

# Step: P2-30-clone-overlay-repos
# Idempotency probe (composite, per inventory):
#   - Personal: every entry in
#     ~/.local/share/chezmoi-private/inventory/repos-personal.yaml has
#     its target path present and origin matching .url.
#   - On work also: every entry in
#     ~/.local/share/chezmoi-enersis/inventory/repos-enersis.yaml.
#
# Behaviour:
#   - probe passes -> skip.
#   - else: phase2_clone_repos_from_yaml on each applicable inventory.
#     Four-state per repo (present-correct / wrong-remote / not-a-repo /
#     missing) — same as Phase 1 P1-50.
#   - tolerate empty/absent inventories -- log info, exit 0.
#   - return non-zero if any entry hit an error.
#
# Standalone-runnable: sources lib/log.sh, lib/idempotent.sh, lib/phase2.sh.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"
# shellcheck source=../lib/phase2.sh
. "$SCRIPT_DIR/../lib/phase2.sh"

step_name="P2-30-clone-overlay-repos"

PERSONAL_YAML="$HOME/.local/share/chezmoi-private/inventory/repos-personal.yaml"
ENERSIS_YAML="$HOME/.local/share/chezmoi-enersis/inventory/repos-enersis.yaml"

if ! require_command git "git not on PATH"; then
  exit 1
fi

machine="$(phase2_machine_type || true)"

# Fast-path probe: walk both inventories without mutating, return 0 only
# if every applicable entry is present-correct.
probe_inventory_clean() {
  local yaml="$1"
  [ -f "$yaml" ] || return 0   # absent -> nothing to clean -> "clean"
  command -v yq >/dev/null 2>&1 || return 1
  local count
  count="$(yq -r '.repos | length // 0' "$yaml" 2>/dev/null || echo 0)"
  [ "${count:-0}" -gt 0 ] || return 0
  local i=0
  while [ "$i" -lt "$count" ]; do
    local url path_rel tags_csv abs clone_url
    url="$(yq -r ".repos[$i].url // \"\"" "$yaml")"
    path_rel="$(yq -r ".repos[$i].path // \"\"" "$yaml")"
    tags_csv="$(yq -r ".repos[$i].tags // [] | join(\",\")" "$yaml")"
    i=$((i + 1))
    [ -n "$url" ] && [ -n "$path_rel" ] || continue
    case ",$tags_csv," in
      *,optional,*)
        [ -n "${PHASE2_INCLUDE_OPTIONAL:-}" ] || continue
        ;;
    esac
    case "$path_rel" in
      /*)   abs="$path_rel" ;;
      \~/*) abs="$HOME/${path_rel#\~/}" ;;
      \~)   abs="$HOME" ;;
      *)    abs="$HOME/$path_rel" ;;
    esac
    clone_url="$url"
    case "$url" in
      git@*|https://*|ssh://*) ;;
      github.com/*)
        local rest="${url#github.com/}"
        clone_url="git@github.com:${rest}.git"
        ;;
    esac
    [ -d "$abs/.git" ] || return 1
    probe_repo_at_path "$abs" "$clone_url" || return 1
  done
  return 0
}

errors=0

if probe_inventory_clean "$PERSONAL_YAML"; then
  personal_ok=1
else
  personal_ok=0
fi

enersis_ok=1
if [ "$machine" = "work" ]; then
  if probe_inventory_clean "$ENERSIS_YAML"; then
    enersis_ok=1
  else
    enersis_ok=0
  fi
fi

if [ "$personal_ok" -eq 1 ] && [ "$enersis_ok" -eq 1 ]; then
  skip "$step_name: all overlay-source repos present and correct"
  exit 0
fi

# Process personal inventory always.
if ! phase2_clone_repos_from_yaml "$PERSONAL_YAML"; then
  errors=$((errors + 1))
fi

# Process enersis inventory on work only.
if [ "$machine" = "work" ]; then
  if ! phase2_clone_repos_from_yaml "$ENERSIS_YAML"; then
    errors=$((errors + 1))
  fi
else
  info "$step_name: skip enersis inventory (machine='${machine:-unset}')"
fi

if [ "$errors" -gt 0 ]; then
  error "$step_name: $errors inventory pass(es) had errors"
  exit 1
fi

ok "$step_name: overlay-source repos cloned"
exit 0
