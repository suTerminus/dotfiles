# Phase Model

The bootstrap is four phases plus a Discovery pre-phase. The split exists
because the first thing a fresh MacBook needs is a working shell, Homebrew, and
the Claude Code CLI — and you cannot bootstrap those from inside a Claude Code
session that does not yet exist. Phase 0 is plain bash-over-curl; from Phase 1
onward Claude Code drives. Every phase is idempotent: re-running on a
configured machine is a fast no-op with all steps reporting `[skip]`.

## Discovery (pre-phase)

Runs on the OLD machine. Walks the existing setup — installed brews and casks,
mise tool versions, dotfiles, shell config — and emits `inventory/*.yaml`
files committed to this repo. Phase 1 reads those inventories.

## Phase 0

- Driver: bash (`curl ... | bash` of `phase0/bootstrap.sh`).
- Entry: factory-fresh macOS, signed in to iCloud, network up.
- Exit: Xcode CLT, Homebrew, the Phase 0 Brewfile (gh, git, node, jq, claude
  cask), `gh` authenticated, Claude Code CLI installed + authenticated, this
  repo cloned to `~/code/personal/dotfiles`.

## Phase 1

- Driver: Claude Code, working from the cloned repo.
- Entry: Phase 0 exit state.
- Exit: chezmoi initialised and applied, public Brewfile rendered + bundled,
  `mise` toolchains installed, public repos cloned, VSCode extensions / krew /
  MAS / helm plugins driven from inventory.

## Phase 2

- Driver: Claude Code.
- Entry: Phase 1 exit state.
- Exit: personal overlay (and, on a work machine, work overlay) applied;
  Bitwarden-templated secrets rendered; AWS profiles configured; personal
  Claude plugin installed and (work machines) work-org marketplace registered.

## Phase 3

- Driver: Claude Code.
- Entry: Phase 2 exit state.
- Exit: macOS defaults applied, Touch ID for sudo enabled, system tweaks
  applied, post-install hooks run, `scripts/doctor.sh` green.

## Re-running phases

Every step in every phase probes for "is this already done?" before acting. On
a fully configured machine a re-run prints `[SKIP]` for every step and exits in
seconds. This means you can safely re-run a phase to recover from a
mid-execution failure, and you can re-run later to pick up new inventory items
without fear of clobbering existing state. See `docs/phase0.md` for the
Phase 0-specific re-run notes.
