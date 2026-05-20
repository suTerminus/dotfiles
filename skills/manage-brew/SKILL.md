---
name: manage-brew
description: Use whenever the user wants to add, remove, relocate, or upgrade a Homebrew tap, formula, or cask within their dotfiles inventory — public, personal overlay, or work (enersis) overlay. Triggers on "add jq to my brew", "install ripgrep via dotfiles", "drop slack", "this cask is work-only, move it to enersis", "make obsidian personal", "what bucket should I put node in", "add openfga tap", "update brew", "what's outdated", "upgrade everything", "upgrade just neovim", "pin node", "brew cleanup". Manages the YAML inventory, classifies tap vs formula vs cask, re-renders the Brewfile, runs brew bundle/update/upgrade, and commits the affected dotfiles repo. Use even when the user only says "add brew package X" or "upgrade brew" without specifying which inventory or which packages — the skill handles classification and the safe-default flow.
---

# manage-brew

Three dotfiles repos declare which Homebrew taps, formulae, and casks
belong on a machine. This skill is the one place that understands all
three at once, so editing brew packages stays consistent across YAML,
the rendered Brewfile, and what's actually installed.

## The three-overlay model

| Scope    | Inventory file                                                            | Rendered Brewfile                           | Bundled by |
|----------|---------------------------------------------------------------------------|---------------------------------------------|------------|
| public   | `~/code/personal/dotfiles/inventory/brew.yaml`                            | `home/dot_config/brew/Brewfile.tmpl`        | P1-20 + P1-30 |
| personal | `~/.local/share/chezmoi-private/inventory/brew-personal.yaml`             | `~/.config/brew/Brewfile.personal`          | P2-20 (personal half) |
| work     | `~/.local/share/chezmoi-enersis/inventory/brew-enersis.yaml`              | `~/.config/brew/Brewfile.enersis`           | P2-20 (work half, work machine only) |

The scripts:
- `~/code/personal/dotfiles/scripts/steps/P1-20-render-brewfile.sh` —
  renders the public yaml into `Brewfile.tmpl`.
- `~/code/personal/dotfiles/scripts/steps/P1-30-brew-bundle.sh` —
  applies the rendered public Brewfile.
- `~/code/personal/dotfiles/scripts/steps/P2-20-brew-bundle-overlays.sh` —
  renders + applies the personal and enersis overlays.

All three are idempotent; re-running on an already-installed package is
a skip.

## Inventory file structure

Each file has three top-level sections — `taps:`, `formulae:`, `casks:`
— and the overlays also carry an empty `mas: []` for symmetry. Each
item:

```yaml
- name: jq                  # the brew name (or "tap/owner/formula" form for tapped formulae)
  tags: []                  # [] / [optional, BUCKET] / [manual]
  note: optional one-liner  # why it's here, or any non-obvious detail
```

**Category matters.** Putting a cask under `formulae:` makes `brew
bundle` fail. If you don't know which section a package belongs to, ask
brew before guessing:

```bash
brew info --json=v2 <name> | jq -r '.formulae[0].name // .casks[0].token // empty'
```

Or check the type:

```bash
brew info --formula <name> >/dev/null 2>&1 && echo formula
brew info --cask    <name> >/dev/null 2>&1 && echo cask
```

Taps are written `owner/repo`, e.g. `bufbuild/buf`. A formula that
lives inside a tap is referenced fully-qualified in the formula list
(e.g. `bufbuild/buf/buf`), and the tap itself must be present in
`taps:`.

## What goes where (classification)

When the user hasn't specified the scope:

- **public** (`brew.yaml`): tools the user wants on every machine —
  shell + editor + general dev (bat, fd, ripgrep, jq, neovim, …) and
  general casks (browsers, terminals, fonts). Use `[]`.
- **personal** (`brew-personal.yaml`): packages tied to the user's
  identity, not the machine type — personal browsers (arc), media
  (iina, vlc), gaming (discord), notes (obsidian), personal VPN.
