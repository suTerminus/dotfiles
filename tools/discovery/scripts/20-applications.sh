#!/usr/bin/env bash
# tools/discovery/scripts/20-applications.sh
# Snapshot installed macOS applications into installed-apps.yaml.
# Read-only, with one exception: may auto-install `mas` via brew (Q-DISC-2)
# so Mac App Store apps can be enumerated. No other system mutation.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
source "$SCRIPT_DIR/../lib/log.sh"
OUTPUT_DIR="$SCRIPT_DIR/../output"

mkdir -p "$OUTPUT_DIR"

TARGET="$OUTPUT_DIR/installed-apps.yaml"

# ---------------------------------------------------------------------------
# Apple-bundled exclusion list. Compared against basename without ".app".
# ---------------------------------------------------------------------------
APPLE_BUNDLED=(
  "Safari"
  "Mail"
  "Calendar"
  "Maps"
  "Music"
  "TV"
  "Podcasts"
  "News"
  "Stocks"
  "Voice Memos"
  "Home"
  "FaceTime"
  "Messages"
  "Photos"
  "Photo Booth"
  "Preview"
  "QuickTime Player"
  "Reminders"
  "Notes"
  "Contacts"
  "Find My"
  "Freeform"
  "Image Capture"
  "Migration Assistant"
  "TextEdit"
  "Time Machine"
  "Stickies"
  "Chess"
  "Calculator"
  "Dictionary"
  "Font Book"
  "Books"
  "Shortcuts"
  "Weather"
  "App Store"
  "Automator"
  "Launchpad"
  "Mission Control"
  "Siri"
  "System Settings"
  "System Preferences"
  "Activity Monitor"
  "AirPort Utility"
  "Audio MIDI Setup"
  "Bluetooth File Exchange"
  "Boot Camp Assistant"
  "ColorSync Utility"
  "Console"
  "Digital Color Meter"
  "Disk Utility"
  "Grapher"
  "Keychain Access"
  "Screen Sharing"
  "Screenshot"
  "Script Editor"
  "Storage Management"
  "System Information"
  "Terminal"
  "VoiceOver Utility"
)

