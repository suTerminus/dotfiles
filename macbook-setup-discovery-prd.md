# PRD Addendum: Discovery — Cataloging the Current Machine

**Owner:** Berkay
**Status:** Draft v2
**Parent doc:** `macbook-setup-prd.md`
**Sibling docs:** `macbook-setup-phase0-prd.md`, `macbook-setup-phase1-prd.md`, `macbook-setup-phase2-prd.md`, `macbook-setup-phase3-prd.md`
**Goal:** Before any new automation is built, produce an annotated catalog of what's on the current machine and in the existing dotfiles + vault repos. The catalog becomes the source data for the inventory files used by Phase 1+.

---

## 1. Why Discovery Exists

The earlier PRD drafts assumed the inventory files (`brew.yaml`, `repos.yaml`, etc.) would be written from scratch. That's the wrong starting point. The current machine has years of accumulated tooling and decisions baked in — some of which should port forward, some shouldn't, some need re-evaluation.

Writing the inventory files from imagination produces a setup that reflects what we *think* matters. Deriving them from a real catalog produces a setup that reflects what *actually* matters, with deliberate decisions about each item.

Discovery is a one-time pre-phase: it runs on the **current** machine, produces structured output, and feeds the inventory-writing step that precedes Phase 0.

---

## 2. Scope

### In scope

- Inventory of installed Homebrew formulae and casks
- Inventory of GUI applications in `/Applications` and `~/Applications`
- Mac App Store apps (via `mas list`)
- Audit of the existing dotfiles repo (file-by-file)
- Audit of the vault repo (high-level summary, plus extraction of any scripts/snippets)
- Categorization framework: `automate` / `manual` / `skip` / `investigate`
- Generation of starter `inventory/*.yaml` files with `[TODO]` tags awaiting your review

### Out of scope

- Capturing every macOS preference (`defaults read` produces hundreds of pages — not useful)
- Backing up application data (not a setup concern)
- Migrating actual config files (Phase 1 chezmoi work, not Discovery)
- Anything on the new MacBook (Discovery is current-machine-only)

---

## 3. The Existing Repo: Branch Strategy

Decided: current work-in-progress lives on the `wip` branch. `main` retains some old config that needs cleaning before the new structure goes in. No history rewrites — branches do the work.

### Current state

- `main` — holds older config, needs cleaning before new structure builds on top
- `wip` — holds current changes, treated as the canonical "old setup" snapshot for Discovery

### Procedure

1. **Discovery audit reads from `wip`.** All current config that matters is there. The audit script (`30-dotfiles-audit.sh`) takes a branch parameter; default to `wip`.
2. **Clean `main` to a baseline.** Once Discovery is done and decisions are made, on `main`: remove anything not carrying forward, leave a minimal `README.md` + the `tools/discovery/` directory. Single commit.
3. **Build new structure on `main`** as Phase 0/1/2+ progresses.
4. **Tag `wip` as `v1-archive`** once the new main is stable enough that you trust it (probably after Phase 1 validates on the new MacBook).
5. **Delete `wip` branch** after the tag exists. The tag preserves the snapshot; the branch isn't needed once it's no longer being worked on.

### Why this works

- No force-push, no orphan branches, no GitHub default-branch change.
- The `wip` branch keeps its history while it's still useful as a reference.
- `v1-archive` tag is the long-term marker — it's immutable, won't accidentally get deleted, and makes "what did the old setup look like" answerable forever.
- Cleaning `main` is a normal commit, fully reversible via `git revert` if needed.

### Sequencing

1. Run Discovery with `wip` as the audit target.
2. Make annotation/categorization decisions.
3. Clean `main` (single commit removing old config).
4. Begin Phase 0 implementation on `main`.
5. Once Phase 1 has run successfully on the new MacBook, tag `wip` as `v1-archive` and delete the branch.

---

## 4. Discovery Scripts Layout

All scripts live in `tools/discovery/` in the dotfiles repo (post-rewrite). They stay there permanently — useful for future re-runs, drift detection, or migrating to another machine.

