# Cheatsheet

Daily-use commands across this dotfiles setup. Keep scannable; deeper docs
live elsewhere in `docs/`.

---

## Window placement — Hammerspoon

| Command | What it does |
| --- | --- |
| `hs -c 'currentPreset()'` | Show active preset, pin state, screen count |
| `hs -c 'preset("office")'` | Pin a preset (`office`, `homeoffice`, `minimal`, `laptop`) |
| `hs -c 'preset("auto")'` | Release pin; resume auto-switching by screen count |
| `hs -c 'commApps()'` | Open Teams, Outlook, Slack, WhatsApp, Spotify; watcher snaps each |
| `hs -c 'snapAll()'` | Re-place every layout-table window using current display order |
| `hs -c 'hs.reload()'` | Reload init.lua after editing presets |

**Auto-switch:** 1 screen → `laptop`; 2 → `minimal`; 3+ → `office`. Pin to
`homeoffice` manually when at home (same display setup as office). Hammerspoon
re-evaluates on every `hs.screen.watcher` event (dock/undock).

Edit `home/dot_hammerspoon/init.lua.tmpl` → `chezmoi apply` → `hs -c 'hs.reload()'`.
Displays are indexed left-to-right by frame x-origin; reorder them in
**System Settings → Displays → Arrangement** to change indices.

Hammerspoon needs **Accessibility** permission once
(System Settings → Privacy & Security → Accessibility → enable Hammerspoon).

---

## App stacks — Raycast

| Stack | Opens |
| --- | --- |
| `Dev Stack — Default` | Arc, Ghostty, VSCode, Obsidian, Spotify |
| `Comms Stack` | Teams, Outlook, Slack, WhatsApp, Spotify (via Hammerspoon, snaps to display 1) |
| `Dev with Comms` | Dev Stack + Comms Stack |
| `Stack — Architect` / `Database` / `Go Dev` | Stubs — edit the script to add apps |

Source: `home/dot_config/raycast/scripts/`. New stacks are just shell scripts
with Raycast metadata comments at the top.

---

## Bootstrap — `scripts/setup.sh`

```bash
./scripts/setup.sh                          # full run
./scripts/setup.sh --phase 1                # everything matching P1-*
./scripts/setup.sh --only P3-00,P3-10       # specific step IDs
./scripts/setup.sh --skip P2-40             # skip a step (wins over --only)
./scripts/setup.sh --include-tag gis        # opt into a tag bucket
./scripts/setup.sh --dry-run                # probe-only, no writes
./scripts/setup.sh --doctor                 # alias for --dry-run --phase 1
./scripts/setup.sh --force                  # re-apply even when probes pass
./scripts/setup.sh --fail-fast              # abort on first non-zero step
./scripts/setup.sh --update-repos           # also pull existing clones in P1-50
PHASE1_DRY_RUN=1 ./scripts/setup.sh         # env-var equivalent of --dry-run
```

`--force` propagates to steps via `PHASE1_FORCE=1`. When running a step
directly you can also narrow the action:

```bash
scripts/steps/P3-00-macos-defaults.sh --force --key dock-autohide-time-modifier
scripts/steps/P3-10-system-tweaks.sh  --force --name login-item-hammerspoon
```

Logs land in `~/.local/state/macbook-setup/run-*.log`.

---

## Doctor

```bash
./scripts/doctor.sh                  # read-only sweep; non-zero on drift
./scripts/setup.sh --doctor          # dry-run of phase 1 (alias)
```

---

## Chezmoi

```bash
chezmoi apply                        # render templates → $HOME
chezmoi diff                         # what would change
chezmoi edit <target-path>           # open the source file for a target
chezmoi source-path <file>           # find which repo file produces a target
chezmoi cd                           # cd into the source dir
chezmoi data | yq                    # values available to .tmpl files
chezmoi init --apply                 # re-init after editing .chezmoi.toml.tmpl
```

Three source dirs (in priority order: work > personal > public):

| Layer | Source | Read by chezmoi from |
| --- | --- | --- |
| Public | `~/code/personal/dotfiles` | symlink |
| Personal | `~/code/personal/dotfiles-private` | `~/.local/share/chezmoi-private` (clone) |
| Work | `~/code/work/dotfiles-<work>` | `~/.local/share/chezmoi-<work>` (clone) |

---

## Theme

```bash
theme-toggle                         # flip macOS appearance + chezmoi apply
```

Reads/writes `~/.theme-mode`. Tools that read `$BAT_THEME` / `$FZF_DEFAULT_OPTS`
re-export on the next prompt via the `__theme_sync` precmd hook.

---

## AWS — work

```bash
awsl                                 # local cache check; no network
awsl <profile>                       # sso login if expired, then export
aws-bootstrap                        # Bitwarden → SSO → kubeconfig refresh
aws-bootstrap --refresh              # refresh creds only, skip enumeration
```

---

## VPN — work

```bash
vpn                                  # open AWS VPN Client (connect manually)
vpn-setup                            # pull .ovpn from Bitwarden, register it
```

---

## Shell shortcuts

```bash
e <file>          # nvim
v <file>          # nvim
md <file.md>      # glow -p (pager-mode markdown render)
k <args>          # kubectl
gs                # git status
gd                # git diff
gp                # git pull && git push
reload            # restart current shell
path              # PATH as newline-separated list
env-refresh       # re-pull personal env vars from Bitwarden
dof               # cd ~/code/personal/dotfiles
rep               # cd ~/code
```

---

## Where things live

| What | Where |
| --- | --- |
| Public dotfiles | `~/code/personal/dotfiles` |
| Private overlay | `~/code/personal/dotfiles-private` |
| Work overlay | `~/code/work/dotfiles-<work>` |
| Inventory (public) | `inventory/*.yaml` in public repo |
| Inventory (personal) | `inventory/*-personal.yaml` in personal overlay |
| Inventory (work) | `inventory/*-<work>.yaml` in work overlay |
| Hammerspoon | `~/.hammerspoon/init.lua` |
| Run logs | `~/.local/state/macbook-setup/run-*.log` |
| chezmoi config | `~/.config/chezmoi/chezmoi.toml` |
| Theme-mode flag | `~/.theme-mode` |
