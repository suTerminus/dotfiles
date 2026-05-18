# PRD: MacBook Setup Automation

**Owner:** Berkay
**Status:** Draft v5 (umbrella)
**Goal:** A single command sets up a new MacBook from zero to fully-configured, supports work/private separation, and is safe to re-run any number of times.

This is the **umbrella PRD**. It defines the goals, architecture, phase model, tooling stack, repository layout, inventory schema framing, and cross-cutting concerns shared across phases. Per-phase implementation detail lives in sibling PRDs:

- `macbook-setup-discovery-prd.md` — pre-phase: catalog the current machine.
- `macbook-setup-phase0-prd.md` — Phase 0: `curl | bash` to Claude Code on the new MacBook.
- `macbook-setup-phase1-prd.md` — Phase 1: chezmoi + public Brewfile pipeline + mise + public repo clone.
- `macbook-setup-phase2-prd.md` — Phase 2: private overlay + Bitwarden + AWS + Claude Code plugins.
- `macbook-setup-phase3-prd.md` — Phase 3: macOS defaults + Touch ID sudo + manual checks + doctor + sign-off.

Reading order: this doc → Discovery → Phase 0 → Phase 1 → Phase 2 → Phase 3.

---

## 1. Goals & Non-Goals

### Goals

- **One-command bootstrap.** A single `curl | bash` that gets a fresh macOS to a fully working state with no manual steps beyond authentication prompts (GitHub login, Bitwarden master password, sudo password).
- **Idempotent.** Re-running the bootstrap (or any sub-script) on an already-configured machine must be safe and produce the same end state. This is treated as a first-class requirement, not a nice-to-have. Expect to run it 20+ times during initial development.
- **Work/private separation.** A public `dotfiles` repo for shareable config, a private `dotfiles-private` repo for everything sensitive or personal. The bootstrap composes them.
- **Tool inventory is data, not code.** Adding/removing a tool means editing a list, not editing a script. Optional tools (e.g., QGIS) can stay declared but un-installed via tags.
- **Repository auto-clone.** A declarative list of repos that get cloned to predictable paths during setup. Re-running the setup clones any new entries without re-cloning existing ones.

### Non-Goals

- Provisioning macOS system settings beyond what `defaults write` (and a small set of scripted exceptions like `pam_tid.so`) can reach. No MDM, no profile installation.
- Backup/restore of personal files (Documents, photos). That's iCloud/Time Machine.
- Cross-platform (Linux/Windows). macOS only.
- Managing the macOS account itself (Apple ID, FileVault). User does this manually before running bootstrap.

---

## 2. Architecture Overview

### Discovery first

Before any of the structure described here is built, a **Discovery** pre-phase runs on the *current* machine to catalog what's installed and what's in the existing dotfiles + vault repos. The output drives the actual contents of the inventory files. See `macbook-setup-discovery-prd.md`.

### Three repos, composed at apply time

**`suTerminus/dotfiles`** (public). Base layer. Non-sensitive configuration: shell, editor, git basics, public CLI tool configs, and the bootstrap scripts themselves. Safe to open-source.

**Personal overlay (private repo).** Personal-sensitive overlay: personal AWS profiles, personal SSH hosts, personal Brewfile entries (e.g., 1Password with license refs), Application Support snapshots for apps holding personal state, Bitwarden-rendered API keys.

**Work overlay (private repo).** Work-org-specific overlay: work AWS SSO profiles, work-only Brewfile entries (Slack, Teams, corporate VPN client), work-org repo references (formerly in public `repos.yaml`), work-org tool configs. Anything that ties the machine to the employer lives here, not in the personal overlay.

All three are managed by **chezmoi**. The public repo is applied first; personal and work overlays are applied on top in order, so later overlays win on conflicts.

### Overlay rules per machine

The `machine` chezmoi prompt drives which overlays apply:

| `machine` value | Overlays applied | Order |
|---|---|---|
| `personal` | public + personal overlay | public → personal |
| `work` | public + personal overlay + work overlay | public → personal → work |

Personal-sensitive content (1Password, personal AWS) lives on both machine types because the user is the same person; work-sensitive content (corporate VPN, work SSO) only lands on work machines.

