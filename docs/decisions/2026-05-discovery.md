# Discovery Decisions

Date: 2026-05-09
Context: Setting up new MacBook, restructuring dotfiles into three repos
(public + private personal overlay + private work overlay).
Currently one machine; planning for two later.

---

## Brew formulae

### Public `[]` (dotfiles/inventory/brew.yaml)

act, bash, bat (new), bufbuild/buf/buf, cloc, coreutils, docutils,
eza (new, replaces exa), fd (new), findutils, fpp, fzf, gh,
git-delta (new), git-filter-repo, git-lfs, gnu-sed, gnupg (resolved),
gotop, graphviz, grpcurl, helm, hyperfine, jq, k9s, kubeconform,
kubernetes-cli (resolved), kustomize, mas, moreutils, neovim, nmap,
pandoc, pinentry-mac (resolved), reattach-to-user-namespace, ripgrep,
scc, sevenzip, starship, tig, tmux, tree, uv, wget, yq,
zoxide, zsh, zsh-autosuggestions (new), zsh-syntax-highlighting (new)

(uv kept public: uvx is daily-use for MCP server invocation.)
(gnupg + pinentry-mac kept public: useful safety net even if SOPS migrates to age.)
(kubernetes-cli explicit: don't rely on transitive of helm/k9s.)

### Personal `[personal]` (dotfiles-private/inventory/brew-personal.yaml)

kind, sops

### Work `[work]` (work overlay's `brew-<work>.yaml`)

aws-rotate-key, awscli, k6, mockery, openfga/tap/fga, protoc-gen-go,
sqlc, **+ argocd (new, replaces flux)**

(awscli moved to work overlay since AWS access is work-scoped today;
will revisit if a personal AWS account starts using it.)

### Optional `[optional, BUCKET]`

| Tag | Items |
|---|---|
| `[optional, gis]` | gdal, pmtiles, tippecanoe |
| `[optional, node]` | node, nvm |
| `[optional, docs]` | mkdocs, structurizr-cli |
| `[optional, java, work]` | maven (declared on work overlay only, skipped by default) |
| `[optional, native]` | cmake (rare; transitive in past workflows) |

### Skip (drop from inventory)

flux, fluxcd/tap/flux, gobject-introspection, guile, kubebuilder,
ktunnel + omrikiei/ktunnel/ktunnel, krr + robusta-dev/krr/krr,
linkerd, openldap, ossp-uuid, pnpm, postgresql@14, powerlevel10k,
pyenv, python@3.9, python@3.10, python@3.11, redis, stern, tfenv,
timewarrior, xkcd, zip

Reasoning notes:
- linkerd/flux/ktunnel/krr — not used anymore (flux replaced by argoCD)
- stern — superseded by Grafana stack (sentimental: liked it)
- kubebuilder — rarely directly used
- postgresql@14, redis, openldap — moving toward containers
- mactex — covered under casks; 5GB, install on demand
- pyenv + python@N — replaced by mise + uv
- powerlevel10k — replaced by starship
- timewarrior, xkcd, guile — niche / unused
- tfenv — not used anymore (mise-driven)
- pnpm — not needed yet; mise on demand
- zip, ossp-uuid, gobject-introspection — system / transitive deps

### `pnpm`

**Skip.** Not needed yet; mise can install it on demand when needed
("mise flow as much as possible").

---

## Brew taps

### Public `[]`
- bufbuild/buf (for `buf` formula)
- derailed/k9s (for `k9s` formula)

### Work `[work]`
- openfga/tap (for `fga` formula)

### Skip (deprecated, built-in, or formula-skipped)
- buo/cask-upgrade — `brew upgrade` covers casks now
- fluxcd/tap — flux skipped
- homebrew/bundle — built-in since brew 4.x
- homebrew/cask-fonts — deprecated, casks merged into homebrew/cask
- omrikiei/ktunnel — ktunnel skipped
- robusta-dev/krr — krr skipped
- romkatv/powerlevel10k — prompt skipped

---

## Brew casks

### Public `[]` (dotfiles/inventory/brew.yaml casks: section)

amethyst, bitwarden, bruno, devutils, docker, font-fira-code,
font-fira-code-nerd-font, ghostty, orbstack,
visual-studio-code, vlc

(amethyst replaced rectangle late in the cycle; rectangle had stopped
being a maintained option.)

### Personal `[personal]` (personal overlay's `brew-personal.yaml`)

arc, obsidian (new, replaces manual), protonvpn (new),
spotify, whatsapp, multiviewer-for-f1 (new, replaces manual)

### Work `[work]` (work overlay's `brew-<work>.yaml`)

aws-vpn-client (new, replaces openvpn-connect), datagrip, goland,
microsoft-office (new, replaces 5 MS Office manual apps),
microsoft-teams (new, replaces manual), slack

### Optional `[optional, BUCKET]`

| Tag | Items |
|---|---|
| `[optional, browser]` | firefox |
| `[optional, gis]` | qgis (replaces manual) |
| `[optional, ml]` | anaconda |
| `[optional, keyboard]` | qmk-toolbox (replaces manual) |
| `[optional, personal]` | gimp, iina, subler (Subler in active use for HDR) |

### Skip

alacritty, iterm2, keepassxc, kitty, mactex, openvpn-connect, postman

---

## Mac App Store (mas)

### Public `[]`
- Xcode (497799835)
- Medis (1579200037)

### Work `[work]`
- Jira (1475897096)
- Harvest (506189836)

### Skip
- 1Password 7 (1333542190) — replaced by Bitwarden

---

## Manual installs (declared, never auto-installed)

| Name | Tags | Detection (kind: app) |
|---|---|---|
| Claude.app | [manual] | bundle_id: com.anthropic.claudefordesktop |
| Claude Code URL Handler | [manual] | bundle_id: com.anthropic.claude-code-url-handler |
| Sophos Device Encryption | [manual, work] | bundle_id: com.sophos.enc.preferences |
| JetBrains Toolbox | [manual, work] | bundle_id: com.jetbrains.toolbox |
| Disk Drill | [manual, personal] | bundle_id: com.cleverfiles.DiskDrill |

---

## Apps explicitly dropped (no inventory entry)

Deezer, GitHub Desktop, GitKraken, Lens, Luna Modeler, Microsoft Edge,
NordVPN, TIDAL, Windsurf, pgModeler, Zoom

(Firefox, GIMP, IINA, Subler retained as `[optional, ...]` casks above.)

---

## Repo decisions (M2.T05 to refine)

| Repo | New home | Notes |
|---|---|---|
| public dotfiles | the public dotfiles repo | currently in this repo; main is the trunk; wip is the legacy snapshot |
| personal overlay | private repo | created in M5.T01; personal Brewfile (Spotify, ProtonVPN, Arc, Obsidian, etc.), personal AWS, personal SSH hosts, sops, kind |
| work overlay | private repo | created in M5.T01; work SSO, work SSH, Slack, MS Office, work chat, GoLand, DataGrip, AWS VPN, work-only Go/k8s tools (argocd, mockery, sqlc, k6, fga, protoc-gen-go), Jira, Harvest |
| vault | private credentials repo (legacy) | 11 real files (168K). Migration plan below; vault repo to be archived/deleted post-Phase 2. |
| personal Claude plugin | private repo | goes in the personal overlay's `repos-personal.yaml` |
| work-org repos (marketplace, docs, postgresql, ...) | private, SSO-gated | go in the work overlay's `repos-<work>.yaml` |

---

## Things explicitly replaced (key migrations)

| Old | New | Tag |
|---|---|---|
| iterm2 / kitty / alacritty | ghostty | [] |
| powerlevel10k | starship | [] |
| 1Password 7 | Bitwarden | [] / [personal] |
| Postman | Bruno | [] |
| TIDAL / Deezer | Spotify only | [personal] |
| GitHub Desktop / GitKraken | gh CLI + tig | [] |
| Lens | k9s | [] |
| flux | argocd | [work] |
| linkerd / ktunnel / krr / stern / kubebuilder | dropped (Grafana stack covers most) | skip |
| nordvpn / openvpn-connect | aws-vpn-client (work) + protonvpn (personal) | [work] / [personal] |
| MS Edge | Arc + Firefox | [personal] / [optional] |
| Microsoft individual apps | microsoft-office cask (one install for Word/Excel/PowerPoint/Outlook/OneNote) | [work] |
| pyenv + python@N | mise + uv | [] for uv |
| nvm + node | mise (kept as [optional, node] fallback) | [optional] |
| tfenv | mise | (skip tfenv) |
| openvpn-connect | aws-vpn-client + protonvpn | [work] / [personal] |
| postgresql@14 / redis / openldap | docker/orbstack containers | skip |
| Windsurf / Cursor | Claude Code + neovim + VS Code | [] |
| Manual: QGIS / Obsidian / MultiViewer / QMK / Subler / GIMP / IINA | brew casks | [optional,...] / [personal] |
| Manual: MS Office, Teams | brew casks | [work] |

---

## Vault migration (M2.T05)

Vault: private legacy credentials repo (cloned out-of-tree).
After migration, vault repo can be archived/deleted (chezmoi + Bitwarden
covers everything via overlays).

| File | Decision | Where it lands |
|---|---|---|
| `.aws/config` | split per profile | personal profiles -> personal overlay chezmoi tmpl; work profiles -> work overlay chezmoi tmpl |
| `.aws/credentials` | drop | all SSO now; static keys deprecated |
| `.config/gh/hosts.yml` | drop | re-auth fresh per machine via `gh auth login` |
| `.gitconfig.local` | port to template | personal overlay chezmoi tmpl, machine-conditional (personal vs work email) |
| `.kube/config` | drop | re-fetch via `aws eks update-kubeconfig` and similar; kind clusters create their own |
| `.zshenv` | split (see below) | secrets to Bitwarden, env/aliases to the work overlay |
| `aws.ovpn` | keep [manual] | work overlay; revisit during Phase 2 setup once aws-vpn-client validated |
| `secret` | drop plaintext, migrate values to Bitwarden | API tokens (GitHub PAT, npm token, etc.) -> Bitwarden -> chezmoi-rendered fragments at Phase 2 |
| `README.md` | drop | placeholder |
| `.DS_Store` | drop | macOS noise |

### `.zshenv` per-line split

| Line | Type | Destination |
|---|---|---|
| personal GH PATs (2x) | personal secrets | Bitwarden -> personal overlay chezmoi tmpl |
| work secrets (vSphere password, etc.) | work secrets | Bitwarden -> work overlay chezmoi tmpl |
| work identifiers (AWS account, etc.) | work identifiers | work overlay env fragment (machine=work) |
| work aliases (cluster login, path shortcuts) | work aliases | work overlay alias fragment (machine=work) |

### Action items before Phase 2

- [ ] Rotate the secrets currently in `.zshenv` once they've been re-stored in Bitwarden.
- [ ] Audit work cluster aliases for stale TLS-skip flags now that current certs are valid.
- [ ] Decide whether `aws.ovpn` is needed once `aws-vpn-client` is validated on the new machine.

---

## Misc.md + shells review (M2.5 - PATH, GPG, SSH, npm, VSCode)

### GPG keys (35 secret keys on this machine)

- **Do NOT migrate to new machine.** Likely not needed post-migration
  (commit signing moves to SSH per Q-PARENT-4; SOPS only used in
  private projects, may not need GPG at all).
- **ACTION ITEM (before wiping current machine):** export and securely
  back up all GPG keys (Bitwarden Send, encrypted volume, or 1Password
  vault). If lazy-import is later needed, add a helper script in
  the work overlay.

### SSH keys
- Only `id_ed25519.pub` exists. Phase 0 generates fresh key per new
  machine and uploads to GitHub. **Don't carry the existing key.**

### npm globals
- **Track:** `@mcp_router/cli` -> personal inventory (used for MCP).
- **Drop tracking:** `corepack`, `npm` (managed by mise + node).

### pip / pipx / uv tools
- All empty on this machine. Clean slate going forward; uv tool is
  the canonical install path.

### VSCode extensions (final, with second-pass clarifications)

#### Public `[]` (dotfiles/inventory/vscode-extensions.yaml) -- 12 universal core

- catppuccin.catppuccin-vsc (palette per PRD)
- anthropic.claude-code (primary AI)
- esbenp.prettier-vscode (formatter)
- davidanson.vscode-markdownlint (md lint)
- redhat.vscode-yaml
- tamasfe.even-better-toml
- yzhang.markdown-all-in-one
- mhutchie.git-graph (visual git log; primary git visual since gitlens dropped)
- mermaidchart.vscode-mermaid-chart (diagrams)
- docker.docker (Docker integration)
- ms-vscode-remote.remote-containers (devcontainers)
- mechatroner.rainbow-csv (CSV; promoted from optional to public per second pass)

#### Personal `[personal]` -- empty

(grammarly dropped per second pass; nothing else qualifies as personal-only.)

#### Work `[work]` (work overlay's `vscode-extensions-<work>.yaml`)
- atlassian.atlascode (Jira/Bitbucket)
- openfga.openfga-vscode
- ms-kubernetes-tools.vscode-kubernetes-tools
- github.vscode-pull-request-github (kept and moved to work per second pass)

#### Optional buckets

- `[optional, go]`: golang.go
- `[optional, rust]`: rust-lang.rust-analyzer
- `[optional, web]`: dbaeumer.vscode-eslint, svelte.svelte-vscode, prisma.prisma, firsttris.vscode-jest-runner
- `[optional, openapi]`: 42crunch.vscode-openapi, arjun.swagger-viewer, quicktype.quicktype
- `[optional, proto]`: bufbuild.vscode-buf
- `[optional, make]`: ms-vscode.makefile-tools
- `[optional, arch]`: ciarant.vscode-structurizr, systemticks.c4-dsl-extension (moved from work to optional per second pass)
- `[optional, java, work]`: redhat.java + 8x vscjava.* (java-pack, debug, dependency, maven, gradle, test, upgrade, migrate-to-azure)
- `[optional, ml]`: 5x ms-toolsai.* + 6x ms-python.* (Jupyter + Python; grouped because notebooks travel with Python tooling)
- `[optional, dotnet]`: ms-dotnettools.vscode-dotnet-modernize, ms-dotnettools.vscode-dotnet-runtime

#### Drop entirely (final list)

- arcticicestudio.nord-visual-studio-code (Catppuccin chosen)
- weaveworks.vscode-gitops-tools (flux dropped)
- bierner.markdown-mermaid (redundant with mermaidchart)
- vstirbu.vscode-mermaid-preview (redundant with mermaidchart)
- pcmx.darker-than-white--brighter-than-black (extra theme)
- ms-vscode.vscode-speech (unused)
- github.copilot-chat (Claude Code covers AI)
- nrwl.angular-console (no Nx work)
- ms-vscode.live-server (unused)
- donjayamanne.githistory (git-graph covers it)
- waderyan.gitblame (git-graph covers it)
- visualstudioexptteam.intellicode + intellicode-api-usage-examples (Claude Code covers AI suggestions)
- oderwat.indent-rainbow (visual noise)
- xyz.local-history (conflicts with git workflow)
- wayou.vscode-todo-highlight (low value)
- ryanluker.vscode-coverage-gutters (specialised)
- ms-azuretools.vscode-containers + ms-azuretools.vscode-docker (docker.docker covers)
- hashicorp.terraform (tfenv skipped)
- **eamodio.gitlens** (most useful features are subscription-gated; rare edge cases not worth the cost; second pass)
- **znck.grammarly** (drop entirely per second pass)
- **signageos.signageos-vscode-sops** (drop entirely per second pass)
- **donjayamanne.typescript-notebook** (drop entirely per second pass; ts-notebook bucket removed)

### PATH cleanup

#### Drop
- ~/.codeium/windsurf/bin (Windsurf skipped)
- ~/.nvm/versions/node/v22.17.0/bin (nvm optional; mise drives node)
- ~/.pyenv/shims, ~/.pyenv/bin, /opt/homebrew/opt/pyenv/bin (pyenv skipped; mise + uv drive Python)
- /opt/homebrew/anaconda3/bin, /opt/homebrew/anaconda3/condabin (anaconda is [optional, ml]; only on activation)
- /Library/TeX/texbin (mactex skipped)
- /usr/local/go/bin (manual Go install; replaced by mise)
- /opt/homebrew/opt/go/libexec/bin (brew Go duplicates mise Go; pick mise)
- /usr/local/bin/protoc (manual; install via brew or mise)
- duplicate /usr/local/bin entries (dedupe)

#### Keep
- standard system: /usr/bin, /bin, /usr/sbin, /sbin
- /opt/homebrew/bin, /opt/homebrew/sbin
- /opt/homebrew/opt/gnu-sed/libexec/gnubin (BSD sed -> GNU sed override)
- ~/.local/bin (uv tool default)
- ~/.cargo/bin (rust user)
- ~/go/bin (Go user binaries)
- ~/.krew/bin (kubectl plugins)
- ~/bin (user scripts)
- /Applications/Ghostty.app/Contents/MacOS (Ghostty CLI)
- ~/.claude/plugins/cache/... (auto-managed by Claude Code)

PATH reduces from ~30 entries to ~15.

### Frameworks
- ~/.tmux.conf -> port to dotfiles via chezmoi tmpl
- ~/.config/starship.toml -> port to dotfiles via chezmoi tmpl
- ~/.config/fish/ -> drop (zsh is the shell per PRD §4)

### Zsh dotfiles
- ~/.zshrc (40B), ~/.zprofile (43B), ~/.zshenv (21B) are thin shims;
  chezmoi rewrites all three from composed public + personal + work
  fragments.

### Zsh content review (.zshrc + .zsh/ from wip)

#### Critical fixes (broken/dangerous regardless of where they land)

| Item | Issue | Action |
|---|---|---|
| `funtion killport()` in .functions | typo: should be `function`; never registers | fix typo |
| `alias airport='/System/Library/.../airport'` | binary removed by Apple in macOS 14.4+ | drop |
| `alias urlencode='python -c "...print ul.quote_plus..."'` | Python 2 syntax; broken on Python 3 | drop |
| `export NPM_TOKEN=${PERSONAL_GH_TOKEN}` in .exports | embeds GitHub PAT into env on every shell init | move to dotfiles-private chezmoi tmpl rendered from Bitwarden |
| `bindkey -s '^e' 'vim $(fzf)\n'` | calls vim, not nvim | update to `nvim $(fzf --preview "bat --color=always {}")\n` per fzf-preview decision |

#### Drops (initialization blocks for skipped tools)

In .zshrc:
- `command -v flux ... completion zsh` (flux skipped)
- `command -v stern ... completion zsh` (stern skipped)
- `command -v kubebuilder ... completion zsh` (kubebuilder skipped)
- entire `# pyenv` block (pyenv skipped; mise drives Python)
- `# Added by Windsurf` block (Windsurf skipped)
- `# >>> conda initialize >>>` block -> move to dotfiles-private `[optional, ml]` fragment loaded only when anaconda is installed
- `NVM_DIR` + nvm.sh source block -> move to `[optional, node]` fragment
- `export GOROOT="$(brew --prefix golang)..."` (mise sets these)

In .exports:
- `export PATH=/opt/homebrew/anaconda3/bin:$PATH` -> move to `[optional, ml]` fragment
- `export PATH=/usr/local/bin/protoc:$PATH` (broken path; install protoc properly via brew)

#### Modernizations to apply

- replace `alias ls="exa"` with `alias ls="eza"` (exa unmaintained since 2022; eza is the maintained fork) -> add `eza` formula to public, drop exa references
- bind fzf-preview into key chord: `bindkey -s '^e' 'nvim $(fzf --preview "bat --color=always {}")\n'` (uses `bat` for syntax-highlighted preview)
- add the following formulae to public `[]`:
  - **bat** (syntax-highlighted cat; powers fzf preview)
  - **eza** (modern ls; replaces exa)
  - **fd** (modern find)
  - **git-delta** (syntax-highlighted git diffs)
  - **zsh-autosuggestions** (qol plugin)
  - **zsh-syntax-highlighting** (qol plugin)

#### Aliases split (three-repo model)

##### Public `[]` (dotfiles)

Navigation: `.., ..., ...., ...., -=cd -, mkdir -p, ln -v, reload, path, week, localip, e=$EDITOR, v=$VISUAL`
File ops: `c (trim+pbcopy), cleanup, bd, be (base64), map=xargs -n1, hd, md5sum, sha1sum`
Git: gpl, gps, gp, gc, gca, gs, gd, gco, gb, gsa, gsl, gss, gsp, gsu
Kube (generic): `k='kubectl '`
Listing: ll, lsl, lsd, lsf, ls=eza
macOS niceties: flush, lscleanup, hidedesktop, showdesktop, emptytrash
Misc: sudo (trailing space), afk (alias + script), yqs
Functions: mkd, fs, diff (git-diff colored), open/o, tre, killport (typo-fixed)

##### Personal `[personal]` (dotfiles-private)

Path shortcuts: `d=cd ~/Documents, dl=cd ~/Downloads, dof=cd ~/code/personal/dotfiles, rep=cd ~/code`

##### Work `[work]` (work overlay)

Path shortcuts for the work ops directory tree
Login: `awsl='aws sso login --profile <work-profile>'`
Function: `k8s_get_decoded_secret` (work-flavoured kubectl helper)
From vault `.zshenv`: work cluster-login alias, work directory shortcut
Env: work-side kubectl/AWS env (Bitwarden-rendered + plain env respectively)

##### Drop

- `airport` (broken on Sequoia)
- `urlencode` (Python 2 syntax)
- HTTP method aliases (GET/HEAD/POST/PUT/DELETE/TRACE/OPTIONS via lwp-request -- niche)
- `commit='bash ~/bin/commit.sh'` (replaced by /commit Claude Code skill)
- `stern='kubectl stern '` (stern dropped)
- `krew='kubectl krew '` (specialized; can recreate if needed)
- the `afk()` function in .functions (duplicate of the `alias afk='osascript ~/.bin/afk'` shorter version; keep the alias path)
- `clr='clear'` (use Ctrl-L)

---

## macOS defaults

**Out of scope for Discovery (M2)** per Discovery PRD §2 -- a full
`defaults read` dump produces hundreds of pages and isn't useful as
inventory.

**Phase 3 territory:** umbrella PRD §3 schedules macOS defaults +
Touch ID sudo + doctor. Phase 3 will define a curated `defaults.sh`
(small set of explicit `defaults write` commands), idempotent, applied
during bootstrap.

Where it'll live in the three-repo model:
- **Public dotfiles**: `defaults.sh` with non-sensitive system prefs
  (Finder, Dock, Trackpad, Screenshots, Keyboard repeat, etc.)
- **dotfiles-private**: personal-only overrides if any
- **work overlay**: employer-mandated tweaks if IT requires any

Action item before Phase 3: when ready, walk current preferences
manually and curate the list. Don't try to capture everything; pick
what actually matters.

---

## Items I missed in earlier passes (catching now)

- **minikube** (formula) -> `[personal]` (same role as kind: local k8s clusters; if kind suffices, drop. Recommend keeping one; pick kind unless minikube has a feature you rely on.)
- **discord** (cask) -> `[personal]` (personal IM)
- **kreya** (cask) -> `[work]` (was kept under "I want to retire eventually" but currently in active gRPC use; cask `kreya` exists for auto-install; replaces the manual app entry)

---

## M2.T04 dotfiles audit (signed off)

| File | Decision | Destination | Notes |
|---|---|---|---|
| .macos (763 lines) | re-fetch upstream + re-curate | dotfiles/defaults.sh | Phase 3: pull current mathiasbynens/dotfiles `.macos`, then re-apply our curated subset on top (better than line-by-line modernizing the 2022 fork). |
| Brewfile | drop | - | drifted (94 lines vs 81 leaves); inventory model replaces |
| Brewfile.lock.json | drop | - | regenerated by brew bundle |
| .gitconfig | port + template-ify | public + personal + work overlays' chezmoi tmpl | switch gpg signing to gpg.format=ssh per Q-PARENT-4; user/email block machine-conditional |
| .gitignore (global) | port | dotfiles dot_gitignore.tmpl | macOS noise |
| .gitmessage | port | dotfiles dot_gitmessage | conventional commit template |
| .gitmodules | drop | - | dotbot + NvChad submodules removed |
| .config/nvim/ (15 files + NvChad submodule) | drop entirely | - | switching to kickstart.nvim per PRD section 4 |
| .config/starship.toml (195 lines) | port + Catppuccin-modernize | dotfiles | confirm Catppuccin palette compat |
| .config/kitty/kitty.conf + session.default | drop | - | kitty replaced by ghostty |
| .config/gh/config.yml | drop | - | gh re-auths fresh per machine |
| .k9s/skin.yml (114 lines) | drop | - | use official Catppuccin/k9s skin |
| .krew/krewfile (ctx, krew, neat, ns, stern, relay, hns, allctx) | port -> work overlay | work k8s plugins | drop stern; relay/hns/allctx work-flavoured |
| .tmux.conf (108 lines) | port + Catppuccin-modernize | dotfiles | per PRD section 4 |
| .vimrc (4 lines) | drop | - | neovim primary |
| .bin/afk (2 lines) | port | dotfiles bin/afk | osascript screen lock; used by `afk` alias |
| .bin/replace_uuid.sh | drop | - | depends on ossp-uuid (skipped) |
| README.md | replace | dotfiles README.md (rewritten) | new structure |
| LICENSE.md (MIT) | keep | dotfiles | required for OSS public repo |
| bootstrap/homebrew/install.sh | drop | - | Phase 0 bootstrap replaces |
| bootstrap/krew/install.sh | drop | - | Phase 1 territory |
| bootstrap/tpm/install (0 bytes) | drop | - | empty stub |
| dotbot/ submodule | drop | - | chezmoi replaces |
| install + install.conf.yaml | drop | - | dotbot entry/config |
| nvim.bak/chadrc.lua | drop | - | old NvChad backup |
| certs.zip (work TLS material) | drop from dotfiles | user manages out-of-band | NOT in any repo |
| .zsh/, .zshrc, .zprofile | port (split + cleanup) | public + personal + work overlays | per zsh review section above |

### .macos approach (Phase 3)

Don't port the existing 2022 `.macos` line-by-line. Instead:
1. Pull the current `.macos` from upstream (mathiasbynens/dotfiles or
   a similar maintained source) -- it'll already have Sequoia-correct
   keys and "System Settings" naming.
2. Re-apply our curated subset on top (the choices we cared about in
   2022: scrollbars Always, save panel expanded, dock animations, etc.).
3. Drop the "Yosemite" / "El Capitan" era cruft; target macOS >= 15.

### .gitconfig templating (chezmoi)

Per-machine `[user]` block: `name` and `email` come from chezmoi prompts
(`personal` vs `work`), so the template branches on `.machine`. SSH
commit signing (`gpg.format = ssh`, `signingkey = <ssh-pub-key-path>`,
`commit.gpgsign = true`) is unconditional. Phase 0 generates the
ed25519 key; Phase 1 wires it into git config via chezmoi tmpl.

---

## Decisions resolved (final pass)

- **gnupg + pinentry-mac**: declare as `[]` public formulae. Useful
  safety net even if SOPS migrates to age and signing moves to SSH.
- **kubernetes-cli (kubectl)**: declare as `[]` public formula. Don't
  rely on it being a transitive dep of helm/k9s.
- **JDK via mise**: consistent with mise-everywhere direction. Add to
  mise.yaml under the optional java/work bucket (e.g., `temurin-21`
  LTS). Fall back to `temurin` cask if mise's Java support causes
  friction.

## Open follow-ups (not blocking inventory generation)

- **`certs.zip` rotation cadence**: not in dotfiles per user; tracked
  out-of-band. Note: if these are TLS certs that expire, rotation
  may need a calendar reminder.
- **GPG keys archive**: action item to securely back up the 30+
  work tenant/env GPG keys before wiping the current machine
  (Bitwarden Send, encrypted volume, or 1Password vault). See vault
  section above.
- **3 secrets in `.zshenv` to rotate**: 2 GitHub PATs and the vSphere
  password; rotate after migrating values to Bitwarden. See vault
  section above.

## mise versions (resolved, final)

```yaml
# inventory/mise.yaml
tools:
  go:
    versions: ["1.26", "1.25", "1.24"]   # newest first
    in_use: "1.26"
    tags: []

  node:
    versions: ["24", "22"]               # 24 = current LTS Krypton (since Oct 2025); 22 = previous LTS Jod
    in_use: "24"
    tags: []

  python:
    versions: ["3.14", "3.11"]           # 3.14 = current stable; 3.11 = pinned for specific projects
    in_use: "3.14"
    tags: []

  java:
    versions: ["temurin-21"]             # 21 = current LTS
    in_use: "temurin-21"
    tags: [optional, java, work]

  rust:
    versions: ["latest"]                 # mise resolves to latest stable (e.g., 1.85+)
    in_use: "latest"
    tags: []
```

Notes:
- 3.9 and 3.10 dropped (replaced by 3.14 + 3.11).
- Rust managed via mise (replacing direct rustup); existing `~/.cargo/bin` in PATH still useful for `cargo install`-installed tools.
- mise picks latest patch within each minor (so "1.26" -> 1.26.3 etc).
- Java only installed when [optional, java, work] bucket is activated.

mise resolves "1.24" to the latest 1.24.x patch (so 1.24.10 or
whatever's current); pin to full patch versions only when reproducing
a specific build. Currently installed on this machine for reference:
- Node via nvm: v22.17.0, v24.13.0
- Python via brew: 3.9, 3.10, 3.11, 3.12, 3.13, 3.14 (most transitive)
- Go via brew: 1.25.7 (and a manual install at /usr/local/go)
- Latest Go release as of 2026-05-09: 1.26.3

---

## Final tally (M2.T02 + M2.T03)

| Bucket | Count |
|---|---|
| Public `[]` | 51 formulae + 11 casks + 2 mas = 64 items |
| Personal `[personal]` | 2 formulae + 7 casks = 9 items |
| Work `[work]` | 8 formulae + 6 casks + 2 mas = 16 items |
| Optional `[optional, ...]` | 6 formulae + 9 casks = 15 items |
| Manual | 5 apps |
| Skip | 21 formulae + 7 casks + 1 mas + 11 manual apps + 7 taps = 47 items |
| Replaced (via cask additions) | 6 new casks (protonvpn, aws-vpn-client, microsoft-office, work chat, multiviewer-for-f1, qgis, obsidian, qmk-toolbox, orbstack, docker) |