```
tools/
└── discovery/
    ├── README.md                      # explains how to run, what each script does
    ├── run-all.sh                     # orchestrator: runs every discovery script
    ├── scripts/
    │   ├── 10-brew.sh                 # brew leaves, brew list --cask, brew tap
    │   ├── 20-applications.sh         # /Applications + ~/Applications + mas list
    │   ├── 30-dotfiles-audit.sh       # walk wip branch, list each file
    │   ├── 40-vault-audit.sh          # walk vault, look for scripts/snippets
    │   ├── 50-mise-asdf.sh            # if mise/asdf present, dump installed languages/versions
    │   ├── 60-shells-and-paths.sh     # current shell, $PATH, oh-my-zsh-style frameworks
    │   └── 70-misc.sh                 # GPG keys, SSH keys metadata (not contents), npm globals, pip user installs
    ├── output/                        # generated artifacts; gitignored except .gitkeep
    │   └── .gitkeep
    └── templates/
        ├── decisions.md.tmpl
        └── catalog-entry.yaml.tmpl
```

**Why output is gitignored:** Discovery output may contain machine names, usernames, lists of personal apps. Worth scrubbing manually before committing anything. The *scripts* are public-safe; the *output* needs review first.

---

## 5. Discovery Outputs

Each script writes to `tools/discovery/output/`. The full set:

### `output/installed-brew.yaml`

Pre-shaped to match the eventual `inventory/brew.yaml` schema, with every entry tagged `[TODO]` for your review.

```yaml
# Generated by tools/discovery/scripts/10-brew.sh on 2026-05-09.
# Each entry has tags: [TODO]. Replace with real tags during review:
#   [] (empty)        → install always
#   [optional, <bucket>]  → declared but skipped by default
#   [work] / [personal]   → conditional on machine type
#   [manual]              → tracked, never auto-installed
#   [skip]                → don't carry forward to the new machine

taps:
  - homebrew/cask-fonts                           # tags: [TODO]
  - homebrew/services                             # tags: [TODO]

formulae:
  - name: bat
    tags: [TODO]
  - name: ffmpeg
    tags: [TODO]
  - name: git
    tags: [TODO]
  # ... etc.

casks:
  - name: ghostty
    tags: [TODO]
  - name: visual-studio-code
    tags: [TODO]
  - name: qgis-ltr
    tags: [TODO]
  # ... etc.
```

### `output/installed-apps.yaml`

GUI apps, separated by source.

```yaml
# Apps in /Applications and ~/Applications, with detected source.
# Sources: brew-cask, mas, manual, unknown.

applications:
  - name: Slack.app
    bundle_id: com.tinyspeck.slackmacgap
    source: brew-cask        # also installable via cask
    version: "4.40.x"
    tags: [TODO]

  - name: Sophos Endpoint.app
    bundle_id: com.sophos.endpoint
    source: manual           # corporate IT, can't auto-install
    version: "..."
    tags: [TODO]             # likely [manual, work]

  - name: 1Password 7.app
    bundle_id: com.agilebits.onepassword7
    source: mas              # Mac App Store
    appid: "1333542190"
    tags: [TODO]

  # ... etc.
```

### `output/dotfiles-audit.md`

A walk of the existing dotfiles repo (`wip` branch by default), with a checkbox per file/directory.

```markdown
# Dotfiles Audit — wip

For each item, decide: keep / port / drop / template-ify.

## ~/.zshrc
- Currently: 412 lines, references `~/.zsh/` for fragments
- [ ] Keep as-is
- [ ] Port to new structure (chezmoi-managed at home/dot_zshrc.tmpl)
- [ ] Template-ify (machine-conditional sections)
- [ ] Drop
- Notes:

## ~/.gitconfig
- Currently: 38 lines, includes user.name/email hardcoded
- [ ] Keep as-is
- [x] Template-ify (user.email varies by machine: work vs personal)
- Notes: split into ~/.config/git/config + conditional include for work email

## bin/some-old-script.sh
- Last modified: 2022-08-14
- [ ] Keep
- [x] Drop (obsolete; references tooling we no longer use)
- Notes:

# ... etc.
```

### `output/vault-audit.md`

Higher-level, since the vault is user data. Goal: identify anything that's *config-or-script-disguised-as-notes* and should migrate.

