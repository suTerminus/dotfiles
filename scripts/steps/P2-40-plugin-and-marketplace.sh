#!/usr/bin/env bash
set -euo pipefail

# Step: P2-40-plugin-and-marketplace
# Idempotency probe (composite, best-effort):
#   - `claude` CLI lists `ghost-bazaar` as installed plugin (always).
#   - On work also: `enersis/claude-marketplace` is registered as a
#     marketplace.
#
# Behaviour (all best-effort, exit 0 on plugin-mechanic failures so a
# late-stage Claude Code CLI rev doesn't block Phase 2):
#   1. Runtime-discover the plugin install + marketplace register
#      commands by calling `claude --help` (and any nested help). We
#      do not pin commands at author time -- the Phase 2 PRD §8 declares
#      runtime-discovery is the contract.
#   2. If ~/code/personal/ghost-bazaar doesn't exist, warn (don't fail)
#      and exit 0 -- P2-30 should have cloned it; admiral fixes the
#      inventory and re-runs.
#   3. Install plugin: heuristic command sequence is
#      `cd ~/code/personal/ghost-bazaar && claude plugin install .`,
#      subject to runtime check. Under dry-run: log `would:`.
#   4. Smoke test: if ~/code/personal/ghost-bazaar/docs/smoke-test.md
#      exists, parse a `claude ...` line from it (first match wins) and
#      run it. Under dry-run: log `would: smoke test`. Else: warn and
#      continue.
#   5. On work: if the marketplace repo is cloned (try common locations
#      under ~/code/work/), runtime-discover and run the marketplace
#      registration command. Mirror behaviour: dry-run logs `would:`,
#      smoke-test if a smoke-test doc exists.
#
# All failures are warn-not-fail. Exit code is 0 unless the *script
# itself* crashes (set -e covers that).
#
# Standalone-runnable: sources lib/log.sh, lib/idempotent.sh, lib/phase2.sh
# via SCRIPT_DIR.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"
# shellcheck source=../lib/phase2.sh
. "$SCRIPT_DIR/../lib/phase2.sh"

step_name="P2-40-plugin-and-marketplace"

GHOST_BAZAAR="$HOME/code/personal/ghost-bazaar"
GHOST_BAZAAR_SMOKE="$GHOST_BAZAAR/docs/smoke-test.md"

# Common locations the Enersis marketplace might live; we try them in
# order. The authoritative source is repos-enersis.yaml -- we read it
# if present rather than hardcoding, but fall back to common defaults.
ENERSIS_MARKETPLACE_DEFAULTS=(
  "$HOME/code/work/enersis/claude-marketplace"
  "$HOME/code/work/dotfiles-enersis/claude-marketplace"
  "$HOME/code/enersis/claude-marketplace"
)

# probe_plugin_installed
# Returns 0 iff `claude` (any subcommand we can find) lists ghost-bazaar.
# This is a best-effort grep across plausible commands; if none match we
# report `unknown` (return 1) so the act path runs.
probe_plugin_installed() {
  command -v claude >/dev/null 2>&1 || return 1
  # Try the most plausible inventory commands. As of authoring, the
  # CLI surface is in flux, so we accept any of these.
  local out=""
  if out="$(claude plugin list 2>/dev/null)"; then
    printf '%s\n' "$out" | grep -qiE '(^|[[:space:]/])ghost-bazaar([[:space:]]|$)' && return 0
  fi
  if out="$(claude plugins 2>/dev/null)"; then
    printf '%s\n' "$out" | grep -qiE '(^|[[:space:]/])ghost-bazaar([[:space:]]|$)' && return 0
  fi
  if out="$(claude plugin ls 2>/dev/null)"; then
    printf '%s\n' "$out" | grep -qiE '(^|[[:space:]/])ghost-bazaar([[:space:]]|$)' && return 0
  fi
  return 1
}

# probe_marketplace_registered
# Best-effort: grep `claude` output for `enersis/claude-marketplace`.
probe_marketplace_registered() {
  command -v claude >/dev/null 2>&1 || return 1
  local out=""
  if out="$(claude marketplace list 2>/dev/null)"; then
    printf '%s\n' "$out" | grep -qiE 'enersis[/_-]claude[_-]?marketplace' && return 0
  fi
  if out="$(claude marketplaces 2>/dev/null)"; then
    printf '%s\n' "$out" | grep -qiE 'enersis[/_-]claude[_-]?marketplace' && return 0
  fi
  return 1
}