is_apple_bundled() {
  local name="$1"
  local b
  for b in "${APPLE_BUNDLED[@]}"; do
    if [ "$name" = "$b" ]; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Q-DISC-2: auto-install mas via brew if missing (the only mutation here).
# ---------------------------------------------------------------------------
mas_available=0
if command -v mas >/dev/null 2>&1; then
  mas_available=1
elif command -v brew >/dev/null 2>&1; then
  log_info "mas not found; auto-installing via brew (Q-DISC-2)"
  if brew install --quiet mas >/dev/null 2>&1; then
    if command -v mas >/dev/null 2>&1; then
      log_ok "mas installed"
      mas_available=1
    else
      log_warn "mas install attempted but command still missing; skipping MAS detection"
    fi
  else
    log_warn "brew install mas failed; skipping MAS detection"
  fi
else
  log_skip "MAS detection: brew and mas both unavailable"
fi

# ---------------------------------------------------------------------------
# Collect cask names (lowercase) for cross-reference.
# ---------------------------------------------------------------------------
cask_names_lower=""
if command -v brew >/dev/null 2>&1; then
  if cask_raw="$(brew list --cask 2>/dev/null)"; then
    cask_names_lower="$(printf '%s\n' "$cask_raw" \
      | sed '/^[[:space:]]*$/d' \
      | LC_ALL=C tr '[:upper:]' '[:lower:]' \
      | LC_ALL=C sort -u)"
  else
    log_warn "brew list --cask failed; cask cross-reference disabled"
  fi
else
  log_skip "brew unavailable; cask cross-reference disabled"
fi

is_cask_installed() {
  # $1 = app basename without .app suffix
  [ -z "$cask_names_lower" ] && return 1
  local lname
  lname="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  if printf '%s\n' "$cask_names_lower" | LC_ALL=C grep -Fxq -- "$lname"; then
    return 0
  fi
  local lname_dash
  lname_dash="$(printf '%s' "$lname" | tr ' ' '-')"
  if [ "$lname_dash" != "$lname" ] && \
     printf '%s\n' "$cask_names_lower" | LC_ALL=C grep -Fxq -- "$lname_dash"; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Build name -> mas appid map (using a tmp file; portable for older bash).
# ---------------------------------------------------------------------------
mas_map_file=""
if [ "$mas_available" -eq 1 ]; then
  mas_map_file="$(mktemp "$OUTPUT_DIR/.mas-map.XXXXXX")"
  if mas_raw="$(mas list 2>/dev/null)"; then
    # mas list line: "<appid> <name spans many words> (<version>)"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      appid="${line%% *}"
      rest="${line#* }"
      # Strip trailing " (version)" then collapse whitespace and trim ends.
      name="$(printf '%s' "$rest" \
        | LC_ALL=C sed -E 's/[[:space:]]+\([^()]*\)[[:space:]]*$//' \
        | LC_ALL=C sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [ -z "$appid" ] && continue
      [ -z "$name" ] && continue
      lname="$(printf '%s' "$name" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
      printf '%s\t%s\n' "$lname" "$appid" >> "$mas_map_file"
    done <<< "$mas_raw"
  else
    log_warn "mas list failed; MAS detection disabled"
  fi
fi

mas_appid_for() {
  # $1 = app basename without .app
  [ -z "$mas_map_file" ] && return 1
  [ ! -s "$mas_map_file" ] && return 1
  local lname
  lname="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  local match
  match="$(LC_ALL=C awk -F '\t' -v n="$lname" '$1 == n { print $2; exit }' "$mas_map_file")"
  if [ -n "$match" ]; then
    printf '%s' "$match"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Collect candidate .app paths from /Applications and ~/Applications.
# Use null-delimited reads to handle spaces.
# ---------------------------------------------------------------------------
app_paths_file="$(mktemp "$OUTPUT_DIR/.app-paths.XXXXXX")"

collect_apps_in() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -type d -name '*.app' -print0 2>/dev/null \
    | while IFS= read -r -d '' p; do
        printf '%s\n' "$p"
      done
}

collect_apps_in "/Applications" >> "$app_paths_file"
if [ -d "$HOME/Applications" ]; then
  collect_apps_in "$HOME/Applications" >> "$app_paths_file"
fi

# Sort by basename for deterministic output.
sorted_paths_file="$(mktemp "$OUTPUT_DIR/.app-paths-sorted.XXXXXX")"
LC_ALL=C awk -F/ '{ print $NF "\t" $0 }' "$app_paths_file" \
  | LC_ALL=C sort -t$'\t' -k1,1 \
  | LC_ALL=C cut -f2- \
  > "$sorted_paths_file"

# ---------------------------------------------------------------------------
# Render entries to a buffer first so we can decide between "applications:"
# and "applications: []" without scanning twice.
# ---------------------------------------------------------------------------
entries_file="$(mktemp "$OUTPUT_DIR/.app-entries.XXXXXX")"
emitted=0

while IFS= read -r app_path; do
  [ -z "$app_path" ] && continue
  base="$(basename "$app_path")"
  name_no_ext="${base%.app}"
  if is_apple_bundled "$name_no_ext"; then
    continue
  fi

  bundle_id=""
  if bid_raw="$(mdls -raw -name kMDItemCFBundleIdentifier "$app_path" 2>/dev/null)"; then
    if [ "$bid_raw" != "(null)" ] && [ -n "$bid_raw" ]; then
      bundle_id="$bid_raw"
    fi
  fi

  version=""
  if v_raw="$(defaults read "$app_path/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)"; then
    version="$v_raw"
  fi

  source_kind="manual"
  appid=""
  if [ -z "$bundle_id" ]; then
    source_kind="unknown"
  elif is_cask_installed "$name_no_ext"; then
    source_kind="brew-cask"
  elif maybe_appid="$(mas_appid_for "$name_no_ext")"; then
    source_kind="mas"
    appid="$maybe_appid"
  fi

  {
    if [ "$emitted" -gt 0 ]; then
      printf '\n'
    fi
    printf '  - name: %s\n' "$base"
    printf '    bundle_id: "%s"\n' "$bundle_id"
    printf '    source: %s\n' "$source_kind"
    if [ "$source_kind" = "mas" ]; then
      printf '    appid: "%s"\n' "$appid"
    fi
    printf '    version: "%s"\n' "$version"
    printf '    tags: [TODO]\n'
  } >> "$entries_file"

  emitted=$((emitted + 1))
done < "$sorted_paths_file"

# ---------------------------------------------------------------------------
# Render final YAML to a tmp file then atomic mv.
# ---------------------------------------------------------------------------
tmp="$(mktemp "$OUTPUT_DIR/.installed-apps.yaml.XXXXXX")"
{
  printf '%s\n' '# Generated by tools/discovery/scripts/20-applications.sh'
  printf '%s\n' '# Sources: brew-cask, mas, manual, unknown.'
  printf '%s\n' '# Apple-bundled apps excluded.'
  printf '\n'
  if [ "$emitted" -eq 0 ]; then
    printf '%s\n' 'applications: []'
  else
    printf '%s\n' 'applications:'
    cat "$entries_file"
  fi
} > "$tmp"

mv "$tmp" "$TARGET"

# Cleanup tmp helper files.
rm -f "$app_paths_file" "$sorted_paths_file" "$entries_file"
[ -n "$mas_map_file" ] && rm -f "$mas_map_file"

log_ok "wrote $TARGET (apps=$emitted)"
