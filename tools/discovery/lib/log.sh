# tools/discovery/lib/log.sh
# Shared logging helpers for tools/discovery/ scripts.
# All output is written to stderr (fd 2) so script stdout stays clean
# for redirection into YAML/markdown artefacts.
# Safe to source multiple times via the sentinel guard below.

if [ -n "${__DISCOVERY_LOG_SH:-}" ]; then
  return 0
fi
__DISCOVERY_LOG_SH=1

log_info()  { printf '[INFO] %s\n' "$*" >&2; }
log_ok()    { printf '[OK]   %s\n' "$*" >&2; }
log_skip()  { printf '[SKIP] %s\n' "$*" >&2; }
log_warn()  { printf '[WARN] %s\n' "$*" >&2; }
log_error() { printf '[ERR]  %s\n' "$*" >&2; }
