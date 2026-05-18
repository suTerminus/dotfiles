# Inventory

This directory holds the declarative source of truth for what a fully
configured machine should have installed. The bootstrap (Phase 1+) reads
these files and applies them.

## Schema

Each file is YAML, lists items, every item has a `tags:` array. The
bootstrap honours tags as follows:

| Tag           | Meaning |
|---------------|---------|
| `[]` (empty)  | Install always, on every machine. |
| `[personal]`  | User's personal scope. Always installed (regardless of machine type). |
| `[work]`      | Work-machine overlay. Only installed when `data.machine == "work"`. |
| `[optional, BUCKET]` | Declared but skipped by default. Install with `--include-tag BUCKET`. |
| `[manual]`    | Tracked, never auto-installed. Bootstrap warns if missing. Often paired with `[work]` or `[personal]`. |

Tags compose. `[optional, java, work]` = optional bucket "java", only
on work machines (`--include-tag java` AND `data.machine == "work"`).

Layering: **public** (`[]`) is always applied; **personal**
(`[personal]`) is always applied — the user's identity scope, not a
per-machine toggle; **work** (`[work]`) layers on top when on a work
machine.

## Files

- `brew.yaml` — Homebrew taps, formulae, casks
- `manual.yaml` — manual installs (corporate IT, license-bound, etc.)
- `mas.yaml` — Mac App Store apps
- `mise.yaml` — language runtimes (Go, Node, Python, Java, Rust)
- `vscode-extensions.yaml` — VSCode extensions
- `krew.yaml` — kubectl plugins (work-tagged)
- `helm-plugins.yaml` — helm plugins
- `macos-defaults.yaml` — Phase 3 `defaults write` entries
- `system-tweaks.yaml` — Phase 3 PAM / pmset / login-item tweaks
- `repos.yaml` — git repositories to clone

## Three-repo partition

The split is live: `[personal]` items belong in the personal overlay's
`inventory/*-personal.yaml` files; `[work]` items belong in the work
overlay's `inventory/*-<work>.yaml` files. Everything in this directory
is public (`[]` or `[optional, *]`).