- **work / enersis** (`brew-enersis.yaml`): packages only useful on the
  work machine — awscli, argocd, krew, k6, datagrip, slack, microsoft-
  teams, work VPN client, etc.

Edge cases:
- A tool useful both at work and personally but with different *usage
  context* (e.g. `slack` for work only) → put where it's primarily
  used. If genuinely both, public is fine.
- An optional bucket already exists in one of the overlays
  (`[optional, gaming]`, `[optional, java]`, etc.) → if the new package
  belongs to an existing bucket, reuse the bucket name.
- Ambiguous (`docker` for personal hobby projects vs work) → ask once.

## Default conventions

- `name`: exactly what `brew install` accepts. For tap-scoped formulae
  use the fully qualified form (`tap/owner/formula`).
- `tags`:
  - `[]` — always install on machines in this scope.
  - `[optional, BUCKET]` — opt-in via `setup.sh --include-tag BUCKET`.
    Match existing bucket names in the file (`gaming`, `media`, `art`,
    `personal-vpn`, `gis`, `node`, `docs`, `native`, `java`,
    `keyboard`, `ml`, `browser`).
  - `[manual]` — declared but never auto-installed; bootstrap warns if
    missing. Rare for brew; use for paid casks or things requiring
    license input.
- `note`: include when the *why* isn't obvious from the name (renamed
  upstream, requires permission grant, drives a specific bootstrap
  step, supersedes another tool, etc.). Skip for self-explanatory
  packages.

## Routing — pick one

Read the reference that matches the user's request. Don't read all
four.

- Adding a tap, formula, or cask → `references/add.md`
- Removing a tap, formula, or cask from inventory → `references/remove.md`
- Moving a package between scopes (public ↔ personal ↔ enersis) →
  `references/move.md`
- Updating brew metadata, upgrading installed packages, pinning, or
  cleaning up old versions → `references/update.md`. This flow usually
  produces no git diff — it's maintenance, not inventory editing.

## Universal rules

1. **Touch the right git repo.** The public inventory lives in
   `~/code/personal/dotfiles`. The personal inventory lives in
   `~/.local/share/chezmoi-private`. The enersis inventory lives in
   `~/.local/share/chezmoi-enersis`. These are three separate repos. A
   "move" operation produces two commits, one in each affected repo.

2. **Preserve YAML structure.** The inventories use section comments
   (`# ---------- Public [] ----------`) to group items by tag. Insert
   new entries in the right section; don't reorder existing ones. Edit
   with the `Edit` tool, never `Write`, so comments survive.

3. **Right section, right file.** A tap goes under `taps:`, formula
   under `formulae:`, cask under `casks:`. Putting a cask under
   `formulae:` will fail at bundle time.

4. **Idempotency before mutation.** Before adding, check all three
   inventories for the same `name` in the same category (taps and casks
   can share a string with formulae — they're separate namespaces).
   Before removing, confirm the entry exists. Before moving, confirm
   the source entry exists and the destination doesn't.

5. **Don't `brew uninstall` casually.** Removing an entry from
   inventory does not automatically uninstall the package locally — the
   user may want to keep it for now and only enforce the removal on the
   next machine. The remove flow asks before running `brew uninstall`.

6. **Don't push.** Stage and commit dotfiles changes, but leave pushing
   to the user.

## After any change

Re-render and re-bundle the right scope to actually install or update:

- **public** edits:
  ```bash
  bash ~/code/personal/dotfiles/scripts/steps/P1-20-render-brewfile.sh
  bash ~/code/personal/dotfiles/scripts/steps/P1-30-brew-bundle.sh
  ```
- **personal or enersis** edits:
  ```bash
  bash ~/code/personal/dotfiles/scripts/steps/P2-20-brew-bundle-overlays.sh
  ```

Stream the output; if a `brew bundle` step fails (formula renamed,
cask deprecated, network), report what failed without retrying
destructively.
