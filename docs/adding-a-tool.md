# Adding a Tool

To add a new CLI tool, GUI cask, or Mac App Store app to the bootstrap, edit one inventory file and re-run the relevant Phase 1 steps. The bootstrap is declarative: every tool is an entry in `inventory/brew.yaml` (Homebrew formulae/casks), `inventory/mas.yaml` (App Store), or `inventory/mise.yaml` (language runtimes). Tags on the entry control which machines pick it up.

## Walkthrough

1. Edit `inventory/brew.yaml` (or `mas.yaml` / `mise.yaml`) and add the entry with appropriate `tags:`.
2. Re-render and apply: `scripts/setup.sh --only P1-20,P1-30`.
3. Verify with `scripts/doctor.sh` — the new tool shows `[ok]` under P1.

Tag composition rules: `[]` installs everywhere; `[work]` / `[personal]` filter by machine type; `[optional, BUCKET]` is opt-in via `--include-tag BUCKET`. See `inventory/README.md` for the full table.

## References

- [Inventory schema](../inventory/README.md)
- [Phase 1 PRD §6 — Inventory schema](../macbook-setup-phase1-prd.md)
- [Phase 1 PRD §7 — Brewfile pipeline](../macbook-setup-phase1-prd.md)
