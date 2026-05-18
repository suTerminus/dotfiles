# phase0/lib/log.sh
# Shared logging helpers for phase0/ scripts.
# All output is written to stderr (fd 2) so script stdout stays clean.
# Safe to source multiple times.

if [ -n "${__PHASE0_LOG_SH:-}" ]; then
  return 0
fi
__PHASE0_LOG_SH=1

info()  { printf '[INFO] %s\n' "$*" >&2; }
ok()    { printf '[OK]   %s\n' "$*" >&2; }
skip()  { printf '[SKIP] %s\n' "$*" >&2; }
warn()  { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERR]  %s\n' "$*" >&2; }
