# PRD Addendum: Phase 3 — Polish, macOS Defaults, Doctor, Real-Machine Validation

**Owner:** Berkay
**Status:** Draft v1
**Parent doc:** `macbook-setup-prd.md`
**Sibling docs:** `macbook-setup-discovery-prd.md`, `macbook-setup-phase0-prd.md`, `macbook-setup-phase1-prd.md`, `macbook-setup-phase2-prd.md`
**Goal:** Apply macOS defaults, enable Touch ID for sudo, surface manual-install warnings, run post-install hooks, ship the doctor script, and end-to-end-validate on real hardware. Last phase of v1.

---

## 1. Phase Boundary

Phase 3 is the closing phase of the v1 setup. It does no net-new tool installation; it polishes the system into the state described by parent §12 and proves that state on real hardware.

### Entry condition

- Phase 1 doctor green for its scope: chezmoi public applied, `brew bundle check` clean against the rendered Brewfile, `mise current` matches `inventory/mise.yaml`, every entry in `inventory/repos.yaml` has been cloned (or correctly tag-skipped), `gh auth status` reports SSH plus an uploaded key, `~/.local/state/macbook-setup/.phase0-complete` marker present.
- Phase 2 doctor green for its scope: private overlay applied, Bitwarden CLI installed and `bw status` reachable, work-tagged Brewfile entries installed on a `machine = "work"` profile, AWS profiles rendered, the work-org marketplace registered as a Claude Code marketplace, the personal Claude plugin installed and at least one of its skills resolvable via Claude Code.
- The `wip` branch still exists. The `v1-archive` tag does **not** yet exist.
- The PRD set (`macbook-setup-prd.md`, `macbook-setup-discovery-prd.md`, `macbook-setup-phase0-prd.md`, `macbook-setup-phase1-prd.md`, `macbook-setup-phase2-prd.md`) is committed to `main`.

### Exit condition

- macOS defaults from `inventory/macos-defaults.yaml` are applied; running `P3-00` again is a no-op and any `killall` targets that fired during the first apply are stable across a logout/reboot.
- Touch ID for sudo is enabled via `/etc/pam.d/sudo_local`; a fresh terminal session honors it on the next `sudo` call.
- The manual-installs check (`P3-20`) reports against `inventory/manual.yaml` with no false positives on the wiped MacBook.
- All post-install hooks (`P3-30`) are idempotent: `gh` extensions installed, Raycast post-install commands run once, Claude Code first-run smoke check passes.
- `scripts/doctor.sh` exists, exercises every probe across Phases 0–3, and exits 0 on the configured machine.
- All parent §12 success criteria are demonstrated with evidence (timing capture, doctor output, log paths) on a wiped MacBook.
- Documentation under `docs/` is complete: `architecture.md`, `adding-a-tool.md`, `adding-a-repo.md`, `troubleshooting.md`, `manual-setup.md`, `v1-signoff.md`, `future-work.md`.
- `wip` is tagged `v1-archive` and the branch is deleted. v1 is signed off.

### macOS baseline

Phase 3 targets macOS Sequoia (`≥15`), aligned with Phase 0's preflight gate. The canonical Touch ID location (`/etc/pam.d/sudo_local`) is present by default on Sequoia. Phase 3 defaults assume Sequoia keys (Dock, Window Manager, etc.) — the doctor reports `[missing]` rather than failing hard if a key is unrecognised by the running macOS.

---

## 2. Phase 3 Scope

### In scope

- `P3-00` macOS defaults application driven by `inventory/macos-defaults.yaml` with the extended schema described in §5.
- `P3-10` system tweaks driven by `inventory/system-tweaks.yaml`. The v1 entry is Touch ID for sudo; the file is structured so future tweaks add cleanly.
- `P3-20` manual-installs check driven by `inventory/manual.yaml`. Schema is owned by `macbook-setup-discovery-prd.md` §9 and is not duplicated here.
- `P3-30` post-install hooks: `gh extension install` set, Raycast post-install commands (the chezmoi-managed config files for those apps were authored in Phase 2 — Phase 3 only invokes the post-install commands), Claude Code first-run smoke check.
- `P3-40` doctor script (`scripts/doctor.sh`). Aggregates probes from every phase, reads every inventory file, prints a tabular report, exits non-zero on any drift or missing item.
- Final documentation pass: `docs/architecture.md`, `docs/adding-a-tool.md`, `docs/adding-a-repo.md`, `docs/troubleshooting.md`, `docs/manual-setup.md`, `docs/v1-signoff.md`, `docs/future-work.md`.
- Real-MacBook end-to-end validation against parent §12.

