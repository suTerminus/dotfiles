#!/usr/bin/env bash
set -euo pipefail

# Step: P2-20-brew-bundle-overlays
# Idempotency probe (composite):
#   - Personal: ~/.config/brew/Brewfile.personal exists AND
#     `brew bundle check --file=...Brewfile.personal` exits 0.
#   - On work also: ~/.config/brew/Brewfile.enersis exists AND
#     `brew bundle check --file=...Brewfile.enersis` exits 0.
#
# Behaviour:
#   - probe passes -> skip.
#   - render personal Brewfile if
#     ~/.local/share/chezmoi-private/inventory/brew-personal.yaml exists,
#     via scripts/render-brewfile.sh --source <yaml> --output <tmpl>.
#     Then chezmoi apply --source <PRIVATE> --include=files
#     dot_config/brew/Brewfile.personal so the apply-time target lands.
#   - bundle personal: brew bundle install --file=~/.config/brew/Brewfile.personal.
#     mas pre-check: warn-not-fail if a `mas` line is present and the
#     user is not signed into the App Store.
#   - on work: repeat for Enersis with brew-enersis.yaml + Brewfile.enersis.
#
# Tolerates missing inventories (early Phase 2 with empty overlay):
# logs `info: no <yaml> found; skipping` and exits 0 for that overlay.
#
# Standalone-runnable: sources lib/log.sh, lib/idempotent.sh, lib/phase2.sh
# via SCRIPT_DIR. Locates render-brewfile.sh under $REPO_ROOT/scripts/.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../lib/log.sh
. "${REPO_ROOT}/scripts/lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "${REPO_ROOT}/scripts/lib/idempotent.sh"
# shellcheck source=../lib/phase2.sh
. "${REPO_ROOT}/scripts/lib/phase2.sh"

step_name="P2-20-brew-bundle-overlays"

RENDERER="${REPO_ROOT}/scripts/render-brewfile.sh"

PRIVATE_SOURCE="$HOME/.local/share/chezmoi-private"
ENERSIS_SOURCE="$HOME/.local/share/chezmoi-enersis"

PERSONAL_YAML="$PRIVATE_SOURCE/inventory/brew-personal.yaml"
ENERSIS_YAML="$ENERSIS_SOURCE/inventory/brew-enersis.yaml"

PERSONAL_TMPL="$PRIVATE_SOURCE/home/dot_config/brew/Brewfile.personal.tmpl"
ENERSIS_TMPL="$ENERSIS_SOURCE/home/dot_config/brew/Brewfile.enersis.tmpl"

PERSONAL_BREWFILE="$HOME/.config/brew/Brewfile.personal"
ENERSIS_BREWFILE="$HOME/.config/brew/Brewfile.enersis"

if ! require_command brew "brew not on PATH; re-run phase0/steps/20-homebrew.sh"; then
  exit 1
fi

machine="$(phase2_machine_type || true)"

# Source-vs-rendered mtime check. If the inventory yaml is newer than
# the rendered Brewfile, the rendered file is stale (could be empty
# from an earlier no-op render). Returns 0 if rendered is current
# or if source doesn't exist (nothing to render).
__source_newer_than_rendered() {
  local src="$1" rendered="$2"
  [ -f "$src" ] || return 1
  [ -f "$rendered" ] || return 0
  local src_mt rendered_mt
  src_mt="$(stat -f '%m' "$src" 2>/dev/null || stat -c '%Y' "$src" 2>/dev/null || echo 0)"
  rendered_mt="$(stat -f '%m' "$rendered" 2>/dev/null || stat -c '%Y' "$rendered" 2>/dev/null || echo 0)"
  [ "$src_mt" -gt "$rendered_mt" ]
}

probe_personal_bundle() {
  [ -f "$PERSONAL_BREWFILE" ] || return 1
  if __source_newer_than_rendered "$PERSONAL_YAML" "$PERSONAL_BREWFILE"; then
    return 1
  fi
  brew bundle check --file="$PERSONAL_BREWFILE" >/dev/null 2>&1
}

probe_enersis_bundle() {
  [ -f "$ENERSIS_BREWFILE" ] || return 1
  if __source_newer_than_rendered "$ENERSIS_YAML" "$ENERSIS_BREWFILE"; then
    return 1
  fi
  brew bundle check --file="$ENERSIS_BREWFILE" >/dev/null 2>&1
}

# mas_precheck FILE
# Warn (don't fail) if FILE contains `mas` lines and `mas account` does
# not report a signed-in user. brew bundle will continue to install
# casks/formulae regardless; only mas entries silently no-op.
mas_precheck() {
  local file="$1"
  [ -f "$file" ] || return 0
  if ! grep -qE '^[[:space:]]*mas[[:space:]]+' "$file"; then
    return 0
  fi
  if ! command -v mas >/dev/null 2>&1; then
    warn "$step_name: $file references mas, but mas CLI is not on PATH; mas entries will be skipped"
    return 0
  fi
  if ! mas account >/dev/null 2>&1; then
    warn "$step_name: $file references mas, but the App Store is not signed in; mas entries will be skipped (sign in via App Store, then re-run)"
  fi
  return 0
}

