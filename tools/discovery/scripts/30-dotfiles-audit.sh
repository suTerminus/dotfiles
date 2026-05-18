#!/usr/bin/env bash
# tools/discovery/scripts/30-dotfiles-audit.sh
# Catalog tracked files on a dotfiles branch into a markdown audit checklist.
# Read-only sensor: never writes outside the discovery output directory.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
source "$SCRIPT_DIR/../lib/log.sh"
OUTPUT_DIR="$SCRIPT_DIR/../output"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

BRANCH="wip"

usage() {
  cat <<'USAGE'
Usage: 30-dotfiles-audit.sh [--branch NAME] [--help]

Audits tracked files on the given dotfiles branch and writes a markdown
checklist to tools/discovery/output/dotfiles-audit.md.

Options:
  --branch NAME  Git branch to audit (default: wip)
  --help         Show this help and exit

For each tracked file the audit records: relative path, last-modified
date (from git log), line count, and a category guess. Subtrees with
more than 5 files are summarised at the directory level.

The script is read-only: it never modifies the dotfiles repo or the
working tree. Output is written atomically.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --branch)
      if [ $# -lt 2 ]; then
        log_error "--branch requires an argument"
        exit 2
      fi
      BRANCH="$2"
      shift 2
      ;;
    --branch=*)
      BRANCH="${1#--branch=}"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      log_error "unknown argument: $1"
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"
TARGET="$OUTPUT_DIR/dotfiles-audit.md"

if ! git -C "$REPO_ROOT" rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  log_error "branch '$BRANCH' not found"
  exit 2
fi

log_info "auditing branch '$BRANCH' in $REPO_ROOT"

