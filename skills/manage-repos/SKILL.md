---
name: manage-repos
description: Use whenever the user wants to add, remove, or move a git repository within their dotfiles inventory — public dotfiles, personal overlay, or work (enersis) overlay. Triggers on "add X to my inventory", "clone this repo", "remove vault", "move daedalus to private", "this is a work repo, put it in enersis", "I transferred foo to enersis on GitHub", "make this repo public/private". Manages the YAML inventory, clones/relocates the local working tree, fixes git remotes, and commits the affected dotfiles repo. Use even when the user only says "add this repo" without specifying which inventory — the skill handles classification.
---

# manage-repos

Three dotfiles repos describe what a fully-configured machine has installed.
Each has its own `inventory/repos*.yaml`. This skill is the one place that
understands all three at once, so adding, removing, or moving a repo stays
consistent across YAML, local clones, and git remotes.

## The three-overlay model

| Scope    | Inventory file                                                          | Working tree                              | Cloned by  |
|----------|-------------------------------------------------------------------------|-------------------------------------------|------------|
| public   | `~/code/personal/dotfiles/inventory/repos.yaml`                          | `~/code/personal/dotfiles`                | P1-50      |
| personal | `~/.local/share/chezmoi-private/inventory/repos-personal.yaml`           | `~/.local/share/chezmoi-private`          | P2-30      |
| work     | `~/.local/share/chezmoi-enersis/inventory/repos-enersis.yaml`            | `~/.local/share/chezmoi-enersis`          | P2-30 (work machine only) |

The clone scripts live in `~/code/personal/dotfiles/scripts/steps/`:
`P1-50-clone-public-repos.sh` and `P2-30-clone-overlay-repos.sh`. They are
idempotent — re-running on an already-cloned repo is a skip.

## What goes where (classification)

Use this when the user hasn't specified the inventory explicitly.

- **public** (`repos.yaml`): third-party OSS reference repos the user wants
  cloned on every machine (e.g. `kubernetes-sigs/kubebuilder`). The dotfiles
  repo itself is the only `suTerminus/*` entry that belongs here.
- **personal** (`repos-personal.yaml`): the user's own `github.com/suTerminus/*`
  repos — daedalus, forge, black-mirror, ghost-bazaar, etc. Cloned on every
  machine the user owns.
- **work / enersis** (`repos-enersis.yaml`): `github.com/enersis/*` repos and
  anything else only relevant on the work machine. SSO-gated; only cloned
  when `machine == work`.

If classification is ambiguous (e.g. a personal fork of an OSS repo), ask
the user once before editing.

## Default conventions

- `url`: store as `github.com/owner/repo` (no `git@`, no `.git`, no `https://`).
  The clone scripts canonicalise to SSH at clone time.
- `path` (relative to `$HOME`):
  - personal repos → `code/personal/<repo-name>`
  - work/enersis repos → `code/work/enersis/<repo-name>`
  - public third-party → `code/third-party/<repo-name>` (or whatever the
    user prefers; ask if not obvious)
- `tags`:
  - public inventory: `[]` is the default; the personal/work overlays already
    encode scope by being in their own file.
  - personal inventory: `[claude, plugin]` for ghost-bazaar plugins, `[meta]`
    for the overlay's own working tree, `[manual]` for warn-not-clone entries.
  - enersis inventory: `[claude, marketplace]` for the marketplace, `[meta]`
    for the overlay's own working tree, `[]` otherwise.
  Match what's already in the file rather than inventing new tags.
- `note`: one sentence, describes what the repo is. Infer from the repo
  name and any context the user gave; ask only if truly unclear.

## Routing — pick one

Read the reference that matches the user's request. Don't read all three.

- Adding a new repo (or cloning one for the first time) → `references/add.md`
- Removing a repo from inventory (and maybe the local clone) → `references/remove.md`
- Moving a repo between scopes, changing its GitHub owner, or flipping
  visibility → `references/move.md`

## Universal rules

These hold across all three operations.

1. **Touch the right git repo.** The public inventory lives in
   `~/code/personal/dotfiles` — commit there. The personal inventory lives
   in `~/.local/share/chezmoi-private` — commit there. The enersis inventory
   lives in `~/.local/share/chezmoi-enersis` — commit there. These are three
   separate repos. A "move" operation will produce two commits, one in each
   affected inventory repo.

2. **Preserve YAML comments.** The inventory files contain explanatory
   comments and section headers the user maintains by hand. Edit with the
   `Edit` tool, not by reading-then-writing the whole file, so you don't
   lose them. Don't reorder existing entries.

3. **Idempotency before mutation.** Before adding, dedupe across **all
   three** inventories — a repo might already be tracked elsewhere. Before
   removing, confirm the entry actually exists. Before moving, confirm the
   source entry exists and the destination doesn't already have it.

4. **Don't push.** Stage and commit dotfiles changes, but leave pushing to
   the user. They run their own commit-push-pr flow.

5. **Don't run destructive `git` ops on the user's working trees** (no
   `git clean -fd`, no `git reset --hard`, no force-pushes) without an
   explicit ask. The move flow involves `git remote set-url` and `mv` on
   a working tree — both are safe; anything stronger needs confirmation.

6. **Surface the plan before acting.** For any non-trivial op (move,
   remove-with-delete), say what you're about to do in one or two
   sentences and let the user redirect. For a vanilla add, just do it.

## After any change

When the inventory has been edited, run the matching clone script as a
sanity check — it'll skip-if-present, clone-if-missing, and warn loudly
if state is wrong:

```bash
bash ~/code/personal/dotfiles/scripts/steps/P1-50-clone-public-repos.sh   # public
bash ~/code/personal/dotfiles/scripts/steps/P2-30-clone-overlay-repos.sh  # personal + enersis
```

The reference files tell you which one to run for their specific op.