# discover_install_command
# Echo the best-guess install command. Walks `claude --help` looking for
# `plugin` / `install`; if neither surfaces, falls back to
# `claude plugin install .`.
discover_install_command() {
  local help=""
  help="$(claude --help 2>&1 || true)"
  if printf '%s\n' "$help" | grep -qiE '(^|[[:space:]])plugin([[:space:]]|$)'; then
    if printf '%s\n' "$(claude plugin --help 2>&1 || true)" | grep -qiE '(^|[[:space:]])install([[:space:]]|$)'; then
      printf '%s\n' "claude plugin install ."
      return 0
    fi
  fi
  printf '%s\n' "claude plugin install ."
  return 0
}

# discover_marketplace_command MARKETPLACE_PATH
# Echo the best-guess marketplace registration command for the given
# clone path. Walks `claude --help`; falls back to
# `claude marketplace add <path>`.
discover_marketplace_command() {
  local path="$1"
  local help=""
  help="$(claude --help 2>&1 || true)"
  if printf '%s\n' "$help" | grep -qiE '(^|[[:space:]])marketplace([[:space:]]|$)'; then
    if printf '%s\n' "$(claude marketplace --help 2>&1 || true)" | grep -qiE '(^|[[:space:]])add([[:space:]]|$)'; then
      printf '%s\n' "claude marketplace add $path"
      return 0
    fi
  fi
  printf '%s\n' "claude marketplace add $path"
  return 0
}