### Out of scope

- Net-new tooling not already in earlier phases. If something missing surfaces during validation it goes to Phase 1 or Phase 2's inventory, not into Phase 3.
- New chezmoi-managed configs. Raycast config templates were authored in Phase 2 (private overlay). Phase 3 only triggers post-install commands.
- Discovery-style audit work. Discovery is a closed pre-phase; any drift between Discovery output and the new machine is a Phase 1/2 inventory bug.
- Force-pushes, history rewrites, or `main` branch surgery. The `wip` branch gets a tag and a delete; nothing else is touched.

### Step IDs

| ID | Step |
|---|---|
| P3-00 | macos-defaults |
| P3-10 | system-tweaks |
| P3-20 | manual-installs-check |
| P3-30 | post-install |
| P3-40 | doctor |

`P3-40` is invoked separately from the orchestrator and aliased as `scripts/setup.sh --doctor`.

---

## 3. Repository Layout (Phase 3 contributions)

Phase 3 adds the following to the public dotfiles repo. Nothing under `phase0/`, `home/`, or `inventory/` from earlier phases is modified.

```
dotfiles/
├── inventory/
│   ├── macos-defaults.yaml             # extended schema (see §5)
│   ├── system-tweaks.yaml              # new file (see §6)
│   └── manual.yaml                     # schema owned by Discovery PRD §9
├── scripts/
│   ├── steps/
│   │   ├── P3-00-macos-defaults.sh
│   │   ├── P3-10-system-tweaks.sh
│   │   ├── P3-20-manual-installs-check.sh
│   │   └── P3-30-post-install.sh
│   ├── lib/
│   │   └── macos.sh                    # helpers for `defaults read`/`write`
│   │                                   # and `killall` queueing
│   └── doctor.sh                       # P3-40
└── docs/
    ├── architecture.md                 # final, kept-current copy of system map
    ├── adding-a-tool.md                # one-file edit walkthrough
    ├── adding-a-repo.md                # one-file edit walkthrough
    ├── troubleshooting.md              # symptom → step → fix table
    ├── manual-setup.md                 # what cannot be automated
    ├── v1-signoff.md                   # success-criteria evidence (§13)
    └── future-work.md                  # Q-PARENT-1 deferral, parent §13 carry-overs
```

The `manual.yaml` file lives in `inventory/` (a Phase 1 directory) but its schema is defined by Discovery PRD §9 and the consuming step is `P3-20`. Phase 3 owns the consumer; Discovery owns the schema.

---

## 4. Step Specifications

Each step is a standalone script under `scripts/steps/`. Each declares its idempotency probe at the top as a comment. Each can be invoked directly without orchestrator context.

### P3-00 macos-defaults

**Probe:** For each entry in `inventory/macos-defaults.yaml`, run `defaults read <domain> <key>` and compare the result to `value` after type coercion. The step is "no-op" iff every entry's current value matches.

**Behavior:**
1. Parse `inventory/macos-defaults.yaml` with `yq`.
2. For each entry, probe the current value.
3. If current == expected: log `skip: <domain> <key>`.
4. If current != expected (or unset): `defaults write <domain> <key> -<type> <value>`. Log `info: <domain> <key> set`.
5. Collect the set of `killall:` targets across entries that were actually written. Deduplicate.
6. After all writes complete, run `killall <Target>` once per unique target. Log `info: killall <Target>`.
7. Exit 0 if all writes succeeded.

**Notes:**
- `killall` runs only for targets whose entries actually changed. A re-run with no drift performs zero `killall` invocations.
- Supported types per the extended schema: `bool`, `int`, `string`, `array`, `dict`. The helper `scripts/lib/macos.sh` encapsulates the read/compare/write triplet for each type.
- For `array` and `dict` values the comparison is structural (parse `defaults read` output as plist, compare against the YAML-declared value). String comparison would be too brittle.
- If `value: []` (empty array) or `value: {}` (empty dict), the step still writes — empty containers are a meaningful state (e.g., clearing the Dock).

