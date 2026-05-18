#!/usr/bin/env bash
set -euo pipefail

# Step: P1-40-mise-install
# Idempotency probe (all of):
#   1. For every entry in inventory/mise.yaml -> tools that survives
#      the tag/machine filter, `mise current <tool>` reports a value
#      containing the declared `in_use` version.
#   2. For every entry in inventory/mise.yaml -> python_tools (which may
#      be absent from the inventory — tolerated as an empty list),
#      `uv tool list` mentions the package.
#
# Behaviour:
#   - require_command mise (it's in the public Brewfile; should be
#     installed by P1-30).
#   - Run `mise install` — naturally idempotent: already-installed
#     versions are skipped silently.
#   - For each tool: if `mise current <tool>` matches in_use, skip.
#     Otherwise `mise use --global <tool>@<version>`.
#   - For each python_tool: if `uv tool list | grep -q <pkg>`, skip.
#     Otherwise `uv tool install <pkg>`.
#
# Tag / machine filter:
#   - tags: []                   -> always include.
#   - tags: [optional, BUCKET]   -> include iff PHASE1_INCLUDE_TAGS
#                                   contains BUCKET.
#   - tags: [work]               -> include iff machine == "work".
#   - tags: [personal]           -> include iff machine == "personal".
#   Combinations compose (e.g. [optional, java, work] needs both the
#   PHASE1_INCLUDE_TAGS bucket and a work machine).
#   Machine type is read from ~/.config/chezmoi/chezmoi.toml (key:
#   `machine = "..."`) when present, falling back to $MACHINE_TYPE then
#   "personal".
#
# Dry-run: log `would:` for `mise install`, every `mise use --global`,
# and every `uv tool install`. No mutations.
#
# Exit codes:
#   0 — every surviving tool / python_tool is at the declared version.
#   1 — mise missing, yq missing, inventory unreadable, or a per-tool
#       install failed.
#
# Depends on: P1-30 brew-bundle (installs mise + uv).

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="P1-40-mise-install"

REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
INVENTORY="${REPO_ROOT}/inventory/mise.yaml"

if [ ! -f "$INVENTORY" ]; then
  error "$step_name: inventory missing: $INVENTORY"
  exit 1
fi

if ! command -v mise >/dev/null 2>&1; then
  if is_dry_run; then
    info "$step_name: would: mise install (mise not yet on PATH; P1-30 brew bundle install installs it in real execution)"
    info "$step_name: would: per-tool mise current/use loop (skipping under dry-run)"
    info "$step_name: would: per-pkg uv tool install loop (skipping under dry-run)"
    exit 0
  fi
  error "$step_name: mise not on PATH; P1-30 should have installed it (re-run brew bundle)"
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  if is_dry_run; then
    info "$step_name: would: yq parse of $INVENTORY (yq not yet on PATH; P1-30 installs it)"
    exit 0
  fi
  error "$step_name: yq not on PATH; P1-30 should have installed it"
  exit 1
fi

# --- Helpers ---------------------------------------------------------------

_detect_machine() {
  if [ -r "$HOME/.config/chezmoi/chezmoi.toml" ]; then
    local m
    m="$(grep -E '^[[:space:]]*machine[[:space:]]*=' "$HOME/.config/chezmoi/chezmoi.toml" 2>/dev/null \
         | sed 's/.*=[[:space:]]*//;s/^"//;s/"$//;s/^[[:space:]]*//;s/[[:space:]]*$//' \
         | head -n1)"
    if [ -n "$m" ]; then
      printf '%s\n' "$m"
      return 0
    fi
  fi
  printf '%s\n' "${MACHINE_TYPE:-personal}"
}

# Normalise PHASE1_INCLUDE_TAGS into a space-separated string for grep -w
# style matching.
_include_tags_normalised() {
  local raw="${PHASE1_INCLUDE_TAGS:-}"
  raw="${raw//,/ }"
  printf '%s' "$raw"
}

# _tag_in_include TAG  -> 0 if PHASE1_INCLUDE_TAGS contains TAG (whitespace-
# bounded), else 1.
_tag_in_include() {
  local needle="$1"
  local hay
  hay=" $(_include_tags_normalised) "
  case "$hay" in
    *" $needle "*) return 0 ;;
    *)             return 1 ;;
  esac
}

# Decide whether a given tag list (space-separated) should be installed
# given the current machine type and PHASE1_INCLUDE_TAGS.
# Returns 0 = include, 1 = skip.
_tags_select() {
  local tags="$1"
  local machine="$2"
  # Empty list — always include.
  if [ -z "$tags" ]; then
    return 0
  fi

  # Walk the tags. Optional + machine constraints both have to pass.
  local has_optional=0 optional_buckets="" t
  local machine_constraint=""
  for t in $tags; do
    case "$t" in
      optional) has_optional=1 ;;
      work|personal)
        machine_constraint="$t"
        ;;
      *)
        # Treat anything else as a bucket name (java / gis / claude / etc).
        optional_buckets="$optional_buckets $t"
        ;;
    esac
  done

  # Machine-gated?
  if [ -n "$machine_constraint" ] && [ "$machine_constraint" != "$machine" ]; then
    return 1
  fi

  # Optional? Need at least one bucket in PHASE1_INCLUDE_TAGS.
  if [ "$has_optional" -eq 1 ]; then
    local opted_in=1 b
    for b in $optional_buckets; do
      if _tag_in_include "$b"; then
        opted_in=0
        break
      fi
    done
    [ "$opted_in" -eq 0 ] || return 1
  fi

  return 0
}

# --- Probe -----------------------------------------------------------------

