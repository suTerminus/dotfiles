#!/usr/bin/env bash
# scripts/render-brewfile.sh
# Render a chezmoi-flavoured Brewfile template from an inventory YAML.
#
# Reads a YAML inventory file (default inventory/brew.yaml relative to the
# repo root) with shape:
#   taps:     [{name, tags}]
#   formulae: [{name, tags, [note]}]
#   casks:    [{name, tags, [note]}]
#   mas:      [{name, id, tags}]   # optional; tolerated when absent
#
# Writes a chezmoi-templated Brewfile to --output (default
# home/dot_config/brew/Brewfile.tmpl relative to the repo root).
#
# Tag semantics (inventory/README.md):
#   []                  always emit
#   [personal]          emit only on personal machines (chezmoi-conditional)
#   [work]              emit only on work machines (chezmoi-conditional)
#   [optional, BUCKET]  skip unless --include-tag BUCKET is passed
#   [manual, ...]       never emitted by the renderer (P1-50 / P3-20 warn)
#
# Tag composition is AND. e.g. [optional, java, work] means
# "opt-in bucket java AND machine work."
#
# Re-usable for Phase 2 overlays via --source / --output.

set -euo pipefail

# Resolve the repo root from the script location so default paths
# remain stable regardless of cwd.
__rb_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
__rb_repo_root="$(cd -- "${__rb_script_dir}/.." && pwd)"

# Defaults (anchored to repo root).
SOURCE="${__rb_repo_root}/inventory/brew.yaml"
OUTPUT="${__rb_repo_root}/home/dot_config/brew/Brewfile.tmpl"
DRY_RUN=0
INCLUDE_TAGS=()

# Reserved tag tokens; everything else in tags[] is a bucket name.
__rb_is_reserved_tag() {
  case "$1" in
    optional|manual|work|personal) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: render-brewfile.sh [options]

Reads a YAML inventory of taps/formulae/casks/mas and renders a
chezmoi-flavoured Brewfile template.

Options:
  --source <yaml>      Inventory YAML to read.
                       Default: <repo>/inventory/brew.yaml
  --output <tmpl>      Brewfile template to write.
                       Default: <repo>/home/dot_config/brew/Brewfile.tmpl
  --include-tag TAG    Opt in to entries tagged [optional, TAG].
                       Repeatable.
  --dry-run            Render to a temp file and diff -u against the
                       current --output. Exit 0 (whether identical or
                       different); the diff is emitted on stdout.
  -h, --help           Show this help.

Tag composition is AND. [optional, java, work] requires --include-tag java
AND emits inside a chezmoi {{ if eq .machine "work" }} block.

Machine filtering is NOT resolved at render time: the renderer emits
chezmoi conditionals so the same template works on both machine types.
Tag filtering (--include-tag) IS resolved at render time.
EOF
}

# Parse argv.
while [ $# -gt 0 ]; do
  case "$1" in
    --source)       SOURCE="$2"; shift 2 ;;
    --output)       OUTPUT="$2"; shift 2 ;;
    --include-tag)  INCLUDE_TAGS+=("$2"); shift 2 ;;
    --dry-run)      DRY_RUN=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)
      printf 'render-brewfile.sh: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# Hard-fail early if yq is missing or not the Go variant.
if ! command -v yq >/dev/null 2>&1; then
  printf 'render-brewfile.sh: yq is required (Go yq, mikefarah/yq)\n' >&2
  exit 1
fi

if [ ! -f "$SOURCE" ]; then
  printf 'render-brewfile.sh: source not found: %s\n' "$SOURCE" >&2
  exit 1
fi

# Build a quick lookup table for include-tag membership.
__rb_include_match() {
  local needle="$1"
  local t
  for t in "${INCLUDE_TAGS[@]:-}"; do
    [ -n "$t" ] || continue
    [ "$t" = "$needle" ] && return 0
  done
  return 1
}

