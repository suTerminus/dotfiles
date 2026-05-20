# Removing a repo

Use this when the user wants a repo gone — from the inventory, and
optionally from disk. "Remove X", "drop X", "I don't need X anymore",
"uninstall X" all map here.

## Locate

The user names the repo, not the inventory it lives in. Search all
three:

```bash
for f in \
  ~/code/personal/dotfiles/inventory/repos.yaml \
  ~/.local/share/chezmoi-private/inventory/repos-personal.yaml \
  ~/.local/share/chezmoi-enersis/inventory/repos-enersis.yaml; do
  printf '\n=== %s ===\n' "$f"
  yq -r '.repos[] | "\(.url)\t\(.path)"' "$f" 2>/dev/null | grep -i "<repo-name>" || true
done
```

If you find the entry in exactly one inventory, proceed. If it's in
multiple (shouldn't happen, but just in case) flag the inconsistency
and ask which to remove. If it's in none, tell the user and stop.

## Safety report on the local clone

Resolve the absolute path (`$HOME/<entry.path>`) and gather signal
before suggesting deletion:

```bash
P=<resolved-path>
git -C "$P" rev-parse --is-inside-work-tree && \
git -C "$P" status -sb && \
git -C "$P" log --oneline @{u}.. 2>/dev/null   # unpushed commits, if any
```

Red flags worth surfacing:
- Uncommitted changes (`git status` non-empty)
- Unpushed commits (`@{u}..` non-empty)
- Branch is not the repo's default (might be in-progress work)
- A stash exists (`git stash list`)
- The directory exists but isn't a git repo (treat as red flag — could
  be unrelated content the user accidentally placed there)

## Confirm

Present the plan in one or two sentences and ask. Default to keeping the
clone if anything in the safety report was flagged — make the user opt
in to deletion explicitly. Example:

> Found `daedalus` in the personal inventory at `~/code/personal/daedalus`.
> Working tree is clean and matches `origin/main`. Plan: remove the
> inventory entry, delete `~/code/personal/daedalus`, commit
> `chezmoi-private`. OK to proceed?

If safety flagged anything:

> Found `daedalus`. Working tree has 3 uncommitted changes and 2
> unpushed commits on a branch `feature/x`. I'll remove the inventory
> entry only and leave the clone in place — delete it yourself once
> you've sorted out the work. OK?

## Remove the inventory entry

Use `Edit` with enough surrounding context to make the `old_string`
unique. Include the trailing blank line in the deletion so you don't
leave a double-blank in the file. Don't rewrite the file with `Write`.

## Delete the clone (only if confirmed)

```bash
rm -rf "<resolved-path>"
```

Only `rm -rf` the path that came out of the inventory entry. Never
guess. If the directory contained anything not a git repo, the safety
step should have flagged it and the user should have explicitly said
"yes, delete anyway".

## Commit the inventory

In the inventory's own repo (see SKILL.md):

```
chore(inventory): remove <repo-name>
```

or `feat(inventory): drop <repo-name>` if it matches the repo's
convention better. Look at recent commits in that repo with
`git -C <repo> log --oneline -5` and match style.

Don't push.
