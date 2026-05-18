# PRD Addendum: Phase 0 — Bootstrap to Claude Code Handoff

**Owner:** Berkay
**Status:** Draft v2
**Parent doc:** `macbook-setup-prd.md`
**Sibling docs:** `macbook-setup-discovery-prd.md`, `macbook-setup-phase1-prd.md`, `macbook-setup-phase2-prd.md`, `macbook-setup-phase3-prd.md`
**Goal:** Define the minimum bootstrap that gets a fresh MacBook from zero to a state where Claude Code can take over and drive the rest of the setup.

---

## 1. Phase Model

The full setup is split into phases. Each phase has a clear entry condition, a clear exit condition, and is independently runnable.

| Phase | Entry state | Exit state | Driver |
|---|---|---|---|
| **0** | Fresh macOS, signed-in user account | Claude Code installed, authenticated, dotfiles repo cloned | Bash script via `curl \| bash` |
| **1** | Phase 0 complete | chezmoi + inventory system in place, public dotfiles applied, mise installed, repos cloned | Claude Code, conversational |
| **2** | Phase 1 complete | Private dotfiles overlay, Bitwarden secrets, AWS profiles, work-specific tooling | Claude Code, conversational |
| **3** | Phase 2 complete | Polish, doctor script complete, macOS defaults applied | Claude Code, conversational |

**Why this split:** Phase 0 is the only phase that must be written entirely up-front, because there's no Claude Code to help yet. Everything from Phase 1 onward is built collaboratively with Claude Code on the actual target machine, which is faster and produces better results than guessing in advance.

**Key invariant:** A fresh machine *always* starts at Phase 0. Phase 0 is never deprecated or replaced — it's the permanent entry point. Re-running Phase 0 on a configured machine is a no-op (idempotent).

---

## 2. Phase 0 Scope

### In scope

- Xcode Command Line Tools
- Homebrew
- Phase 0 Brewfile (minimal: `gh`, `git`, `node`, `jq` + cask `claude`)
- GitHub authentication via `gh`
- Claude Code installation via npm
- Claude Code authentication (subscription, browser flow)
- Claude Desktop authentication (subscription, browser flow) -- enables cowork for Phase 1 agent
- Cloning the public dotfiles repo to `~/code/personal/dotfiles`
- Handoff instructions printed to terminal

### Out of scope (deferred to later phases)

- chezmoi
- Bitwarden CLI
- mise / language version managers
- Any tools beyond the four Phase 0 essentials
- Private dotfiles repo
- macOS system preferences
- The full inventory YAML system
- Any skills, slash commands, or maintenance tooling

### Why these five packages

| Package | Why in Phase 0 |
|---|---|
| `gh` | GitHub auth + SSH key upload in one command, used by clone step |
| `git` | Newer than Xcode CLT's bundled git, needed by gh |
| `node` | Required runtime for Claude Code (`npm install -g @anthropic-ai/claude-code`) |
| `jq` | JSON parsing in scripts (e.g., reading `gh auth status --json`) |
| `claude` (cask) | Claude Desktop app; pairs with Claude Code CLI to enable cowork on the new machine while Phase 1 agent finishes setup |

`yq` is *not* in Phase 0 because Phase 0 has no YAML to parse. It joins in Phase 1 with the inventory system.

---

## 3. Repository Layout (Phase 0 only)

When Phase 0 is built, the public dotfiles repo looks like this. Phase 1+ adds to it without modifying these files.

```
dotfiles/
├── README.md                          # explains phase model, links to docs/phases.md
├── phase0/
│   ├── bootstrap.sh                   # the curl | bash entrypoint
│   ├── Brewfile                       # phase 0 packages
│   ├── lib/
│   │   ├── log.sh                     # info, warn, error, ok, skip helpers
│   │   └── idempotent.sh              # ensure_installed, ensure_authed, etc.
│   └── steps/
│       ├── 00-preflight.sh
│       ├── 10-xcode-clt.sh
│       ├── 20-homebrew.sh
│       ├── 30-phase0-brew.sh
│       ├── 40-github-auth.sh
│       ├── 50-claude-code.sh
│       └── 60-clone-self.sh
└── docs/
    ├── phases.md                      # phase model explained
    └── phase0.md                      # phase 0 specifics, troubleshooting
```

---

## 4. The Bootstrap Script

### Entry point

```bash
curl -fsSL https://raw.githubusercontent.com/suTerminus/dotfiles/main/phase0/bootstrap.sh | bash
```

