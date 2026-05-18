# scripts/lib/macos.sh
# Shared macOS-specific helpers for Phase 3 steps:
#   - typed `defaults` read / write / compare
#   - deduplicated `killall` queue (so writes to many keys in one
#     domain only refresh the affected app once at end-of-pass)
#   - manual-install detection per `kind` (app / command / file / launchd)
#
# Lives in scripts/lib/ alongside log.sh and idempotent.sh and uses the
# same Phase 1 source-guard convention; Phase 3 steps source it via
# SCRIPT_DIR/lib/macos.sh.
#
# Safe to source multiple times.

if [ -n "${__PHASE1_MACOS_SH:-}" ]; then
  return 0
fi
__PHASE1_MACOS_SH=1

# Source companion log.sh from the same directory so callers do not have
# to source both manually.
__phase1_macos_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=log.sh
. "${__phase1_macos_dir}/log.sh"

# ---------------------------------------------------------------------------
# defaults read / write / compare
# ---------------------------------------------------------------------------

# mac_default_get <domain> <key>
# Echoes the current value via `defaults read`. Returns 0 on success,
# non-zero (and prints nothing) when the key is unset or `defaults` errors.
mac_default_get() {
  local domain="$1"
  local key="$2"
  local out
  if ! out="$(defaults read "$domain" "$key" 2>/dev/null)"; then
    return 1
  fi
  printf '%s' "$out"
  return 0
}

# mac_default_set <domain> <key> <type> <value>
# Runs `defaults write <domain> <key> -<type> <value>`. <type> must be one
# of bool|int|string|array|dict. For array/dict the caller is expected to
# pass a value `defaults write` accepts (typically a JSON-ish plist
# fragment); v1 callers pass empty `()`/`{}` for the common "clear" cases.
mac_default_set() {
  local domain="$1"
  local key="$2"
  local type="$3"
  local value="$4"
  case "$type" in
    bool)   defaults write "$domain" "$key" -bool   "$value" ;;
    int)    defaults write "$domain" "$key" -int    "$value" ;;
    float)  defaults write "$domain" "$key" -float  "$value" ;;
    string) defaults write "$domain" "$key" -string "$value" ;;
    array)
            # Empty arrays: `defaults write -array` with no values writes
            # an empty array. `defaults write -array []` shell-glob-fails.
            case "$value" in
              ''|'[]'|'()')
                defaults write "$domain" "$key" -array
                ;;
              *)
                # `value` is interpreted as a plist array fragment;
                # intentional word-splitting on the eval expansion.
                # shellcheck disable=SC2086
                eval defaults write "$domain" "$key" -array $value
                ;;
            esac ;;
    dict)   # shellcheck disable=SC2086
            eval defaults write "$domain" "$key" -dict  $value ;;
    *)
      error "mac_default_set: unsupported type \"$type\""
      return 2
      ;;
  esac
}

# __mac_normalise_bool <value>
# Maps macOS bool surface forms to the canonical "true"/"false" so two
# differently-spelt booleans compare equal. `defaults read` for a bool
# returns 0/1; YAML may declare true/false/YES/NO. We fold them all.
__mac_normalise_bool() {
  case "$1" in
    1|YES|yes|Yes|true|TRUE|True)   printf 'true' ;;
    0|NO|no|No|false|FALSE|False)   printf 'false' ;;
    *) printf '%s' "$1" ;;
  esac
}

# mac_default_compare <type> <current> <expected>
# Returns 0 iff <current> and <expected> are equivalent under <type>'s
# equality rules. Returns non-zero otherwise. <type> must be one of
# bool|int|string|array|dict.
#
#   bool    -> normalise both sides, string-compare
#   int     -> numeric compare via -eq (rejects non-numeric loudly)
#   string  -> exact byte-for-byte compare (whitespace preserved)
#   array   -> structural compare via plutil JSON round-trip if available;
#             fallback: trim whitespace and string-compare
#   dict    -> same as array
mac_default_compare() {
  local type="$1"
  local current="$2"
  local expected="$3"
  case "$type" in
    bool)
      local nc ne
      nc="$(__mac_normalise_bool "$current")"
      ne="$(__mac_normalise_bool "$expected")"
      [ "$nc" = "$ne" ]
      ;;
    int)
      # Reject non-numeric input on either side; treat as drift.
      case "$current$expected" in
        ''|*[!0-9-]*) return 1 ;;
      esac
      [ "$current" -eq "$expected" ] 2>/dev/null
      ;;
    float)
      # awk-based float compare; tolerate empty input.
      [ -n "$current" ] && [ -n "$expected" ] || return 1
      awk -v c="$current" -v e="$expected" 'BEGIN { exit (c+0 == e+0) ? 0 : 1 }'
      ;;
    string)
      [ "$current" = "$expected" ]
      ;;
    array|dict)
      # Try plutil JSON canonicalisation first. defaults read returns
      # OpenStep plist syntax; plutil can convert that to JSON via stdin
      # when given `-` and `-convert json`. If conversion fails on either
      # side we fall back to a whitespace-collapsed string compare.
      if command -v plutil >/dev/null 2>&1; then
        local cj ej
        if cj="$(printf '%s' "$current"  | plutil -convert json -o - - 2>/dev/null)" \
        && ej="$(printf '%s' "$expected" | plutil -convert json -o - - 2>/dev/null)"; then
          [ "$cj" = "$ej" ] && return 0
          return 1
        fi
      fi
      # Fallback: collapse all runs of whitespace and compare.
      local cs es
      cs="$(printf '%s' "$current"  | tr -s '[:space:]' ' ')"
      es="$(printf '%s' "$expected" | tr -s '[:space:]' ' ')"
      cs="${cs# }"; cs="${cs% }"
      es="${es# }"; es="${es% }"
      [ "$cs" = "$es" ]
      ;;
    *)
      error "mac_default_compare: unsupported type \"$type\""
      return 2
      ;;
  esac
}

