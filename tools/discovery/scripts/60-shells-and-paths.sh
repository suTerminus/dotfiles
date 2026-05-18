#!/usr/bin/env bash
# tools/discovery/scripts/60-shells-and-paths.sh
# Snapshot login shell, $PATH (with provenance guess), shell framework
# presence, and zsh dotfile sizes into shells-and-paths.md. Read-only.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
source "$SCRIPT_DIR/../lib/log.sh"
OUTPUT_DIR="$SCRIPT_DIR/../output"

mkdir -p "$OUTPUT_DIR"

TARGET="$OUTPUT_DIR/shells-and-paths.md"

# Resolve $HOME defensively (set -u safe).
HOME_DIR="${HOME:-}"
if [ -z "$HOME_DIR" ]; then
  HOME_DIR="$(cd ~ 2>/dev/null && pwd)"
fi

# Determine login shell.
log_info "detecting login shell"
SHELL_ENV="${SHELL:-unknown}"
LOGIN_SHELL="unknown"

if command -v dscl >/dev/null 2>&1; then
  if dscl_out="$(dscl . -read "$HOME_DIR" UserShell 2>/dev/null)"; then
    # Output: "UserShell: /bin/zsh"
    parsed="$(printf '%s' "$dscl_out" | awk '/^UserShell:/ {print $2}')"
    [ -n "$parsed" ] && LOGIN_SHELL="$parsed"
  fi
fi

if [ "$LOGIN_SHELL" = "unknown" ] && command -v getent >/dev/null 2>&1; then
  if getent_out="$(getent passwd "$(id -un)" 2>/dev/null)"; then
    parsed="$(printf '%s' "$getent_out" | awk -F: '{print $7}')"
    [ -n "$parsed" ] && LOGIN_SHELL="$parsed"
  fi
fi

if [ "$LOGIN_SHELL" = "unknown" ] && [ -r /etc/passwd ]; then
  username="$(id -un)"
  parsed="$(awk -F: -v u="$username" '$1==u {print $7}' /etc/passwd | head -n1)"
  [ -n "$parsed" ] && LOGIN_SHELL="$parsed"
fi

if [ "$LOGIN_SHELL" = "unknown" ] && [ -n "$SHELL_ENV" ] && [ "$SHELL_ENV" != "unknown" ]; then
  LOGIN_SHELL="$SHELL_ENV"
fi

