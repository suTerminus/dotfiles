#!/usr/bin/env bash
set -euo pipefail

# Step: P1-50-clone-public-repos
# Idempotency probe: for every repo entry in inventory/repos.yaml that
# survives the tag/machine filter, the declared path exists, contains a
# .git/ directory, and `git -C <path> remote get-url origin` matches the
# declared URL (after lower-casing and stripping trailing /.git).
#
# Behaviour: per-repo, four-state handler.
#   1. present-correct  -> skip. If PHASE1_UPDATE_REPOS=1, also
#                          `git -C <path> pull --ff-only` (warn on fail).
#   2. present-not-a-repo -> error. Do NOT delete or modify. Skip entry.
#                            Accumulate error count for non-zero exit.
#   3. present-wrong-remote -> warn. Do NOT modify. Skip entry.
#   4. missing            -> mkdir -p <parent> && git clone <url> <path>.
#                            On clone failure: error, accumulate count.
#
# Errors are localised: one failed clone does not abort the loop. After
# the loop, log `cloned: N; skipped: M; errors: K` and return non-zero
# iff K > 0.
#
# Tag / machine filter (PRD §5):
#   - tags: []                 -> always include.
#   - tags: [personal]         -> include only on personal machines.
#   - tags: [work]             -> include only on work machines.
#   - tags: [manual]           -> always warn-skip (warn-not-fail). Any
#                                  combination including `manual` is
#                                  treated this way.
#   - tags: [optional, BUCKET] -> include iff PHASE1_INCLUDE_TAGS
#                                  contains BUCKET.
#   Machine type is read from ~/.config/chezmoi/chezmoi.toml when
#   present, else $MACHINE_TYPE, else "personal".
#
# URL handling: entries like `github.com/owner/repo` are converted to
# `git@github.com:owner/repo.git` for cloning. SSH form is canonical.
#
# Path resolution: leading `~/` -> $HOME/. Leading `/` -> as-is. Bare
# relative paths (e.g. `code/personal/dotfiles`) -> $HOME/<path>.
#
# Dry-run: every git clone / git pull is replaced by an `info: would:`
# line; mkdir is also gated.
#
# Exit codes:
#   0 — every surviving entry is cloned (or already correct), no errors.
#   1 — yq missing, git missing, inventory missing, or one or more
#       per-repo errors accumulated.
#
# Depends on: P1-00 preflight (gh+ssh ready), P1-30 brew-bundle
# (installs git + yq).

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
. "$SCRIPT_DIR/../lib/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

step_name="P1-50-clone-public-repos"

REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
INVENTORY="${REPO_ROOT}/inventory/repos.yaml"

if [ ! -f "$INVENTORY" ]; then
  error "$step_name: inventory missing: $INVENTORY"
  exit 1
fi

if ! require_command yq "$step_name: yq not on PATH; P1-30 should have installed it"; then
  exit 1
fi
if ! require_command git "$step_name: git not on PATH; install Xcode CLT or re-run Phase 0"; then
  exit 1
fi

# --- Helpers ---------------------------------------------------------------

_detect_machine() {
  if [ -r "$HOME/.config/chezmoi/chezmoi.toml" ]; then
    local m
    m="$(grep -E '^[[:space:]]*machine[[:space:]]*=' "$HOME/.config/chezmoi/chezmoi.toml" 2>/dev/null \
         | sed 's/.*=[[:space:]]*//;s/^"//;s/"$//;s/^[[:space:]]*//;s/[[:space:]]*$//' \
         | head -n1)"
    if [ -n "$m" ]; then
      printf '%s\n' "$m"
      return 0
    fi
  fi
  printf '%s\n' "${MACHINE_TYPE:-personal}"
}

_include_tags_normalised() {
  local raw="${PHASE1_INCLUDE_TAGS:-}"
  raw="${raw//,/ }"
  printf '%s' "$raw"
}

_tag_in_include() {
  local needle="$1"
  local hay
  hay=" $(_include_tags_normalised) "
  case "$hay" in
    *" $needle "*) return 0 ;;
    *)             return 1 ;;
  esac
}

