# Removing a brew package

Use this when the user wants a tap, formula, or cask gone. "Remove
slack", "drop the openfga tap", "I don't use multiviewer anymore".

## Locate

Search all three inventories, across all three categories:

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

If found in exactly one place, proceed. If multiple (shouldn't happen,
but possible across categories), surface the inconsistency and ask
which to remove. If not found, tell the user and stop.

## Surface what's at stake

For a formula, check if anything depends on it before removing — pulls
the rug out of any package the user still wants:

```bash
brew uses --installed <name>
```

For a tap, list the formulae that came from it (they'll break if the
tap goes away while they're still in the formula list):

```bash
brew tap-info --json <tap-name> | jq -r '.[0].formula_names[]?'
```

Cross-reference those formula names against the inventories — if any
are still declared, surface them. The user probably wants to remove
those too, or move them to a different tap.

For a cask, mention briefly if the app currently exists on disk:

```bash
brew list --cask | grep -x <name> >/dev/null && echo "currently installed"
```

## Confirm — and ask about local uninstall

Default to **inventory-only** removal. The user may want to keep the
package installed locally for now ("remove from inventory but don't
uninstall — I might still use it"). Surface the choice:

> Found `multiviewer` in the personal overlay's `casks:` list. Plan:
> 1. Remove the inventory entry, 2. commit `chezmoi-private`. The
> package stays installed on this machine — uninstall it yourself with
> `brew uninstall --cask multiviewer` once you're sure. OK?

If they want the uninstall too, also surface that as part of the plan.

## Remove the inventory entry

Use `Edit` with enough surrounding context to make the `old_string`
unique. Include the trailing blank line in the deletion so you don't
leave a double-blank in the file. If the entry has a comment line
above it (e.g. a section header `# ---------- Optional [optional,
gaming] ----------`), don't delete the header just because the
entry below it goes — there may be other items in that bucket.

If the entry is the last in its `[optional, BUCKET]` group and the
bucket is otherwise empty, ask before removing the section header.

## (Optional) Uninstall locally

Only if the user explicitly said yes:

```bash
brew uninstall <name>        # formula
brew uninstall --cask <name> # cask
brew untap <owner>/<repo>    # tap (refuses if any installed formula depends on it — good)
```

If `brew untap` complains about installed formulae, surface what it
said. Don't `--force` without an explicit ask.

## Render + bundle (or skip)

Removing from inventory doesn't require a re-bundle to make the change
take effect (`brew bundle install` is additive — it doesn't uninstall
things that fall off the list unless you also run `brew bundle
cleanup`). But re-running the bundle is harmless and verifies the
inventory still renders cleanly:

- **public** removal: `bash ~/code/personal/dotfiles/scripts/steps/P1-20-render-brewfile.sh`
  (skip the bundle step — nothing new to install)
- **personal/enersis** removal: skip both unless the user wants a
  sanity render.

Mention `brew bundle cleanup` only if the user asks — it removes
*everything* not in the Brewfile, which can surprise.

## Commit the inventory

In the inventory's own repo:

```
chore(brew): remove <name>
```

Or match the repo's preferred style — look at recent commits
(`git -C <repo> log --oneline -5 -- inventory/brew*`).

Don't push.
