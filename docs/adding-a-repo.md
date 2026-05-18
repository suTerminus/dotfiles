# Adding a Repo

To add a git repository to the bootstrap's auto-clone set, append an entry to `inventory/repos.yaml` (public) or to the overlay-specific repos file (`repos-personal.yaml` in the personal overlay, `repos-<work>.yaml` in the work overlay). The bootstrap clones each entry to `$HOME/<path>` over SSH, gated by tags so personal repos don't land on work machines and vice versa.

## Walkthrough

1. Edit `inventory/repos.yaml` (or the overlay file) and add `{ name, url, path, tags }`.
2. Re-run `scripts/setup.sh --only P1-50` (public clone step) — idempotent: existing clones with the right origin are skipped.
3. Verify with `scripts/doctor.sh` — the new repo shows `[ok]` under P1 (or P2 for overlay-clones).

Moving an existing repo between overlays is a source-of-truth edit: change the inventory file the entry lives in; the on-disk clone path doesn't change.

## References

- [Inventory schema](../inventory/README.md)
- [Phase 1 PRD §6 — Inventory schema](../macbook-setup-phase1-prd.md)
- [Phase 2 PRD §6 — Overlay inventory](../macbook-setup-phase2-prd.md)
