# dotfiles

Public dotfiles for a macOS setup. The repository is organized as a
phased bootstrap: a tiny `curl | bash` entry point gets a fresh MacBook to
the point where Claude Code can take over and drive the rest. Private
overlays (personal + work) layer on top via chezmoi.

## Quick start

On a fresh macOS machine:

```
curl -fsSL https://raw.githubusercontent.com/suTerminus/dotfiles/main/phase0/bootstrap.sh | bash
```

The bootstrap script is idempotent and safe to re-run.

## Phase model

- Phase 0 -- `curl | bash` to Claude Code + Claude Desktop. Pure shell, no
  Claude required. Owns Xcode CLT, Homebrew, gh/git/node/jq, Claude Code,
  Claude Desktop.
- Phase 1 -- Claude Code drives chezmoi, mise, the inventory-driven
  Brewfile, and clones the rest of the repos.
- Phase 2 -- Private overlay, secrets (1Password / op), AWS profiles.
- Phase 3 -- macOS defaults, Touch ID for sudo, doctor / verification.

See `docs/phases.md` and the per-phase PRDs for detail.

## Repository layout

```
README.md
phase0/
  Brewfile          # minimum brew/cask set
  bootstrap.sh      # curl | bash entry point
  lib/
    log.sh          # info/ok/skip/warn/error -> stderr
    idempotent.sh   # probe_then_act, is_dry_run, require_command
  steps/            # numbered phase 0 step scripts
docs/               # phase docs and runbooks
inventory/          # data files driving Phase 1+
tools/              # repo-local helper scripts
```

Per-phase specifications:

- `macbook-setup-prd.md` -- top-level plan
- `macbook-setup-phase0-prd.md` -- this phase
- `macbook-setup-phase1-prd.md`
- `macbook-setup-phase2-prd.md`
- `macbook-setup-phase3-prd.md`

## License

License: MIT. The `LICENSE` file lands in a follow-up commit.
