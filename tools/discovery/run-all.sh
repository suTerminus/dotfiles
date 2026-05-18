#!/usr/bin/env bash
# tools/discovery/run-all.sh
# Orchestrator for the discovery sensor array.
# Runs each numbered script in order, seeds editable templates,
# and prints a summary of artefacts produced under output/.
#
# All discovery scripts are read-only on the system they probe.
# Outputs land in tools/discovery/output/ (gitignored).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"

OUTPUT_DIR="$SCRIPT_DIR/output"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

BRANCH=""
VAULT_PATH_FLAG=""

usage() {
  cat <<'USAGE'
Usage: run-all.sh [--branch NAME] [--vault-path PATH] [--help]

Runs the seven read-only discovery scripts in numeric order and seeds
editable templates into output/ if they are missing.

Options:
  --branch NAME         Forwarded to scripts/30-dotfiles-audit.sh.
                        Branch to compare against in the dotfiles audit.
  --vault-path PATH     Forwarded to scripts/40-vault-audit.sh.
                        Path to the Obsidian vault to audit.
  --help                Show this message and exit.

Outputs (under tools/discovery/output/):
  installed-brew.yaml
  installed-apps.yaml
  dotfiles-audit.md
  vault-audit.md
  mise-asdf.yaml
  shells-and-paths.md
  misc.md
  manual-installs.yaml   (seeded from template, not overwritten)
  decisions.md           (seeded from template, not overwritten)

Exit code:
  0 if all seven discovery scripts exited 0.
  Non-zero if any discovery script failed (run continues past failures).
USAGE
}

# ---------- Argument parsing ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --branch)
      if [ $# -lt 2 ]; then
        log_error "--branch requires an argument"
        usage >&2
        exit 2
      fi
      BRANCH="$2"
      shift 2
      ;;
    --branch=*)
      BRANCH="${1#--branch=}"
      shift
      ;;
    --vault-path)
      if [ $# -lt 2 ]; then
        log_error "--vault-path requires an argument"
        usage >&2
        exit 2
      fi
      VAULT_PATH_FLAG="$2"
      shift 2
      ;;
    --vault-path=*)
      VAULT_PATH_FLAG="${1#--vault-path=}"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

# ---------- Template seeding (idempotent) ----------
seed_template() {
  local src="$1"
  local dst="$2"
  local label="$3"
  if [ -e "$dst" ]; then
    log_skip "$label exists; not overwriting"
  else
    cp "$src" "$dst"
    log_ok "seeded $label from template"
  fi
}

seed_template \
  "$TEMPLATE_DIR/decisions.md.tmpl" \
  "$OUTPUT_DIR/decisions.md" \
  "decisions.md"

seed_template \
  "$TEMPLATE_DIR/catalog-entry.yaml.tmpl" \
  "$OUTPUT_DIR/manual-installs.yaml" \
  "manual-installs.yaml"

# ---------- Run discovery scripts ----------
overall_rc=0
declare -a FAILED_SCRIPTS=()

run_script() {
  local rel="$1"
  shift
  local path="$SCRIPTS_DIR/$rel"
  log_info "Running: scripts/$rel"
  set +e
  bash "$path" "$@"
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    log_error "scripts/$rel exited $rc"
    overall_rc=1
    FAILED_SCRIPTS+=("scripts/$rel (exit $rc)")
  fi
}

run_script "10-brew.sh"
run_script "20-applications.sh"

if [ -n "$BRANCH" ]; then
  run_script "30-dotfiles-audit.sh" --branch "$BRANCH"
else
  run_script "30-dotfiles-audit.sh"
fi

if [ -n "$VAULT_PATH_FLAG" ]; then
  run_script "40-vault-audit.sh" --vault-path "$VAULT_PATH_FLAG"
else
  run_script "40-vault-audit.sh"
fi

run_script "50-mise-asdf.sh"
run_script "60-shells-and-paths.sh"
run_script "70-misc.sh"

# ---------- Summary ----------
# Each artefact: filename + label suffix (empty or "(seeded from template)").
ARTEFACTS=(
  "installed-brew.yaml|"
  "installed-apps.yaml|"
  "dotfiles-audit.md|"
  "vault-audit.md|"
  "mise-asdf.yaml|"
  "shells-and-paths.md|"
  "misc.md|"
  "manual-installs.yaml|(seeded from template)"
  "decisions.md|(seeded from template)"
)

{
  printf '\n'
  printf 'Discovery complete.\n'
  printf '\n'
  printf 'Outputs in tools/discovery/output/:\n'
  for entry in "${ARTEFACTS[@]}"; do
    name="${entry%%|*}"
    suffix="${entry#*|}"
    if [ -e "$OUTPUT_DIR/$name" ]; then
      marker="[OK]"
    else
      marker="[MISSING]"
    fi
    if [ -n "$suffix" ]; then
      printf '  %s  %s %s\n' "$marker" "$name" "$suffix"
    else
      printf '  %s  %s\n' "$marker" "$name"
    fi
  done
  printf '\n'
  printf 'Next: review each file, replace [TODO] tags with real categorization,\n'
  printf 'fill in decisions.md. Then translate into inventory/*.yaml.\n'
  if [ ${#FAILED_SCRIPTS[@]} -gt 0 ]; then
    printf '\n'
    printf 'Failures:\n'
    for f in "${FAILED_SCRIPTS[@]}"; do
      printf '  [FAIL] %s\n' "$f"
    done
  fi
} >&2

exit "$overall_rc"
