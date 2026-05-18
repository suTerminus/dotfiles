#!/usr/bin/env bash
set -euo pipefail

# Step: P3-10-system-tweaks
# Idempotency probe (per-entry):
#   For each entry of `kind: pam-line` in inventory/system-tweaks.yaml,
#   `grep -F "<line>" <file>` exits 0. The v1 entry is the Touch ID
#   line in /etc/pam.d/sudo_local.
#
# When a tweak is missing AND `sudo: true`:
#   - dry-run: log `would: append <line> to <file> (sudo)`.
#   - real:   require_tty_stdin (sudo prompt may need it), `sudo -v` to
#             pre-cache, then `printf ... | sudo tee -a "<file>" >/dev/null`.
#             Re-probe; fail loudly if still missing.
#
# Touch ID for sudo takes effect on the NEXT shell session, not the
# current one. We log this so the user isn't surprised when their
# very next `sudo` in the same window still asks for a password.
#
# Tolerates inventory/system-tweaks.yaml being absent (HMS Faithful
# authors it in parallel) — logs `warn` and exits 0.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
# shellcheck source=../lib/log.sh
. "$LIB_DIR/log.sh"
# shellcheck source=../lib/idempotent.sh
. "$LIB_DIR/idempotent.sh"
# shellcheck source=../lib/macos.sh
. "$LIB_DIR/macos.sh"

step_name="P3-10-system-tweaks"

REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
INVENTORY_FILE="$REPO_ROOT/inventory/system-tweaks.yaml"

# Flags. Also honour PHASE1_FORCE from the orchestrator's --force flag.
FORCE="${PHASE1_FORCE:-0}"
NAME_FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force|-f)   FORCE=1; shift ;;
    --name)       NAME_FILTER="$2"; shift 2 ;;
    --name=*)     NAME_FILTER="${1#--name=}"; shift ;;
    -h|--help)
      cat <<EOF
Usage: $step_name [flags]
  --force, -f       Re-apply every tweak (skip the probe-then-act guard).
                    Also activated by PHASE1_FORCE=1 from setup.sh --force.
  --name <name>     Only act on the tweak whose `name:` field matches.
                    Useful after editing one entry in inventory/system-tweaks.yaml.
EOF
      exit 0 ;;
    *) error "$step_name: unknown flag: $1"; exit 2 ;;
  esac
done

if [ ! -r "$INVENTORY_FILE" ]; then
  warn "$step_name: inventory/system-tweaks.yaml not found; skipping P3-10"
  exit 0
fi

if ! require_command yq "$step_name: yq required to parse inventory/system-tweaks.yaml"; then
  exit 1
fi

# --------------------------------------------------------------------
# Parse tweaks. We project each entry to a tab-separated row:
#   name<TAB>kind<TAB>file<TAB>line<TAB>sudo
# Booleans render as `true`/`false`. Missing fields render as empty.
# --------------------------------------------------------------------
NAMES=()
KINDS=()
FILES=()
LINES=()
SUDOS=()
PROBES=()
CMDS=()