A teammate cloning only the public repo gets a working public-dotfiles setup with no expectation of access to either overlay.

### Why three repos and not two

- The public repo can genuinely stay public — no risk of leaking via a misconfigured template.
- The personal/work split lets each have its own access control, history, and rotation cadence. The work overlay can be granted to a coworker for fleet-style standardisation without exposing personal secrets.
- Putting work-only content (Slack, Teams, work AWS) in the work overlay keeps the personal overlay usable on a strictly-personal machine that should never get work tooling.
- Anyone can clone the public dotfiles to bootstrap a similar setup without needing access to either overlay.

---

## 3. Phase Model & Reading Order

The full setup is split into phases. Each phase has a clear entry condition, a clear exit condition, and is independently runnable. A fresh machine *always* starts at Phase 0; re-running any phase on a configured machine is a no-op (idempotent).

| Phase | Entry state | Exit state | Driver | PRD |
|---|---|---|---|---|
| **Discovery** | Existing machine with current dotfiles | Annotated catalog → `inventory/*.yaml` | Bash + manual review | `macbook-setup-discovery-prd.md` |
| **0** | Fresh macOS, signed-in user | Claude Code installed + dotfiles cloned | `curl \| bash` | `macbook-setup-phase0-prd.md` |
| **1** | Phase 0 complete | chezmoi public applied, mise + language tools, public Brewfile bundled, public repos cloned | Claude Code | `macbook-setup-phase1-prd.md` |
| **2** | Phase 1 complete | Private overlay applied, Bitwarden secrets rendered, AWS profiles, ghost-bazaar plugin, marketplace registered | Claude Code | `macbook-setup-phase2-prd.md` |
| **3** | Phase 2 complete | macOS defaults applied, Touch ID sudo, manual-installs check, doctor.sh complete, real-machine validated | Claude Code | `macbook-setup-phase3-prd.md` |

Phases are documentation/scope groupings, not separate scripts. Phase 0 has its own orchestrator (`phase0/bootstrap.sh`, the public curl URL). Phases 1–3 share `scripts/setup.sh` and select work via `--only` filters or the per-phase step prefixes (`P1-NN`, `P2-NN`, `P3-NN`).

**Step ID convention:** every step in Phases 0–3 uses a phase prefix and dense 10-spacing (`P0-00`, `P0-10`, …). The legacy `00/50/60/70/80/85/90/95/97/99` numbering from earlier drafts has been retired.

---

## 4. Tooling Stack

| Layer | Tool | Why |
|---|---|---|
| Package manager | Homebrew | macOS standard, has `brew bundle` for declarative installs |
| Dotfile manager | chezmoi | Templating, machine-specific config, native Bitwarden integration |
| Secrets | Bitwarden CLI (`bw`) | Already in use, scriptable, good chezmoi integration |
| GitHub auth | `gh` CLI | Handles SSH key generation + upload in one step |
| Language runtimes | mise | Replaces asdf; handles Go/Node/Python in one tool |
| Python tooling | uv | Modern Python package/project manager; provides `uvx` and `uv tool install` |
| Shell | zsh (default on macOS) | No reason to switch |
| Editor (chosen v1) | Neovim (kickstart.nvim base) | Single-file config; lightweight; off-the-shelf with full ownership |
| Multiplexer | tmux + tpm | tpm + tmux-sensible + tmux-resurrect + tmux-continuum + catppuccin/tmux |
| Terminal | Ghostty | Native macOS, supports declarative `theme = light:…,dark:…` auto-switching |
| Palette | Catppuccin (latte / mocha) | Best cross-tool ecosystem coverage; consistent across nvim/tmux/ghostty/bat/delta/k9s/starship |

---

## 5. Repository Layout (high level)

The public dotfiles repo holds everything except secrets. Per-phase PRDs detail which paths each phase creates and uses.