### P3-10 system-tweaks

**Probe:** For each entry in `inventory/system-tweaks.yaml` of `kind: pam-line`, the probe is: `grep -F "<line>" <file>` exits 0. The v1 entry is the Touch ID line in `/etc/pam.d/sudo_local`.

**Behavior:**
1. Parse `inventory/system-tweaks.yaml`.
2. For each tweak: probe.
3. If probe passes: log `skip: <name>`.
4. If probe fails and `sudo: true`: warn the user that a sudo password prompt is about to appear, then run a sudo-elevated append of the missing line. The append is idempotent because the probe gates it.
5. Re-probe after writing. Fail loudly if still missing.

**Notes:**
- `/etc/pam.d/sudo_local` exists by default on macOS Sonoma and later as an empty include hook; Phase 3 appends to it rather than replacing it. If the file does not exist, create it with mode `0644` and root-owned (matching system convention).
- The schema currently supports `kind: pam-line`. Future kinds (e.g., `kind: launchd-load`, `kind: defaults-system`) land here as needed; Phase 3 v1 only specifies the one kind.
- Touch ID takes effect on the **next** terminal session. Document this in `docs/troubleshooting.md`.
- Re-running the step after enabling Touch ID does not re-prompt for sudo (the line is present, the probe passes, the step skips).

### P3-20 manual-installs-check

**Probe:** Per-item detection block. Kinds defined in Discovery PRD §9 are: `app` (checks `/Applications` and `~/Applications` for a matching `bundle_id`), `command` (checks `command -v <command>`), `file` (checks path existence), `launchd` (checks `launchctl list | grep <label>`).

**Behavior:**
1. Parse `inventory/manual.yaml`.
2. For each item, evaluate its `detection` block.
3. If detected: log `ok: <name>`.
4. If missing: log `warn: <name> — missing` plus the item's `reason` and `docs_url`.
5. Always exit 0. This step is informational; it never blocks the run and never installs anything.

**Notes:**
- The `inventory/manual.yaml` schema is defined and maintained in `macbook-setup-discovery-prd.md` §9. **Do not redefine it in this PRD.** Any schema change happens in the Discovery PRD; Phase 3 follows.
- The literal output format is reproduced verbatim from Discovery PRD §9 in §7 below for reader convenience.
- Filing IT tickets, requesting installs, or contacting users are explicitly outside the bootstrap's responsibility. The step surfaces, the human acts.

### P3-30 post-install

**Probe:** Each hook has its own probe; the step composes them.

**Hooks (v1):**

| Hook | Probe | Action |
|---|---|---|
| gh extensions | `gh extension list` contains every required extension name | `gh extension install <repo>` for each missing |
| Raycast post-install | Raycast settings file timestamp matches the chezmoi-managed source (or a marker file in `~/.local/state/macbook-setup/`) | `defaults import com.raycast.macos <path-to-rendered-plist>` if a plist is provided; otherwise no-op |
| Claude Code smoke check | `claude --version` returns a version string and `claude` can execute a trivial non-interactive command | log only; no remediation here (auth was Phase 0, plugin install was Phase 2) |

**Behavior:**
1. For each hook: probe; if pass, `skip`; if fail, run the action; re-probe.
2. Each hook's outcome is independent — a failure in one hook does not skip the others.
3. Step exits non-zero only if a hook's action ran and its re-probe still fails.

**Notes:**
- Raycast config files are authored in Phase 2 inside the private overlay (per parent §10 Q-6 and Phase 2 scope). Phase 3 has no opinion on the contents — it only ensures the post-install command runs once.
- The Claude Code smoke check is deliberately shallow: a deeper check (plugins resolvable, marketplace registered) is Phase 2's job and is reflected in the Phase 2 doctor probes that `P3-40` re-runs.
- `gh extension install` is network-dependent. On flaky network the step fails the affected hook only; re-running succeeds when the network returns.

### P3-40 doctor

