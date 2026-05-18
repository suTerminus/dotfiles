# scripts/lib/phase2.sh
# Phase 2-specific shared helpers:
#   - phase2_machine_type   : echo "personal" | "work" | "" by reading
#                             chezmoi config (or falling back to env).
#   - phase2_load_bw_session: source the persisted BW_SESSION file (if any)
#                             into the calling shell, mode-validating the
#                             file along the way. Never echoes the token.
#   - phase2_clone_repos_from_yaml : parse a repos-*.yaml inventory and
#                             clone any missing entries; idempotent on
#                             repo-already-present, hard-fails on
#                             wrong-remote / not-a-repo. Mirrors P1-50's
#                             four-state model for symmetry.
#
# Source after lib/log.sh and lib/idempotent.sh — this file does the same
# multi-source guard the rest of the lib uses, so re-sourcing is cheap.

if [ -n "${__PHASE2_SH:-}" ]; then
  return 0
fi
__PHASE2_SH=1

__phase2_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=log.sh
. "${__phase2_dir}/log.sh"
# shellcheck source=idempotent.sh
. "${__phase2_dir}/idempotent.sh"

# phase2_machine_type
# Echo "personal" or "work" based on the chezmoi data dictionary.
# Falls back to $PHASE2_MACHINE if chezmoi is not on PATH or its data
# does not contain a `.machine` field. Echoes the empty string and
# returns non-zero if neither source resolves.
#
# The two sources of truth are:
#   1. `chezmoi data | jq -r '.machine // empty'`
#   2. ~/.config/chezmoi/chezmoi.toml (machine = "...") -- a cheap regex
#      so we don't depend on jq parsing the toml.
#   3. $PHASE2_MACHINE override (escape hatch for tests + dry-run probes).
phase2_machine_type() {
  if [ -n "${PHASE2_MACHINE:-}" ]; then
    printf '%s\n' "$PHASE2_MACHINE"
    return 0
  fi

  if command -v chezmoi >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    local m
    m="$(chezmoi data 2>/dev/null | jq -r '.machine // empty' 2>/dev/null || true)"
    if [ -n "$m" ] && [ "$m" != "null" ]; then
      printf '%s\n' "$m"
      return 0
    fi
  fi

  local toml="$HOME/.config/chezmoi/chezmoi.toml"
  if [ -f "$toml" ]; then
    local line
    line="$(grep -E '^[[:space:]]*machine[[:space:]]*=' "$toml" 2>/dev/null | head -n1 || true)"
    if [ -n "$line" ]; then
      # Strip everything up to and including the first '=' then strip
      # quotes + whitespace.
      local val="${line#*=}"
      val="${val#"${val%%[![:space:]]*}"}"   # ltrim
      val="${val%"${val##*[![:space:]]}"}"   # rtrim
      val="${val%\"}"
      val="${val#\"}"
      val="${val%\'}"
      val="${val#\'}"
      if [ -n "$val" ]; then
        printf '%s\n' "$val"
        return 0
      fi
    fi
  fi

  printf ''
  return 1
}

# phase2_load_bw_session
# If $BW_SESSION is already set + non-empty, return 0.
# Otherwise read from ~/.local/state/macbook-setup/bw-session if present,
# export BW_SESSION, and return 0. Returns 1 if no session is available.
# Verifies the session file mode is 0600; warns (does not fail) on drift.
# Never echoes the session value.
phase2_load_bw_session() {
  local session_file="$HOME/.local/state/macbook-setup/bw-session"
  if [ -n "${BW_SESSION:-}" ]; then
    return 0
  fi
  if [ ! -f "$session_file" ]; then
    return 1
  fi
  # Mode check: 0600. Use stat -f on macOS / -c on Linux.
  local mode
  if mode="$(stat -f '%Lp' "$session_file" 2>/dev/null)"; then
    :
  else
    mode="$(stat -c '%a' "$session_file" 2>/dev/null || echo '')"
  fi
  if [ -n "$mode" ] && [ "$mode" != "600" ]; then
    warn "phase2: bw-session file mode is $mode, expected 600"
  fi
  # Read into BW_SESSION without echoing or logging the value.
  BW_SESSION="$(cat "$session_file" 2>/dev/null || true)"
  if [ -z "$BW_SESSION" ]; then
    return 1
  fi
  export BW_SESSION
  return 0
}

# phase2_clone_repos_from_yaml YAML_PATH
# Read a repos-*.yaml inventory and, for each entry, clone if missing.
# Mirrors the four-state model:
#   - present-correct      -> info: "repo: ok"
#   - present-wrong-remote -> error: hard-fail this entry, continue loop
#   - present-not-a-repo   -> error: hard-fail this entry, continue loop
#   - missing              -> clone via SSH; if fails, error
#
# Schema accepted (matches inventory/repos.yaml + repos-*.yaml):
#   repos:
#     - url: github.com/owner/repo  (or git@github.com:owner/repo.git)
#       path: relative/to/$HOME     (or absolute)
#       tags: [foo, bar]            (ignored here -- caller decides
#                                    whether to filter optional tag,
#                                    but we honor `tags: [optional]` by
#                                    skipping unless PHASE2_INCLUDE_OPTIONAL=1)
#
# Returns 0 if every entry succeeded (or was already correct), non-zero
# if any entry hit an error. Tolerates missing/empty YAML by logging
# `info: 0 repos to process` and returning 0.
#
# Under PHASE1_DRY_RUN=1, only logs `would: clone ...` for missing repos
# and probes the rest. Errors on present-wrong-remote / not-a-repo are
# still surfaced (those are detection-only, no mutation needed).
phase2_clone_repos_from_yaml() {
  local yaml="$1"
  if [ ! -f "$yaml" ]; then
    info "phase2_clone_repos: $yaml not found; 0 repos to process"
    return 0
  fi

  if ! command -v yq >/dev/null 2>&1; then
    error "phase2_clone_repos: yq not on PATH (install via Phase 1 Brewfile)"
    return 1
  fi

  local count
  count="$(yq -r '.repos | length // 0' "$yaml" 2>/dev/null || echo 0)"
  if [ "${count:-0}" -eq 0 ]; then
    info "phase2_clone_repos: 0 repos in $yaml"
    return 0
  fi

  local errors=0 i=0
  while [ "$i" -lt "$count" ]; do
    local url path_rel tags_csv abs
    url="$(yq -r ".repos[$i].url // \"\"" "$yaml")"
    path_rel="$(yq -r ".repos[$i].path // \"\"" "$yaml")"
    tags_csv="$(yq -r ".repos[$i].tags // [] | join(\",\")" "$yaml")"

    i=$((i + 1))

    if [ -z "$url" ] || [ -z "$path_rel" ]; then
      warn "phase2_clone_repos: entry $i in $yaml missing url or path; skipping"
      continue
    fi

    # Honor `tags: [optional]` unless explicitly opted in.
    case ",$tags_csv," in
      *,optional,*)
        if [ -z "${PHASE2_INCLUDE_OPTIONAL:-}" ]; then
          info "phase2_clone_repos: skip $path_rel (tagged optional)"
          continue
        fi
        ;;
    esac

    # Resolve to an absolute path: ~ -> $HOME; relative -> $HOME/...
    case "$path_rel" in
      /*)         abs="$path_rel" ;;
      \~/*)       abs="$HOME/${path_rel#\~/}" ;;
      \~)         abs="$HOME" ;;
      *)          abs="$HOME/$path_rel" ;;
    esac

    # Normalize URL to git@ form for SSH cloning if it's a github.com/...
    # short form. Leave full git@ / https:// URLs untouched.
    local clone_url="$url"
    case "$url" in
      git@*|https://*|ssh://*) ;;
      github.com/*)
        # github.com/owner/repo -> git@github.com:owner/repo.git
        local rest="${url#github.com/}"
        clone_url="git@github.com:${rest}.git"
        ;;
    esac

    # Four-state probe.
    if [ -d "$abs/.git" ]; then
      if probe_repo_at_path "$abs" "$clone_url"; then
        info "phase2_clone_repos: $path_rel ok"
      else
        local actual
        actual="$(git -C "$abs" remote get-url origin 2>/dev/null || echo '<unknown>')"
        error "phase2_clone_repos: $path_rel has wrong remote (got $actual, expected $clone_url)"
        errors=$((errors + 1))
      fi
      continue
    fi

    if [ -e "$abs" ] && [ ! -d "$abs/.git" ]; then
      error "phase2_clone_repos: $abs exists but is not a git repo; refusing to overwrite"
      errors=$((errors + 1))
      continue
    fi

    # Missing -> clone (or dry-run log).
    if is_dry_run; then
      info "phase2_clone_repos: would clone $clone_url -> $abs"
      continue
    fi
    info "phase2_clone_repos: cloning $clone_url -> $abs"
    mkdir -p "$(dirname -- "$abs")"
    if ! git clone "$clone_url" "$abs"; then
      error "phase2_clone_repos: clone failed for $clone_url"
      errors=$((errors + 1))
      continue
    fi
    ok "phase2_clone_repos: cloned $path_rel"
  done

  if [ "$errors" -gt 0 ]; then
    error "phase2_clone_repos: $errors error(s) in $yaml"
    return 1
  fi
  return 0
}