```markdown
# Vault Audit

## Structure
- Top-level folders: <list>
- Total files: N
- Total size: X MB

## Notes containing scripts/snippets

Things found that look like they should live in code, not notes:

- `vault/dev/aws-helpers.md` — has 6 bash functions for AWS profile switching.
  - [ ] Migrate to ghost-bazaar/scripts/
  - [ ] Migrate to dotfiles ~/.config/aws/helpers.sh
  - [ ] Leave in vault (reference only)

- `vault/setup/old-mac-setup.md` — has a partial install script.
  - [x] Reference during this Discovery; drop afterward.

## Notes containing decisions

Things that document *why* something is set up a certain way — useful to migrate to dotfiles/docs/decisions.md:

- `vault/work/mise-vs-asdf.md`
- `vault/dev/why-not-fish.md`

## Action items
- [ ] Extract the AWS helpers
- [ ] Migrate decision notes to docs/decisions/
- [ ] Confirm vault repo URL for inventory/repos.yaml
```

### `output/mise-asdf.yaml`

Currently installed language versions. Becomes the basis for `inventory/mise.yaml`.

```yaml
# Detected via mise current / asdf current.
# Versions to carry forward: review and prune.

tools:
  go:
    installed: ["1.21.5", "1.22.3", "1.23.1"]
    in_use: "1.23.1"
    tags: [TODO]
  node:
    installed: ["18.19.0", "20.11.0", "22.3.0"]
    in_use: "22.3.0"
    tags: [TODO]
  python:
    installed: ["3.11.7", "3.12.1"]
    in_use: "3.12.1"
    tags: [TODO]
```

### `output/decisions.md`

Empty template you fill in *during* the review. This becomes the running record of decisions made, eventually moves to `docs/decisions/2026-05-discovery.md` in the new repo.

```markdown
# Discovery Decisions

Date: 2026-05-09
Context: Setting up new MacBook, restructuring dotfiles.

## Per-tool decisions

| Tool | Decision | Reason |
|---|---|---|
| Sophos | manual, work | Corporate IT install; never auto |
| QGIS | optional, gis | Rarely used, want declared but lazy install |
| Karabiner | keep, template config | Different keymaps for work/personal layout |
| <fill in as you review> | | |

## Repo decisions

The architecture uses **three repos** (see parent PRD §2): the public dotfiles repo, a private personal overlay, and a private work overlay. Each cataloged repo lands in exactly one of them.

| Repo | New home | Notes |
|---|---|---|
| dotfiles | `github.com/suTerminus/dotfiles` (public), main cleaned and built fresh | `wip` branch tagged as `v1-archive` once stable, then deleted |
| personal overlay | private repo, personal scope | Holds personal AWS, personal SSH hosts, personal Brewfile entries, Raycast App Support |
| work overlay | private repo, work scope | Holds work SSO, work SSH hosts, work-only Brewfile entries, work-org repo references |
| vault | path TBD — captured during M2 review | Personal Obsidian vault → `dotfiles-private/inventory/repos-personal.yaml` |
| ghost-bazaar | `github.com/suTerminus/ghost-bazaar` (private) | Already exists; goes in `dotfiles-private/inventory/repos-personal.yaml` (personal Claude Code plugin) |
| work-org marketplace | private, SSO-gated | Goes in the work overlay's `repos-<work>.yaml` — formerly in public `repos.yaml`, now moved here per three-repo architecture |
| other work-org repos | as above | Go in the work overlay's `repos-<work>.yaml` |
| <fill in others during M2.T05> | | |

## Things explicitly dropped
- <obsolete tool 1>: reason
- <obsolete tool 2>: reason
```

### `output/manual-installs.yaml`

Special inventory for things tagged `manual` during review. Tracked but never auto-installed.

```yaml
# Manual installs: declared, never auto-installed.
# Bootstrap warns if missing on a target machine.

manual:
  - name: Sophos Endpoint
    tags: [manual, work]
    reason: Corporate IT-managed; install via work IT request
    detection:
      kind: app
      bundle_id: com.sophos.endpoint
    docs_url: <internal Confluence link>

  - name: <other corporate tool>
    tags: [manual, work]
    # ...
```

The `detection` block lets the bootstrap *check* whether the manual install is present. Useful diagnostic: "manual installs declared but missing: Sophos." You then know to file an IT ticket.

