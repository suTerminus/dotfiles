#!/usr/bin/env bash
set -euo pipefail

# Step: P3-30-post-install
# Composes four independent hooks, each with its own probe-then-act:
#
#   1. gh extensions     — probe `gh extension list | grep -q <ext>` per
#                          required extension (current default:
#                          dlvhdr/gh-dash); install missing ones with
#                          `gh extension install`. (gh-copilot dropped:
#                          `gh copilot` is now a built-in subcommand.)
#   2. Raycast settings  — if a settings file exists in the chezmoi
#                          private-overlay output AND Raycast.app is
#                          installed, log a manual-import pointer
#                          (Raycast has no stable settings-import CLI).
#   3. Amethyst presence — informational check that Amethyst.app is
#                          installed (it's the chosen tiling WM;
#                          configure via its own preferences UI).
#   4. Claude Code smoke — `claude --version` exits 0; warn (not fail) on
#                          missing.
#
# Each hook is self-contained; a failing hook does not abort the others.
# The step's overall exit code is non-zero only if a hook tried to act
# and its re-probe still failed — read-only / informational hooks (e.g.
# the Claude smoke check) never fail the step on their own.
#
# Under PHASE1_DRY_RUN=1, each hook logs `would: <action>` for the
# branches that would mutate state and skips the actual command.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
# shellcheck source=../lib/log.sh
. "$LIB_DIR/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$LIB_DIR/idempotent.sh"
# shellcheck source=../lib/macos.sh
. "$LIB_DIR/macos.sh"

step_name="P3-30-post-install"

# Conservative default extension set. Future work: read from
# inventory/manual.yaml or a dedicated inventory/gh-extensions.yaml
# rather than hard-coding here.
# `gh copilot` is a built-in gh subcommand on recent versions; the
# old github/gh-copilot extension is no longer installable. Keeping the
# list short and current.
#   dlvhdr/gh-dash    — TUI dashboard for PRs/issues
#   dlvhdr/gh-enhance — TUI dashboard for GitHub Actions runs
GH_EXTENSIONS=(
  "dlvhdr/gh-dash"
  "dlvhdr/gh-enhance"
)

RAYCAST_SETTINGS="$HOME/.config/raycast/settings.json"

hook_failures=0

# --------------------------------------------------------------------
# Hook 1: gh extensions
# --------------------------------------------------------------------
hook_gh_extensions() {
  if ! command -v gh >/dev/null 2>&1; then
    warn "$step_name: gh not on PATH; skipping gh-extensions hook"
    return 0
  fi

  local listed
  if ! listed="$(gh extension list 2>/dev/null)"; then
    listed=""
  fi

  local ext short missing_any=0
  for ext in "${GH_EXTENSIONS[@]}"; do
    # Match either the org/repo form or the bare repo name (gh prints
    # the repo column, sometimes prefixed with `gh-`).
    short="${ext##*/}"
    if printf '%s\n' "$listed" | grep -q -E "(^|[[:space:]/])${short}([[:space:]]|$)"; then
      skip "$step_name: gh extension $ext already installed"
      continue
    fi

    missing_any=1
    if is_dry_run; then
      info "would: gh extension install $ext"
      continue
    fi

    info "$step_name: installing gh extension $ext"
    if ! gh extension install "$ext"; then
      warn "$step_name: gh extension install $ext failed"
      hook_failures=$((hook_failures + 1))
      continue
    fi
    ok "$step_name: gh extension $ext installed"
  done

  if [ "$missing_any" -eq 0 ]; then
    skip "$step_name: all gh extensions present"
  fi
}

# --------------------------------------------------------------------
# Hook 2: Raycast settings (manual-import pointer)
# --------------------------------------------------------------------
hook_raycast() {
  if [ ! -f "$RAYCAST_SETTINGS" ]; then
    skip "$step_name: no Raycast settings at $RAYCAST_SETTINGS; nothing to import"
    return 0
  fi

  if ! mac_manual_detect_app "com.raycast.macos"; then
    warn "$step_name: Raycast settings present but Raycast.app not installed"
    return 0
  fi

  # Raycast has no stable CLI for settings import; the user must import
  # manually. We surface the file path so they know exactly which file.
  info "$step_name: Raycast settings present at $RAYCAST_SETTINGS"
  info "$step_name: import manually via Raycast > Preferences > Advanced > Import"
}

# --------------------------------------------------------------------
# Hook 3: Amethyst presence check (configures via its own UI; no
# defaults-import path like Rectangle had).
# --------------------------------------------------------------------
hook_amethyst() {
  if ! mac_manual_detect_app "com.amethyst.Amethyst"; then
    skip "$step_name: Amethyst.app not installed (will install via Phase 1 brew bundle)"
    return 0
  fi
  ok "$step_name: Amethyst.app present (configure via its preferences UI)"
}

# --------------------------------------------------------------------
# Hook 4: Claude Code smoke test
# --------------------------------------------------------------------
hook_claude_smoke() {
  if ! command -v claude >/dev/null 2>&1; then
    warn "$step_name: claude CLI not on PATH (smoke test skipped)"
    return 0
  fi
  if claude --version >/dev/null 2>&1; then
    ok "$step_name: claude --version ok"
  else
    warn "$step_name: claude --version failed (CLI present but not runnable)"
  fi
}

# --------------------------------------------------------------------
# Hook 5: Hammerspoon Accessibility-permission nudge.
# Hammerspoon needs Accessibility to move windows; the grant is per-user
# and can only be granted through System Settings. We probe the API and
# emit a one-line manual instruction if it's denied.
# --------------------------------------------------------------------
hook_hammerspoon() {
  if ! mac_manual_detect_app "org.hammerspoon.Hammerspoon"; then
    skip "$step_name: Hammerspoon.app not installed (will install via Phase 1 brew bundle)"
    return 0
  fi
  if ! command -v hs >/dev/null 2>&1; then
    warn "$step_name: Hammerspoon installed but \`hs\` CLI not on PATH yet (start Hammerspoon once so init.lua runs cliInstall)"
    return 0
  fi
  # `hs.accessibilityState()` returns true iff Accessibility is granted.
  if [ "$(hs -c 'return hs.accessibilityState()' 2>/dev/null)" = "true" ]; then
    ok "$step_name: Hammerspoon Accessibility granted (layout watcher live)"
  else
    warn "$step_name: Hammerspoon needs Accessibility — System Settings → Privacy & Security → Accessibility → enable Hammerspoon"
  fi
}

# --------------------------------------------------------------------

hook_gh_extensions
hook_raycast
hook_amethyst
hook_claude_smoke
hook_hammerspoon

if [ "$hook_failures" -gt 0 ]; then
  error "$step_name: $hook_failures hook(s) failed"
  exit 1
fi

ok "$step_name: post-install hooks complete"
exit 0
