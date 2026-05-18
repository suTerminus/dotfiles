# Manual Setup

Some configuration cannot be automated and must be performed by the human operator. The bootstrap surfaces missing manual items via `inventory/manual.yaml` and `scripts/doctor.sh`; this doc explains *why* each item is manual and *what* to do.

- **Browser sign-ins (Chrome, Safari, Arc).** iCloud / Google account login required for profile + bookmark sync.
- **Mac App Store sign-in.** Must be done before P1-30 / P1-80 mas entries can install. Open App Store, sign in, re-run.
- **Raycast configuration sync.** Settings live behind a paid sync; manual export/import on first run.
- **1Password / Bitwarden master-password unlock.** No automation by design.
- **Corporate IT installs.** Items flagged in `inventory/manual.yaml` (e.g., Sophos, JetBrains Toolbox); filed via the appropriate IT request channel.
- **SSH key registration with GitHub.** Phase 0 step P0-40 handles this; recovery path is `gh auth login --git-protocol ssh --web` from a fresh shell.
- **Hammerspoon Accessibility permission.** System Settings → Privacy & Security → Accessibility → enable Hammerspoon. Required before the window-to-display watcher in `~/.hammerspoon/init.lua` can move windows. Hammerspoon prompts on first launch; granting and relaunching is enough.

## References

- [Parent PRD §13 — Open questions](../macbook-setup-prd.md)
- [Discovery PRD §9 — Manual install mechanism](../macbook-setup-discovery-prd.md)
- [Phase 3 PRD §7 — Manual installs integration](../macbook-setup-phase3-prd.md)
