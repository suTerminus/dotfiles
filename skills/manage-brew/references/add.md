# Adding a brew package

Use this when the user wants a new tap, formula, or cask tracked in
inventory and installed. Inputs can be terse: `jq`, `add font-jetbrains-mono`,
`tap openfga/tap`.

## Classify (which category)

If the user said "tap", `name` looks like `owner/repo` (no third
component), or the input matches `brew tap` output → **tap**.

Otherwise ask brew:

```bash
brew info --formula <name> >/dev/null 2>&1 && echo formula
brew info --cask    <name> >/dev/null 2>&1 && echo cask
```

If both succeed (rare — same name in both namespaces), prefer the one
the user clearly meant (a GUI app is a cask). If neither succeeds, the
name is likely wrong or upstream renamed it — tell the user the brew
search results:

```bash
brew search <name>
```

## Classify (which inventory)

Use the SKILL.md "What goes where" rules.

- The user *named* the scope ("add `jq` to enersis"): use that.
- The package is obviously work-flavoured (`awscli`, `kubectl`-adjacent,
  `slack`, `microsoft-*`) → **enersis**.
- Personal-flavoured (browsers like `arc`, media, gaming, notes,
  personal VPN) → **personal**.
- Generic dev tool → **public**.
- If unsure, ask once. Don't guess on borderline cases — moving across
  inventories later is cheap but noisy.

## Compute the fields

```yaml
- name: <brew-name>
  tags: <see SKILL.md "Default conventions">
  note: <optional one-liner>
```

For a tap-scoped formula: add the tap to `taps:` first (if not already
there), then the formula to `formulae:` with the fully qualified
`tap-owner/tap-name/formula` form.

## Dedupe across all three inventories

The same `name` shouldn't appear in two inventories within the same
category. Quick check:

```bash
NAME='<name>'
CATEGORY='casks'   # or 'formulae' or 'taps'
for f in \
  ~/code/personal/dotfiles/inventory/brew.yaml \
  ~/.local/share/chezmoi-private/inventory/brew-personal.yaml \
  ~/.local/share/chezmoi-enersis/inventory/brew-enersis.yaml; do
  match="$(yq -r ".$CATEGORY[]?.name | select(. == \"$NAME\")" "$f" 2>/dev/null)"
  [ -n "$match" ] && printf '%s\thas %s\n' "$f" "$NAME"
done
```

If already in the target inventory → skip, tell the user. If in a
*different* inventory → the user probably wants to move it, not
re-add; switch to `references/move.md`.

## Insert into the right section

Use `Edit` to insert the new entry at the end of the right section
within the right inventory file. Match indentation (two spaces for list
items, four for fields). Respect the `# ---------- Public [] ----------`
and `# ---------- Optional [optional, BUCKET] ----------` section
boundaries — put `[]` entries before `[optional, *]` entries.

If adding to an existing optional bucket, place the entry adjacent to
its bucket-mates (the file groups them visually with a blank line).

A clean public-section insertion looks like:

```
old_string:
  - name: bat
    tags: []

new_string:
  - name: bat
    tags: []
  - name: <name>
    tags: []
    note: <note>
```

## Render + bundle

After editing, run the relevant scripts so the package actually
installs:

- **public** edit:
  ```bash
  bash ~/code/personal/dotfiles/scripts/steps/P1-20-render-brewfile.sh
  bash ~/code/personal/dotfiles/scripts/steps/P1-30-brew-bundle.sh
  ```
- **personal or enersis** edit:
  ```bash
  bash ~/code/personal/dotfiles/scripts/steps/P2-20-brew-bundle-overlays.sh
  ```

If the package was added to an `[optional, BUCKET]` slot it won't
install automatically — note that, and tell the user to re-run
`setup.sh --include-tag BUCKET` if they want it now.

Stream output. If `brew bundle` fails, report what the error said
without retrying destructively (typically: wrong category, renamed
upstream, deprecated).

## Commit the inventory

In the inventory's own repo (see SKILL.md "Touch the right git repo"):

```
feat(brew): add <name>
```

For multiple: `feat(brew): add <a>, <b>, <c>`. For a tap + its first
formula: `feat(brew): add <tap> and <formula>`.

Don't push.