machine_type="$(_detect_machine)"
info "$step_name: machine_type=$machine_type include_tags=\"${PHASE1_INCLUDE_TAGS:-}\""

# Read all tool keys.
mapfile -t TOOL_NAMES < <(yq -r '.tools | keys | .[]' "$INVENTORY" 2>/dev/null || true)

# Read python_tools (tolerate absent / null key as empty).
mapfile -t PYTHON_TOOLS < <(yq -r '(.python_tools // []) | .[]' "$INVENTORY" 2>/dev/null || true)

probe_all_satisfied() {
  command -v mise >/dev/null 2>&1 || return 1

  local tool tags in_use cur
  for tool in "${TOOL_NAMES[@]}"; do
    [ -n "$tool" ] || continue
    tags="$(yq -r ".tools.${tool}.tags // [] | join(\" \")" "$INVENTORY" 2>/dev/null || echo "")"
    if ! _tags_select "$tags" "$machine_type"; then
      continue
    fi
    in_use="$(yq -r ".tools.${tool}.in_use" "$INVENTORY" 2>/dev/null || echo "")"
    [ -n "$in_use" ] && [ "$in_use" != "null" ] || continue
    cur="$(mise current "$tool" 2>/dev/null || echo "")"
    # "latest" in the inventory means "any installed version is fine"
    # (mise resolves "latest" to a real version like 1.95.0 at install
    # time, so a substring match would always fail). Otherwise verify
    # the resolved version contains the declared version prefix.
    if [ "$in_use" = "latest" ]; then
      [ -n "$cur" ] || return 1
    else
      case "$cur" in
        *"$in_use"*) ;;
        *) return 1 ;;
      esac
    fi
  done

  if [ "${#PYTHON_TOOLS[@]}" -gt 0 ] && command -v uv >/dev/null 2>&1; then
    local pkg uvlist
    uvlist="$(uv tool list 2>/dev/null || echo "")"
    for pkg in "${PYTHON_TOOLS[@]}"; do
      [ -n "$pkg" ] || continue
      if ! printf '%s\n' "$uvlist" | grep -qi -E "(^|[[:space:]])${pkg}([[:space:]]|$)"; then
        return 1
      fi
    done
  fi

  return 0
}

if probe_all_satisfied; then
  if is_dry_run; then
    info "$step_name: dry-run; probe passes, would skip"
  else
    skip "$step_name: all mise tools and python_tools satisfied"
  fi
  exit 0
fi

# --- Act -------------------------------------------------------------------

# Step A: `mise install` — idempotent; skips already-installed versions.
if is_dry_run; then
  info "$step_name: would: mise install"
else
  info "$step_name: running: mise install"
  if ! mise install; then
    error "$step_name: mise install failed"
    exit 1
  fi
fi

# Step B: per-tool default check.
for tool in "${TOOL_NAMES[@]}"; do
  [ -n "$tool" ] || continue
  tags="$(yq -r ".tools.${tool}.tags // [] | join(\" \")" "$INVENTORY" 2>/dev/null || echo "")"
  if ! _tags_select "$tags" "$machine_type"; then
    info "$step_name: skip $tool (tags=[$tags] excluded for machine=$machine_type)"
    continue
  fi
  in_use="$(yq -r ".tools.${tool}.in_use" "$INVENTORY" 2>/dev/null || echo "")"
  if [ -z "$in_use" ] || [ "$in_use" = "null" ]; then
    info "$step_name: skip $tool (no in_use declared)"
    continue
  fi
  cur="$(mise current "$tool" 2>/dev/null || echo "")"
  case "$cur" in
    *"$in_use"*)
      skip "$step_name: ${tool}@${in_use} already installed"
      continue
      ;;
  esac
  if is_dry_run; then
    info "$step_name: would: mise use --global ${tool}@${in_use}"
  else
    info "$step_name: running: mise use --global ${tool}@${in_use}"
    if ! mise use --global "${tool}@${in_use}"; then
      error "$step_name: mise use --global ${tool}@${in_use} failed"
      exit 1
    fi
    ok "$step_name: ${tool}@${in_use} now active"
  fi
done

# Step C: python_tools loop. Tolerate absent uv (will be present after
# P1-30 installs it; only relevant on standalone P1-40 invocations).
if [ "${#PYTHON_TOOLS[@]}" -gt 0 ]; then
  if ! command -v uv >/dev/null 2>&1; then
    if is_dry_run; then
      for pkg in "${PYTHON_TOOLS[@]}"; do
        [ -n "$pkg" ] || continue
        info "$step_name: would: uv tool install $pkg (uv not yet on PATH)"
      done
    else
      error "$step_name: uv not on PATH; cannot install python_tools (re-run P1-30)"
      exit 1
    fi
  else
    uvlist="$(uv tool list 2>/dev/null || echo "")"
    for pkg in "${PYTHON_TOOLS[@]}"; do
      [ -n "$pkg" ] || continue
      if printf '%s\n' "$uvlist" | grep -qi -E "(^|[[:space:]])${pkg}([[:space:]]|$)"; then
        skip "$step_name: $pkg already installed"
        continue
      fi
      if is_dry_run; then
        info "$step_name: would: uv tool install $pkg"
      else
        info "$step_name: running: uv tool install $pkg"
        if ! uv tool install "$pkg"; then
          error "$step_name: uv tool install $pkg failed"
          exit 1
        fi
        ok "$step_name: $pkg installed"
      fi
    done
  fi
fi

if is_dry_run; then
  exit 0
fi

if probe_all_satisfied; then
  ok "$step_name: all mise tools and python_tools satisfied"
  exit 0
fi

error "$step_name: post-install probe still fails; inspect mise current and uv tool list"
exit 1