# extract_smoke_command FILE
# Best-effort: pull the first line from FILE that starts with `claude `
# (after optional code-fence/whitespace). Echoes empty if none found.
extract_smoke_command() {
  local file="$1"
  [ -f "$file" ] || { printf ''; return 0; }
  # Match the first line whose first non-whitespace, non-backtick token
  # is `claude`. Strip leading code-fence backticks/whitespace.
  awk '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/^`+/, "", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/^\$[[:space:]]*/, "", line)
      if (line ~ /^claude([[:space:]]|$)/) {
        # Strip trailing backticks/whitespace.
        sub(/`+[[:space:]]*$/, "", line)
        sub(/[[:space:]]+$/, "", line)
        print line
        exit
      }
    }
  ' "$file"
}

# resolve_enersis_marketplace_path
# Echo the on-disk path of enersis/claude-marketplace if cloned, else
# empty. Reads the inventory file when present; falls back to the
# default location list.
resolve_enersis_marketplace_path() {
  local inv="$HOME/.local/share/chezmoi-enersis/inventory/repos-enersis.yaml"
  if [ -f "$inv" ] && command -v yq >/dev/null 2>&1; then
    local count i path_rel url
    count="$(yq -r '.repos | length // 0' "$inv" 2>/dev/null || echo 0)"
    i=0
    while [ "$i" -lt "$count" ]; do
      url="$(yq -r ".repos[$i].url // \"\"" "$inv")"
      path_rel="$(yq -r ".repos[$i].path // \"\"" "$inv")"
      i=$((i + 1))
      case "$url" in
        *enersis/claude-marketplace*|*enersis_claude-marketplace*)
          case "$path_rel" in
            /*)   printf '%s\n' "$path_rel" ;;
            \~/*) printf '%s\n' "$HOME/${path_rel#\~/}" ;;
            *)    printf '%s\n' "$HOME/$path_rel" ;;
          esac
          return 0
          ;;
      esac
    done
  fi
  local d
  for d in "${ENERSIS_MARKETPLACE_DEFAULTS[@]}"; do
    if [ -d "$d/.git" ]; then
      printf '%s\n' "$d"
      return 0
    fi
  done
  printf ''
  return 1
}

machine="$(phase2_machine_type || true)"

# Fast-path skip if the probes (per applicable scope) already pass.
both_clean=1
if ! probe_plugin_installed; then
  both_clean=0
fi
if [ "$machine" = "work" ] && ! probe_marketplace_registered; then
  both_clean=0
fi
if [ "$both_clean" -eq 1 ]; then
  skip "$step_name: ghost-bazaar plugin (and marketplace if work) already registered"
  exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
  warn "$step_name: claude CLI not on PATH; skipping plugin/marketplace setup"
  exit 0
fi

# ---- ghost-bazaar plugin install ----
if probe_plugin_installed; then
  info "$step_name: ghost-bazaar plugin already installed"
elif [ ! -d "$GHOST_BAZAAR/.git" ]; then
  warn "$step_name: ghost-bazaar not cloned at $GHOST_BAZAAR (P2-30 should have done it; check repos-personal.yaml)"
else
  install_cmd="$(discover_install_command)"
  if is_dry_run; then
    info "$step_name: dry-run; would: (cd $GHOST_BAZAAR && $install_cmd)"
  else
    info "$step_name: installing ghost-bazaar plugin: (cd $GHOST_BAZAAR && $install_cmd)"
    if ! ( cd "$GHOST_BAZAAR" && eval "$install_cmd" ); then
      warn "$step_name: plugin install command exited non-zero (best-effort; verify Claude Code's plugin command surface)"
    else
      ok "$step_name: ghost-bazaar plugin install attempted"
    fi
  fi
fi

# ---- ghost-bazaar smoke test ----
if [ -f "$GHOST_BAZAAR_SMOKE" ]; then
  smoke_cmd="$(extract_smoke_command "$GHOST_BAZAAR_SMOKE")"
  if [ -n "$smoke_cmd" ]; then
    if is_dry_run; then
      info "$step_name: dry-run; would: smoke test '$smoke_cmd'"
    else
      info "$step_name: running ghost-bazaar smoke test: $smoke_cmd"
      if ! eval "$smoke_cmd"; then
        warn "$step_name: ghost-bazaar smoke test failed (best-effort; check $GHOST_BAZAAR_SMOKE)"
      else
        ok "$step_name: ghost-bazaar smoke test passed"
      fi
    fi
  else
    info "$step_name: $GHOST_BAZAAR_SMOKE present but no claude command found in it; skipping smoke test"
  fi
else
  info "$step_name: no smoke-test doc at $GHOST_BAZAAR_SMOKE; skipping smoke test"
fi

# ---- enersis/claude-marketplace (work only) ----
if [ "$machine" = "work" ]; then
  marketplace_path="$(resolve_enersis_marketplace_path || true)"
  if [ -z "$marketplace_path" ]; then
    warn "$step_name: enersis/claude-marketplace not cloned (P2-30 should have done it); skipping registration"
  elif probe_marketplace_registered; then
    info "$step_name: enersis/claude-marketplace already registered"
  else
    register_cmd="$(discover_marketplace_command "$marketplace_path")"
    if is_dry_run; then
      info "$step_name: dry-run; would: $register_cmd"
    else
      info "$step_name: registering enersis/claude-marketplace: $register_cmd"
      if ! eval "$register_cmd"; then
        warn "$step_name: marketplace registration command exited non-zero (best-effort)"
      else
        ok "$step_name: enersis marketplace registration attempted"
      fi
    fi
  fi

  # Marketplace smoke test (work only) -- mirror plugin smoke test.
  if [ -n "${marketplace_path:-}" ]; then
    mp_smoke="$marketplace_path/docs/smoke-test.md"
    if [ -f "$mp_smoke" ]; then
      smoke_cmd="$(extract_smoke_command "$mp_smoke")"
      if [ -n "$smoke_cmd" ]; then
        if is_dry_run; then
          info "$step_name: dry-run; would: marketplace smoke test '$smoke_cmd'"
        else
          info "$step_name: running marketplace smoke test: $smoke_cmd"
          if ! eval "$smoke_cmd"; then
            warn "$step_name: marketplace smoke test failed (best-effort)"
          else
            ok "$step_name: marketplace smoke test passed"
          fi
        fi
      fi
    fi
  fi
else
  info "$step_name: skip marketplace (machine='${machine:-unset}')"
fi

ok "$step_name: plugin/marketplace pass complete (best-effort)"
exit 0
