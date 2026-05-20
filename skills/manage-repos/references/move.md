# Moving a repo

"Move" covers three related ops the user might mix together. Decide which
one (or which combination) applies before editing anything.

| Flavor                    | What changed?                                    | Triggers                                        |
|---------------------------|--------------------------------------------------|-------------------------------------------------|
| Scope move                | Which inventory it lives in (and maybe path)     | "move daedalus to work", "this is actually a work repo, put it in enersis", "make it public" |
| GitHub owner change       | The remote URL (org/owner transfer on GitHub)    | "I transferred foo to enersis", "the repo lives at enersis/foo now"                  |
| Visibility change         | GitHub privacy (public ↔ private)                | "make this repo private", "publish this one"    |

A real move often combines flavors — e.g. "I transferred my dotfiles-side
tool to the enersis org" is *owner change + scope move*. Walk through
each flavor that applies.

## Locate the entry

Same search as `remove.md`:

```bash
for f in \
  ~/code/personal/dotfiles/inventory/repos.yaml \
  ~/.local/share/chezmoi-private/inventory/repos-personal.yaml \
  ~/.local/share/chezmoi-enersis/inventory/repos-enersis.yaml; do
  printf '\n=== %s ===\n' "$f"
  yq -r '.repos[] | "\(.url)\t\(.path)\t\(.tags // [])"' "$f" 2>/dev/null \
    | grep -i "<repo-name>" || true
done
```

Note the current entry's url, path, and tags — you'll need them.

## Plan the new state

Compute the new fields the user wants:

- New scope (which inventory file) — drives the new tag conventions and
  often the new path.
- New URL (only if owner changed).
- New path (only if the scope move implies a new conventional location —
  e.g. `code/personal/foo` → `code/work/enersis/foo`).

State the plan before touching anything:

> Plan: move `foo` from public to enersis. Will:
> 1. `mv ~/code/personal/foo ~/code/work/enersis/foo`
> 2. Remove entry from `dotfiles/inventory/repos.yaml`
> 3. Add entry to `chezmoi-enersis/inventory/repos-enersis.yaml`
> 4. Commit both repos
>
> Remote URL stays `github.com/enersis/foo` — looks like the GitHub
> transfer already happened. OK?

## Flavor: GitHub owner change

If the repo was transferred on GitHub (or the user is asking you to do
the transfer), handle the remote side before touching local paths:

1. **Verify the new URL resolves**:
   ```bash
   gh repo view <new-owner>/<repo> --json name -q .name
   ```
   If that fails, the transfer hasn't happened yet — stop and ask.
2. **Optionally perform the transfer** with `gh repo transfer`. This is
   a destructive cross-org operation; only do it if the user explicitly
   asked. Surface the command first.
3. **Fix the local clone's remote**:
   ```bash
   git -C <local-path> remote set-url origin git@github.com:<new-owner>/<repo>.git
   git -C <local-path> remote -v   # verify
   git -C <local-path> fetch origin
   ```
   If the clone has unpushed local branches, `fetch` will pick up the
   new remote refs without disturbing them. Don't rebase or reset.

## Flavor: visibility change

```bash
gh repo edit <owner>/<repo> --visibility public   # or private
```

Visibility changes also often imply a scope move (e.g. "I made this
public — move it out of the personal overlay"). Walk through the scope
move flavor afterwards if so.

## Flavor: scope move (and path move)

This is the most involved flavor — it touches two inventory repos and
the local filesystem.

1. **Move the directory** (if the path changes):
   ```bash
   mkdir -p "$(dirname <new-path>)"
   mv <old-path> <new-path>
   ```
   `mv` within the same filesystem is atomic and preserves the entire
   `.git/` directory — local branches, stashes, refs, hooks, config all
   come along. If the move crosses filesystems (rare on macOS) `mv`
   falls back to copy+delete; warn the user and confirm.

2. **Remove the entry from the old inventory** (see `remove.md` for the
   Edit pattern). Don't delete the clone in this flow — the `mv` above
   already relocated it.

3. **Add the entry to the new inventory** (see `add.md` for the Edit
   pattern). Use the new path, the appropriate tags for the new scope,
   and (if owner changed) the new URL.

4. **Sanity check** with the relevant clone script — it should report
   the repo as `present-correct` at the new path:
   ```bash
   bash ~/code/personal/dotfiles/scripts/steps/P1-50-clone-public-repos.sh
   bash ~/code/personal/dotfiles/scripts/steps/P2-30-clone-overlay-repos.sh
   ```

## Commit

A scope move produces **two** commits in **two** different inventory
repos (the source and the destination). Do them as separate commits in
their respective working trees.

Message style:

```
chore(inventory): move <repo-name> to <new-scope>
```

Or, in the destination repo:

```
feat(inventory): adopt <repo-name> from <old-scope>
```

If only the remote URL changed (no scope move), one commit in one repo:

```
chore(inventory): retarget <repo-name> to <new-owner>/<repo>
```

Don't push.