---

## 6. Discovery Script Specifications

Each script is small, idempotent, and writes to `output/`. None modify anything on the system.

### `10-brew.sh`

Reads:
- `brew leaves` (formulae installed as direct dependencies, not transitive)
- `brew list --cask`
- `brew tap`

Writes: `output/installed-brew.yaml` with `tags: [TODO]` per entry.

Notes:
- Use `brew leaves`, not `brew list`. The latter includes transitive dependencies, which doesn't belong in inventory.
- For each formula, optionally annotate with `brew uses --installed <pkg>` to flag entries depended on by others (might affect the "drop" decision).

### `20-applications.sh`

Reads:
- `ls /Applications` and `ls ~/Applications` (Setapp creates the latter)
- For each app: `mdls -name kMDItemCFBundleIdentifier` for bundle ID
- `mas list` if `mas` is installed (Mac App Store apps)
- Cross-references against `brew list --cask` to detect apps installed via Homebrew

Writes: `output/installed-apps.yaml`.

Notes:
- The `source: manual` heuristic is "not in brew-cask AND not in mas list." Imperfect (some apps come from arbitrary DMGs), but a good starting point.
- Skip Apple's bundled apps (Safari, Mail, Calendar, etc.). Hardcode an exclusion list.

### `30-dotfiles-audit.sh`

Walks the existing dotfiles repo on a given branch (default `wip`). For each tracked file:
- Path
- Last modified date
- Line count
- A guess at the category (zsh config / git config / editor config / script / etc.)

Writes: `output/dotfiles-audit.md` with checkboxes.

Notes:
- This is generation-with-template. The script populates the structure; you fill in checkboxes during review.
- For deeply nested dotfiles (like `~/.config/nvim/...`), summarize at directory level rather than listing every file.

### `40-vault-audit.sh`

