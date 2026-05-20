# Moving a brew package

Use this when a tap/formula/cask is in the wrong inventory and should
live in a different scope. Triggers: "move slack to enersis", "this is
actually work-only", "make obsidian personal", "discord doesn't belong
in public".

Unlike `manage-repos`, there's no GitHub-owner or visibility flavor for
brew — moving a package is purely an inventory-side rearrangement.
What's installed on disk doesn't change; the package is the same
package regardless of which overlay declares it. The point of the move
is *correctness* — getting machines without that scope (e.g. a
personal-only machine) to not try to install a work tool.

## Locate the entry

Same search as `remove.md`:

```bash
NAME='<name>'
for f in \
  ~/code/personal/dotfiles/inventory/brew.yaml \
  ~/.local/share/chezmoi-private/inventory/brew-personal.yaml \
  ~/.local/share/chezmoi-enersis/inventory/brew-enersis.yaml; do
  for cat in taps formulae casks; do
    if [ -n "$(yq -r ".$cat[]?.name | select(. == \"$NAME\")" "$f" 2>/dev/null)" ]; then
      printf '%s\t%s\n' "$f" "$cat"
    fi
  done
done
```

Note the current entry's full record — name, tags, note — you'll
recreate it verbatim in the destination unless something needs to
change.

## Plan

State the plan in one or two sentences before editing:

> Plan: move `slack` from public `brew.yaml` (casks) to
> `brew-enersis.yaml` (casks). Keep the same tags `[]`. Will produce
> two commits, one in each repo. The package stays installed on this
> machine.

If the destination's optional buckets are different (e.g. public has
`[optional, ml]`, personal doesn't), pick the right bucket for the
destination or ask. If the entry was in a `[optional, BUCKET]` slot
and the bucket doesn't exist in the destination, surface that and ask
whether to drop the optional tag or create a new bucket in the
destination.

## Remove from the source inventory

Use `Edit` to delete the entry from its current file/section. Same
"include the trailing blank line" rule as `remove.md`. Don't delete a
section header just because the last item in that bucket went away —
ask first.

## Add to the destination inventory

Use `Edit` to insert the entry into the correct section
(`taps`/`formulae`/`casks`) of the destination file. Follow the
section-ordering convention (`[]` entries before `[optional, *]`
entries). If the destination has an existing bucket the package
belongs in, place it adjacent to its bucket-mates.

## Tap-aware moves

If the package being moved is a formula from a tap (e.g.
`openfga/tap/fga`), and the source inventory was the only thing
referencing that tap, the tap itself should probably move too. Check:

```bash
yq -r '.formulae[]?.name' <source-file> | grep -E '^openfga/tap/'
```

If no other formulae from that tap remain in the source, move the
`taps:` entry alongside the formula. If other formulae still need it,
leave the tap in both inventories (it's safe to have the same tap in
two scopes; `brew tap` is idempotent).

## Render + bundle

A scope move can shift install behaviour on machines you're *not*
currently on:
- moving from public → enersis means personal-only machines will stop
  installing the package on the next bootstrap.
- moving the other direction means it'll start installing on machines
  that didn't have it.

On the *current* machine, the practical effect of a move is usually
"none" (the package was already in scope and remains so, or wasn't and
remains so). Re-run the matching bundle script if you want to be sure:

- Either repo touched: `bash ~/code/personal/dotfiles/scripts/steps/P2-20-brew-bundle-overlays.sh`
- If the source was public: also `bash ~/code/personal/dotfiles/scripts/steps/P1-20-render-brewfile.sh`
  to refresh the public Brewfile so `brew bundle cleanup` (if ever
  run) won't try to remove the package on this machine.

Mention to the user: this move affects future machine setups more than
the current state.

## Commit

A move produces **two** commits in **two** different inventory repos.
Do them separately in their respective working trees.

Source repo:

```
chore(brew): move <name> to <new-scope>
```

Destination repo:

```
feat(brew): adopt <name> from <old-scope>
```

Don't push.
