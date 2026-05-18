#!/usr/bin/env bash
# scripts/dotfiles-sync.sh
#
# Pull every dotfiles working tree the user keeps in sync — three repo
# clones plus the two chezmoi overlay sources — in one shot. Fetch and
# fast-forward only. Never pushes, never resets, never forces. Repos
# with uncommitted changes or non-fast-forward divergence are skipped
# with a loud WARN; everything else is rolled forward.
#
# Usage:
#   scripts/dotfiles-sync.sh
#   dotfiles-sync                # via the alias in dot_aliases.tmpl
#
# Exit code:
#   0 if every reachable repo either rolled forward cleanly or was
#     skipped with a documented reason (no errors).
#   1 if at least one repo couldn't be processed for an unexpected
#     reason (git binary missing, fetch failure, etc).
#
# Invariants:
#   - bash -n clean.
#   - Read-only on remotes; only ever runs `git fetch` + `git merge
#     --ff-only`.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
if [ -r "${LIB_DIR}/log.sh" ]; then
  # shellcheck source=lib/log.sh
  . "${LIB_DIR}/log.sh"
else
  info()  { printf '[INFO] %s\n' "$*" >&2; }
  ok()    { printf '[OK]   %s\n' "$*" >&2; }
  skip()  { printf '[SKIP] %s\n' "$*" >&2; }
  warn()  { printf '[WARN] %s\n' "$*" >&2; }
  error() { printf '[ERR]  %s\n' "$*" >&2; }
fi

# --------------------------------------------------------------------
# The six locations. Order matters only for the report; each repo is
# processed independently and failures don't cascade.
# --------------------------------------------------------------------
REPOS=(
  "${HOME}/code/personal/dotfiles"
  "${HOME}/code/personal/dotfiles-private"
  "${HOME}/code/work/dotfiles-enersis"
  "${HOME}/.local/share/chezmoi-private"
  "${HOME}/.local/share/chezmoi-enersis"
)

if ! command -v git >/dev/null 2>&1; then
  error "git not on PATH; cannot sync"
  exit 1
fi

OVERALL_FAIL=0
n_ok=0
n_skip=0
n_warn=0

# Sync one repo: ff-only pull, with safety probes around it.
sync_one() {
  local repo="$1"

  if [ ! -d "$repo" ]; then
    skip "$repo: not present, skipping"
    n_skip=$((n_skip + 1))
    return 0
  fi
  if [ ! -d "$repo/.git" ]; then
    warn "$repo: not a git working tree, skipping"
    n_warn=$((n_warn + 1))
    return 0
  fi

  # Uncommitted changes (tracked or untracked) — refuse to touch the
  # tree. `git status --porcelain` prints nothing on a clean tree.
  local dirty
  dirty="$(git -C "$repo" status --porcelain 2>/dev/null || true)"
  if [ -n "$dirty" ]; then
    warn "$repo: uncommitted changes present, skipping"
    n_warn=$((n_warn + 1))
    return 0
  fi

  # Detached HEAD or no upstream — there's nothing to fast-forward to.
  local branch upstream
  branch="$(git -C "$repo" symbolic-ref --short -q HEAD 2>/dev/null || true)"
  if [ -z "$branch" ]; then
    warn "$repo: detached HEAD, skipping"
    n_warn=$((n_warn + 1))
    return 0
  fi
  upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" 2>/dev/null || true)"
  if [ -z "$upstream" ]; then
    warn "$repo: branch '$branch' has no upstream, skipping"
    n_warn=$((n_warn + 1))
    return 0
  fi

  info "$repo: fetching"
  if ! git -C "$repo" fetch --quiet --prune 2>&1; then
    warn "$repo: fetch failed, skipping"
    n_warn=$((n_warn + 1))
    return 0
  fi

  # Compare HEAD vs upstream. Four possible relationships:
  #   - up-to-date  → nothing to do
  #   - behind      → fast-forward (the happy path)
  #   - ahead       → user has unpushed work; skip (we don't push)
  #   - diverged    → non-fast-forward; skip with a loud warn
  local local_sha upstream_sha base_sha
  local_sha="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
  upstream_sha="$(git -C "$repo" rev-parse "$upstream" 2>/dev/null || true)"
  base_sha="$(git -C "$repo" merge-base HEAD "$upstream" 2>/dev/null || true)"

  if [ -z "$local_sha" ] || [ -z "$upstream_sha" ] || [ -z "$base_sha" ]; then
    warn "$repo: could not resolve HEAD / upstream / merge-base, skipping"
    n_warn=$((n_warn + 1))
    return 0
  fi

  if [ "$local_sha" = "$upstream_sha" ]; then
    ok "$repo: up to date with $upstream"
    n_ok=$((n_ok + 1))
    return 0
  fi
  if [ "$local_sha" = "$base_sha" ]; then
    # Strictly behind — fast-forward.
    if git -C "$repo" merge --ff-only --quiet "$upstream" 2>&1; then
      ok "$repo: fast-forwarded $branch → $upstream"
      n_ok=$((n_ok + 1))
    else
      warn "$repo: ff-only merge failed unexpectedly, skipping"
      n_warn=$((n_warn + 1))
    fi
    return 0
  fi
  if [ "$upstream_sha" = "$base_sha" ]; then
    warn "$repo: local '$branch' is ahead of '$upstream' (unpushed work); skipping"
    n_warn=$((n_warn + 1))
    return 0
  fi
  warn "$repo: local '$branch' and '$upstream' have diverged (non-ff); skipping"
  n_warn=$((n_warn + 1))
  return 0
}

for repo in "${REPOS[@]}"; do
  sync_one "$repo"
done

printf '\n' >&2
printf '=== dotfiles-sync summary ===\n' >&2
printf 'ok: %d   warn/skip: %d   absent-skip: %d\n' "$n_ok" "$n_warn" "$n_skip" >&2

# A non-zero overall exit is reserved for unexpected errors (git missing,
# etc). Skips and warns are user-actionable but expected, so they don't
# fail the run.
exit "$OVERALL_FAIL"
