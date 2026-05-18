#!/usr/bin/env bash
set -euo pipefail

# Step: 50-claude-code
# Idempotency probe (all of):
#   1. `command -v claude` resolves AND `claude --version` exits 0
#      (Claude Code CLI installed and runnable).
#   2. Claude Code config dir signals an authenticated session: either
#      `~/.claude/.credentials.json` is a non-empty file, OR
#      `~/.claude/` exists and is non-empty (loose check, since the exact
#      auth state path may evolve across CLI versions).
#   3. Claude Desktop config dir exists at
#      `~/Library/Application Support/Claude` (Desktop has been launched
#      at least once and the user has signed in).
#
# Authentication note: this step uses the Claude.ai subscription auth
# flow (Pro/Max). No ANTHROPIC_API_KEY is required. Both CLI and Desktop
# authenticate against the same claude.ai account.
#
# If sub-probe 1 fails: install the CLI globally via npm
#   `npm install -g @anthropic-ai/claude-code`.
# Fallback if global install fails due to npm prefix permissions:
#   npm config set prefix ~/.npm-global
#   export PATH="$HOME/.npm-global/bin:$PATH"
#   npm install -g @anthropic-ai/claude-code
# (and add the bin dir to PATH in the shell rc; that's a Phase 1 concern).
#
# If sub-probe 2 fails: prompt the user to run `claude` once and complete
# the browser login, then wait for confirmation and re-probe.
#
# If sub-probe 3 fails: prompt the user to launch Claude Desktop via
# `open -a Claude` and sign in, then wait for confirmation and re-probe.
#
# Depends on step 30 (Brewfile installs `cask "claude"` which provides
# Claude Desktop) and step 20 (Homebrew + node toolchain on PATH so npm
# is available; node may also be installed via the Brewfile).

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="50-claude-code"

CLAUDE_CONFIG_DIR="$HOME/.claude"
CLAUDE_CREDENTIALS_FILE="$CLAUDE_CONFIG_DIR/.credentials.json"
CLAUDE_DESKTOP_CONFIG_DIR="$HOME/Library/Application Support/Claude"

probe_cli_installed() {
  command -v claude >/dev/null 2>&1 || return 1
  claude --version >/dev/null 2>&1 || return 1
  return 0
}

probe_cli_authed() {
  if [ -s "$CLAUDE_CREDENTIALS_FILE" ]; then
    return 0
  fi
  if [ -d "$CLAUDE_CONFIG_DIR" ] && [ -n "$(ls -A "$CLAUDE_CONFIG_DIR" 2>/dev/null)" ]; then
    return 0
  fi
  return 1
}

probe_desktop_configured() {
  [ -d "$CLAUDE_DESKTOP_CONFIG_DIR" ]
}

if is_dry_run; then
  if probe_cli_installed; then
    info "$step_name: dry-run; CLI installed (claude --version ok)"
  else
    info "$step_name: dry-run; would run: npm install -g @anthropic-ai/claude-code"
  fi

  if probe_cli_authed; then
    info "$step_name: dry-run; CLI auth state present at $CLAUDE_CONFIG_DIR"
  else
    info "$step_name: dry-run; would prompt user to run \`claude\` and complete browser login"
  fi

  if probe_desktop_configured; then
    info "$step_name: dry-run; Claude Desktop config dir present"
  else
    info "$step_name: dry-run; would prompt user to launch Claude Desktop via \`open -a Claude\` and sign in"
  fi

  exit 0
fi

# Sub-probe 1: install CLI if missing.
if probe_cli_installed; then
  skip "$step_name: claude CLI already installed"
else
  if ! require_command npm "npm not on PATH; ensure node is installed (Brewfile or step 30)"; then
    exit 1
  fi
  info "$step_name: installing @anthropic-ai/claude-code globally via npm"
  if ! npm install -g @anthropic-ai/claude-code; then
    error "$step_name: npm install -g @anthropic-ai/claude-code failed"
    error "$step_name: if this is a permissions issue, try:"
    error "$step_name:   npm config set prefix ~/.npm-global"
    error "$step_name:   export PATH=\"\$HOME/.npm-global/bin:\$PATH\""
    error "$step_name:   npm install -g @anthropic-ai/claude-code"
    exit 1
  fi
  if ! probe_cli_installed; then
    error "$step_name: claude CLI still not runnable after npm install"
    exit 2
  fi
  ok "$step_name: claude CLI installed"
fi

# Sub-probe 2: authenticate CLI if needed.
if probe_cli_authed; then
  skip "$step_name: claude CLI auth state already present"
else
  if ! require_tty_stdin "$step_name: stdin is not a TTY; the 'Press Enter when Claude Code login completes' prompt would return instantly on EOF -- re-run from an interactive terminal session"; then
    exit 2
  fi
  info "$step_name: claude CLI is not yet authenticated"
  info "$step_name: in another terminal (or after this prompt) run: claude"
  info "$step_name: complete the browser login flow with your claude.ai (Pro/Max) account"
  read -r -p "Press Enter when Claude Code login completes..." _
  if ! probe_cli_authed; then
    error "$step_name: CLI auth probe still fails after user confirmation"
    error "$step_name: expected non-empty $CLAUDE_CREDENTIALS_FILE or non-empty $CLAUDE_CONFIG_DIR"
    exit 2
  fi
  ok "$step_name: claude CLI authenticated"
fi

# Sub-probe 3: ensure Claude Desktop has been launched and signed in.
if probe_desktop_configured; then
  skip "$step_name: Claude Desktop config dir present"
else
  if ! require_tty_stdin "$step_name: stdin is not a TTY; the 'Press Enter when Claude Desktop login completes' prompt would return instantly on EOF -- re-run from an interactive terminal session"; then
    exit 2
  fi
  info "$step_name: Claude Desktop has not been launched yet"
  info "$step_name: launching Claude Desktop now -- sign in with your claude.ai account"
  if ! open -a Claude >/dev/null 2>&1; then
    warn "$step_name: \`open -a Claude\` failed; trying explicit path"
    if ! open -a "/Applications/Claude.app" >/dev/null 2>&1; then
      warn "$step_name: could not auto-launch Claude Desktop; please open it manually"
    fi
  fi
  read -r -p "Press Enter when Claude Desktop login completes..." _
  if ! probe_desktop_configured; then
    error "$step_name: Claude Desktop config dir still missing at $CLAUDE_DESKTOP_CONFIG_DIR"
    exit 2
  fi
  ok "$step_name: Claude Desktop configured"
fi

ok "Claude Code CLI + Desktop authenticated"
exit 0
