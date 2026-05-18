# New machine bootstrap

Naming theme: constellations. Currently registered (in `home/.chezmoi.toml.tmpl`):

| Hostname | Type | Tags |
|---|---|---|
| `draco`   | work     | media, go, node, openapi, proto, arch |
| `cygnus`  | personal | gaming, media, art, personal-vpn |
| `lyra`    | personal | media, art |

## Steps

### 0. Add the new machine to the registry (skip if reusing one of the above)

Add a block to `home/.chezmoi.toml.tmpl`:

```toml
{{- else if eq $hostname "vega" -}}
  {{- $machine  = "personal" -}}
  {{- $tagsList = list "gaming" "media" -}}
{{- end -}}
```

Commit + push. Now the new machine knows its defaults.

### 1. Set the hostname

```sh
sudo scutil --set ComputerName  vega
sudo scutil --set HostName       vega
sudo scutil --set LocalHostName  vega
```

All three should match. macOS uses different names internally for different purposes (system identity, network advertisement, Bonjour); keeping them aligned avoids surprise in tools like `tmux` or `git` that read `hostname`.

### 2. Phase 0 — curl | bash

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/suTerminus/dotfiles/main/phase0/bootstrap.sh)
```

Installs: Xcode CLT, Homebrew, `gh`, `jq`, `node`, Claude Code CLI + Desktop. Clones the public dotfiles to `~/code/personal/dotfiles`. Writes `~/.local/state/macbook-setup/.phase0-complete`.

### 3. Phase 1 / 2 / 3 — driven by Claude Code

```sh
cd ~/code/personal/dotfiles
claude
```

In Claude Code:
- `run setup.sh --phase 1` — chezmoi init (Enter through prompts), brew bundle (~70 packages), mise (go/node/python/rust), repo clones, vscode extensions, krew plugins, mas apps, helm plugins.
- `run setup.sh --phase 2` — Bitwarden unlock (master password + 2FA), personal + work overlays apply, marketplace registration. **Requires the personal overlay (and, for work, the work overlay) repos to already exist on GitHub.**
- `run setup.sh --phase 3` — macOS defaults (62 entries), Touch ID PAM line (sudo prompt), post-install hooks (gh extensions, Amethyst presence check, Claude smoke), system tweaks (pmset, nvram boot-chime).

### 4. Reload + verify

```sh
exec zsh
./scripts/setup.sh --doctor
```

`--doctor` is the read-only sweep across all phases. Anything `[drift]` or `[missing]` is reported; exit code = count.

## Interactive prompts you'll hit

| Prompt | When | What to type |
|---|---|---|
| chezmoi `machine`, `name`, `email` | P1-10, first init | Enter (hostname-driven defaults are right) |
| sudo password | P1-30 occasionally; P3-10 always | macOS user password |
| Bitwarden master | P2-00 | vault master password |
| Bitwarden 2FA | P2-00 if enabled | TOTP / yubikey |
| App Store sign-in (rare) | P1-30/P1-80 if MAS apps fail | sign into App Store, re-run `--only P1-30,P1-80` |

## Time budget

- Phase 0: 5–15 min (Xcode CLT is the slow bit — single ~3GB download).
- Phase 1: 15–30 min (mostly brew bundle for ~70 packages).
- Phase 2: 5–10 min (overlay clones + apply, often empty inventories).
- Phase 3: <1 min (defaults + PAM line are instant).
- Doctor: <5 sec.

Total: ~30–60 min wall clock; ~5 min of your attention (the keyboard-prompt moments above).

## Re-running

Every step is idempotent. `setup.sh --phase 1` on a fresh terminal completes in <30s with all-`skip`. To re-execute selectively:

```sh
./scripts/setup.sh --only P1-20    # re-render the public Brewfile
./scripts/setup.sh --only P1-30    # re-bundle install
./scripts/setup.sh --only P3-00    # re-apply macOS defaults (skip if no drift)
```

### Forcing a re-apply

When you edit an inventory entry and the probe doesn't notice (or you want to be explicit), use `--force`. P3-00 and P3-10 honour it natively; other steps treat it as a no-op.

```sh
./scripts/setup.sh --only P3-00 --force                 # re-apply ALL macOS defaults
./scripts/setup.sh --only P3-10 --force                 # re-apply ALL system tweaks

# Or call the step directly for a single entry:
./scripts/steps/P3-00-macos-defaults.sh --force --key com.apple.dock.tilesize
./scripts/steps/P3-10-system-tweaks.sh   --force --name pmset-displaysleep-15min
```

### Reverting macOS defaults

```sh
./scripts/revert-macos-defaults.sh        # interactive confirm
./scripts/revert-macos-defaults.sh --yes  # skip prompt
./scripts/revert-macos-defaults.sh --dry-run
```

### Other tools

- **AWS bootstrap** (work machines only): regenerate `~/.aws/config` with all SSO-visible accounts + import EKS contexts. Reads `AWS Work SSO` from Bitwarden.
  ```sh
  aws-bootstrap                         # full: rewrite config + login + EKS
  aws-bootstrap --refresh               # skip rewrite; just login + EKS
  aws-bootstrap --skip-eks              # only the config
  ```
- **VPN setup**: pull `.ovpn` from Bitwarden into AWS VPN Client's profile dir.
  ```sh
  vpn-setup                             # full
  vpn-setup --print-only                # write file but don't launch app
  vpn                                   # open AWS VPN Client (manual Connect click)
  ```
- **Theme toggle**: flip macOS appearance + regen per-tool configs.
  ```sh
  theme-toggle                          # flip current
  theme-toggle light                    # explicit
  theme-toggle --status                 # print current
  ```