# Convert bare github.com/owner/repo into git@github.com:owner/repo.git.
# Pass full SSH or HTTPS URLs through unchanged.
_url_to_clone_form() {
  local raw="$1"
  case "$raw" in
    git@*|ssh://*|https://*|http://*|git://*)
      printf '%s' "$raw"
      ;;
    github.com/*)
      local rest="${raw#github.com/}"
      # Strip a trailing .git if present, then add it back exactly once.
      rest="${rest%.git}"
      printf 'git@github.com:%s.git' "$rest"
      ;;
    *)
      printf '%s' "$raw"
      ;;
  esac
}

# Compare two URLs in normalised form (lowercase, strip trailing / and .git).
_url_canonical() {
  local u="$1"
  u="$(printf '%s' "$u" | tr '[:upper:]' '[:lower:]')"
  u="${u%/}"
  u="${u%.git}"
  printf '%s' "$u"
}

_resolve_path() {
  local p="$1"
  case "$p" in
    "~/"*) printf '%s' "$HOME/${p#~/}" ;;
    /*)    printf '%s' "$p" ;;
    *)     printf '%s' "$HOME/$p" ;;
  esac
}

# Decide inclusion for a repo's tag list. Returns:
#   0 -> include (clone normally)
#   1 -> hard skip (machine / optional excluded)
#   2 -> warn-skip (manual)
_repo_tags_select() {
  local tags="$1"
  local machine="$2"

  # Manual short-circuits everything else with a warn-skip.
  local t
  for t in $tags; do
    if [ "$t" = "manual" ]; then
      return 2
    fi
  done

  if [ -z "$tags" ]; then
    return 0
  fi

  local has_optional=0 buckets="" has_work=0 has_personal=0
  for t in $tags; do
    case "$t" in
      optional) has_optional=1 ;;
      work)     has_work=1 ;;
      personal) has_personal=1 ;;
      *) buckets="$buckets $t" ;;
    esac
  done

  # Layering model (per user's "we always do public + private then work
  # on top"): [personal] always clones — it's the user's personal scope
  # regardless of machine context. [work] only clones on work machines.
  # Untagged ([] or descriptive-only tags) clones unconditionally.
  if [ "$has_work" -eq 1 ] && [ "$machine" != "work" ]; then
    return 1
  fi

  if [ "$has_optional" -eq 1 ]; then
    local opted_in=1 b
    for b in $buckets; do
      if _tag_in_include "$b"; then
        opted_in=0
        break
      fi
    done
    [ "$opted_in" -eq 0 ] || return 1
  fi

  return 0
}

# --- Update flag -----------------------------------------------------------

_update_repos_requested() {
  case "${PHASE1_UPDATE_REPOS:-0}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Main loop -------------------------------------------------------------

machine_type="$(_detect_machine)"
info "$step_name: machine_type=$machine_type include_tags=\"${PHASE1_INCLUDE_TAGS:-}\""

# Count of repos in the inventory.
repo_count="$(yq -r '.repos | length' "$INVENTORY" 2>/dev/null || echo 0)"
if ! [[ "$repo_count" =~ ^[0-9]+$ ]] || [ "$repo_count" -eq 0 ]; then
  warn "$step_name: no repos declared in $INVENTORY"
  exit 0
fi

# Quick aggregate probe: if every surviving entry is already present-correct,
# we can short-circuit with skip.
probe_all_present() {
  local i tags decision url path full_url canonical_expected canonical_actual actual
  for ((i=0; i<repo_count; i++)); do
    tags="$(yq -r ".repos[$i].tags // [] | join(\" \")" "$INVENTORY" 2>/dev/null || echo "")"
    decision=0
    _repo_tags_select "$tags" "$machine_type" || decision=$?
    [ "$decision" -eq 0 ] || continue
    url="$(yq -r ".repos[$i].url" "$INVENTORY" 2>/dev/null || echo "")"
    path="$(yq -r ".repos[$i].path" "$INVENTORY" 2>/dev/null || echo "")"
    [ -n "$url" ] && [ -n "$path" ] || return 1
    full_url="$(_url_to_clone_form "$url")"
    path="$(_resolve_path "$path")"
    [ -d "$path/.git" ] || return 1
    actual="$(git -C "$path" remote get-url origin 2>/dev/null || echo "")"
    canonical_expected="$(_url_canonical "$full_url")"
    canonical_actual="$(_url_canonical "$actual")"
    [ "$canonical_actual" = "$canonical_expected" ] || return 1
  done
  return 0
}

if probe_all_present && ! _update_repos_requested; then
  if is_dry_run; then
    info "$step_name: dry-run; probe passes, would skip"
  else
    skip "$step_name: all repos present with correct remotes"
  fi
  exit 0
fi

cloned=0
skipped=0
errors=0

for ((i=0; i<repo_count; i++)); do
  url="$(yq -r ".repos[$i].url" "$INVENTORY" 2>/dev/null || echo "")"
  path="$(yq -r ".repos[$i].path" "$INVENTORY" 2>/dev/null || echo "")"
  tags="$(yq -r ".repos[$i].tags // [] | join(\" \")" "$INVENTORY" 2>/dev/null || echo "")"
  name_hint="$(yq -r ".repos[$i].name // .repos[$i].url" "$INVENTORY" 2>/dev/null || echo "<unknown>")"

  if [ -z "$url" ] || [ -z "$path" ]; then
    error "$step_name: entry [$i] missing url or path; skipping"
    errors=$((errors + 1))
    continue
  fi

  decision=0
  _repo_tags_select "$tags" "$machine_type" || decision=$?

  case "$decision" in
    1)
      info "$step_name: skip $name_hint (tags=[$tags] excluded for machine=$machine_type / include_tags)"
      skipped=$((skipped + 1))
      continue
      ;;
    2)
      warn "$step_name: $name_hint is manual; skipping (warn-not-fail)"
      skipped=$((skipped + 1))
      continue
      ;;
  esac

  full_url="$(_url_to_clone_form "$url")"
  resolved_path="$(_resolve_path "$path")"
  parent_dir="$(dirname "$resolved_path")"

  # Determine state.
  state=""
  actual_url=""
  if [ -d "$resolved_path/.git" ]; then
    actual_url="$(git -C "$resolved_path" remote get-url origin 2>/dev/null || echo "")"
    if [ "$(_url_canonical "$actual_url")" = "$(_url_canonical "$full_url")" ]; then
      state="present-correct"
    else
      state="present-wrong-remote"
    fi
  elif [ -e "$resolved_path" ]; then
    state="present-not-a-repo"
  else
    state="missing"
  fi

  case "$state" in
    present-correct)
      skip "$step_name: $name_hint already cloned at $resolved_path"
      skipped=$((skipped + 1))
      if _update_repos_requested; then
        if is_dry_run; then
          info "$step_name: would: git -C $resolved_path pull --ff-only"
        else
          info "$step_name: PHASE1_UPDATE_REPOS=1; pulling $name_hint"
          if ! git -C "$resolved_path" pull --ff-only; then
            warn "$step_name: pull --ff-only failed for $name_hint (non-fast-forward or network); leaving as-is"
          fi
        fi
      fi
      ;;
    present-not-a-repo)
      error "$step_name: $resolved_path exists but is not a git repository"
      errors=$((errors + 1))
      ;;
    present-wrong-remote)
      warn "$step_name: $resolved_path origin is $actual_url, expected $full_url"
      skipped=$((skipped + 1))
      ;;
    missing)
      if is_dry_run; then
        info "$step_name: would: git clone $full_url $resolved_path"
      else
        info "$step_name: cloning $name_hint -> $resolved_path"
        if ! mkdir -p "$parent_dir"; then
          error "$step_name: failed to mkdir -p $parent_dir for $name_hint"
          errors=$((errors + 1))
          continue
        fi
        if ! git clone "$full_url" "$resolved_path"; then
          error "$step_name: git clone $full_url failed for $name_hint"
          errors=$((errors + 1))
          # Clean up any partial dir the failed clone may have left so
          # the next pass starts from "missing" rather than
          # "present-not-a-repo".
          if [ -d "$resolved_path" ] && [ ! -d "$resolved_path/.git" ]; then
            rm -rf "$resolved_path"
          fi
          continue
        fi
        ok "$step_name: cloned $name_hint"
        cloned=$((cloned + 1))
      fi
      ;;
  esac
done

info "$step_name: cloned: $cloned; skipped: $skipped; errors: $errors"

if [ "$errors" -gt 0 ]; then
  exit 1
fi
exit 0