# Classify a single PATH entry.
classify_path_entry() {
  local entry="$1"
  case "$entry" in
    /opt/homebrew/*|/usr/local/Homebrew/*|/usr/local/Cellar/*)
      printf 'homebrew'
      return
      ;;
  esac
  # Tilde-style $HOME-prefix matching. We compare against expanded $HOME.
  case "$entry" in
    "$HOME_DIR/.mise/"*|"$HOME_DIR"/*.mise/*|*/.mise/*)
      printf 'mise'
      return
      ;;
    "$HOME_DIR/.asdf/"*|*/.asdf/*)
      printf 'asdf'
      return
      ;;
    "$HOME_DIR/.rbenv/"*|*/.rbenv/*)
      printf 'rbenv'
      return
      ;;
    "$HOME_DIR/.pyenv/"*|*/.pyenv/*)
      printf 'pyenv'
      return
      ;;
    "$HOME_DIR/.nodenv/"*|*/.nodenv/*)
      printf 'nodenv'
      return
      ;;
    "$HOME_DIR/.cargo/bin"*)
      printf 'user'
      return
      ;;
    "$HOME_DIR/.local/bin"*|"$HOME_DIR/bin"*|"$HOME_DIR/bin")
      printf 'user'
      return
      ;;
  esac
  case "$entry" in
    /usr/bin|/bin|/usr/sbin|/sbin|/usr/local/bin|/usr/local/sbin)
      printf 'system'
      return
      ;;
  esac
  # Generic user home fallback before unknown.
  case "$entry" in
    "$HOME_DIR"/*)
      printf 'user'
      return
      ;;
  esac
  printf 'unknown'
}

# Render a "yes" / "no" line for a path's existence.
yn_path() {
  local p="$1"
  if [ -e "$p" ]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

# Get size in bytes for a file, or "absent".
file_size_or_absent() {
  local f="$1"
  if [ ! -e "$f" ]; then
    printf 'absent'
    return
  fi
  local sz
  if sz="$(stat -f '%z' "$f" 2>/dev/null)"; then
    printf '%s bytes' "$sz"
    return
  fi
  if sz="$(stat -c '%s' "$f" 2>/dev/null)"; then
    printf '%s bytes' "$sz"
    return
  fi
  if sz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"; then
    printf '%s bytes' "$sz"
    return
  fi
  printf 'unknown size'
}

log_info "decomposing PATH"
PATH_ENTRIES="${PATH:-}"

log_info "detecting frameworks and dotfiles"

tmp="$(mktemp "$OUTPUT_DIR/.shells-and-paths.md.XXXXXX")"

{
  printf '%s\n' '# Shells and PATH'
  printf '\n'
  printf '%s\n' '## Login shell'
  printf -- '- $SHELL: %s\n' "$SHELL_ENV"
  printf -- '- Login shell (from /etc/passwd or dscl): %s\n' "$LOGIN_SHELL"
  printf '\n'
  printf '%s\n' '## PATH (in order)'

  if [ -z "$PATH_ENTRIES" ]; then
    printf '%s\n' '- (PATH is empty)'
  else
    # Split on ':' deterministically; preserve order. Empty entries become
    # the special CWD marker; render explicitly so we do not silently drop them.
    IFS=':' read -r -a _path_arr <<< "$PATH_ENTRIES"
    for entry in "${_path_arr[@]}"; do
      if [ -z "$entry" ]; then
        printf -- '- %-40s [%s]\n' "(empty: cwd)" "unknown"
        continue
      fi
      tag="$(classify_path_entry "$entry")"
      printf -- '- %-40s [%s]\n' "$entry" "$tag"
    done
  fi

  printf '\n'
  printf '%s\n' '## Frameworks present'
  printf -- '- ~/.oh-my-zsh/           : %s\n' "$(yn_path "$HOME_DIR/.oh-my-zsh")"
  printf -- '- ~/.zprezto/             : %s\n' "$(yn_path "$HOME_DIR/.zprezto")"
  if [ -e "$HOME_DIR/.zinit" ] || [ -e "$HOME_DIR/.local/share/zinit" ]; then
    zinit_status="yes"
  else
    zinit_status="no"
  fi
  printf -- '- ~/.zinit/ (or local/share/zinit/) : %s\n' "$zinit_status"
  printf -- '- ~/.tmux.conf            : %s\n' "$(yn_path "$HOME_DIR/.tmux.conf")"
  printf -- '- ~/.config/tmux/         : %s\n' "$(yn_path "$HOME_DIR/.config/tmux")"
  printf -- '- ~/.config/nushell/      : %s\n' "$(yn_path "$HOME_DIR/.config/nushell")"
  printf -- '- ~/.config/starship.toml : %s\n' "$(yn_path "$HOME_DIR/.config/starship.toml")"
  printf -- '- ~/.config/fish/         : %s\n' "$(yn_path "$HOME_DIR/.config/fish")"

  printf '\n'
  printf '%s\n' '## Zsh dotfiles'
  printf -- '- ~/.zshrc:    %s\n' "$(file_size_or_absent "$HOME_DIR/.zshrc")"
  printf -- '- ~/.zprofile: %s\n' "$(file_size_or_absent "$HOME_DIR/.zprofile")"
  printf -- '- ~/.zshenv:   %s\n' "$(file_size_or_absent "$HOME_DIR/.zshenv")"
  printf -- '- ~/.zlogin:   %s\n' "$(file_size_or_absent "$HOME_DIR/.zlogin")"
  printf -- '- ~/.zlogout:  %s\n' "$(file_size_or_absent "$HOME_DIR/.zlogout")"
} > "$tmp"

mv "$tmp" "$TARGET"
log_ok "wrote $TARGET"
