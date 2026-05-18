# Discovery Tooling

## Purpose

This directory is a read-only sensor array that catalogs the current
machine's state before migrating to the new three-repo dotfiles
architecture. The scripts observe and record; they never install,
remove, or transform anything on the host. Their job is to produce
artefacts that downstream migration work can consume with confidence.

## Layout

```
tools/
  discovery/
    README.md
    lib/
      log.sh
    output/
      .gitkeep
    scripts/
    templates/
```

## Running everything

```
bash tools/discovery/run-all.sh
```

Supported flags:

- `--branch NAME` is forwarded to `30-dotfiles-audit.sh` to pin the
  branch under audit.
- `--vault-path PATH` is forwarded to `40-vault-audit.sh` to point at
  a non-default vault location.

## Running a single script

Each script under `scripts/` is standalone-runnable. Invoke any of
them directly with `bash tools/discovery/scripts/<name>.sh` and it
will source `lib/log.sh` and write its artefact under `output/`.

## Outputs

The full run produces nine artefacts in `output/`:

- `installed-brew.yaml`
- `installed-apps.yaml`
- `dotfiles-audit.md`
- `vault-audit.md`
- `mise-asdf.yaml`
- `shells-and-paths.md`
- `misc.md`
- `manual-installs.yaml` (seeded from template on first run)
- `decisions.md` (seeded from template on first run)

## Idempotency

Re-running any script, including `run-all.sh`, is safe. Templates are
seeded into `output/` only when the destination file does not yet
exist; subsequent runs leave seeded files alone so hand edits are
preserved.

## Privacy

The `output/` directory is gitignored. Vault audit content in
particular stays local. Do not commit anything from `output/` without
a manual review of the file first.

## Deviation from PRD section 4

The PRD section 4 layout does not list `lib/` as a sibling of
`scripts/`. The deviation is intentional and tracked under plan task
M1.T02: shared logging helpers live in `tools/discovery/lib/log.sh`
so every script in `scripts/` can source them with a stable relative
path.
