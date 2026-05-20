# Updating and upgrading brew packages

Use this when the user wants to refresh and upgrade what's actually
installed — not change the inventory. "Update brew", "what's
outdated", "upgrade everything", "upgrade just neovim", "clean up old
versions", "should I pin X".

This flow is maintenance, not inventory editing. Most steps produce no
git diff. The exception is **pinning**, which is recorded in the
inventory (see below).

## The brew commands at a glance

| Command                             | Effect                                                  |
|-------------------------------------|---------------------------------------------------------|
| `brew update`                       | Refresh formula/cask metadata from upstream. No installs. |
| `brew outdated`                     | List installed packages with newer versions available.  |
| `brew upgrade`                      | Upgrade all outdated packages.                          |
| `brew upgrade <name>`               | Upgrade one package.                                    |
| `brew bundle install --file <bf>`   | Install anything in the Brewfile that's missing. Doesn't downgrade or uninstall. |
| `brew bundle check --file <bf>`     | Report what's missing without installing.               |
| `brew bundle cleanup --file <bf>`   | Show (or, with `--force`, remove) installed packages not in the Brewfile. **Destructive with `--force`.** |
| `brew pin <name>` / `brew unpin`    | Block a formula from upgrades (formulae only, not casks). |
| `brew cleanup`                      | Remove old versions / cached downloads. Safe.           |
| `brew autoremove`                   | Remove formulae no longer required as dependencies.     |
| `brew doctor`                       | Diagnose brew environment issues.                       |

## Routine refresh (the safe default)

When the user says "update brew" without further detail, this is what
they mean 90% of the time. No prompting needed:

```bash
brew update
brew outdated
```

Then ask whether to upgrade. Show the outdated list first — the user
might want to upgrade selectively (e.g. hold back a major version
bump).

```bash
brew upgrade          # everything
brew upgrade <name>   # just one
```

After upgrade, optional housekeeping:

```bash
brew cleanup           # reclaim disk space; safe
brew autoremove        # drop orphaned deps; safe but read the list first
```

No git changes. Nothing to commit.

## Re-running the inventory bundle

If the user's actual question is "make sure my machine matches the
inventory" (e.g. after pulling new commits in any of the three
dotfiles repos), the right tool is the bundle script, not `brew
upgrade`:

```bash
# public
bash ~/code/personal/dotfiles/scripts/steps/P1-20-render-brewfile.sh
bash ~/code/personal/dotfiles/scripts/steps/P1-30-brew-bundle.sh
# overlays
bash ~/code/personal/dotfiles/scripts/steps/P2-20-brew-bundle-overlays.sh
```

`brew bundle install` installs anything missing but doesn't upgrade
already-installed packages to newer versions — those two needs are
separate. A "full refresh" is: `brew update` → `brew upgrade` → run the
bundle scripts → `brew cleanup`.

## Selective upgrade with a pin

If the user wants "upgrade everything except X" (e.g. X has a known
regression, or they need to wait for a config migration):

```bash
brew pin <name>     # block future upgrades
brew upgrade        # safe — pinned packages stay put
brew unpin <name>   # once ready
```

**Important:** `brew pin` only works on formulae. Casks can't be
pinned via brew; the only way to hold a cask back is to remove it from
inventory temporarily or remove the formula from `brew upgrade`'s
target list manually.

If the pin is meant to be persistent (not just a one-off skip),
**record it in inventory** with a `pin: true` field (or a `[manual]`
tag if you'd rather not auto-install at all) and a `note:` explaining
why. Without that, anyone reading the inventory has no idea why your
machine is held back and another machine bootstrapped from the same
inventory will happily upgrade.

The inventory schema doesn't currently have a `pin` field — propose
the change to the user before introducing it, and document it in
`inventory/README.md`. Until that lands, use `[manual]` + a clear note
as the workaround.

## "What's outdated and what should I upgrade?"

```bash
brew update
brew outdated --verbose   # shows current vs. new version
```

For each outdated package, classify before recommending:
- Major version bump (e.g. `node 20 → 22`) — surface the upgrade
  separately; often has migration notes.
- Patch / minor — safe to bundle into a wholesale `brew upgrade`.
- Casks — they upgrade silently most of the time. Apps with
  configuration (e.g. `obsidian`, `raycast`) may want to be quit first.

Don't blindly run `brew upgrade` if the list contains anything
config-bearing the user has open right now (terminal, IDE, browser).
Surface that.

## Cleanup commands (destructive flavors)

These need explicit consent. Don't run on a casual "clean up brew":

- `brew bundle cleanup --force` — removes everything not in the
  Brewfile. Will purge things the user installed ad-hoc that aren't
  declared. If they want a Brewfile-only machine, this is the move,
  but ask first and show the list (`--no-force` first to preview).
- `brew uninstall --force` — same energy.

Safe cleanups (no confirmation needed):
- `brew cleanup` (old versions, downloads cache)
- `brew autoremove` (after showing the list)

## Doctor / diagnostics

If `brew update` or `brew upgrade` fails, run `brew doctor` and surface
what it says rather than guessing. Don't fix doctor warnings unrelated
to the user's task — half of them are advisory (extra taps, custom
PATH order, etc.) and not problems.

## Git: usually nothing to commit

This whole flow typically produces **no inventory diff**. The exception
is when the user asked to pin/hold something and you recorded it in
the YAML (see "Selective upgrade with a pin" above) — then commit per
the SKILL.md "Universal rules":

```
chore(brew): pin <name> at <version> (<reason>)
```
