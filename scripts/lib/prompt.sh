# scripts/lib/prompt.sh
# Small interactive helpers wrapping `read -p` behind require_tty_stdin.
# Safe to source multiple times.

if [ -n "${__PHASE1_PROMPT_SH:-}" ]; then
  return 0
fi
__PHASE1_PROMPT_SH=1

# Source companion libs from the same directory.
__phase1_prompt_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=log.sh
. "${__phase1_prompt_dir}/log.sh"
# shellcheck source=idempotent.sh
. "${__phase1_prompt_dir}/idempotent.sh"

# confirm QUESTION [default-y|default-n]
# Prompts the user with QUESTION and returns 0 for yes, non-zero for no.
# The default applies when the user hits Enter on an empty line; it also
# governs the [Y/n] vs [y/N] hint. require_tty_stdin guards every read:
# in CI / piped contexts the prompt would otherwise return EOF and
# silently take a side, which is exactly the bug Phase 0 chased through
# gh auth.
confirm() {
  local question="$1"
  local default="${2:-default-n}"
  require_tty_stdin "confirm: refusing to prompt without an interactive stdin" || return 2

  local hint reply
  case "$default" in
    default-y) hint="[Y/n]" ;;
    default-n) hint="[y/N]" ;;
    *)
      error "confirm: unknown default \"$default\" (expected default-y or default-n)"
      return 2
      ;;
  esac

  # Read from /dev/tty when available so a step invoked with redirected
  # stdout still gets a real prompt. Falls back to plain read otherwise.
  if [ -r /dev/tty ]; then
    read -r -p "$question $hint " reply </dev/tty || reply=""
  else
    read -r -p "$question $hint " reply || reply=""
  fi

  case "$reply" in
    y|Y|yes|YES|Yes) return 0 ;;
    n|N|no|NO|No)    return 1 ;;
    "")
      [ "$default" = "default-y" ] && return 0
      return 1
      ;;
    *) return 1 ;;
  esac
}
