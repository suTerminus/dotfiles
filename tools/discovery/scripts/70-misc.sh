#!/usr/bin/env bash
# tools/discovery/scripts/70-misc.sh
# Miscellaneous catalog: GPG keys, SSH pubkey filenames (NEVER contents),
# npm globals, pip --user, pipx, uv tools, VSCode/Cursor extensions.
# Read-only sensor.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
source "$SCRIPT_DIR/../lib/log.sh"
OUTPUT_DIR="$SCRIPT_DIR/../output"

mkdir -p "$OUTPUT_DIR"

TARGET="$OUTPUT_DIR/misc.md"
HOME_DIR="${HOME:-}"
if [ -z "$HOME_DIR" ]; then
  HOME_DIR="$(cd ~ 2>/dev/null && pwd)"
fi

tmp="$(mktemp "$OUTPUT_DIR/.misc.md.XXXXXX")"

emit_section_block() {
  # $1 = label for log
  # $2 = command output (string, possibly empty)
  # $3 = "skip-msg" used if output is empty
  local label="$1"
  local body="$2"
  local skip_msg="$3"
  printf '%s\n' '```'
  if [ -z "$body" ]; then
    printf '%s\n' "$skip_msg"
  else
    printf '%s\n' "$body"
  fi
  printf '%s\n' '```'
}

{
  printf '%s\n' '# Miscellaneous Catalog'
  printf '\n'
  printf '%s\n' '## GPG keys'
  if command -v gpg >/dev/null 2>&1; then
    log_info "collecting gpg secret-key metadata"
    gpg_out="$(gpg --list-secret-keys --keyid-format=long 2>/dev/null || true)"
    if [ -z "$gpg_out" ]; then
      gpg_msg="none"
    else
      gpg_msg="$gpg_out"
    fi
    emit_section_block "gpg" "$gpg_msg" "none"
  else
    log_skip "gpg not installed"
    emit_section_block "gpg" "" "gpg not installed"
  fi
  printf '\n'

  printf '%s\n' '## SSH public key filenames'
  if [ -d "$HOME_DIR/.ssh" ]; then
    log_info "listing ssh public key filenames (names only)"
    # Filenames only. Sorted, no contents read.
    pub_list="$(LC_ALL=C ls -1 "$HOME_DIR/.ssh" 2>/dev/null | awk '/\.pub$/' | LC_ALL=C sort -u)"
    if [ -z "$pub_list" ]; then
      printf '%s\n' '- (no .pub files found)'
    else
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        printf -- '- %s\n' "$f"
      done <<< "$pub_list"
    fi
  else
    log_skip "no ~/.ssh directory"
    printf '%s\n' '- (~/.ssh directory not present)'
  fi
  printf '\n'

  printf '%s\n' '## npm global packages'
  if command -v npm >/dev/null 2>&1; then
    log_info "collecting npm global packages"
    npm_out="$(npm list -g --depth=0 2>/dev/null || true)"
    emit_section_block "npm" "$npm_out" "(npm produced no output)"
  else
    log_skip "npm not installed"
    emit_section_block "npm" "" "npm not installed"
  fi
  printf '\n'

  printf '%s\n' '## pip user packages'
  pip_cmd=""
  if command -v pip >/dev/null 2>&1; then
    pip_cmd="pip"
  elif command -v pip3 >/dev/null 2>&1; then
    pip_cmd="pip3"
  fi
  if [ -n "$pip_cmd" ]; then
    log_info "collecting pip user packages via $pip_cmd"
    pip_out="$("$pip_cmd" list --user 2>/dev/null || true)"
    emit_section_block "pip" "$pip_out" "(no user-installed packages)"
  else
    log_skip "pip not installed"
    emit_section_block "pip" "" "pip not installed"
  fi
  printf '\n'

  printf '%s\n' '## pipx packages'
  if command -v pipx >/dev/null 2>&1; then
    log_info "collecting pipx packages"
    pipx_out="$(pipx list --short 2>/dev/null || true)"
    emit_section_block "pipx" "$pipx_out" "(no pipx packages)"
  else
    log_skip "pipx not installed"
    emit_section_block "pipx" "" "pipx not installed"
  fi
  printf '\n'

  printf '%s\n' '## uv tools'
  if command -v uv >/dev/null 2>&1; then
    log_info "collecting uv tools"
    uv_out="$(uv tool list 2>/dev/null || true)"
    emit_section_block "uv" "$uv_out" "(no uv tools installed)"
  else
    log_skip "uv not installed"
    emit_section_block "uv" "" "uv not installed"
  fi
  printf '\n'

  printf '%s\n' '## VSCode extensions'
  if command -v code >/dev/null 2>&1; then
    log_info "collecting VSCode extensions"
    code_out="$(code --list-extensions 2>/dev/null | LC_ALL=C sort -u || true)"
    emit_section_block "code" "$code_out" "(no VSCode extensions reported)"
  else
    log_skip "code not installed"
    emit_section_block "code" "" "code not installed"
  fi
  printf '\n'

  printf '%s\n' '## Cursor extensions'
  if command -v cursor >/dev/null 2>&1; then
    log_info "collecting Cursor extensions"
    cursor_out="$(cursor --list-extensions 2>/dev/null | LC_ALL=C sort -u || true)"
    emit_section_block "cursor" "$cursor_out" "(no Cursor extensions reported)"
  else
    log_skip "cursor not installed"
    emit_section_block "cursor" "" "cursor not installed"
  fi
} > "$tmp"

mv "$tmp" "$TARGET"
log_ok "wrote $TARGET"