The script self-checks: if `~/code/personal/dotfiles/phase0/bootstrap.sh` already exists and is the same as the curl'd version, it re-execs from the local copy. This makes second-run-onward not depend on network for the script itself.

### Orchestrator behavior

`bootstrap.sh` is a thin orchestrator that:

1. Sources `lib/log.sh` and `lib/idempotent.sh`.
2. Parses flags: `--only <step>`, `--skip <step>`, `--dry-run`, `--fail-fast`.
3. Iterates through `steps/*.sh` in numeric order.
4. For each step: prints a header, runs it, captures exit code.
5. On error: by default, logs and continues. With `--fail-fast`: exits immediately.
6. At end: prints a summary table (step / status / duration).
7. Prints handoff message if all steps succeeded.

### Logging

- Full output to `~/.local/state/macbook-setup/phase0-<timestamp>.log`.
- Colored, human-readable summary to stdout.
- Each step uses log helpers: `info`, `ok`, `skip`, `warn`, `error`.
- `skip` is first-class — most re-run steps will print `skip: already installed`.

---

## 5. Step Specifications

Each step is its own script under `phase0/steps/`. Each is independently runnable. Each is idempotent. Each declares its idempotency probe at the top as a comment.

### 00-preflight.sh

**Probe:** N/A (always runs; it's the gate).

**Checks:**
- macOS version ≥ 15 (Sequoia). Fail if older. (Bumped from Sonoma per architectural review C-5; today's date is 2026-05-09 — Sequoia is current, Sonoma is two majors behind.)
- Apple Silicon (`uname -m` == `arm64`). Warn but continue if Intel — the rest probably works but is untested.
- Internet reachable (curl to `https://github.com` with 5s timeout).
- Not running as root (`$EUID != 0`).
- `~/code/personal` writable (or doesn't exist yet — will be created).

**Exit:** 0 on pass, non-zero on any hard fail.

### 10-xcode-clt.sh

**Probe:** `xcode-select -p` returns successfully and points to a real path.

**Behavior:**
- If installed: `skip`.
- If not: trigger `xcode-select --install` (opens GUI dialog).
- Poll every 10 seconds until installed, with a 30-minute timeout.
- Print friendly status while polling: `info: waiting for Xcode CLT install (this opens a system dialog)`.

**Notes:** This is the only step that requires GUI interaction outside the terminal. Document this in the handoff message.

### 20-homebrew.sh

**Probe:** `command -v brew` resolves and `brew --version` succeeds.

**Behavior:**
- If present: `skip`.
- If not: run the official installer non-interactively:
  ```
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```
- After install: write shellenv to `~/.zprofile` if not already there:
  ```
  eval "$(/opt/homebrew/bin/brew shellenv)"
  ```
- Source it for the current shell so subsequent steps see `brew`.

**Notes:** `NONINTERACTIVE=1` skips the "press enter to continue" prompt. The installer still asks for sudo. Document this.

### 30-phase0-brew.sh

**Probe:** `brew bundle check --file=phase0/Brewfile` exits 0.

**Behavior:**
- If probe passes: `skip`.
- Else: `brew bundle install --file=phase0/Brewfile`.
- Re-check after install; fail loudly if probe still fails (means a package didn't install).

**Brewfile contents:**

```ruby
# phase0/Brewfile
# Minimum tools to bootstrap to Claude Code + Claude Desktop.
# Everything else lives in the inventory-driven Brewfile in Phase 1+.

brew "gh"      # GitHub CLI: auth, SSH key upload, repo clone
brew "git"     # Newer than Xcode CLT's bundled git
brew "node"    # Required by Claude Code
brew "jq"      # JSON parsing in shell scripts
cask "claude"  # Claude Desktop app for cowork with Phase 1 agent
```

### 40-github-auth.sh

**Probe:** `gh auth status` exits 0 AND reports SSH protocol AND has at least one SSH key registered.

**Behavior:**
- If probe passes: `skip`.
- Else: run `gh auth login --git-protocol ssh --web`.
  - `gh` will offer to generate an SSH key and upload it. Accept.
  - User must complete browser flow and paste device code.
- Re-check probe; fail if still not authed.

**Notes:** This is the second human-interactive step. Browser opens automatically.

### 50-claude-code.sh

**Probe:** `command -v claude` resolves AND `claude --version` succeeds AND there's a non-empty config at `~/.claude/.credentials.json` (or wherever Claude Code stores subscription auth — verify on first run). AND Claude Desktop app is installed (covered by step 30 via Brewfile cask `claude`) AND its config exists at `~/Library/Application Support/Claude/`.

**Behavior:**
- If `claude` (CLI) not installed: `npm install -g @anthropic-ai/claude-code`.
  - This may need `sudo` depending on npm prefix. Document the issue and recommend setting `npm config set prefix ~/.npm-global` + adding to PATH if it fails.
- If CLI installed but not authed: print instruction to run `claude` once and complete browser login. Pause, wait for user confirmation (`read -p "Press Enter when Claude Code login completes..."`).
- Claude Desktop is already installed by step 30 via Brewfile cask. If its config dir is missing (i.e., never launched), instruct the user to launch it once and sign in: `open -a Claude`. Pause, wait for user confirmation (`read -p "Press Enter when Claude Desktop login completes..."`).
- Verify CLI by running `claude --version`. Verify Desktop by checking the config dir exists.

**Notes:**
- This step now covers both CLI and Desktop. Two browser auth flows on first run — both use the same claude.ai subscription, so it's two clicks not two new logins.
- Cowork between CLI and Desktop is the reason Desktop ships in Phase 0: the Phase 1 agent can hand off to the Desktop app while it finishes setup work.
- Subscription auth (claude.ai Pro/Max) is what we're using here — no API key needed.
- The exact auth verification commands may evolve; the probe should be loose enough to handle minor changes.

### 60-clone-self.sh

**Probe:** `~/code/personal/dotfiles/.git` exists AND `git -C ~/code/personal/dotfiles remote get-url origin` matches the expected URL.

**Behavior:**
- If probe passes: `skip` (optionally pull with `--update` flag — off by default).
- Else: `mkdir -p ~/code/personal && git clone git@github.com:suTerminus/dotfiles.git ~/code/personal/dotfiles`.
- Verify the clone has the expected structure (at minimum `phase0/` directory).
- Write a `.phase0-complete` marker file to `~/.local/state/macbook-setup/` so Phase 1 can verify entry condition.

**Notes:** Uses SSH because `gh auth login` configured SSH in step 40. If SSH clone fails, fall back to https with a warning — likely means SSH key didn't propagate yet.

---

## 6. The Handoff Message

When all Phase 0 steps succeed, `bootstrap.sh` prints:

```
═══════════════════════════════════════════════════════════════
  ✓ Phase 0 complete

  Installed:
    • Xcode Command Line Tools
    • Homebrew
    • gh, git, node, jq
    • Claude Code CLI (authenticated)
    • Claude Desktop app (authenticated; pairs with CLI for cowork)

  Cloned:
    • github.com/suTerminus/dotfiles → ~/code/personal/dotfiles

  Next steps:
    1. cd ~/code/personal/dotfiles
    2. cp phase0/claude-settings-bootstrap.json ~/.claude/settings.json
       (pre-allows brew/gh/common reads so Phase 1 doesn't prompt on every command)
    3. claude
    4. Tell Claude: "Help me build Phase 1 from the PRD"

  Phase 1 will set up:
    • chezmoi (dotfile management)
    • Inventory system (brew.yaml, repos.yaml, mise.yaml)
    • Full Brewfile, language runtimes, repo auto-clone

  Logs: ~/.local/state/macbook-setup/phase0-<timestamp>.log
═══════════════════════════════════════════════════════════════
```

If any step failed, the message instead shows which step, the error, and points to the log file.

---

## 7. Idempotency Contract (Phase 0 specifics)

Same rules as the parent PRD's section 4, restated for clarity:

- Every step probes before acting. If the probe passes, the step prints `skip` and exits 0.
- Every step can be run independently: `phase0/steps/30-phase0-brew.sh` works without orchestrator context (it sources `lib/` itself).
- Re-running `bootstrap.sh` on a fully configured machine should complete in **under 15 seconds** with all steps showing `skip`.
- A failed step does not corrupt prior steps. The orchestrator collects errors and reports at the end.
- `--dry-run` runs all probes and prints what would happen, without executing any modifying commands.

---

## 8. What Phase 0 Does *Not* Do

Worth being explicit, because the temptation will be strong:

- **Does not configure shell.** No `.zshrc`, no aliases, no PS1 changes. That's chezmoi's job in Phase 1.
- **Does not install dotfiles.** The repo is cloned, but nothing is symlinked or rendered. chezmoi does this in Phase 1.
- **Does not handle private repo.** Phase 0 only knows about public dotfiles.
- **Does not install any application beyond the four CLIs.** No editors, no Slack, no anything. Brewfile is intentionally tiny.
- **Does not pull secrets.** No Bitwarden, no AWS, no API keys.
- **Does not configure git identity.** `git config --global user.name/email` happens in Phase 1 via chezmoi templates.
- **Does not ship skills, slash commands, or any Claude Code customization.** Stock Claude Code is enough to drive Phase 1.

**If you find yourself adding to Phase 0, ask: does Claude Code on the new machine actually need this to start working?** If not, defer.

---

## 9. Testing Phase 0

### On the new MacBook

1. Make sure user account exists, signed into iCloud/Apple ID, FileVault enabled if desired.
2. Open Terminal.
3. Paste the curl command.
4. Walk through the four interactive prompts (Xcode CLT, GitHub auth, Claude Code CLI auth, Claude Desktop auth).
5. After completion: `cd ~/code/personal/dotfiles && claude`.
6. Ask Claude Code to verify Phase 0 state by checking the marker file and running the idempotency probes manually.

### On a VM (recommended for iteration)

UTM with a clean macOS Sequoia image. Snapshot before each test run, restore after. This lets you validate Phase 0 over and over without touching the real MacBook until you're confident.

### What to specifically verify

- Re-running `bootstrap.sh` on a complete install takes <15s and shows all `skip`.
- `phase0/steps/30-phase0-brew.sh` works standalone (without orchestrator).
- A simulated failure in step `P0-50` (claude-code) doesn't break step `P0-60` (clone-self) from running on the next attempt.
- `--dry-run` actually doesn't modify anything (check with `brew list`, `gh auth status` before/after).
- The handoff message shows the right paths.
- `claude` launches successfully from `~/code/personal/dotfiles`.

---

## 10. Implementation Order (Phase 0 only)

When you sit down to write Phase 0:

1. **Repo skeleton.** Create the `dotfiles` repo on GitHub (private to start, flip to public later). Push empty structure: `phase0/`, `docs/`.
2. **`lib/log.sh` and `lib/idempotent.sh`.** Logging helpers, generic probe wrappers. Test in isolation.
3. **`bootstrap.sh` orchestrator.** Just step iteration, flag parsing, summary table. Test with empty step files.
4. **`00-preflight.sh`.** Easiest first real step.
5. **`10-xcode-clt.sh`.** Test on a VM that doesn't have CLT installed.
6. **`20-homebrew.sh`.**
7. **`30-phase0-brew.sh` + Brewfile.**
8. **`40-github-auth.sh`.**
9. **`50-claude-code.sh`.** Trickiest — auth flow validation.
10. **`60-clone-self.sh`.**
11. **Handoff message + summary table polish.**
12. **`docs/phases.md` + `docs/phase0.md`.** Document for the next person (or future-you).
13. **Final VM end-to-end test.** Wipe, run from curl, verify all green.

Each numbered item is a checkpoint. Phase 0 is small enough that this can realistically be done in one focused session.

---

## 11. Success Criteria (Phase 0)

- A fresh macOS install reaches "Claude Code CLI + Claude Desktop running from the cloned repo, paired for cowork" in one terminal command and four interactive prompts.
- Re-running `bootstrap.sh` on a configured machine completes in under 15 seconds, all steps `skip`.
- Each step in `phase0/steps/` runs standalone.
- The handoff message gives unambiguous next steps.
- A teammate could fork the public dotfiles repo, change the username, and run their own Phase 0 in under 15 minutes (mostly waiting for Xcode CLT).
- Phase 1 work happens entirely inside Claude Code on the new machine, with no further bash scripting before that handoff.

---

## 12. Open Questions

- Should `60-clone-self.sh` also clone the private dotfiles repo if the user has access? **Recommendation: No.** Defer to Phase 2 to keep Phase 0 single-repo.
- Should Phase 0 install `direnv` or similar to make later steps cleaner? **Recommendation: No.** Four packages, hard line.
- ~~Does Claude Code on first launch need any project-level `.claude/settings.json` for permissions?~~ **RESOLVED.** Phase 0 now ships `phase0/claude-settings-bootstrap.json` and the handoff message instructs the user to copy it to `~/.claude/settings.json` (or the repo's `.claude/settings.local.json`) before starting Phase 1. This pre-allows `bash:brew*`, `bash:gh*`, and common reads so Phase 1 conversations don't permission-prompt on every shell call. The file lives alongside the bootstrap script and is verified against current Claude Code settings schema during M3.T11.
