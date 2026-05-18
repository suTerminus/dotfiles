#!/usr/bin/env bash
# scripts/doctor.sh -- standalone read-only sweep across all phases (P3-40).
#
# Read-only contract (Phase 3 PRD §8):
#   This script never modifies state; never elevates privileges; never
#   installs packages; never clones repos. Every probe is a read-only
#   operation. Verify with:
#       grep -E 'sudo|defaults write|brew install|git clone' scripts/doctor.sh
#   That command must return no matches outside this contract block.
#
# Output (Phase 3 PRD §8):
#   Three columns: status, phase, item. Status is one of
#   [ok] / [drift] / [missing] / [skip]. Footer counts non-ok rows and
#   suggests a remediation invocation naming the failing steps.
#
# Exit code:
#   0 if every row is [ok] (or [skip], which is treated as non-failing).
#   Otherwise the count of [drift] + [missing] rows, capped at 255.
#
# Usage:
#   scripts/doctor.sh
#
# Invariants:
#   - bash -n clean.
#   - No mutating commands. The verification grep above is part of CI.

set -uo pipefail
# Note: we intentionally do not `set -e`. The doctor must keep probing
# even when individual probes fail; failure is reported per row, not by
# aborting the run.

# ---------------------------------------------------------------------------
# Bootstrap: locate ourselves and source the shared libs.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
INVENTORY_DIR="${REPO_ROOT}/inventory"

# log.sh and idempotent.sh ship with Phase 1; doctor depends on them.
# shellcheck source=lib/log.sh
. "${LIB_DIR}/log.sh"
# shellcheck source=lib/idempotent.sh
. "${LIB_DIR}/idempotent.sh"

# macos.sh is being authored in parallel by HMS Indomitable (P3 squadron).
# Tolerate its absence: probes that need it emit [skip] rows instead of
# failing the doctor.
HAVE_MACOS_LIB=0
if [ -f "${LIB_DIR}/macos.sh" ]; then
  # shellcheck source=lib/macos.sh
  . "${LIB_DIR}/macos.sh"
  HAVE_MACOS_LIB=1
fi

# ---------------------------------------------------------------------------
# Row accumulator + remediation hint set.
# ---------------------------------------------------------------------------

# Each element is a TSV-encoded "STATUS\tPHASE\tITEM" string. We render
# them at the end as a padded three-column table.
ROWS=()
# Set of step IDs whose probes failed. Joined into the footer hint.
FAILING_STEPS=()

row() {
  # row STATUS PHASE ITEM
  ROWS+=("$1"$'\t'"$2"$'\t'"$3")
}

mark_step() {
  # mark_step STEP_ID  -- record once.
  local step="$1"
  local existing
  for existing in "${FAILING_STEPS[@]:-}"; do
    [ "$existing" = "$step" ] && return 0
  done
  FAILING_STEPS+=("$step")
}

# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------

# yaml_keys FILE TOP_KEY  -- emit one line per child mapping under TOP_KEY.
# Falls back to a yq probe when yq exists; otherwise returns 1 so the
# caller can emit a [skip] row.
yaml_keys() {
  local file="$1" top="$2"
  [ -f "$file" ] || return 1
  command -v yq >/dev/null 2>&1 || return 1
  yq -r ".${top} | keys | .[]" "$file" 2>/dev/null
}

# yaml_count FILE JQ_PATH  -- emit the integer length of a sequence.
yaml_count() {
  local file="$1" path="$2"
  [ -f "$file" ] || { printf '0'; return 1; }
  command -v yq >/dev/null 2>&1 || { printf '0'; return 1; }
  yq -r "${path} | length" "$file" 2>/dev/null || { printf '0'; return 1; }
}

# yaml_field FILE JQ_PATH  -- emit a scalar field, empty string on miss.
yaml_field() {
  local file="$1" path="$2"
  [ -f "$file" ] || return 1
  command -v yq >/dev/null 2>&1 || return 1
  yq -r "${path}" "$file" 2>/dev/null
}

