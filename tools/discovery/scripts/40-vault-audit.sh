#!/usr/bin/env bash
# tools/discovery/scripts/40-vault-audit.sh
# Audit a private Obsidian-style vault using METADATA-ONLY commands.
#
# Design rule: this script never reads the contents of any file inside
# the vault. Allowed tools against the vault are find (used only with
# metadata predicates such as -type, -name, -iname, -mindepth,
# -maxdepth), ls, stat, du, and file. File counts are obtained via
# pipelines that emit only paths and feed them through wc -l.
#
# Pipelines that would emit file CONTENTS are intentionally absent:
# no content-dump utilities, no shell redirection from a vault file,
# no -exec invocations that read bytes, no awk-over-record-text,
# no sed-print-cycle. The red-cell navigator scans for these.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
source "$SCRIPT_DIR/../lib/log.sh"
OUTPUT_DIR="$SCRIPT_DIR/../output"

VAULT_FLAG=""

usage() {
  printf '%s\n' \
    'Usage: 40-vault-audit.sh [--vault-path PATH] [--help]' \
    '' \
    'Audits a private vault by recording structure and counts only.' \
    'File contents are never inspected.' \
    '' \
    'Options:' \
    '  --vault-path PATH  Path to the vault directory.' \
    '  --help             Show this help and exit.' \
    '' \
    'Resolution order:' \
    '  1. --vault-path flag' \
    '  2. $VAULT_PATH environment variable' \
    '  3. If neither is set, write a "skipped" artefact and exit 0.' \
    '' \
    'Captured metadata:' \
    '  - Top-level directory listing (one level deep)' \
    '  - Total file count' \
    '  - Total disk usage (du -sh)' \
    '  - File counts by extension (.md, .txt, .canvas, .json, .png, .jpg, .pdf)' \
    '  - Filename-pattern hits for *config*, *setup*, *decision*, *script*' \
    '' \
    'Output: tools/discovery/output/vault-audit.md'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --vault-path)
      if [ $# -lt 2 ]; then
        log_error "--vault-path requires an argument"
        exit 2
      fi
      VAULT_FLAG="$2"
      shift 2
      ;;
    --vault-path=*)
      VAULT_FLAG="${1#--vault-path=}"
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
TARGET="$OUTPUT_DIR/vault-audit.md"

write_atomic() {
  local body="$1"
  local tmp
  tmp="$(mktemp "$OUTPUT_DIR/.vault-audit.md.XXXXXX")"
  printf '%s' "$body" > "$tmp"
  mv "$tmp" "$TARGET"
}

VAULT="${VAULT_FLAG:-${VAULT_PATH:-}}"

if [ -z "$VAULT" ]; then
  log_skip "vault audit: no --vault-path or \$VAULT_PATH set"
  body="$(printf '%s\n' \
    '# Vault Audit' \
    '' \
    '## Status' \
    'Skipped: no --vault-path provided and $VAULT_PATH unset.' \
    'Re-run with --vault-path PATH to audit.')"
  write_atomic "$body"
  log_ok "wrote $TARGET (skipped)"
  exit 0
fi

if [ ! -e "$VAULT" ]; then
  log_warn "vault path '$VAULT' does not exist"
  body="$(printf '%s\n' \
    '# Vault Audit' \
    '' \
    '## Status' \
    "Vault path missing: $VAULT" \
    'The configured vault path does not exist on this machine.' \
    'Re-run with --vault-path PATH pointing at an existing directory.')"
  write_atomic "$body"
  log_ok "wrote $TARGET (missing path)"
  exit 0
fi

if [ ! -d "$VAULT" ]; then
  log_error "vault path '$VAULT' is not a directory"
  exit 2
fi

log_info "auditing vault metadata at $VAULT"

# Top-level directories (one level deep, sorted, basename only).
top_dirs="$(find "$VAULT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
  | LC_ALL=C sort \
  | while IFS= read -r d; do printf '%s\n' "${d##*/}"; done)"

if [ -z "$top_dirs" ]; then
  top_dirs_csv="(none)"
else
  top_dirs_csv="$(printf '%s' "$top_dirs" | paste -sd, - | sed 's/,/, /g')"
fi

# Total file count.
total_files="$(find "$VAULT" -type f 2>/dev/null | wc -l | tr -d ' ')"
[ -z "$total_files" ] && total_files=0

