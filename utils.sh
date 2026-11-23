#!/usr/bin/env bash
# Shared helper functions for the Website Uptime Monitor.

# --- Colors (only when output goes to a terminal) ---------------------------
_color() {
  # usage: _color CODE TEXT  -> prints TEXT, wrapped in color only on a terminal
  if [[ -t 1 ]]; then
    printf '\033[%sm%s\033[0m' "$1" "$2"
  else
    printf '%s' "$2"
  fi
}

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

validate_url() {
  local url="$1"
  [[ "$url" =~ ^https?://[^[:space:]/]+(/[^[:space:]]*)?$ ]]
}

check_internet() {
  ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1
}

log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# --- Result rows: print_up|print_slow|print_down URL CODE TIME --------------
# Only the [ TAG ] part is colored.
print_up() {
  _color 32 "[ UP   ]"
  printf '  %-32s%-7s%s\n' "$1" "$2" "$3"
}

print_slow() {
  _color 33 "[ SLOW ]"
  printf '  %-32s%-7s%s\n' "$1" "$2" "$3"
}

print_down() {
  _color 31 "[ DOWN ]"
  printf '  %-32s%-7s%s\n' "$1" "$2" "$3"
}