```
suTerminus/dotfiles
├── .chezmoiroot                 # contains "home"
├── home/                        # chezmoi target — only this dir is applied
│   ├── .chezmoi.toml.tmpl       # prompts on first init: machine, name, email
│   ├── .chezmoiignore.tmpl      # templated; gates work-only files on .machine
│   ├── dot_zshrc.tmpl
│   ├── dot_zshenv.tmpl
│   ├── dot_gitconfig.tmpl       # incl. SSH commit signing config
│   ├── dot_gitignore_global
│   ├── dot_config/
│   │   ├── git/
│   │   ├── mise/config.toml.tmpl
│   │   ├── brew/Brewfile.tmpl   # public Brewfile (rendered from inventory)
│   │   ├── ghostty/config.tmpl  # light/dark auto-switch
│   │   ├── nvim/                # kickstart.nvim base
│   │   ├── tmux/                # tpm + plugins + light/dark theme files
│   │   ├── k9s/
│   │   └── claude/settings.json.tmpl
│   ├── dot_local/
│   │   ├── bin/theme-toggle     # macOS appearance flip + tmux/nvim signal
│   │   └── share/chezmoi-hooks/
│   └── ...
├── inventory/                   # data files — see §6
│   ├── brew.yaml                # public packages (source for Brewfile.tmpl)
│   ├── repos.yaml               # public repos to auto-clone
│   ├── mise.yaml                # language runtimes + python_tools
│   ├── macos-defaults.yaml      # system preferences (Phase 3)
│   ├── system-tweaks.yaml       # pam_tid.so etc. (Phase 3)
│   └── manual.yaml              # tracked, never auto-installed (Phase 3)
├── phase0/                      # Phase 0 self-contained bootstrap (curl entry)
│   ├── bootstrap.sh
│   ├── Brewfile
│   ├── claude-settings-bootstrap.json
│   ├── lib/{log,idempotent}.sh
│   └── steps/P0-*.sh
├── scripts/                     # Phase 1+ orchestrator & steps
│   ├── setup.sh                 # full bootstrap orchestrator (NOT bootstrap.sh — that's Phase 0)
│   ├── doctor.sh                # health check
│   ├── render-brewfile.sh       # inventory/brew.yaml → Brewfile.tmpl
│   ├── lib/{log,idempotent,prompt,macos}.sh
│   └── steps/{P1-*,P2-*,P3-*}.sh
├── tools/discovery/             # Discovery pre-phase scripts (gitignored output/)
└── docs/
    ├── phases.md
    ├── architecture.md
    ├── adding-a-tool.md
    ├── adding-a-repo.md
    ├── manual-setup.md
    ├── troubleshooting.md
    └── decisions/               # dated decision log (e.g., discovery decisions)
```

Each overlay repo (personal, work) mirrors the layout for `home/` and `inventory/`, holding `private_*` chezmoi files and an inventory directory:

- **Personal overlay `inventory/`**: `brew-personal.yaml`, `repos-personal.yaml`, plus templated config files under `home/private_dot_*` (personal AWS, personal SSH hosts, personal Claude-plugin reference).
- **Work overlay `inventory/`**: `brew-<work>.yaml`, `repos-<work>.yaml` (work-org repos — NOT in the public `repos.yaml`), plus `home/private_dot_*` files for work SSO, work SSH hosts, etc.

See Phase 2 PRD §4 for the full overlay layout.

`chezmoi apply` only sees `home/` (because of `.chezmoiroot`). Everything else in the repo (`phase0/`, `scripts/`, `inventory/`, `tools/`, `docs/`) is plain files chezmoi ignores.

### Naming convention: `bootstrap.sh` vs `setup.sh`

- `phase0/bootstrap.sh` — the public curl entry point. Name is fixed because it appears in the `curl -fsSL …/phase0/bootstrap.sh | bash` URL. Does Phase 0 only.
- `scripts/setup.sh` — the Phase 1+ orchestrator. Renamed from earlier `bootstrap.sh` drafts to avoid conversational ambiguity ("run bootstrap.sh — which one?").

---

## 6. Inventory Schema Reference

Tool definitions, repo lists, language versions, and macOS preferences are **data**, not scripts. Every phase reads from `inventory/*.yaml` and acts on it. Adding a tool means adding one line.