`P3-40` is not invoked from the orchestrator's main flow. It is a standalone command, aliased as `scripts/setup.sh --doctor`.

**Probe:** N/A. The doctor *is* a collection of probes.

**Behavior:**
1. Read every inventory file the doctor knows about: Phase 1 public (`inventory/brew.yaml`, `repos.yaml`, `mise.yaml`), Phase 2 personal overlay (`brew-personal.yaml`, `repos-personal.yaml`), Phase 2 work overlay (`brew-<work>.yaml`, `repos-<work>.yaml`; only on `machine == "work"`), Phase 3 (`inventory/macos-defaults.yaml`, `system-tweaks.yaml`, `manual.yaml`).
2. Run every idempotency probe across phases. Concretely:
   - Phase 0: `~/.local/state/macbook-setup/.phase0-complete` marker present, `gh auth status` clean.
   - Phase 1: `chezmoi diff` empty, `brew bundle check` clean, per-tool `mise current` matches, per-repo dir + remote check.
   - Phase 2: private overlay applied, `bw status` reachable, work/personal Brewfile checks, plugin presence in Claude Code.
   - Phase 3: per-default value match, `/etc/pam.d/sudo_local` contains the Touch ID line, per-manual-install detection block, post-install hook probes.
3. Print a table with three columns: status (`[ok]` / `[drift]` / `[missing]`), phase, item.
4. Print a footer with issue count and a suggested remediation invocation (`scripts/setup.sh --only <step-list>`).
5. Exit non-zero if any row is `[drift]` or `[missing]`. Exit 0 otherwise.

**Notes:**
- The doctor is read-only. It never writes, never installs, never elevates with sudo. The Touch ID probe reads `/etc/pam.d/sudo_local` (world-readable) without sudo.
- Target runtime: under 5 seconds on a fully configured machine. The slowest probe is `chezmoi diff` (full source vs target diff); everything else is fast.
- The doctor has no `--fix` mode in v1. Remediation is "read the report, run the suggested `--only`."

---

## 5. macOS Defaults Inventory Schema

Phase 1 sketched `inventory/macos-defaults.yaml` with `domain`, `key`, `type`, `value`. Phase 3 extends the schema with a `killall` field per entry.

### Schema

```yaml
- domain: <string>          # e.g., NSGlobalDomain, com.apple.dock
  key: <string>             # e.g., AppleShowAllExtensions, autohide
  type: bool|int|string|array|dict
  value: <typed value>
  killall: <App>            # optional; e.g., Dock, Finder, SystemUIServer
```

### Examples

```yaml
- domain: NSGlobalDomain
  key: AppleShowAllExtensions
  type: bool
  value: true
  killall: Finder

- domain: com.apple.dock
  key: autohide
  type: bool
  value: true
  killall: Dock

- domain: com.apple.dock
  key: tilesize
  type: int
  value: 48
  killall: Dock

- domain: com.apple.dock
  key: persistent-apps
  type: array
  value: []
  killall: Dock

- domain: com.apple.menuextra.clock
  key: DateFormat
  type: string
  value: "EEE d MMM HH:mm"
  killall: SystemUIServer

- domain: com.apple.finder
  key: FXPreferredViewStyle
  type: string
  value: "Nlsv"
  killall: Finder
```

### Per-key probe

| Type | Probe | Comparison |
|---|---|---|
| bool | `defaults read <domain> <key>` returns `0` or `1` | normalize to `true`/`false`, string compare |
| int | `defaults read <domain> <key>` returns numeric string | numeric compare |
| string | `defaults read <domain> <key>` returns string | exact compare (whitespace preserved) |
| array | `defaults read <domain> <key>` returns plist array | parse, structural compare |
| dict | `defaults read <domain> <key>` returns plist dict | parse, structural compare |

If `defaults read` fails (key unset), the entry counts as drift — the doctor reports `[missing]` and `P3-00` will write.

### Killall queueing

`P3-00` runs in two passes:

1. **Pass 1 (compute):** For each entry, probe; if drift, mark for write and add `killall` target (if any) to a set.
2. **Pass 2 (act):** Run all `defaults write` calls. Then iterate the deduplicated `killall` set and `killall <Target>` once each.

