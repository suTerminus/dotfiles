# Adding a repo

Use this when the user wants a new repo tracked in inventory and cloned
locally. Inputs can be terse: a single URL, `owner/repo`, or just a name
they expect you to look up.

## Classify (which inventory)

Decide before touching anything:

- URL starts with `github.com/enersis/` (or any other work org) → **enersis**
- URL starts with `github.com/suTerminus/` → **personal**
- Any other public OSS repo the user wants on every machine → **public**

Edge cases:
- A personal *fork* of an OSS repo lives in the same overlay as other
  personal work — **personal**.
- A work-only fork → **enersis**.
- If the user's intent is ambiguous (e.g. "add `kubebuilder` — I want it
  for reference") ask once: "personal scope, work scope, or public for
  every machine?"

## Compute the fields

```yaml
- url: github.com/<owner>/<repo>     # normalised: no git@, no .git, no https://
  path: <see below>
  tags: <see SKILL.md "Default conventions">
  note: <one-sentence description>
```

Path conventions (`$HOME`-relative):
- **personal** → `code/personal/<repo>`
- **enersis** → `code/work/enersis/<repo>`
- **public/third-party** → `code/third-party/<repo>` (ask if a different
  path is expected)

Note: infer from the repo name and any user-supplied context. If you
genuinely can't tell what the repo is for, fetch the GitHub description
with `gh repo view <owner>/<repo> --json description -q .description`
before asking — saves a round trip.

## Dedupe across all three inventories

The same repo URL must not appear in two inventories. Check all three
before adding (use `yq -r '.repos[].url' <file>` on each). If it already
exists in the target inventory: tell the user, skip. If it exists in a
*different* inventory: the user probably wants `move`, not `add` — switch
to `references/move.md` after confirming.

## Append, preserving structure

Use the `Edit` tool to insert the new entry at the end of the `repos:`
list in the target inventory file. Don't rewrite the file with `Write`
— the comments and section headers matter.

A clean insertion looks like:

```
old_string:
  - url: github.com/suTerminus/vault
    path: code/personal/vault
    tags: [manual]
    note: Legacy private credentials repo. ...

new_string:
  - url: github.com/suTerminus/vault
    path: code/personal/vault
    tags: [manual]
    note: Legacy private credentials repo. ...

  - url: github.com/<owner>/<repo>
    path: <path>
    tags: <tags>
    note: <note>
```

Match the indentation (two spaces for list items, four for fields) and
the blank-line spacing the file already uses.

## Clone

Run the right script. It's idempotent and will skip if already present:

- **public** → `bash ~/code/personal/dotfiles/scripts/steps/P1-50-clone-public-repos.sh`
- **personal or enersis** → `bash ~/code/personal/dotfiles/scripts/steps/P2-30-clone-overlay-repos.sh`

Stream the output so the user sees the clone progress. If the clone
fails (SSH key, SSO, typo in URL), report what happened — don't retry
destructively.

## Commit the inventory

Commit happens in the inventory's *own* repo:

- public → `git -C ~/code/personal/dotfiles ...`
- personal → `git -C ~/.local/share/chezmoi-private ...`
- enersis → `git -C ~/.local/share/chezmoi-enersis ...`

Message style (match the recent log in that repo):

```
feat(inventory): add <repo-name>
```

If multiple repos were added in one go, list them all:

```
feat(inventory): add <repo-a>, <repo-b>
```

Don't push. The user runs their own push/PR flow.
