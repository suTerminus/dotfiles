# Phase 0

Phase 0 is the bash bootstrap that runs before any Claude Code session exists
on the machine. You curl `phase0/bootstrap.sh` from GitHub, pipe it to bash,
and it brings the machine from factory-fresh to "ready to start a Claude Code
session from inside the cloned dotfiles repo." Everything in Phase 0 is plain
POSIX-ish bash so it works on a stock macOS install with nothing but the
preinstalled `/bin/bash` and `curl`.

## What Phase 0 installs

- Xcode Command Line Tools (provides `git`, `cc`, headers; required by
  Homebrew).
- Homebrew itself (the package manager).
- Five Brewfile entries:
  - `gh` -- GitHub CLI, used for auth and HTTPS/SSH key registration.
  - `git` -- a current git from Homebrew, shadowing the Apple-shipped one.
  - `node` -- needed to `npm install -g @anthropic-ai/claude-code`.
  - `jq` -- JSON query tool used by later steps and by Claude Code itself.
  - `claude` (cask) -- the Claude Desktop application.
- The Claude Code CLI, installed globally via `npm install -g`.
- This dotfiles repo, cloned to `~/code/personal/dotfiles` (SSH if `gh` set up
  keys, HTTPS otherwise).

## Interactive prompts

Phase 0 will pause and wait for the user four times:

1. The macOS Xcode Command Line Tools install dialog (a system modal -- click
   Install, agree to the licence, wait for the download).
2. `gh auth login` opens a browser tab to authorise the GitHub CLI.
3. `claude` (the CLI) opens a browser tab on first run to authorise Claude
   Code.
4. Claude Desktop launches once after the cask install so the user can sign in
   to the desktop app.

Outside those four points Phase 0 runs unattended.

## Step-by-step

Steps live in `phase0/steps/` and are executed in order by `bootstrap.sh`.

- `00-preflight.sh` -- checks macOS version, architecture, network, and disk
  space; aborts early if any are wrong.
- `10-xcode-clt.sh` -- triggers the CLT install if `xcode-select -p` shows
  nothing; waits for the dialog to complete.
- `20-homebrew.sh` -- installs Homebrew via the official install script if
  `brew` is not on PATH; configures the shell environment for the current
  session.
- `30-phase0-brew.sh` -- runs `brew bundle --file phase0/Brewfile` to install
  the five Phase 0 brews/casks.
- `40-github-auth.sh` -- runs `gh auth status` and, if not authenticated,
  `gh auth login` with SSH key upload.
- `50-claude-code.sh` -- `npm install -g @anthropic-ai/claude-code` and a
  first-run prompt to authenticate the CLI.
- `60-clone-self.sh` -- clones this repo to `~/code/personal/dotfiles` (SSH first,
  HTTPS fallback) so Phase 1 has somewhere to run from.

Each step starts by asking "is the thing I am about to do already done?" -- if
yes, it prints `[SKIP]` and returns immediately. That is the idempotency probe.

## Re-running

Re-running `bootstrap.sh` on a finished Phase 0 machine completes in under 15
seconds with every step reporting `[SKIP]`. Pass `--dry-run` to see what each
step would do without making changes.

## Common failures and fixes

- npm prefix permission error during `50-claude-code.sh`: the global `npm`
  prefix points somewhere root-owned. Fix with
  `npm config set prefix ~/.npm-global` and add `~/.npm-global/bin` to PATH,
  then re-run the step.
- Xcode CLT install dialog never appears: there is usually a partial install
  in the way. Run `xcode-select --install` manually, accept the dialog, then
  re-run `bootstrap.sh`.
- `gh auth login` complains about needing sudo to upload an SSH key: follow
  `gh`'s prompt -- it knows what to do and will request only what it needs.
- SSH clone in `60-clone-self.sh` fails: the script falls back to HTTPS
  automatically. Once your SSH key is happy you can switch later with
  `git remote set-url origin git@github.com:<user>/dotfiles.git`.
- Claude Desktop did not appear in `/Applications`: `30-phase0-brew.sh`
  probably failed mid-cask. Re-run just that step:
  `bash phase0/steps/30-phase0-brew.sh`.

## Logs

Every Phase 0 run writes a timestamped log to
`~/.local/state/macbook-setup/phase0-<timestamp>.log`. Attach this when filing
issues or asking for help.

## Beyond Phase 0

Phase 0 stops once the repo is cloned and Claude Code is authenticated. From
there, see `docs/phases.md` for the full four-phase model and the handoff
message printed at the end of `bootstrap.sh` for the exact next-steps command
to start Phase 1.