# Total size.
total_size="$(du -sh "$VAULT" 2>/dev/null | awk '{print $1}')"
[ -z "$total_size" ] && total_size="unknown"

# Extension counts.
count_ext() {
  local ext="$1"
  local n
  n="$(find "$VAULT" -type f -iname "*.${ext}" 2>/dev/null | wc -l | tr -d ' ')"
  [ -z "$n" ] && n=0
  printf '%s' "$n"
}

c_md="$(count_ext md)"
c_txt="$(count_ext txt)"
c_canvas="$(count_ext canvas)"
c_json="$(count_ext json)"
c_png="$(count_ext png)"
c_jpg="$(count_ext jpg)"
c_pdf="$(count_ext pdf)"

tracked_sum=$(( c_md + c_txt + c_canvas + c_json + c_png + c_jpg + c_pdf ))
other_count=$(( total_files - tracked_sum ))
[ "$other_count" -lt 0 ] && other_count=0

# Pattern hits. We count files whose basename matches the pattern
# (case-insensitive) and emit the deduplicated set of top-level
# directories under which they appear. Only top-level dir names are
# disclosed; deep paths are never emitted.
pattern_hit() {
  local pat="$1"
  local count=0
  local -A topset=()
  local f rel top
  # Use find with -iname pattern; iterate via process substitution.
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    count=$(( count + 1 ))
    rel="${f#"$VAULT"/}"
    case "$rel" in
      */*)
        top="${rel%%/*}"
        ;;
      *)
        top="(root)"
        ;;
    esac
    topset[$top]=1
  done < <(find "$VAULT" -type f -iname "$pat" 2>/dev/null)
  local tops=""
  if [ ${#topset[@]} -gt 0 ]; then
    tops="$(printf '%s\n' "${!topset[@]}" | LC_ALL=C sort | paste -sd, - | sed 's/,/, /g')"
  fi
  printf '%s|%s' "$count" "$tops"
}

format_pattern_line() {
  local label="$1" data="$2"
  local n="${data%%|*}"
  local where="${data#*|}"
  if [ -z "$where" ]; then
    printf -- '- %s filenames: %s\n' "$label" "$n"
  else
    printf -- '- %s filenames: %s (under %s)\n' "$label" "$n" "$where"
  fi
}

p_config="$(pattern_hit '*config*')"
p_setup="$(pattern_hit '*setup*')"
p_decision="$(pattern_hit '*decision*')"
p_script="$(pattern_hit '*script*')"

tmp="$(mktemp "$OUTPUT_DIR/.vault-audit.md.XXXXXX")"

{
  printf '# Vault Audit\n\n'
  printf '## Structure\n'
  printf -- '- Vault path: %s\n' "$VAULT"
  printf -- '- Top-level directories: %s\n' "$top_dirs_csv"
  printf -- '- Total files: %s\n' "$total_files"
  printf -- '- Total size: %s\n\n' "$total_size"

  printf '## Files by extension\n'
  printf -- '- .md: %s\n' "$c_md"
  printf -- '- .txt: %s\n' "$c_txt"
  printf -- '- .canvas: %s\n' "$c_canvas"
  printf -- '- .json: %s\n' "$c_json"
  printf -- '- .png: %s\n' "$c_png"
  printf -- '- .jpg: %s\n' "$c_jpg"
  printf -- '- .pdf: %s\n' "$c_pdf"
  printf -- '- other: %s\n\n' "$other_count"

  printf '## Filename pattern hits\n'
  format_pattern_line "'*config*'"   "$p_config"
  format_pattern_line "'*setup*'"    "$p_setup"
  format_pattern_line "'*decision*'" "$p_decision"
  format_pattern_line "'*script*'"   "$p_script"
  printf '\n'

  printf '## Action items\n'
  printf '(populated during M2 review; left blank by Discovery)\n'
  printf -- '- [ ] Extract any decisions worth migrating to docs/decisions/\n'
  printf -- '- [ ] Extract any scripts worth migrating to dotfiles or ghost-bazaar\n'
  printf -- '- [ ] Confirm vault repo URL and access pattern\n'
} > "$tmp"

mv "$tmp" "$TARGET"

log_ok "wrote $TARGET (files=$total_files size=$total_size)"