# render_overlay_brewfile YAML TMPL SOURCE_DIR APPLY_PATH
# Render via scripts/render-brewfile.sh, then chezmoi apply the rendered
# Brewfile so the apply-time target lands at $HOME/.config/brew/<name>.
# Under dry-run, log `would:` lines.
render_overlay_brewfile() {
  local yaml="$1" tmpl="$2" source_dir="$3" apply_path="$4"

  if [ ! -x "$RENDERER" ]; then
    error "$step_name: renderer not executable: $RENDERER"
    return 1
  fi
  if [ ! -f "$yaml" ]; then
    info "$step_name: no $yaml found; skipping render"
    return 0
  fi

  # apply_path is the chezmoi source-state name (e.g.
  # dot_config/brew/Brewfile.personal); convert it to the destination
  # path chezmoi expects as a positional argument.
  local dest_path="$HOME/$(printf '%s' "$apply_path" | sed 's|^dot_|.|; s|/dot_|/.|g')"

  if is_dry_run; then
    info "$step_name: dry-run; would: $RENDERER --source $yaml --output $tmpl"
    info "$step_name: dry-run; would: chezmoi apply --source $source_dir $dest_path"
    return 0
  fi

  info "$step_name: rendering $yaml -> $tmpl"
  mkdir -p "$(dirname -- "$tmpl")"
  if ! "$RENDERER" --source "$yaml" --output "$tmpl"; then
    error "$step_name: render failed for $yaml"
    return 1
  fi

  if command -v chezmoi >/dev/null 2>&1; then
    info "$step_name: applying via chezmoi --source $source_dir $dest_path"
    if ! chezmoi apply --source "$source_dir" --force "$dest_path"; then
      warn "$step_name: chezmoi apply failed for $dest_path; the rendered template did not land on disk"
      return 1
    fi
  else
    warn "$step_name: chezmoi not on PATH; rendered template will not be applied"
    return 1
  fi
  return 0
}

# bundle_overlay BREWFILE LABEL
bundle_overlay() {
  local brewfile="$1" label="$2"
  if [ ! -f "$brewfile" ]; then
    info "$step_name: no $brewfile found; skipping $label bundle"
    return 0
  fi
  mas_precheck "$brewfile"
  if is_dry_run; then
    info "$step_name: dry-run; would: brew bundle install --file=$brewfile"
    return 0
  fi
  info "$step_name: brew bundle install --file=$brewfile"
  if ! brew bundle install --file="$brewfile"; then
    error "$step_name: brew bundle install failed for $brewfile"
    return 1
  fi
  ok "$step_name: $label bundle satisfied"
  return 0
}

# Decide which overlays to process.
do_personal=1
do_enersis=0
if [ "$machine" = "work" ]; then
  do_enersis=1
fi

# Fast-path skip if both probes (per applicable overlay) already pass.
both_clean=1
if [ "$do_personal" -eq 1 ] && ! probe_personal_bundle; then
  both_clean=0
fi
if [ "$do_enersis" -eq 1 ] && ! probe_enersis_bundle; then
  both_clean=0
fi
if [ "$both_clean" -eq 1 ]; then
  skip "$step_name: overlay Brewfiles already satisfied"
  exit 0
fi

errors=0

# ---- Personal overlay ----
if [ "$do_personal" -eq 1 ]; then
  if probe_personal_bundle; then
    info "$step_name: personal Brewfile already satisfied; skipping render+bundle"
  else
    if [ -f "$PERSONAL_YAML" ]; then
      if ! render_overlay_brewfile "$PERSONAL_YAML" "$PERSONAL_TMPL" "$PRIVATE_SOURCE" "dot_config/brew/Brewfile.personal"; then
        errors=$((errors + 1))
      fi
    else
      info "$step_name: no brew-personal.yaml found at $PERSONAL_YAML; skipping personal Brewfile bundle"
    fi
    if ! bundle_overlay "$PERSONAL_BREWFILE" "personal"; then
      errors=$((errors + 1))
    fi
  fi
fi

# ---- Enersis overlay (work only) ----
if [ "$do_enersis" -eq 1 ]; then
  if probe_enersis_bundle; then
    info "$step_name: enersis Brewfile already satisfied; skipping render+bundle"
  else
    if [ -f "$ENERSIS_YAML" ]; then
      if ! render_overlay_brewfile "$ENERSIS_YAML" "$ENERSIS_TMPL" "$ENERSIS_SOURCE" "dot_config/brew/Brewfile.enersis"; then
        errors=$((errors + 1))
      fi
    else
      info "$step_name: no brew-enersis.yaml found at $ENERSIS_YAML; skipping enersis Brewfile bundle"
    fi
    if ! bundle_overlay "$ENERSIS_BREWFILE" "enersis"; then
      errors=$((errors + 1))
    fi
  fi
fi

if [ "$errors" -gt 0 ]; then
  error "$step_name: $errors overlay(s) failed"
  exit 1
fi

ok "$step_name: overlay Brewfiles applied"
exit 0
