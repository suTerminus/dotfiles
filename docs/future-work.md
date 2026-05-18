# Future Work

This document collects items deferred past v1: parent PRD §13 carry-overs, Q-PARENT-1 and friends, and follow-ups discovered during execution. Each item gets a one-line description and a pointer to the PRD section that originated it. Promote an item to a real plan by opening an issue or a new PRD section.

## TODO

- [ ] **Q-PARENT-1**: cross-machine synchronisation strategy beyond the three-repo overlay (deferred — parent PRD §13).
- [ ] Future `system-tweaks.yaml` kinds: `defaults-system`, `launchd-load`, `system-cmd` (Phase 3 PRD §6 future-tweaks table).
- [ ] VM-based regression target: snapshot lineage `clean-sequoia -> phase0-complete -> phase1-complete -> phase2-complete` (Phase 2 PRD §11).
- [ ] CI runner that executes `scripts/doctor.sh` post-merge against a long-lived test machine.
- [ ] Rotation policy for SSH keys, GPG keys, and Bitwarden master password.
- [ ] Onboarding script that prints a punch-list of manual steps before the first `phase0/bootstrap.sh` run.
- [ ] Migration plan: when the public dotfiles ship personal/work overlay skeletons, archive the legacy `vault` repo (per `inventory/repos.yaml` note).

## References

- [Parent PRD §13 — Open questions](../macbook-setup-prd.md)
- [Phase 3 PRD §14 — Open questions](../macbook-setup-phase3-prd.md)
- [Discovery PRD](../macbook-setup-discovery-prd.md)
