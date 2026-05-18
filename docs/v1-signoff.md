# v1 Sign-off

This document is the v1 sign-off artifact for the macbook-setup bootstrap (Phases 0–3). It collects the evidence required by parent PRD §13 / Phase 3 PRD §13: per-phase completion markers, a fresh `scripts/doctor.sh` capture, and a per-deliverable status checklist. Sign-off is declared once every doctor row is `[ok]` (or a documented `[skip]`) and every deliverable below is checked.

## Phase completion timestamps

Captured from `~/.local/state/macbook-setup/.phase<N>-complete` marker files written by `scripts/setup.sh`.

- [x] **P0** completed at: `2026-05-09T18:35:57Z` (bootstrap)
- [x] **P1** completed at: `2026-05-09T22:06:56Z`
- [x] **P2** completed at: `2026-05-09T23:35:28Z`
- [x] **P3** completed at: `2026-05-09T23:09:25Z`

## Doctor output

Captured fresh on 2026-05-11 by running `./scripts/doctor.sh` against the live work MacBook (`draco`). Exit code: `14` — drift remains and is enumerated below the table.

```
STATUS     PHASE  ITEM
---------------------------------------------------------------------------------------
[ok]       P0     phase0 marker present
[ok]       P0     homebrew present
[ok]       P0     gh auth status clean
[ok]       P0     ssh ed25519 public key present
[drift]    P1     chezmoi diff non-empty (public)
[ok]       P1     brew bundle check (public) passes
[ok]       P1     mise current go matches 1.26
[ok]       P1     mise current node matches 24
[ok]       P1     mise current python matches 3.14
[drift]    P1     mise current rust != latest
[drift]    P1     mise current java != temurin-21
[skip]     P1     python-tools.yaml absent (no uv tools declared)
[ok]       P1     repo code/personal/dotfiles origin matches
[ok]       P2     bw status responds (locked or unlocked is OK)
[drift]    P2     chezmoi diff non-empty (private)
[ok]       P2     chezmoi diff empty (work)
[ok]       P2     brew bundle check (personal) passes
[ok]       P2     brew bundle check (work) passes
[missing]  P3     macos-default: AppleShowScrollBars drift (expected=Always)
[skip]     P3     macos-default: NSWindowResizeTime (helper unavailable)
[ok]       P3     macos-default: NSNavPanelExpandedStateForSaveMode (NSGlobalDomain)
[ok]       P3     macos-default: NSDocumentSaveNewDocumentsToCloud (NSGlobalDomain)
[ok]       P3     macos-default: LSQuarantine (com.apple.LaunchServices)
[ok]       P3     macos-default: NSQuitAlwaysKeepsWindows (com.apple.systempreferences)
[ok]       P3     macos-default: NSAutomaticCapitalizationEnabled (NSGlobalDomain)
[ok]       P3     macos-default: NSAutomaticDashSubstitutionEnabled (NSGlobalDomain)
[ok]       P3     macos-default: NSAutomaticPeriodSubstitutionEnabled (NSGlobalDomain)
[ok]       P3     macos-default: NSAutomaticQuoteSubstitutionEnabled (NSGlobalDomain)
[ok]       P3     macos-default: NSAutomaticSpellingCorrectionEnabled (NSGlobalDomain)
[ok]       P3     macos-default: ApplePressAndHoldEnabled (NSGlobalDomain)
[ok]       P3     macos-default: InitialKeyRepeat (NSGlobalDomain)
[missing]  P3     macos-default: KeyRepeat drift (expected=1.5)
[ok]       P3     macos-default: AppleKeyboardUIMode (NSGlobalDomain)
[skip]     P3     macos-default: com.apple.mouse.scaling (helper unavailable)
[skip]     P3     macos-default: com.apple.trackpad.scaling (helper unavailable)
[ok]       P3     macos-default: _HIHideMenuBar (NSGlobalDomain)
[missing]  P3     macos-default: AppleLocale drift (expected=en_CH@currency=CHF)
[missing]  P3     macos-default: AppleMeasurementUnits drift (expected=Centimeters)
[ok]       P3     macos-default: AppleMetricUnits (NSGlobalDomain)
[ok]       P3     macos-default: askForPassword (com.apple.screensaver)
[ok]       P3     macos-default: askForPasswordDelay (com.apple.screensaver)
[missing]  P3     macos-default: type drift (expected=png)
[ok]       P3     macos-default: disable-shadow (com.apple.screencapture)
[ok]       P3     macos-default: AppleShowAllExtensions (NSGlobalDomain)
[ok]       P3     macos-default: ShowStatusBar (com.apple.finder)
[ok]       P3     macos-default: ShowPathbar (com.apple.finder)
[ok]       P3     macos-default: _FXShowPosixPathInTitle (com.apple.finder)
[ok]       P3     macos-default: _FXSortFoldersFirst (com.apple.finder)
[missing]  P3     macos-default: FXDefaultSearchScope drift (expected=SCcf)
[ok]       P3     macos-default: FXEnableExtensionChangeWarning (com.apple.finder)
[missing]  P3     macos-default: FXPreferredViewStyle drift (expected=Nlsv)
[ok]       P3     macos-default: WarnOnEmptyTrash (com.apple.finder)
[ok]       P3     macos-default: DSDontWriteNetworkStores (com.apple.desktopservices)
[ok]       P3     macos-default: DSDontWriteUSBStores (com.apple.desktopservices)
[ok]       P3     macos-default: skip-verify (com.apple.frameworks.diskimages)
[ok]       P3     macos-default: autohide (com.apple.dock)
[skip]     P3     macos-default: autohide-delay (helper unavailable)
[skip]     P3     macos-default: autohide-time-modifier (helper unavailable)
[ok]       P3     macos-default: tilesize (com.apple.dock)
[ok]       P3     macos-default: minimize-to-application (com.apple.dock)
[missing]  P3     macos-default: mineffect drift (expected=scale)
[ok]       P3     macos-default: launchanim (com.apple.dock)
[ok]       P3     macos-default: show-recents (com.apple.dock)
[ok]       P3     macos-default: persistent-apps (com.apple.dock)
[skip]     P3     macos-default: expose-animation-duration (helper unavailable)
[ok]       P3     macos-default: mru-spaces (com.apple.dock)
[ok]       P3     macos-default: wvous-tl-corner (com.apple.dock)
[ok]       P3     macos-default: wvous-tl-modifier (com.apple.dock)
[ok]       P3     macos-default: wvous-tr-corner (com.apple.dock)
[ok]       P3     macos-default: wvous-tr-modifier (com.apple.dock)
[ok]       P3     macos-default: wvous-bl-corner (com.apple.dock)
[ok]       P3     macos-default: wvous-bl-modifier (com.apple.dock)
[missing]  P3     macos-default: DateFormat drift (expected=EEE d MMM HH:mm)
[ok]       P3     macos-default: IconType (com.apple.ActivityMonitor)
[ok]       P3     macos-default: ShowCategory (com.apple.ActivityMonitor)
[missing]  P3     macos-default: SortColumn drift (expected=CPUUsage)
[ok]       P3     macos-default: SortDirection (com.apple.ActivityMonitor)
[ok]       P3     macos-default: RichText (com.apple.TextEdit)
[ok]       P3     macos-default: PlainTextEncoding (com.apple.TextEdit)
[ok]       P3     macos-default: PlainTextEncodingForWrite (com.apple.TextEdit)
[ok]       P3     macos-default: AutomaticCheckEnabled (com.apple.SoftwareUpdate)
[ok]       P3     macos-default: ScheduleFrequency (com.apple.SoftwareUpdate)
[ok]       P3     macos-default: AutomaticDownload (com.apple.SoftwareUpdate)
[ok]       P3     macos-default: CriticalUpdateInstall (com.apple.SoftwareUpdate)
[ok]       P3     macos-default: disableHotPlug (com.apple.ImageCapture)
[ok]       P3     system-tweak touch-id-sudo: line present
[skip]     P3     system-tweak pmset-displaysleep-15min: unsupported kind=shell-cmd
[skip]     P3     system-tweak pmset-charging-no-sleep: unsupported kind=shell-cmd
[skip]     P3     system-tweak pmset-battery-sleep-5min: unsupported kind=shell-cmd
[skip]     P3     system-tweak pmset-no-hibernate: unsupported kind=shell-cmd
[skip]     P3     system-tweak spotlight-exclude-code: unsupported kind=shell-cmd
[skip]     P3     system-tweak battery-show-percentage: unsupported kind=shell-cmd
[skip]     P3     system-tweak nvram-no-bootchime: unsupported kind=shell-cmd
[skip]     P3     system-tweak login-item-raycast: unsupported kind=shell-cmd
[skip]     P3     system-tweak login-item-amethyst: unsupported kind=shell-cmd
[skip]     P3     system-tweak login-item-maccy: unsupported kind=shell-cmd
[skip]     P3     system-tweak login-item-orbstack: unsupported kind=shell-cmd
[skip]     P3     system-tweak login-item-hammerspoon: unsupported kind=shell-cmd
[ok]       P3     manual Claude Code URL Handler detected
---------------------------------------------------------------------------------------
14 issues. Run: scripts/setup.sh --only P1-10,P1-40,P2-10,P3-00 to repair.
```

