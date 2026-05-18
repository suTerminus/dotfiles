# Troubleshooting

When `scripts/doctor.sh` reports drift or a `setup.sh` step fails, "re-run the step" is almost always the right first move — every step is idempotent. The table below covers the cases where it isn't.

| Symptom | Step | Fix |
|---|---|---|
| `chezmoi diff` non-empty after apply | P1-10 | Local edit drifted from source. `chezmoi re-add <file>` to capture, or `chezmoi apply` to revert. |
| `brew bundle check` reports drift | P1-30 | `brew bundle install --file=<path>` to remediate. |
| `bw` session expired mid-run | P2-00 | Re-unlock with `bw unlock`; re-export `BW_SESSION`. |
| MAS app fails to install | P1-30 / P1-80 | Open App Store, sign in, re-run `--only P1-30,P1-80`. |
| Private overlay clone fails on first run | P2-10 / P2-12 | Verify SSH key uploaded to GitHub (`gh auth status`); re-run. |
| Touch ID sudo not active | P3-10 | Open a fresh terminal session (the line is appended; PAM re-reads on new sessions only). |
| Phase 0 marker absent on re-run | P0 | Re-run `phase0/bootstrap.sh`; safe and idempotent. |

## References

- [Phase 1 PRD §8 — Idempotency contract](../macbook-setup-phase1-prd.md)
- [Phase 2 PRD §11 — Iteration & testing](../macbook-setup-phase2-prd.md)
- [Phase 3 PRD §8 — The Doctor Script](../macbook-setup-phase3-prd.md)