Two consequences:
- A single `defaults write` to `com.apple.dock` for `autohide` plus another for `tilesize` produces exactly one `killall Dock`.
- A re-run with no drift produces zero `killall` invocations — re-runs are quiet.

Targets typically used: `Dock`, `Finder`, `SystemUIServer`, `cfprefsd` (rare; mention as available but discourage).

---

## 6. System Tweaks Inventory Schema

A new inventory file `inventory/system-tweaks.yaml` holds system-level (sudo-required) tweaks that don't fit the user-defaults shape and don't deserve standalone scripts.

### Schema

```yaml
tweaks:
  - name: <string>          # stable identifier; used by doctor output
    kind: pam-line          # v1 supports only pam-line
    file: <absolute path>
    line: <string>
    sudo: <bool>            # true when the file requires sudo to edit
    reason: <string>        # human-readable why
```

### v1 contents

```yaml
tweaks:
  - name: touch-id-sudo
    kind: pam-line
    file: /etc/pam.d/sudo_local
    line: "auth sufficient pam_tid.so"
    sudo: true
    reason: Reduces sudo friction across re-runs and ongoing brew operations.
```

### Future tweaks

Anticipated but not in v1:

| Name | Kind (proposed) | Why |
|---|---|---|
| key-repeat-system | defaults-system | `defaults write -g KeyRepeat` requires sudo on some keys |
| input-source-pin | launchd-load | Pin Swiss German vs US layout |
| firewall-on | system-cmd | `defaults write` on the firewall plist plus `launchctl kickstart` |

When added, the schema gains new `kind:` discriminators with their own probe/action logic in `P3-10`. v1 only ships `pam-line`.

### Idempotency

The probe for `kind: pam-line` is `grep -F "<line>" "<file>"`. The action is `printf '%s\n' "<line>" | sudo tee -a "<file>" > /dev/null`. The probe gates the action, so re-runs are no-ops and never re-prompt for sudo.

---

## 7. Manual Installs Integration

Phase 3 owns the *consumer* of the manual installs inventory. The schema is owned upstream.

### Schema reference

The canonical schema for `inventory/manual.yaml`, including the `detection` block and its supported `kind:` values, lives in `macbook-setup-discovery-prd.md` §9 — "The Manual Install Mechanism". **Do not duplicate the schema here.** When the schema changes, the Discovery PRD is the single source of truth.

### What `P3-20` does with it

`P3-20` reads `inventory/manual.yaml`, evaluates each entry's `detection` block, and prints one line per item with `ok` (detected) or `warn` (missing). Missing items also print `reason` and `docs_url` so the user knows what to do without re-reading the inventory.

### Output (reproduced from Discovery PRD §9 verbatim, for reader convenience)

```
Manual installs check:
  ✓ 1Password 7 (mas)
  ⚠ Sophos Endpoint — missing
       reason: Corporate IT-managed; install via work IT request
       docs:   <internal Confluence link>
  ⚠ <other> — missing
```

### Exit semantics

`P3-20` always exits 0. Manual installs are out of the bootstrap's control by definition; they are not allowed to fail the run. The doctor (`P3-40`) reports them as `[missing]` and *does* exit non-zero when any are missing — this is the formal mechanism that surfaces them in CI-style runs.

### Detection-block kinds

Per Discovery PRD §9: `app`, `command`, `file`, `launchd`. Phase 3 implements the probe logic for each kind in `scripts/lib/macos.sh` (the `app` and `launchd` probes are macOS-specific; `command` and `file` are POSIX). If a future detection kind is added in the Discovery PRD, the implementation lives in `scripts/lib/macos.sh` and is invoked by `P3-20`.

---

## 8. The Doctor Script

`scripts/doctor.sh` is the single source of truth for "is this machine in the state the inventory says it should be in." It exists to make drift visible. It does not fix drift.

### Inputs

Every inventory file in `inventory/` plus per-phase markers:

| Source | Probes |
|---|---|
| `~/.local/state/macbook-setup/.phase0-complete` | marker present |
| `gh auth status` | clean, SSH protocol, ≥1 key |
| `chezmoi diff` (public) | empty |
| `chezmoi diff` (private overlay) | empty |
| `brew bundle check` against rendered Brewfiles | clean |
| `mise current` for each tool in `mise.yaml` | matches default version |
| Each repo in `repos.yaml` + `repos-personal.yaml` + `repos-<work>.yaml` (last only on work machine) | dir present, `git remote get-url origin` matches |
| `bw status` | command runs, status returned (locked is OK) |
| Claude Code plugin presence | personal plugin loaded; work-org marketplace registered |
| Each `macos-defaults.yaml` entry | current matches expected |
| Each `system-tweaks.yaml` entry | probe passes |
| Each `manual.yaml` entry | detection probe |
| Each post-install hook probe | passes |

### Output format

Three-column table: status, phase, item. Status is `[ok]`, `[drift]`, or `[missing]`. Phase is `P0`/`P1`/`P2`/`P3`. Item is the human-readable identifier.

### Example output

```
[ok]      P0  homebrew installed
[ok]      P0  gh auth status (SSH, 1 key)
[ok]      P1  chezmoi diff empty
[drift]   P1  brew bundle: missing 'lazygit'
[ok]      P1  mise: go 1.23, node 22, python 3.12
[ok]      P2  bw status: locked (expected)
[ok]      P2  ghost-bazaar plugin loaded
[missing] P3  macos-default: AppleShowAllExtensions (current=false, expected=true)
[ok]      P3  Touch ID sudo enabled
──────────────────────────────────────────────────
2 issues. Run: scripts/setup.sh --only P1-30,P3-00 to repair.
```

### Exit code

- `0` if all rows are `[ok]`.
- non-zero if any row is `[drift]` or `[missing]`. The exit code is the count of non-ok rows, capped at 255.

### Performance budget

Under 5 seconds on a fully-configured machine. The two slow probes are `chezmoi diff` and `brew bundle check`; both are kept by leveraging their own caching where available.

### Read-only contract

The doctor never writes, never installs, never invokes sudo. The Touch ID probe reads a world-readable file. The macOS defaults probe uses `defaults read`, which does not require elevation. This contract is what makes the doctor safe to run from any context (CI-style hooks, alias in shell, anywhere).

### Relationship to step probes

Each step's idempotency probe and the corresponding doctor probe should be identical or strictly compatible. When they disagree the doctor takes precedence. Practically, the step probes call into helpers in `scripts/lib/` and the doctor calls the same helpers — they cannot diverge.

---

## 9. Idempotency Contract (Phase 3)

The Phase 3 contract sits on top of the parent's:

- Every step probes before acting. A re-run of any Phase 3 step on a fully-configured machine logs only `skip` and `ok` lines.
- `P3-00` writes only the defaults that drift; `killall` runs only for targets touched in the current pass.
- `P3-10` line-greps before appending; never duplicates lines in `/etc/pam.d/sudo_local`; only re-prompts for sudo when an actual write is needed.
- `P3-20` is read-only. It never modifies the system. It always exits 0.
- `P3-30` hooks are independent; each has its own probe; a re-run on a configured machine is silent per hook.
- `P3-40` is read-only. It is safe to run any number of times in any order.
- Re-running `scripts/setup.sh` end-to-end on a configured machine should still hit the parent's <30s target with all steps from P0–P3 reporting `skip`.

---

## 10. Iteration & Testing

The same test loop the earlier phases use, plus one new fidelity tier.

### Test targets

| Target | Use for |
|---|---|
| Phase-2-complete VM snapshot | Iterating on `P3-*` steps without re-doing earlier phases each round. UTM with macOS Sequoia, snapshot taken at the moment Phase 2 finishes. |
| Wiped real MacBook | Final v1 sign-off run. One-shot; no retry. |

### Specifically verify