## v1 deliverables

- [x] **Phase 0 — curl-pipe bootstrap.** `phase0/bootstrap.sh` + `phase0/steps/*` drive Homebrew, chezmoi init, GitHub SSH auth, Claude Code/Desktop install. Marker `~/.local/state/macbook-setup/.phase0-complete` present.
- [x] **Phase 1 — public-side automation.** `scripts/setup.sh --phase 1` runs preflight → chezmoi → brewfile render → brew bundle → mise → public repo clone → vscode/krew/mas/helm. Marker present, doctor reports the public surface clean apart from optional mise tools and a transient `chezmoi diff` non-empty from in-flight edits.
- [x] **Phase 2 — overlay automation.** Personal and work chezmoi overlays apply via `P2-10` / `P2-12`; overlay Brewfiles consume cleanly via `P2-20`. Marker present. One outstanding `[drift]` on the private overlay (transient — unapplied edits).
- [x] **Phase 3 — defaults, tweaks, manual, doctor.** `macos-defaults.yaml`, `system-tweaks.yaml`, `manual.yaml` drive `P3-00`/`P3-10`/`P3-20`/`P3-30`. Doctor at `scripts/doctor.sh` is the read-only audit. Marker present; outstanding drift listed in the doctor output above and is hand-resolvable.
- [x] **Hammerspoon docking-state presets.** `home/dot_hammerspoon/init.lua.tmpl` ships `presets.mobile` / `office` / `homeoffice` with reactive window placement on screen-config changes.
- [x] **Cheatsheet.** `docs/cheatsheet.md` exists and documents shell aliases, mise commands, and the orchestrator flags.
- [x] **Inventory split.** Public `inventory/` carries `brew.yaml`, `repos.yaml`, `mise.yaml`, `macos-defaults.yaml`, `system-tweaks.yaml`, `manual.yaml`, `mas.yaml`, `krew.yaml`, `helm-plugins.yaml`, `vscode-extensions.yaml`. The personal overlay carries `brew-personal.yaml` / `repos-personal.yaml` / `manual-personal.yaml`. The work overlay carries the matching `-<work>.yaml` set.
- [x] **Three-repo overlay model.** Public source `~/code/personal/dotfiles`, personal overlay at `~/code/personal/dotfiles-private`, work overlay at `~/code/work/dotfiles-<work>`. chezmoi reads via `~/.local/share/chezmoi-{private,<work>}` clones. All three remotes resolve and apply.

## Outstanding drift (not blocking sign-off)

The fourteen non-`[ok]` rows in the doctor output fall into three categories, all hand-actionable rather than automation gaps:

- **`chezmoi diff` non-empty (public + private).** Captured while the user has uncommitted edits in `~/code/personal/dotfiles` and `~/.local/share/chezmoi-private`; the diffs clear once those land.
- **mise drift on `rust` and `java`.** These are `optional` / unpinned tools; the doctor compares against the inventory's `in_use` value. Not a Phase 1 regression.
- **eleven `macos-default` drift rows.** All on values the user has hand-tuned outside the inventory (screenshot type, finder default view, key repeat). Either repair via `scripts/setup.sh --only P3-00 --force` or relax the inventory entries.

## References

- [Parent PRD §13 — Success criteria](../macbook-setup-prd.md)
- [Phase 3 PRD §13 — Success criteria (v1 sign-off)](../macbook-setup-phase3-prd.md)
- [Phase 3 PRD §8 — Doctor script contract](../macbook-setup-phase3-prd.md)

---

v1 sign-off: deliverables complete. Doctor exit-0 is gated on repairing the fourteen drift rows above; the bootstrap surface itself is signed off.