> **The actual contents** of these files are produced by Discovery, reviewed, and translated. Per-phase PRDs document which inventory file each phase reads or writes. Schemas:
>
> - **Public** (in `dotfiles/inventory/`): `brew.yaml`, `repos.yaml`, `mise.yaml`, `macos-defaults.yaml`, `system-tweaks.yaml`, `manual.yaml`. Schemas in Phase 1 PRD §6 and Phase 3 PRD §5–§7. Manual schema is owned by Discovery PRD §9.
> - **Personal overlay** (in the personal overlay repo's `inventory/`): `brew-personal.yaml`, `repos-personal.yaml`. Phase 2 PRD §6.
> - **Work overlay** (in the work overlay repo's `inventory/`): `brew-<work>.yaml`, `repos-<work>.yaml`. Phase 2 PRD §6.

### chezmoi source directory

chezmoi's source dir is set to the working dotfiles repo directly:

```toml
# home/.chezmoi.toml.tmpl
sourceDir = "{{ .chezmoi.homeDir }}/code/personal/dotfiles"
```

Trade-off: tighter dev loop. Edit at `~/code/personal/dotfiles`, run `chezmoi apply` immediately — no push/pull cycle. `chezmoi update` is reserved for *other* machines that consume the repo via chezmoi's default source path.

### Brewfile pipeline

```
inventory/brew.yaml ──[scripts/render-brewfile.sh]──> home/dot_config/brew/Brewfile.tmpl
                                                                  │
                                                                  ▼
                                                          [chezmoi apply]
                                                                  │
                                                                  ▼
                                                       ~/.config/brew/Brewfile
                                                                  │
                                                                  ▼
                                                       [brew bundle install]
```

Render is a separate explicit step (`P1-20`), not a chezmoi `run_before_` hook. Easier to test in isolation. The same pipeline applies to the personal overlay's `brew-personal.yaml` and the work overlay's `brew-<work>.yaml` in Phase 2 (`P2-20`).

Public `inventory/repos.yaml`, the personal overlay's `repos-personal.yaml`, and the work overlay's `repos-<work>.yaml` are consumed *directly* by the clone steps (`P1-50` for public, `P2-30` for both overlays), not rendered through chezmoi.

### Tag semantics

- A tool/repo/cask with no tags is **always installed**.
- `tags: [optional, <bucket>]` is **skipped by default**, installed only with `--include-tag <bucket>`.
- `tags: [work]` is installed only on machines where chezmoi prompted `machine = "work"`. Same for `personal`.
- Tags compose: `tags: [work, optional]` means "work machine + explicit opt-in."

---

## 7. Cross-Cutting Concerns

### Idempotency contract

- **Every step probes before acting.** If the probe passes, the step prints `skip: <reason>` and exits 0.
- **Every step is independently runnable.** `scripts/steps/P1-30-brew-bundle.sh` should work standalone.
- **`scripts/doctor.sh` runs every idempotency probe and reports state.** Use this before deciding what to fix. Output: `[ok] / [drift] / [missing]` table; non-zero exit on any non-ok.
- **Errors are localized.** A failure in one step should not leave prior steps broken. The orchestrator continues by default and prints a summary at the end (`--fail-fast` opts in to early exit).
- **Logging.** Every step writes to `~/.local/state/macbook-setup/run-<timestamp>.log` with full output, plus a colored summary to stdout. Diffs (e.g., what brew installed) are captured.

### Bootstrapping vs maintenance modes

`scripts/setup.sh` supports both:

```
setup.sh                                # full Phase 1+ run, all steps
setup.sh --only P1-30,P3-00             # specific steps
setup.sh --skip P2-00                   # skip Bitwarden unlock (e.g., already in env)
setup.sh --include-tag gis              # opt in to optional-tagged tools
setup.sh --update-repos                 # pull existing clones (off by default)
setup.sh --dry-run                      # show what would change
setup.sh --doctor                       # alias for scripts/doctor.sh
setup.sh --fail-fast                    # exit on first error
```

### Secrets handling principles

- **Nothing sensitive in the public repo.** Ever. Including comments.
- **Templates over scripts.** Use chezmoi's `bitwarden*` template functions instead of shelling out to `bw get`.
- **Document what's referenced.** `dotfiles-private/docs/secrets.md` lists every Bitwarden item used by templates, what field, and why.

Full handling — Bitwarden item conventions, session lifecycle, template syntax — lives in Phase 2 PRD §7.

### Commit signing

`dot_gitconfig.tmpl` enables SSH-key commit signing using the key generated in Phase 0:

```
[gpg]
    format = ssh
[user]
    signingkey = ~/.ssh/id_ed25519.pub
[commit]
    gpgsign = true
[tag]
    gpgsign = true
```

No GPG dance. The key is generated and uploaded to GitHub by Phase 0 step `P0-40`. The same key is referenced (read-only) by Phase 2's `private_dot_ssh/config.tmpl`. The private key file itself is **never** chezmoi-managed.

### Light / dark mode

- Ghostty auto-switches via `theme = light:catppuccin-latte,dark:catppuccin-mocha` (follows macOS appearance).
- nvim uses `f-person/auto-dark-mode.nvim` to swap between catppuccin-latte and catppuccin-mocha.
- tmux uses two theme files (`tmux/light.conf`, `tmux/dark.conf`) sourced by a `<prefix>+T` toggle and by `~/.local/bin/theme-toggle`.
- bat, delta, starship, k9s, lazygit, btop all read a single `~/.theme-mode` file the toggle script writes.
- macOS appearance flip is `osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to not dark mode'`.

The toggle script and per-tool theme files are authored on the current machine in M2.5 (see plan) and shipped via chezmoi in Phase 1.

---

## 8. Pointers to Per-Phase PRDs

| File | What it owns |
|---|---|
| `macbook-setup-discovery-prd.md` | Branch strategy (`wip` archive plan), Discovery scripts under `tools/discovery/`, catalog → inventory translation, `inventory/manual.yaml` schema (canonical) |
| `macbook-setup-phase0-prd.md` | `phase0/` curl entrypoint, Xcode CLT, Homebrew, four-package Brewfile, GitHub auth + SSH key, Claude Code install + auth, repo clone, `claude-settings-bootstrap.json` handoff |
| `macbook-setup-phase1-prd.md` | `scripts/setup.sh`, `scripts/lib/`, chezmoi init, `scripts/render-brewfile.sh`, public Brewfile bundle, mise + python_tools, public repo clone, gitconfig template (incl. SSH signing), `inventory/{brew,repos,mise}.yaml` schemas |
| `macbook-setup-phase2-prd.md` | Bitwarden unlock, personal + work overlay clones and applies (overlay order matters), AWS/SSH/API templates, personal + work Brewfiles, private repo clone (incl. personal Claude plugin from personal, work-org repos from work), Raycast App Support, personal Claude plugin install, marketplace registration, per-overlay `docs/secrets.md` |
| `macbook-setup-phase3-prd.md` | macOS defaults (extended schema with `killall:`), Touch ID sudo, system tweaks, manual-installs check, post-install hooks, `scripts/doctor.sh`, real-MacBook validation, `wip` archive tag, v1 sign-off doc |

---

## 9. Future Work

Things discussed but explicitly out of scope for v1.

- **Skills system.** Skills like `update-brewfile`, `add-tool`, `add-repo`, `bootstrap-doctor`, `audit-dotfiles` would automate the maintenance lifecycle. Deferred until the bootstrap is stable and the patterns these skills should encode are clearer from real use.
- **Session journal hook.** A `Stop` hook calling Haiku to summarize each Claude Code session. Separate concern from setup automation.
- **Cross-machine sync.** Once there are 2+ machines, a way to reconcile drift between them. Premature now.
- **Public/private split for ghost-bazaar.** Some skills/commands may turn out to be shareable. Defer until concrete examples exist.
- **Curl-script checksum verification.** Considered for Phase 0; deferred to v2. Trade-off: more secure, more friction on updates. Revisit if the public repo becomes shared with non-trusted parties.
- **GPG signing.** Considered for commit signing; rejected in favor of SSH signing (already have the key from Phase 0). If a future requirement demands GPG (e.g., Debian package signing), revisit.
- **App Support backups beyond Raycast.** Per-app evaluation as the need emerges.
- **Browser profile sync.** Manual; account-level concern. Profile sign-in stays a post-bootstrap manual step.

Each item gets its own PRD when its time comes.