# ---------------------------------------------------------------------------
# killall queue
# ---------------------------------------------------------------------------
# A single shell-global array, populated across calls within one step.
# Add targets via mac_killall_queue_add; flush with mac_killall_queue_flush.

# Initialised to empty unless a prior source already populated it.
if [ -z "${__MAC_KILLALL_QUEUE+x}" ]; then
  __MAC_KILLALL_QUEUE=()
fi

# mac_killall_queue_add <target>
# Adds <target> to the global queue, deduplicating. Empty / "none" entries
# are ignored so callers can blindly forward a YAML field.
mac_killall_queue_add() {
  local target="$1"
  [ -n "$target" ] || return 0
  case "$target" in
    none|None|NONE) return 0 ;;
  esac
  local existing
  for existing in "${__MAC_KILLALL_QUEUE[@]+"${__MAC_KILLALL_QUEUE[@]}"}"; do
    [ "$existing" = "$target" ] && return 0
  done
  __MAC_KILLALL_QUEUE+=("$target")
}

# mac_killall_queue_flush
# Runs `killall <target>` per unique queued target. Tolerates targets
# that aren't currently running (killall returns non-zero in that case;
# we explicitly `|| true` so the step doesn't blow up). Empties the queue
# on the way out so a re-call is a no-op.
mac_killall_queue_flush() {
  local target
  for target in "${__MAC_KILLALL_QUEUE[@]+"${__MAC_KILLALL_QUEUE[@]}"}"; do
    info "killall $target"
    killall "$target" >/dev/null 2>&1 || true
  done
  __MAC_KILLALL_QUEUE=()
}

# ---------------------------------------------------------------------------
# manual-install detection
# ---------------------------------------------------------------------------

# mac_manual_detect_app <bundle_id>
# Returns 0 iff a .app with the given CFBundleIdentifier is installed in
# /Applications, ~/Applications, or anywhere Spotlight indexes. Prefers
# `mdfind` when available (fast, recursive); falls back to scanning the
# usual /Applications/*.app and ~/Applications/*.app Info.plist files.
mac_manual_detect_app() {
  local bundle_id="$1"
  [ -n "$bundle_id" ] || return 1

  if command -v mdfind >/dev/null 2>&1; then
    local hit
    hit="$(mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" 2>/dev/null | head -n1)"
    if [ -n "$hit" ]; then
      return 0
    fi
  fi

  # Fallback: scan top-level .app bundles in the two canonical locations.
  local dir app plist current
  for dir in "/Applications" "$HOME/Applications"; do
    [ -d "$dir" ] || continue
    for app in "$dir"/*.app; do
      [ -e "$app" ] || continue
      plist="$app/Contents/Info.plist"
      [ -r "$plist" ] || continue
      if current="$(defaults read "$plist" CFBundleIdentifier 2>/dev/null)"; then
        if [ "$current" = "$bundle_id" ]; then
          return 0
        fi
      fi
    done
  done

  return 1
}

# mac_manual_detect_command <cmd>
# Returns 0 iff <cmd> is on PATH.
mac_manual_detect_command() {
  local cmd="$1"
  [ -n "$cmd" ] || return 1
  command -v "$cmd" >/dev/null 2>&1
}

# mac_manual_detect_file <path>
# Returns 0 iff <path> exists. A leading `~` is expanded to $HOME.
mac_manual_detect_file() {
  local path="$1"
  [ -n "$path" ] || return 1
  case "$path" in
    "~")    path="$HOME" ;;
    "~/"*)  path="$HOME/${path#~/}" ;;
  esac
  [ -e "$path" ]
}

# mac_manual_detect_launchd <label>
# Returns 0 iff `launchctl list` mentions the given label. Matches by
# trailing-column equality (label is the last column of `launchctl list`
# output) so a substring like "com.foo" doesn't accidentally match
# "com.foo.bar".
mac_manual_detect_launchd() {
  local label="$1"
  [ -n "$label" ] || return 1
  command -v launchctl >/dev/null 2>&1 || return 1
  launchctl list 2>/dev/null | awk -v l="$label" '$NF == l { found=1 } END { exit !found }'
}