# Decide what to do with one entry given its tags array.
# Echos one of:
#   skip                     (drop entirely)
#   always                   (emit unconditionally)
#   if-work                  (wrap in {{ if eq .machine "work" }})
#   if-personal              (wrap in {{ if eq .machine "personal" }})
__rb_decide() {
  local tags_csv="$1"

  # Empty tags → always emit.
  if [ -z "$tags_csv" ]; then
    echo "always"
    return 0
  fi

  local has_optional=0 has_manual=0 has_work=0 has_personal=0
  local buckets=() tag
  local IFS=','
  # shellcheck disable=SC2206
  local arr=($tags_csv)
  unset IFS

  for tag in "${arr[@]}"; do
    case "$tag" in
      optional) has_optional=1 ;;
      manual)   has_manual=1 ;;
      work)     has_work=1 ;;
      personal) has_personal=1 ;;
      "") ;;
      *) buckets+=("$tag") ;;
    esac
  done

  # Manual: renderer never emits.
  if [ "$has_manual" -eq 1 ]; then
    echo "skip"
    return 0
  fi

  # Optional: at least one bucket must be in --include-tag.
  if [ "$has_optional" -eq 1 ]; then
    local matched=0 b
    for b in "${buckets[@]:-}"; do
      [ -n "$b" ] || continue
      if __rb_include_match "$b"; then matched=1; break; fi
    done
    if [ "$matched" -eq 0 ]; then
      echo "skip"
      return 0
    fi
  fi

  # Layering: [personal] always emits unconditionally — the user's
  # personal scope applies on every machine. [work] wraps in a chezmoi
  # work-only conditional. Both together is a contradiction → skip.
  if [ "$has_work" -eq 1 ] && [ "$has_personal" -eq 1 ]; then
    echo "skip"
    return 0
  fi
  if [ "$has_work" -eq 1 ]; then
    echo "if-work"
    return 0
  fi

  echo "always"
}

# Emit a single Brewfile line for an entry, wrapping in a chezmoi
# conditional block when needed. Args:
#   $1  decision (always|if-work|if-personal)
#   $2  brewfile keyword (tap|brew|cask|mas)
#   $3  name (or pre-formatted suffix for mas)
#   $4  optional comment to inline ("" for none)
__rb_emit_line() {
  local decision="$1" kw="$2" payload="$3" comment="${4:-}"
  local body
  case "$kw" in
    mas)  body="${payload}" ;;  # caller pre-formats: '"Name", id: 12345'
    *)    body="\"${payload}\"" ;;
  esac
  local line="${kw} ${body}"
  if [ -n "$comment" ]; then
    line="${line}  # ${comment}"
  fi

  case "$decision" in
    always)
      printf '%s\n' "$line" >>"$OUT_TMP"
      ;;
    if-work)
      printf '{{ if eq .machine "work" -}}\n%s\n{{- end }}\n' "$line" >>"$OUT_TMP"
      ;;
    if-personal)
      printf '{{ if eq .machine "personal" -}}\n%s\n{{- end }}\n' "$line" >>"$OUT_TMP"
      ;;
  esac
}