# is_work_machine  -- best-effort heuristic. Work machines have a
# work chezmoi overlay or a work brewfile. Personal otherwise.
# (The bare "enersis" suffix in the paths below is the literal disk
# layout the private work overlay uses on this author's machine; the
# probe is structural and the names don't change anything publicly.)
is_work_machine() {
  [ -d "${HOME}/.local/share/chezmoi-enersis" ] && return 0
  [ -f "${HOME}/.config/brew/Brewfile.enersis" ] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Phase 0 probes.
# ---------------------------------------------------------------------------

probe_phase0() {
  local marker="${HOME}/.local/state/macbook-setup/.phase0-complete"
  if [ -f "$marker" ]; then
    row "[ok]" "P0" "phase0 marker present"
  else
    row "[missing]" "P0" "phase0 marker missing (${marker})"
    mark_step "P0"
  fi

  if command -v brew >/dev/null 2>&1; then
    row "[ok]" "P0" "homebrew present"
  else
    row "[missing]" "P0" "homebrew not on PATH"
    mark_step "P0-20"
  fi

  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      row "[ok]" "P0" "gh auth status clean"
    else
      row "[drift]" "P0" "gh auth status not clean"
      mark_step "P0-40"
    fi
  else
    row "[missing]" "P0" "gh not installed"
    mark_step "P0-40"
  fi

  local pubkey="${HOME}/.ssh/id_ed25519.pub"
  if [ -f "$pubkey" ]; then
    row "[ok]" "P0" "ssh ed25519 public key present"
  else
    row "[missing]" "P0" "ssh ed25519 public key missing (${pubkey})"
    mark_step "P0-40"
  fi
}

# ---------------------------------------------------------------------------
# Phase 1 probes.
# ---------------------------------------------------------------------------

probe_phase1() {
  # chezmoi diff (public) empty.
  if command -v chezmoi >/dev/null 2>&1; then
    local out
    out="$(chezmoi diff 2>/dev/null || true)"
    if [ -z "$out" ]; then
      row "[ok]" "P1" "chezmoi diff empty (public)"
    else
      row "[drift]" "P1" "chezmoi diff non-empty (public)"
      mark_step "P1-10"
    fi
  else
    row "[skip]" "P1" "chezmoi not on PATH"
  fi

  # brew bundle check against the public Brewfile.
  local brewfile="${HOME}/.config/brew/Brewfile"
  if command -v brew >/dev/null 2>&1 && [ -f "$brewfile" ]; then
    if brew bundle check --file="$brewfile" >/dev/null 2>&1; then
      row "[ok]" "P1" "brew bundle check (public) passes"
    else
      row "[drift]" "P1" "brew bundle drift (public)"
      mark_step "P1-30"
    fi
  else
    row "[skip]" "P1" "brew bundle (public): brew or Brewfile absent"
  fi

  # mise tools.
  local mise_yaml="${INVENTORY_DIR}/mise.yaml"
  if [ -f "$mise_yaml" ] && command -v yq >/dev/null 2>&1; then
    local tool
    while IFS= read -r tool; do
      [ -n "$tool" ] || continue
      local in_use tags_csv apply
      in_use="$(yaml_field "$mise_yaml" ".tools.${tool}.in_use")"
      tags_csv="$(yaml_field "$mise_yaml" ".tools.${tool}.tags | join(\",\")")"
      apply=1
      case ",${tags_csv}," in
        *,work,*)     is_work_machine || apply=0 ;;
        *,personal,*) is_work_machine && apply=0 ;;
        *,optional,*) apply=0 ;;
      esac
      if [ "$apply" -eq 0 ]; then
        row "[skip]" "P1" "mise tool ${tool}: tags=${tags_csv:-none}"
        continue
      fi
      if probe_mise_tool "$tool" "$in_use"; then
        row "[ok]" "P1" "mise current ${tool} matches ${in_use}"
      else
        row "[drift]" "P1" "mise current ${tool} != ${in_use}"
        mark_step "P1-40"
      fi
    done < <(yaml_keys "$mise_yaml" "tools" || true)
  else
    row "[skip]" "P1" "mise.yaml or yq absent"
  fi

  # uv python_tools (optional inventory).
  local uv_yaml="${INVENTORY_DIR}/python-tools.yaml"
  if [ -f "$uv_yaml" ] && command -v yq >/dev/null 2>&1; then
    local pkg
    while IFS= read -r pkg; do
      [ -n "$pkg" ] || continue
      if probe_uv_tool "$pkg"; then
        row "[ok]" "P1" "uv tool ${pkg} present"
      else
        row "[drift]" "P1" "uv tool ${pkg} missing"
        mark_step "P1-40"
      fi
    done < <(yq -r '.python_tools[].name' "$uv_yaml" 2>/dev/null || true)
  else
    row "[skip]" "P1" "python-tools.yaml absent (no uv tools declared)"
  fi

  # repos.
  local repos_yaml="${INVENTORY_DIR}/repos.yaml"
  if [ -f "$repos_yaml" ] && command -v yq >/dev/null 2>&1; then
    local n i
    n="$(yaml_count "$repos_yaml" '.repos')"
    i=0
    while [ "$i" -lt "$n" ]; do
      local rurl rpath rtags apply
      rurl="$(yaml_field "$repos_yaml" ".repos[$i].url")"
      rpath="$(yaml_field "$repos_yaml" ".repos[$i].path")"
      rtags="$(yaml_field "$repos_yaml" ".repos[$i].tags | join(\",\")")"
      apply=1
      case ",${rtags}," in
        *,work,*)     is_work_machine || apply=0 ;;
        *,personal,*) is_work_machine && apply=0 ;;
        *,manual,*)   apply=0 ;;
      esac
      if [ "$apply" -eq 0 ]; then
        row "[skip]" "P1" "repo ${rpath}: tags=${rtags:-none}"
        i=$((i + 1))
        continue
      fi
      local abs="${HOME}/${rpath}"
      # Normalise URL: strip github.com/ prefix tolerance handled by probe_repo_at_path.
      local url_norm="$rurl"
      case "$url_norm" in
        github.com/*) url_norm="git@github.com:${url_norm#github.com/}" ;;
      esac
      if probe_repo_at_path "$abs" "$url_norm" \
         || probe_repo_at_path "$abs" "$rurl" \
         || probe_repo_at_path "$abs" "https://${rurl}"; then
        row "[ok]" "P1" "repo ${rpath} origin matches"
      else
        row "[drift]" "P1" "repo ${rpath} missing or wrong origin"
        mark_step "P1-50"
      fi
      i=$((i + 1))
    done
  else
    row "[skip]" "P1" "repos.yaml or yq absent"
  fi
}

# ---------------------------------------------------------------------------
# Phase 2 probes.
# ---------------------------------------------------------------------------

probe_phase2() {
  # bw availability.
  if command -v bw >/dev/null 2>&1; then
    if bw status >/dev/null 2>&1; then
      row "[ok]" "P2" "bw status responds (locked or unlocked is OK)"
    else
      row "[drift]" "P2" "bw status command errored"
      mark_step "P2-20"
    fi
  else
    row "[missing]" "P2" "bw CLI not installed"
    mark_step "P2-20"
  fi

  # private overlay diff.
  local priv_src="${HOME}/.local/share/chezmoi-private"
  if command -v chezmoi >/dev/null 2>&1 && [ -d "$priv_src" ]; then
    local out
    out="$(chezmoi diff --source "$priv_src" 2>/dev/null || true)"
    if [ -z "$out" ]; then
      row "[ok]" "P2" "chezmoi diff empty (private)"
    else
      row "[drift]" "P2" "chezmoi diff non-empty (private)"
      mark_step "P2-10"
    fi
  else
    row "[skip]" "P2" "private overlay or chezmoi absent"
  fi

  # work overlay (work-machine only).
  local ent_src="${HOME}/.local/share/chezmoi-enersis"
  if is_work_machine; then
    if command -v chezmoi >/dev/null 2>&1 && [ -d "$ent_src" ]; then
      local out
      out="$(chezmoi diff --source "$ent_src" 2>/dev/null || true)"
      if [ -z "$out" ]; then
        row "[ok]" "P2" "chezmoi diff empty (work)"
      else
        row "[drift]" "P2" "chezmoi diff non-empty (work)"
        mark_step "P2-12"
      fi
    else
      row "[drift]" "P2" "work machine missing work overlay"
      mark_step "P2-12"
    fi
  else
    if [ -d "$ent_src" ]; then
      row "[drift]" "P2" "work overlay present on personal machine"
      mark_step "P2-12"
    else
      row "[skip]" "P2" "work overlay (personal machine, not expected)"
    fi
  fi

  # Brewfile.personal.
  local bf_pers="${HOME}/.config/brew/Brewfile.personal"
  if command -v brew >/dev/null 2>&1 && [ -f "$bf_pers" ]; then
    if brew bundle check --file="$bf_pers" >/dev/null 2>&1; then
      row "[ok]" "P2" "brew bundle check (personal) passes"
    else
      row "[drift]" "P2" "brew bundle drift (personal)"
      mark_step "P2-30"
    fi
  else
    row "[skip]" "P2" "Brewfile.personal absent"
  fi

  # Brewfile.enersis (work only).
  local bf_ent="${HOME}/.config/brew/Brewfile.enersis"
  if is_work_machine; then
    if command -v brew >/dev/null 2>&1 && [ -f "$bf_ent" ]; then
      if brew bundle check --file="$bf_ent" >/dev/null 2>&1; then
        row "[ok]" "P2" "brew bundle check (work) passes"
      else
        row "[drift]" "P2" "brew bundle drift (work)"
        mark_step "P2-32"
      fi
    else
      row "[drift]" "P2" "Brewfile.work absent on work machine"
      mark_step "P2-32"
    fi
  else
    row "[skip]" "P2" "Brewfile.work (personal machine, not expected)"
  fi
}

# ---------------------------------------------------------------------------
# Phase 3 probes.
# ---------------------------------------------------------------------------

# probe_default DOMAIN KEY TYPE EXPECTED  -- compare current value to expected.
# Uses `defaults read` (read-only). Returns:
#   0 if match, 1 if drift/missing.
probe_default() {
  local domain="$1" key="$2" type="$3" expected="$4"
  command -v defaults >/dev/null 2>&1 || return 2
  local current
  if ! current="$(defaults read "$domain" "$key" 2>/dev/null)"; then
    return 1
  fi
  case "$type" in
    bool)
      # `defaults read` prints 0 or 1 for booleans.
      local exp_norm cur_norm
      case "$expected" in true|1|YES) exp_norm=1 ;; *) exp_norm=0 ;; esac
      case "$current" in 1) cur_norm=1 ;; *) cur_norm=0 ;; esac
      [ "$exp_norm" = "$cur_norm" ]
      ;;
    int)
      [ "$current" = "$expected" ]
      ;;
    string)
      [ "$current" = "$expected" ]
      ;;
    array|dict)
      # Structural compare requires the macos.sh helpers; if absent, fall
      # back to substring presence as a weak heuristic.
      if [ "$HAVE_MACOS_LIB" -eq 1 ] && declare -f macos_compare_complex >/dev/null 2>&1; then
        macos_compare_complex "$domain" "$key" "$type" "$expected"
      else
        # Empty array/dict: defaults read prints "( )" or "{ }" with whitespace.
        case "$expected" in
          "[]"|"") printf '%s' "$current" | tr -d '[:space:]' | grep -qE '^\(\)$' ;;
          "{}")    printf '%s' "$current" | tr -d '[:space:]' | grep -qE '^\{\}$' ;;
          *)       return 2 ;;  # cannot compare without helper
        esac
      fi
      ;;
    *)
      return 2
      ;;
  esac
}

probe_phase3() {
  # macos defaults.
  local md_yaml="${INVENTORY_DIR}/macos-defaults.yaml"
  if [ -f "$md_yaml" ] && command -v yq >/dev/null 2>&1 && command -v defaults >/dev/null 2>&1; then
    local n i
    n="$(yaml_count "$md_yaml" '.defaults')"
    i=0
    while [ "$i" -lt "$n" ]; do
      local d k t v
      d="$(yaml_field "$md_yaml" ".defaults[$i].domain")"
      k="$(yaml_field "$md_yaml" ".defaults[$i].key")"
      t="$(yaml_field "$md_yaml" ".defaults[$i].type")"
      v="$(yaml_field "$md_yaml" ".defaults[$i].value")"
      probe_default "$d" "$k" "$t" "$v"
      case $? in
        0) row "[ok]"      "P3" "macos-default: ${k} (${d})" ;;
        1) row "[missing]" "P3" "macos-default: ${k} drift (expected=${v})"
           mark_step "P3-00" ;;
        2) row "[skip]"    "P3" "macos-default: ${k} (helper unavailable)" ;;
      esac
      i=$((i + 1))
    done
  else
    row "[skip]" "P3" "macos-defaults.yaml, yq, or defaults command absent"
  fi

  # system tweaks.
  local st_yaml="${INVENTORY_DIR}/system-tweaks.yaml"
  if [ -f "$st_yaml" ] && command -v yq >/dev/null 2>&1; then
    local n i
    n="$(yaml_count "$st_yaml" '.tweaks')"
    i=0
    while [ "$i" -lt "$n" ]; do
      local name kind file line
      name="$(yaml_field "$st_yaml" ".tweaks[$i].name")"
      kind="$(yaml_field "$st_yaml" ".tweaks[$i].kind")"
      file="$(yaml_field "$st_yaml" ".tweaks[$i].file")"
      line="$(yaml_field "$st_yaml" ".tweaks[$i].line")"
      case "$kind" in
        pam-line)
          if [ -r "$file" ] && grep -F -- "$line" "$file" >/dev/null 2>&1; then
            row "[ok]" "P3" "system-tweak ${name}: line present"
          else
            row "[missing]" "P3" "system-tweak ${name}: line absent in ${file}"
            mark_step "P3-10"
          fi
          ;;
        *)
          row "[skip]" "P3" "system-tweak ${name}: unsupported kind=${kind}"
          ;;
      esac
      i=$((i + 1))
    done
  else
    row "[skip]" "P3" "system-tweaks.yaml or yq absent"
  fi

  # manual installs.
  local m_yaml="${INVENTORY_DIR}/manual.yaml"
  if [ -f "$m_yaml" ] && command -v yq >/dev/null 2>&1; then
    local n i
    n="$(yaml_count "$m_yaml" '.manual')"
    i=0
    while [ "$i" -lt "$n" ]; do
      local name dkind dval bid cmd path label tags apply
      name="$(yaml_field "$m_yaml" ".manual[$i].name")"
      dkind="$(yaml_field "$m_yaml" ".manual[$i].detection.kind")"
      tags="$(yaml_field "$m_yaml" ".manual[$i].tags | join(\",\")")"
      apply=1
      case ",${tags}," in
        *,work,*)     is_work_machine || apply=0 ;;
        *,personal,*) is_work_machine && apply=0 ;;
      esac
      if [ "$apply" -eq 0 ]; then
        row "[skip]" "P3" "manual ${name}: tags=${tags}"
        i=$((i + 1))
        continue
      fi
      local detected=1
      case "$dkind" in
        app)
          bid="$(yaml_field "$m_yaml" ".manual[$i].detection.bundle_id")"
          # Read-only: scan /Applications and ~/Applications for a matching bundle id.
          if [ "$HAVE_MACOS_LIB" -eq 1 ] && declare -f macos_app_present >/dev/null 2>&1; then
            macos_app_present "$bid" && detected=0 || detected=1
          else
            # Fallback: mdfind by bundle identifier (read-only).
            if command -v mdfind >/dev/null 2>&1 && \
               [ -n "$(mdfind "kMDItemCFBundleIdentifier == '${bid}'" 2>/dev/null)" ]; then
              detected=0
            else
              detected=1
            fi
          fi
          ;;
        command)
          cmd="$(yaml_field "$m_yaml" ".manual[$i].detection.command")"
          command -v "$cmd" >/dev/null 2>&1 && detected=0 || detected=1
          ;;
        file)
          path="$(yaml_field "$m_yaml" ".manual[$i].detection.path")"
          [ -e "$path" ] && detected=0 || detected=1
          ;;
        launchd)
          label="$(yaml_field "$m_yaml" ".manual[$i].detection.label")"
          if command -v launchctl >/dev/null 2>&1 && \
             launchctl list 2>/dev/null | grep -q -F -- "$label"; then
            detected=0
          else
            detected=1
          fi
          ;;
        *)
          row "[skip]" "P3" "manual ${name}: unknown detection kind=${dkind}"
          i=$((i + 1))
          continue
          ;;
      esac
      if [ "$detected" -eq 0 ]; then
        row "[ok]" "P3" "manual ${name} detected"
      else
        row "[missing]" "P3" "manual ${name} not detected"
        mark_step "P3-20"
      fi
      i=$((i + 1))
    done
  else
    row "[skip]" "P3" "manual.yaml or yq absent"
  fi
}

# ---------------------------------------------------------------------------
# Render + footer.
# ---------------------------------------------------------------------------

render() {
  local entry status phase item bad=0
  # First pass: compute column widths so the table aligns regardless of
  # the longest status / phase / item we end up with.
  local status_w=6 phase_w=5 item_w=4 # header minimums: STATUS / PHASE / ITEM
  for entry in "${ROWS[@]}"; do
    IFS=$'\t' read -r status phase item <<<"$entry"
    [ "${#status}" -gt "$status_w" ] && status_w=${#status}
    [ "${#phase}"  -gt "$phase_w"  ] && phase_w=${#phase}
    [ "${#item}"   -gt "$item_w"   ] && item_w=${#item}
  done

  # Header row + rule. Three columns: status | phase | item (Phase 3 PRD §8).
  printf '%-*s  %-*s  %s\n' \
    "$status_w" "STATUS" "$phase_w" "PHASE" "ITEM"
  local total_w=$((status_w + 2 + phase_w + 2 + item_w))
  local rule="" i=0
  while [ "$i" -lt "$total_w" ]; do rule="${rule}-"; i=$((i + 1)); done
  printf '%s\n' "$rule"

  # Body.
  for entry in "${ROWS[@]}"; do
    IFS=$'\t' read -r status phase item <<<"$entry"
    printf '%-*s  %-*s  %s\n' \
      "$status_w" "$status" "$phase_w" "$phase" "$item"
    case "$status" in
      "[drift]"|"[missing]") bad=$((bad + 1)) ;;
    esac
  done

  # Footer rule + summary.
  printf '%s\n' "$rule"
  if [ "$bad" -eq 0 ]; then
    printf '0 issues. All probes pass.\n'
  else
    local steps_csv=""
    if [ "${#FAILING_STEPS[@]}" -gt 0 ]; then
      local first=1 s
      for s in "${FAILING_STEPS[@]}"; do
        if [ "$first" -eq 1 ]; then steps_csv="$s"; first=0
        else steps_csv="${steps_csv},${s}"
        fi
      done
    fi
    if [ -n "$steps_csv" ]; then
      printf '%d issues. Run: scripts/setup.sh --only %s to repair.\n' \
        "$bad" "$steps_csv"
    else
      printf '%d issues. Run: scripts/setup.sh to repair.\n' "$bad"
    fi
  fi
  # Cap exit code at 255 so callers don't wrap to 0.
  if [ "$bad" -gt 255 ]; then bad=255; fi
  return "$bad"
}

# ---------------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------------

main() {
  probe_phase0
  probe_phase1
  probe_phase2
  probe_phase3
  render
}

main "$@"
