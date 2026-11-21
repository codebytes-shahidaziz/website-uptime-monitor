#!/usr/bin/env bash

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

validate_url() {
  [[ "$1" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?(/.*)?$ ]]
}

check_internet() {
  ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1
}

print_up()   { printf "[ UP   ]  %-30s  %-5s  %s\n" "$1" "$2" "$3"; }
print_slow() { printf "[ SLOW ]  %-30s  %-5s  %s\n" "$1" "$2" "$3"; }
print_down() { printf "[ DOWN ]  %-30s  %-5s  %s\n" "$1" "$2" "$3"; }

log_warn()   { echo "WARNING: $1" >&2; }
log_error()  { echo "ERROR: $1" >&2; }