# Categorise a path. Echoes the category string.
categorise() {
  local p="$1"
  local base="${p##*/}"
  case "$p" in
    *.zsh|*.zsh-theme|*/zshrc|*/.zshrc|*/.zshenv|*/.zprofile)
      echo "zsh-config"; return ;;
  esac
  case "$base" in
    .zshrc|.zshenv|.zprofile|zshrc|zshenv|zprofile)
      echo "zsh-config"; return ;;
    .gitconfig|gitconfig|.gitignore|.gitmessage|.gitmodules)
      echo "git-config"; return ;;
    Brewfile|Brewfile.lock.json)
      echo "brew-bundle"; return ;;
  esac
  case "$p" in
    .zsh/*)
      echo "zsh-config"; return ;;
    *nvim/*|*vim/*|*.lua|*.vim|.vimrc)
      echo "editor-config"; return ;;
    *tmux*)
      echo "multiplexer-config"; return ;;
    *.sh|bin/*|.bin/*|*/bin/*)
      echo "script"; return ;;
    Brewfile*)
      echo "brew-bundle"; return ;;
  esac
  echo "other"
}

# Collect tracked files (sorted, deterministic).
files_raw="$(git -C "$REPO_ROOT" ls-tree -r --name-only "$BRANCH" | LC_ALL=C sort)"

if [ -z "$files_raw" ]; then
  log_warn "branch '$BRANCH' has no tracked files"
fi

# Identify subtrees with > 5 files. We use the immediate parent directory
# as the grouping key, but only treat it as a "deeply nested" subtree
# when the parent itself contains a slash (i.e. depth >= 2). Top-level
# files (no slash) and shallow ones (one component) are always listed
# individually.
declare -a GROUP_DIRS=()
declare -A DIR_COUNT=()

while IFS= read -r path; do
  [ -z "$path" ] && continue
  case "$path" in
    */*)
      parent="${path%/*}"
      ;;
    *)
      continue
      ;;
  esac
  # Only consider as a subtree group if parent has at least one slash
  # OR the top-level dir starts with a dotfile-style nested config dir.
  # Spec example uses ~/.config/nvim/ which has parent ".config/nvim".
  case "$parent" in
    */*)
      DIR_COUNT[$parent]=$(( ${DIR_COUNT[$parent]:-0} + 1 ))
      ;;
    *)
      # Single-component parent (e.g. "bootstrap"); allow grouping too
      # so a flat-but-large dir of >5 files collapses.
      DIR_COUNT[$parent]=$(( ${DIR_COUNT[$parent]:-0} + 1 ))
      ;;
  esac
done <<< "$files_raw"

# Determine which directories qualify (> 5 files). Sort for determinism.
qualified_dirs=""
for d in "${!DIR_COUNT[@]}"; do
  if [ "${DIR_COUNT[$d]}" -gt 5 ]; then
    qualified_dirs+="$d"$'\n'
  fi
done
qualified_dirs="$(printf '%s' "$qualified_dirs" | sed '/^$/d' | LC_ALL=C sort)"

# A path is "covered" by a qualified dir if any qualified dir is a
# prefix (matching whole path components) of its parent chain.
is_covered() {
  local path="$1"
  local q
  while IFS= read -r q; do
    [ -z "$q" ] && continue
    case "$path" in
      "$q"/*)
        printf '%s' "$q"
        return 0
        ;;
    esac
  done <<< "$qualified_dirs"
  return 1
}

# When multiple qualified dirs match (e.g. ".config" and ".config/nvim"),
# collapse to the deepest (longest) match for display.
deepest_cover() {
  local path="$1"
  local best=""
  local q
  while IFS= read -r q; do
    [ -z "$q" ] && continue
    case "$path" in
      "$q"/*)
        if [ ${#q} -gt ${#best} ]; then
          best="$q"
        fi
        ;;
    esac
  done <<< "$qualified_dirs"
  printf '%s' "$best"
}

# Build the set of dirs we will actually emit as group entries (only
# the deepest qualifying dir on any given path's chain).
declare -A EMIT_DIR=()
declare -A EMIT_DIR_FILES=()
declare -A EMIT_DIR_LINES=()

# First pass: assign each file to either a group dir or to "individual".
declare -a INDIV_PATHS=()

while IFS= read -r path; do
  [ -z "$path" ] && continue
  cover="$(deepest_cover "$path")"
  if [ -n "$cover" ]; then
    EMIT_DIR[$cover]=1
    EMIT_DIR_FILES[$cover]=$(( ${EMIT_DIR_FILES[$cover]:-0} + 1 ))
    # Read blob and count lines. This reads dotfiles-repo content (we own
    # this repo; it is not the vault).
    if blob_lines="$(git -C "$REPO_ROOT" show "$BRANCH:$path" 2>/dev/null | wc -l | tr -d ' ')"; then
      EMIT_DIR_LINES[$cover]=$(( ${EMIT_DIR_LINES[$cover]:-0} + blob_lines ))
    fi
  else
    INDIV_PATHS+=("$path")
  fi
done <<< "$files_raw"

# Build a merged, sorted list of emission keys: each individual path
# and each group dir. For group dirs we use a synthetic key suffixed
# with a trailing slash so it sorts naturally next to its siblings.
declare -a EMIT_KEYS=()
for p in "${INDIV_PATHS[@]}"; do
  EMIT_KEYS+=("F:$p")
done
for d in "${!EMIT_DIR[@]}"; do
  EMIT_KEYS+=("D:$d")
done

# Sort keys by the path portion (after "F:" / "D:") for deterministic output.
sorted_keys="$(printf '%s\n' "${EMIT_KEYS[@]}" | LC_ALL=C sort -t: -k2)"

tmp="$(mktemp "$OUTPUT_DIR/.dotfiles-audit.md.XXXXXX")"

{
  printf '# Dotfiles Audit -- %s\n\n' "$BRANCH"
  printf 'For each item, decide: keep / port / drop / template-ify.\n\n'

  while IFS= read -r key; do
    [ -z "$key" ] && continue
    kind="${key%%:*}"
    rest="${key#*:}"
    if [ "$kind" = "F" ]; then
      path="$rest"
      # Last-modified date (YYYY-MM-DD slice of %ai).
      last_mod_full="$(git -C "$REPO_ROOT" log -1 --format=%ai "$BRANCH" -- "$path" 2>/dev/null || true)"
      last_mod="${last_mod_full%% *}"
      [ -z "$last_mod" ] && last_mod="unknown"
      lines="$(git -C "$REPO_ROOT" show "$BRANCH:$path" 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
      [ -z "$lines" ] && lines=0
      cat="$(categorise "$path")"
      printf '## %s\n' "$path"
      printf -- '- Currently: %s lines, last modified %s, category: %s\n' "$lines" "$last_mod" "$cat"
      printf -- '- [ ] Keep as-is\n'
      printf -- '- [ ] Port to new structure\n'
      printf -- '- [ ] Template-ify\n'
      printf -- '- [ ] Drop\n'
      printf -- '- Notes:\n\n'
    else
      d="$rest"
      files="${EMIT_DIR_FILES[$d]:-0}"
      total_lines="${EMIT_DIR_LINES[$d]:-0}"
      cat="$(categorise "$d/_placeholder")"
      printf '## %s/ (directory)\n' "$d"
      printf -- '- Currently: %s files, %s lines total, category: %s\n' "$files" "$total_lines" "$cat"
      printf -- '- [ ] Keep as-is\n'
      printf -- '- [ ] Port to new structure\n'
      printf -- '- [ ] Template-ify\n'
      printf -- '- [ ] Drop\n'
      printf -- '- Notes:\n\n'
    fi
  done <<< "$sorted_keys"
} > "$tmp"

mv "$tmp" "$TARGET"

indiv_count="${#INDIV_PATHS[@]}"
dir_count="${#EMIT_DIR[@]}"
log_ok "wrote $TARGET (files=$indiv_count dirs=$dir_count branch=$BRANCH)"