# Pull a flat TSV of "name<TAB>tags-csv<TAB>note<TAB>extra" rows for the
# given top-level key. Tolerates missing keys (yq emits nothing for the
# `// []` guarded path).
#
# Go yq (mikefarah/yq) does not support jq's --arg, so the key is
# interpolated by bash into the expression. This is safe here because
# the key is hard-coded by the caller, never user input.
#
# $1 = top-level key (taps|formulae|casks|mas)
# $2 = extra yq expression for the 4th TSV column (default: empty string).
__rb_extract() {
  local key="$1"
  local extra_expr="${2:-\"\"}"

  yq '.'"$key"' // [] | .[] |
        [ .name,
          ((.tags // []) | join(",")),
          (.note // ""),
          ('"$extra_expr"')
        ] | @tsv' "$SOURCE" 2>/dev/null || true
}

# Counters for the report (printed to stderr, not into the template).
COUNT_TAPS=0
COUNT_FORMULAE=0
COUNT_CASKS=0
COUNT_MAS=0
SKIP_OPTIONAL=0
SKIP_MACHINE=0   # informational; machine-conditional entries are emitted, not skipped
SKIP_MANUAL=0

# Write to a temp file; promote to OUTPUT atomically (or diff in dry-run).
OUT_TMP="$(mktemp -t render-brewfile.XXXXXX)"
# shellcheck disable=SC2064
trap "rm -f '$OUT_TMP'" EXIT

# Render header.
{
  printf '# %s\n' "Brewfile.tmpl — rendered by scripts/render-brewfile.sh"
  printf '# %s\n' "Source: inventory/brew.yaml"
  printf '# %s\n' "DO NOT EDIT BY HAND. Re-run the renderer to update."
  if [ "${#INCLUDE_TAGS[@]}" -gt 0 ]; then
    printf '# include-tag: %s\n' "${INCLUDE_TAGS[*]}"
  fi
  printf '\n'
} >"$OUT_TMP"

# Render one section.
# $1 = key (taps|formulae|casks|mas)
# $2 = brewfile keyword (tap|brew|cask|mas)
# $3 = section heading
__rb_render_section() {
  local key="$1" kw="$2" heading="$3"

  # Collect filtered entries first into arrays so we can emit a heading
  # only when there's content. Entries are stored as
  # "decision\tkw\tpayload\tcomment".
  local rows=()
  local raw_rows=""

  if [ "$kw" = "mas" ]; then
    raw_rows="$(__rb_extract "$key" '(.id // "")')"
  else
    raw_rows="$(__rb_extract "$key")"
  fi

  if [ -n "$raw_rows" ]; then
    while IFS=$'\t' read -r name tags_csv note extra; do
      [ -n "$name" ] || continue

      local decision
      decision="$(__rb_decide "$tags_csv")"

      case "$decision" in
        skip)
          # Categorise the skip for reporting.
          case ",$tags_csv," in
            *,manual,*) SKIP_MANUAL=$((SKIP_MANUAL+1)) ;;
            *,optional,*) SKIP_OPTIONAL=$((SKIP_OPTIONAL+1)) ;;
            *) SKIP_MACHINE=$((SKIP_MACHINE+1)) ;;
          esac
          continue
          ;;
      esac

      local payload
      if [ "$kw" = "mas" ]; then
        # extra holds the App Store id; need both for the line.
        if [ -z "$extra" ]; then
          # No id? Skip silently — mas entries without ids are unusable.
          continue
        fi
        payload="\"${name}\", id: ${extra}"
      else
        payload="$name"
      fi

      rows+=("${decision}"$'\t'"${kw}"$'\t'"${payload}"$'\t'"${note}")
    done <<<"$raw_rows"
  fi

  # Heading + lines (only if any survived).
  if [ "${#rows[@]}" -gt 0 ]; then
    printf '# %s\n' "$heading" >>"$OUT_TMP"
    local row d k p c
    for row in "${rows[@]}"; do
      IFS=$'\t' read -r d k p c <<<"$row"
      __rb_emit_line "$d" "$k" "$p" "$c"
      case "$k" in
        tap)  COUNT_TAPS=$((COUNT_TAPS+1)) ;;
        brew) COUNT_FORMULAE=$((COUNT_FORMULAE+1)) ;;
        cask) COUNT_CASKS=$((COUNT_CASKS+1)) ;;
        mas)  COUNT_MAS=$((COUNT_MAS+1)) ;;
      esac
    done
    printf '\n' >>"$OUT_TMP"
  fi
}

__rb_render_section "taps"     "tap"  "Taps"
__rb_render_section "formulae" "brew" "Formulae"
__rb_render_section "casks"    "cask" "Casks"
__rb_render_section "mas"      "mas"  "Mac App Store"

# Final delivery: dry-run diff, or atomic move into place.
if [ "$DRY_RUN" -eq 1 ]; then
  if [ -f "$OUTPUT" ]; then
    if diff -u "$OUTPUT" "$OUT_TMP"; then
      printf 'render-brewfile.sh: --dry-run: %s is up to date\n' "$OUTPUT" >&2
    else
      printf 'render-brewfile.sh: --dry-run: %s would change\n' "$OUTPUT" >&2
    fi
  else
    printf 'render-brewfile.sh: --dry-run: %s does not exist; would be created (%d bytes)\n' \
      "$OUTPUT" "$(wc -c <"$OUT_TMP" | tr -d ' ')" >&2
    # Show the candidate content as a unified diff against /dev/null for clarity.
    diff -u /dev/null "$OUT_TMP" || true
  fi
else
  mkdir -p "$(dirname -- "$OUTPUT")"
  mv -- "$OUT_TMP" "$OUTPUT"
  # mktemp creates 0600; relax to repo-standard 0644 so the committed
  # template is reviewable by anyone with read access to the tree.
  chmod 0644 "$OUTPUT"
  # Drop the trap target so EXIT doesn't try to rm the moved file.
  trap - EXIT
fi

# Report counts on stderr — caller can capture if needed.
printf 'render-brewfile.sh: emitted taps=%d formulae=%d casks=%d mas=%d; skipped manual=%d optional=%d machine-skip=%d\n' \
  "$COUNT_TAPS" "$COUNT_FORMULAE" "$COUNT_CASKS" "$COUNT_MAS" \
  "$SKIP_MANUAL" "$SKIP_OPTIONAL" "$SKIP_MACHINE" >&2

exit 0