- macOS defaults survive a reboot. Apply, reboot, run `P3-40`; expect all `[ok]`.
- `killall` actually takes effect. After `P3-00` writes a Dock change, the Dock visually reflects the new state without log-out.
- Touch ID sudo works on a **fresh terminal session**. The same session that ran `P3-10` does not have Touch ID active; a newly opened terminal does. Verify by quitting Ghostty and reopening.
- The Claude Code smoke check fires correctly when Claude Code is broken. Manually `npm uninstall -g @anthropic-ai/claude-code`, run `P3-30`, expect the hook to fail loudly. Then reinstall and re-run.
- The doctor exits non-zero when drift is present. Manually `defaults write` a tracked key to a wrong value, run doctor, expect a non-zero exit and a `[drift]` row.
- The manual-installs check warns but does not fail. Add a fake entry with a `kind: app` detection that won't match, run `P3-20`, expect a warning row and a `0` exit.
- `--dry-run` does not modify anything. Compare `defaults read` and `grep` results before and after a `--dry-run`.

### What to expect breaking

- macOS Sequoia point releases sometimes rename or relocate defaults keys. Drift on a previously-stable key after an OS update is usually this. Fix by updating the inventory entry, not by working around in script.
- `defaults import` for app preferences can race with the app being open. Document: quit Raycast before running `P3-30`, or accept that the import takes effect on next launch.
- Touch ID `pam_tid.so` interacts oddly with tmux/Screen-detached sessions on some machine generations; the failure mode is "sudo asks for password silently." Document in `troubleshooting.md`.

---

## 11. Implementation Order (Phase 3 only)

Paraphrased from the approved M6 task list:

1. **`P3-00 macos-defaults.sh` + `inventory/macos-defaults.yaml`.** Implement the per-type probe, the `killall` queue, the `scripts/lib/macos.sh` helpers. Test against a small inventory (one bool, one string, one array) before scaling up.
2. **`P3-10 system-tweaks.sh` + `inventory/system-tweaks.yaml`.** Implement `kind: pam-line`. Verify Touch ID enables on a VM, verify the probe correctly skips on a re-run.
3. **`P3-20 manual-installs-check.sh`.** Implement the four detection kinds. Cross-reference Discovery PRD §9 schema; do not duplicate it.
4. **`P3-30 post-install.sh`.** Implement the three hooks (gh extensions, Raycast, Claude smoke). Each in its own helper.
5. **`scripts/doctor.sh`.** Aggregate every probe. Format the table. Verify exit-code semantics. Verify under-5s runtime.
6. **Documentation pass.** Write `docs/architecture.md`, `docs/adding-a-tool.md`, `docs/adding-a-repo.md`, `docs/troubleshooting.md`, `docs/manual-setup.md`.
7. **Real-MacBook end-to-end.** Wipe, run from `curl | bash` (Phase 0), drive Phases 1–3 from Claude Code, capture timings, capture `doctor` output, file under `docs/v1-signoff.md`.
8. **Re-run validation.** With the machine now configured, re-run the full bootstrap; verify the parent §12 "<30s with zero changes" target.
9. **Tag + cleanup.** Tag `wip` as `v1-archive`. Delete the `wip` branch (per Discovery PRD §3 procedure). Confirm `git branch --show-current` is `main` and `git stash list` is empty before deleting.
10. **Sign-off doc.** Write `docs/v1-signoff.md` with the evidence captured in step 7. Write `docs/future-work.md` capturing Q-PARENT-1 (curl checksum deferral) and any items from parent §13 that surfaced during validation.

Each numbered item is a checkpoint where the system should still be runnable end-to-end, even if incomplete.

---

## 12. Boundary with Earlier Phases

Phase 3 is the last phase. The boundaries are sharp by design:

