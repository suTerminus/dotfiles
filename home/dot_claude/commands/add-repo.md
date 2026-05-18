Add one or more repos to the dotfiles inventory and clone them locally.

## Arguments

`$ARGUMENTS` is a space- or newline-separated list of repos. Each repo can be:
- `github.com/owner/repo` (preferred shorthand)
- `git@github.com:owner/repo.git` (full SSH)
- `owner/repo` (treated as github.com/owner/repo)

If `$ARGUMENTS` is empty, ask the user which repo(s) to add.

## Steps

For each repo in the list:

1. **Determine the entry fields**
   - `url`: normalise to `github.com/owner/repo` form (strip `git@github.com:`, strip trailing `.git`, strip leading `https://github.com/`).
   - `path`: default to `code/personal/<repo-name>` (the last path segment of the URL). If a better path is obvious from context (e.g. it's a work repo), use `code/work/<repo-name>` instead.
   - `tags`: default to `[]`. Use `[work]` for work repos, `[personal]` for personal-only repos.
   - `note`: one short sentence describing what the repo is. Infer from the repo name or any context the user provided; ask only if it's unclear.

2. **Check for duplicates** — read `~/code/personal/dotfiles/inventory/repos.yaml` and skip any repo whose `url` is already present (after normalisation).

3. **Append the entry** to the `repos:` list in `~/code/personal/dotfiles/inventory/repos.yaml`, preserving the existing structure and comments. New entries go at the end of their tag section (public `[]` entries before tagged ones).

4. After all entries are written, **run the clone script**:
   ```
   bash ~/code/personal/dotfiles/scripts/steps/P1-50-clone-public-repos.sh
   ```
   Show its output. If it errors, report what failed without retrying destructively.

5. **Commit** the inventory change to the dotfiles repo with a short message like `feat(inventory): add <repo-name>`.