The vault is likely an Obsidian vault (markdown files). The script:
- Counts files and total size
- Lists top-level directory structure
- Greps for code blocks (` ``` `) longer than N lines — those are candidate scripts to migrate
- Greps for filenames matching common config patterns (`*config*`, `*setup*`, `*decision*`)

Writes: `output/vault-audit.md`.

Notes:
- The vault almost certainly contains private content. Output stays local; don't commit it without scrubbing.
- The action-item list at the bottom is hand-curated, not generated.

### `50-mise-asdf.sh`

Detects `mise` and/or `asdf`. For each:
- `mise list` / `asdf list` to enumerate installed versions
- `mise current` / `asdf current` for per-language defaults

Writes: `output/mise-asdf.yaml`.

### `60-shells-and-paths.sh`

Reads:
- Current default shell (`echo $SHELL`)
- `$PATH` decomposed into entries with provenance guess
- Existence of `~/.oh-my-zsh`, `~/.zprezto`, `~/.zinit`, etc. (zsh frameworks)
- Existence of `~/.tmux.conf`, `~/.config/nushell/`, etc.

Writes: `output/shells-and-paths.md` (markdown for narrative; not strictly schema'd).

Notes:
- This one's mostly informational. Helps you decide whether to carry forward oh-my-zsh, switch to starship, etc.

### `70-misc.sh`

Catches the leftovers:
- GPG keys: `gpg --list-secret-keys --keyid-format=long` (lists, doesn't export)
- SSH keys: `ls ~/.ssh/*.pub` (filenames only, no contents)
- Globally installed npm packages: `npm list -g --depth=0`
- Globally installed pip packages: `pip list --user` (and equivalents for pipx, uv tool)

Writes: `output/misc.md`.

### `run-all.sh`

Orchestrator. Runs every script, reports completion, prints a summary at the end:

```
✓ Discovery complete.

Outputs in tools/discovery/output/:
  • installed-brew.yaml          (143 entries — review and tag)
  • installed-apps.yaml          (47 entries — review and tag)
  • dotfiles-audit.md            (89 files — check boxes)
  • vault-audit.md               (review action items)
  • mise-asdf.yaml               (3 languages, 8 versions)
  • shells-and-paths.md
  • misc.md
  • manual-installs.yaml         (empty — populate during review)
  • decisions.md                 (empty template — fill during review)

Next: review each file, replace [TODO] tags with real categorization,
fill in decisions.md. Then translate into inventory/*.yaml files
in the new dotfiles structure.
```

---

## 7. The Review & Annotation Loop

Discovery produces *catalog with TODOs*. The review step turns it into *annotated catalog with decisions*. This is a manual step — you doing it, possibly in conversation with Claude Code.

### What review involves

For each item in `installed-brew.yaml` and `installed-apps.yaml`, decide:

- **install always** (most common case): empty tags
- **optional, <bucket>**: declared but skip by default; install with `--include-tag <bucket>` (e.g., `optional, gis` for QGIS)
- **work / personal**: conditional on machine type
- **manual**: declared, never auto-installed; bootstrap warns if missing
- **skip**: don't carry to the new machine

For each item in `dotfiles-audit.md`, decide: keep / port / template-ify / drop.

For each action item in `vault-audit.md`, decide: migrate (where to?) / leave / drop.

### How to make this fast

The catalog will have ~150 entries. Reviewing each is tedious but valuable. To keep momentum:

- **Batch by category.** Do all formulae first, then all casks, then apps. Same context = faster decisions.
- **Default everything to "install always" first.** Only mark exceptions. Most things will have empty tags.
- **Don't over-engineer the optional buckets.** `optional, gis` is fine. Don't create `optional, gis, qgis-related, vector-tools` — that's premature.
- **For "investigate" cases, just put `tags: [TODO, investigate]` and move on.** Come back to them once the rest is done.
- **Use Claude Code as a sounding board.** "I have these 6 fonts installed — which are likely actually used?" Claude can guess from context (you mentioned preferring Nerd Fonts, etc.).

### Output of review

After review, the same `output/` files are now fully tagged. They're ready to be **translated** into the actual `inventory/*.yaml` files for the new dotfiles structure.

---

## 8. Translation: Catalog → Inventory

The catalog files in `output/` aren't quite the final inventory files — they have one-time stuff like `version` fields, `installed` lists, audit metadata. The inventory files are leaner.

The translation step:

1. Read `output/installed-brew.yaml`, drop entries tagged `skip`, drop fields that don't belong in inventory (versions, etc.), write `inventory/brew.yaml`.
2. Read `output/installed-apps.yaml`, partition by source: public/non-sensitive brew-cask entries merge into public `inventory/brew.yaml`, personal-private cask + mas entries go to the personal overlay's `inventory/brew-personal.yaml`, work-only cask + mas entries go to the work overlay's `inventory/brew-<work>.yaml`, manual entries go to public `inventory/manual.yaml`.
3. Read `output/mise-asdf.yaml`, prune unused versions, write `inventory/mise.yaml`.
4. Read `decisions.md`, anything that affects repo configuration goes to public `inventory/repos.yaml` (only public, non-work repos), the personal overlay's `repos-personal.yaml` (personal repos like the Claude plugin), or the work overlay's `repos-<work>.yaml` (work-org repos).

This step is mostly mechanical — a Claude Code conversation can do it from the annotated catalog. Worth doing in a single session so context stays warm.

---

## 9. The Manual Install Mechanism

Decided: items tagged `manual` are tracked in inventory and the bootstrap warns if missing.

### Behavior

`inventory/manual.yaml` (or `inventory/brew.yaml` entries with `tags: [manual]`) drive a check step in the bootstrap:

```
# scripts/steps/P3-20-manual-check.sh (Phase 3 step in the full bootstrap)
# Probe each manual item's `detection` block.
# For each missing item: log a warning with the item's `reason` and `docs_url`.
# Never installs. Always exits 0 (warnings, not errors).
```

Output looks like:

```
Manual installs check:
  ✓ 1Password 7 (mas)
  ⚠ Sophos Endpoint — missing
       reason: Corporate IT-managed; install via work IT request
       docs:   <internal Confluence link>
  ⚠ <other> — missing
```

This makes "what's installed" answerable from inventory + bootstrap output. The bootstrap can't fix corporate IT installs, but it can tell you what's expected and missing.

### Detection blocks

The `detection` block in `manual.yaml` supports a few kinds:

```yaml
detection:
  kind: app                    # checks /Applications and ~/Applications
  bundle_id: com.sophos.endpoint

# or:
detection:
  kind: command                # checks PATH
  command: orbstack-helper

# or:
detection:
  kind: file                   # checks file existence
  path: /Library/Application Support/Sophos/

# or:
detection:
  kind: launchd                # checks for a registered launchd agent/daemon
  label: com.sophos.endpoint
```

Most manual installs will use `kind: app`. The others handle edge cases.

---

## 10. Where Discovery Fits in the Overall Flow

Updated phase model:

| Phase | When | Where it runs | Driver |
|---|---|---|---|
| **Discovery** | Before everything | Current machine | Bash scripts + manual review |
| **Catalog → Inventory translation** | After Discovery | Current machine | Claude Code, conversational |
| **Main cleanup** | After translation | Current machine | Single commit on `main` |
| **Phase 0** | New MacBook, fresh install | New machine | curl \| bash |
| **Phase 1** | After Phase 0 | New machine | Claude Code |
| **Phase 2+** | After Phase 1 | New machine | Claude Code |
| **Archive `wip`** | After Phase 1 stable | Either machine | Tag `v1-archive`, delete branch |

Discovery and translation happen on the **current** machine. The main-cleanup commit happens once between translation and Phase 0. Then everything from Phase 0 onward runs on the new machine. The `wip` branch sticks around until Phase 1 is validated, then gets archived as a tag and deleted.

---

## 11. Implementation Order (Discovery only)

1. **Create `tools/discovery/` skeleton** in the existing dotfiles repo (on a feature branch, not main yet).
2. **Write `lib/log.sh`** — shared logging helpers.
3. **Write `10-brew.sh`** — easiest first. Validate output.
4. **Write `20-applications.sh`** — slightly trickier (mdls, mas, source detection).
5. **Write `30-dotfiles-audit.sh`** — walks the repo itself.
6. **Write `40-vault-audit.sh`** — needs vault repo path as input.
7. **Write `50-mise-asdf.sh`, `60-shells-and-paths.sh`, `70-misc.sh`.**
8. **Write `run-all.sh` orchestrator and templates.**
9. **Run `run-all.sh` on the current machine.**
10. **Review the output and fill in tags / checkboxes / decisions.md.**
11. **Translate annotated catalog into `inventory/*.yaml`** (Claude Code conversation).
12. **Clean main** — single commit on `main` removing config that won't carry forward, leaving baseline (README, `tools/discovery/`, anything else explicitly kept).
13. **Begin Phase 0 implementation** on `main`.

Steps 1–8 build the discovery tooling. Steps 9–11 use it. Step 12 commits the cleanup. Steps 13+ are the existing PRDs.

After Phase 1 validates on the new MacBook (much later): tag `wip` as `v1-archive`, delete the `wip` branch.

---

## 12. Success Criteria (Discovery)

- Every Homebrew package, GUI app, MAS app, and dotfile in the existing setup is accounted for in the catalog.
- Every item has an explicit decision (install / optional / manual / skip / port / drop). Nothing is forgotten by accident.
- The catalog can be re-generated by re-running `tools/discovery/run-all.sh` (idempotent: same input produces same output, modulo what's actually installed).
- After translation, the new inventory files reflect deliberate choices, not guesses.
- After main cleanup, the `main` branch contains only what's deliberately kept; `wip` still holds the old setup as a reference until archived.
- The Sophos-style "manual install" pattern is established and tracked.

---

## 13. Open Questions

- **What's the vault repo URL and structure?** Needed to scope `40-vault-audit.sh`. Defer until that script is written.
- **Is `mas` already installed?** If not, `20-applications.sh` skips MAS detection or installs `mas` first as part of Discovery setup.
- **Should Discovery output include screenshot of current Dock + menu bar configuration?** For visual reference when reconfiguring on the new machine. Probably not — over-engineering. Mention but skip.
- **What about Docker, OrbStack, container images?** Lists of currently-pulled images aren't really inventory (they pull on-demand). Skip from Discovery.
- **VSCode/Cursor extensions?** `code --list-extensions` would catalog these. Useful, but worth a separate small script in `60-shells-and-paths.sh` or `70-misc.sh`. Add to `70`.