| Phase | Owns |
|---|---|
| Phase 0 | Curl-bootstrap, Xcode CLT, Homebrew, Phase 0 Brewfile, `gh` auth, Claude Code install, public dotfiles clone. |
| Phase 1 | chezmoi public source + apply, full Brewfile via inventory, `mise` install, public repo auto-clone, `inventory/macos-defaults.yaml` *file* (Phase 3 extends the schema and consumes it). |
| Phase 2 | Bitwarden unlock, private overlay clone + apply, AWS profiles, work/personal Brewfile splits, Claude Code marketplace + plugin wiring, app-config templates for Raycast (private overlay). |
| Phase 3 | macOS defaults application + `killall` queueing, system tweaks (Touch ID for sudo today, future tweaks tomorrow), manual-installs check (consumer; schema is Discovery's), post-install hooks (gh extensions, app post-install, Claude smoke), doctor script, final docs, v1 sign-off. |

The discriminator: *if installing a new tool, that's Phase 1 or Phase 2's inventory. If observing or polishing the system after everything is installed, that's Phase 3.*

A few specific clarifications:

- The `inventory/macos-defaults.yaml` *file* was created in Phase 1 with the basic schema (domain, key, type, value). Phase 3 extends it with `killall:` and is the only consumer that uses the extended field. The Phase 1 doctor probe still works against the basic fields; the Phase 3 doctor probe additionally validates `killall:` integrity.
- Raycast: Phase 2 *authors* the chezmoi-managed config files (in the private overlay, since the configs may be personal). Phase 3 *triggers* the `defaults import` post-install. If a user opens a re-run with a fresh Raycast preferences file, Phase 3 imports it; it does not own the contents.
- The `--doctor` flag on `scripts/setup.sh` is owned by Phase 3 because the doctor script itself is. Earlier phases provide probes; Phase 3 aggregates.

Phase 3 is the final gate to v1. Once it signs off, the Phase 1/2/3 surface area is what the v1 system actually is.

---

## 13. Success Criteria (v1 sign-off)

The parent §12 list, restated with concrete evidence requirements. Sign-off requires evidence for every row.

| Criterion | Evidence |
|---|---|
| One-command bootstrap to fully-configured | Wipe MacBook, run the curl command from Phase 0, drive Phases 1–3 to completion. Capture wall-clock duration end-to-end. Save the run log file path under `docs/v1-signoff.md`. Acceptance: completes without manual scripting steps beyond GitHub auth, Bitwarden master password, and sudo. |
| Re-run <30s zero changes | Immediately after the prior run, re-execute `scripts/setup.sh`. Capture wall-clock duration with `time`. Acceptance: under 30 seconds; every step prints `skip`. |
| Add a tool = edit one file | Add a representative tool to `inventory/brew.yaml`. Run `scripts/setup.sh`. Verify it installs. Remove the entry, run again, verify the doctor reports the package as drift (or absent). Document the round-trip in `docs/adding-a-tool.md`. Acceptance: only `inventory/brew.yaml` was edited. |
| Add a repo = edit one file | Same shape as above, with `inventory/repos.yaml`. Document in `docs/adding-a-repo.md`. Acceptance: only `inventory/repos.yaml` was edited. |
| Public dotfiles usable as starter by teammate | Create a fresh user account on the MacBook (`sudo dscl . -create /Users/test`), log in, run the curl command pointed at the public repo. Acceptance: reaches Phase 1 completion using only public files; private steps cleanly skip. |
| Inventory files answer "what tools and why" | Manual review of `inventory/brew.yaml`, `repos.yaml`, `mise.yaml`, `macos-defaults.yaml`, `system-tweaks.yaml`, `manual.yaml`. Acceptance: every entry has either an obvious name or a `desc:`/`reason:` field; nothing is mysterious. |
| All doctor probes green on real hardware | Run `scripts/setup.sh --doctor` after the full bootstrap. Capture stdout. Acceptance: zero `[drift]`, zero `[missing]`; exit code 0. Output file linked from `docs/v1-signoff.md`. |

The `docs/v1-signoff.md` document collects all evidence — timings, log paths, doctor output, screenshots if useful — and is the single artifact that says "v1 is done."

After sign-off: tag `wip` as `v1-archive`, delete `wip`, close the v1 milestone.

---

## 14. Open Questions

Most parent §10 open questions are owned by earlier phases (Bitwarden lifecycle by Phase 2, GPG by future work, Mac App Store by Phase 1's brew inventory, etc.). Phase 3 carries only one:

- **Q-PARENT-1 (curl checksum verification of the bootstrap script).** Resolved as **deferred** for v1. Document the deferral in `docs/future-work.md` with the rationale: the trade-off (more secure vs friction on every PR-driven update) is real, but the threat model for a personal dotfiles bootstrap on a brand-new machine — where the curl URL is typed by a human who already trusts GitHub — does not justify the friction yet. Revisit when the dotfiles ship to a wider audience or when GitHub adds first-class signed releases for raw-blob URLs.

All other questions are owned upstream and not blocking Phase 3.

---