# `` (unit separator) survives shell expansion better than \t when
# the YAML values contain shell metacharacters in `probe`/`cmd`.
n_total="$(yq '[.tweaks[]] | length' "$INVENTORY_FILE" 2>/dev/null || echo 0)"
__i=0
while [ "$__i" -lt "$n_total" ]; do
  name="$(yq -r ".tweaks[$__i].name // \"\"" "$INVENTORY_FILE" 2>/dev/null)"
  [ -n "$name" ] || { __i=$((__i + 1)); continue; }
  NAMES+=("$name")
  KINDS+=("$(yq -r ".tweaks[$__i].kind // \"\"" "$INVENTORY_FILE" 2>/dev/null)")
  FILES+=("$(yq -r ".tweaks[$__i].file // \"\"" "$INVENTORY_FILE" 2>/dev/null)")
  LINES+=("$(yq -r ".tweaks[$__i].line // \"\"" "$INVENTORY_FILE" 2>/dev/null)")
  SUDOS+=("$(yq -r ".tweaks[$__i].sudo // false" "$INVENTORY_FILE" 2>/dev/null)")
  PROBES+=("$(yq -r ".tweaks[$__i].probe // \"\"" "$INVENTORY_FILE" 2>/dev/null)")
  CMDS+=("$(yq -r ".tweaks[$__i].cmd // \"\"" "$INVENTORY_FILE" 2>/dev/null)")
  __i=$((__i + 1))
done
unset __i n_total

n="${#NAMES[@]}"
if [ "$n" -eq 0 ]; then
  info "$step_name: inventory has zero tweaks; nothing to do"
  exit 0
fi

failures=0
applied=0
sudo_primed=0

i=0
while [ "$i" -lt "$n" ]; do
  name="${NAMES[$i]}"
  kind="${KINDS[$i]}"
  file="${FILES[$i]}"
  line="${LINES[$i]}"
  needs_sudo="${SUDOS[$i]}"

  probe="${PROBES[$i]}"
  cmd="${CMDS[$i]}"

  # --name narrows action to one tweak.
  if [ -n "$NAME_FILTER" ] && [ "$name" != "$NAME_FILTER" ]; then
    i=$((i + 1)); continue
  fi

  case "$kind" in
    pam-line) ;;
    shell-cmd)
      # shell-cmd kind: probe-then-act with arbitrary shell.
      if [ -z "$probe" ] || [ -z "$cmd" ]; then
        error "$step_name: $name: shell-cmd kind requires both 'probe' and 'cmd' fields"
        failures=$((failures + 1))
        i=$((i + 1))
        continue
      fi

      # Probe (skipped under --force).
      if [ "$FORCE" -ne 1 ] && eval "$probe" >/dev/null 2>&1; then
        skip "$step_name: $name already satisfied"
        i=$((i + 1))
        continue
      fi

      if is_dry_run; then
        if [ "$needs_sudo" = "true" ]; then
          info "would: sudo $cmd"
        else
          info "would: $cmd"
        fi
        i=$((i + 1))
        continue
      fi

      # Prime sudo if needed.
      if [ "$needs_sudo" = "true" ] && [ "$sudo_primed" -eq 0 ]; then
        if ! require_tty_stdin "$step_name: stdin is not a TTY; sudo prompt for $name needs an interactive terminal"; then
          exit 2
        fi
        info "$step_name: a sudo password prompt is about to appear (priming credentials)"
        if ! sudo -v; then
          error "$step_name: sudo -v failed; cannot apply $name"
          exit 1
        fi
        sudo_primed=1
      fi

      info "$step_name: applying $name: $cmd"
      if [ "$needs_sudo" = "true" ]; then
        if ! sudo bash -c "$cmd"; then
          error "$step_name: $name: command exited non-zero"
          failures=$((failures + 1))
          i=$((i + 1))
          continue
        fi
      else
        if ! bash -c "$cmd"; then
          error "$step_name: $name: command exited non-zero"
          failures=$((failures + 1))
          i=$((i + 1))
          continue
        fi
      fi

      # Re-probe.
      if eval "$probe" >/dev/null 2>&1; then
        ok "$step_name: $name applied"
        applied=$((applied + 1))
      else
        error "$step_name: $name: command ran but re-probe still fails"
        failures=$((failures + 1))
      fi

      i=$((i + 1))
      continue
      ;;
    *)
      warn "$step_name: $name: unsupported kind \"$kind\"; skipping"
      i=$((i + 1))
      continue
      ;;
  esac

  # ---- pam-line below ----

  # Probe: is the line already present? grep -F treats <line> literally.
  # Skipped under --force (we'll still avoid double-appending below).
  if [ "$FORCE" -ne 1 ] && [ -r "$file" ] && grep -F -- "$line" "$file" >/dev/null 2>&1; then
    skip "$step_name: $name already present"
    i=$((i + 1))
    continue
  fi

  if is_dry_run; then
    if [ "$needs_sudo" = "true" ]; then
      info "would: append $line to $file (sudo)"
    else
      info "would: append $line to $file"
    fi
    i=$((i + 1))
    continue
  fi

  if [ "$needs_sudo" = "true" ]; then
    # Pre-cache sudo credentials once per step run, with a TTY guard.
    if [ "$sudo_primed" -eq 0 ]; then
      if ! require_tty_stdin "$step_name: stdin is not a TTY; sudo prompt for $name needs an interactive terminal"; then
        exit 2
      fi
      info "$step_name: a sudo password prompt is about to appear (priming credentials)"
      if ! sudo -v; then
        error "$step_name: sudo -v failed; cannot apply $name"
        exit 1
      fi
      sudo_primed=1
    fi

    # Ensure the file exists (root-owned, mode 0644) before appending.
    # On Sequoia /etc/pam.d/sudo_local exists by default but may not on
    # older systems; tolerate either case.
    if [ ! -e "$file" ]; then
      info "$step_name: $file does not exist; creating empty file"
      if ! sudo install -m 0644 -o root /dev/null "$file" 2>/dev/null; then
        # Fallback: touch + chmod via sudo.
        sudo touch "$file"
        sudo chmod 0644 "$file"
      fi
    fi

    if ! printf '%s\n' "$line" | sudo tee -a "$file" >/dev/null; then
      error "$step_name: $name: append via sudo tee failed"
      failures=$((failures + 1))
      i=$((i + 1))
      continue
    fi
  else
    if ! printf '%s\n' "$line" >> "$file"; then
      error "$step_name: $name: append failed"
      failures=$((failures + 1))
      i=$((i + 1))
      continue
    fi
  fi

  # Re-probe.
  if grep -F -- "$line" "$file" >/dev/null 2>&1; then
    ok "$step_name: $name applied"
    applied=$((applied + 1))
    if [ "$name" = "touch-id-sudo" ]; then
      info "$step_name: Touch ID for sudo takes effect on the NEXT shell session, not this one"
    fi
  else
    error "$step_name: $name: append succeeded but probe still fails"
    failures=$((failures + 1))
  fi

  i=$((i + 1))
done

if [ "$failures" -gt 0 ]; then
  error "$step_name: $failures tweak(s) failed"
  exit 1
fi

if [ "$applied" -eq 0 ]; then
  skip "$step_name: all tweaks already in place"
else
  ok "$step_name: applied $applied tweak(s)"
fi
exit 0
