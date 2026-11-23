#!/usr/bin/env bash
# SSL certificate expiry checker.
# Usage: ssl_check.sh [-f FILE] [-u URL] [-w DAYS] [-h]
# Exit code 1 if any site is not OK.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SITE_CONF="$SCRIPT_DIR/config/sites.conf"
MONITOR_CONF="$SCRIPT_DIR/config/monitor.conf"
SINGLE_URL=""
WARN_DAYS=14
TIMEOUT=10

# Load TIMEOUT from config if present (script still works without it)
[[ -f "$MONITOR_CONF" ]] && source "$MONITOR_CONF"

# Use the shared library if it exists, otherwise fall back to local helpers
# so this script runs on its own.
if [[ -f "$SCRIPT_DIR/lib/utils.sh" ]]; then
  source "$SCRIPT_DIR/lib/utils.sh"
fi
if ! declare -f _color >/dev/null 2>&1; then
  _color() {
    if [[ -t 1 ]]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
  }
fi
if ! declare -f log_warn >/dev/null 2>&1; then
  log_warn() { echo "[WARN]  $*" >&2; }
fi
if ! declare -f log_error >/dev/null 2>&1; then
  log_error() { echo "[ERROR] $*" >&2; }
fi

usage() {
  cat <<USAGE
Usage: ssl_check.sh [-f FILE] [-u URL] [-w DAYS] [-h]
  -f FILE   sites file to read (default: config/sites.conf)
  -u URL    check a single https URL
  -w DAYS   warn when this many days or fewer are left (default: 14)
  -h        show this help
Exit code is 1 if any site is not OK.
USAGE
}

ANY_PROBLEM=false

print_row() {
  local tag="$1" color="$2" url="$3" detail="$4"
  _color "$color" "$(printf '[ %-7s ]' "$tag")"
  printf '  %-32s%s\n' "$url" "$detail"
}

check_site() {
  local url="$1"

  if [[ "$url" == http://* ]]; then
    echo "[ SKIP    ]  $url   (http only, no SSL)"
    return 0
  fi

  local host
  host=$(echo "$url" | sed -E 's#https://([^/:]+).*#\1#')

  local out expiry
  out=$(echo | timeout "$TIMEOUT" openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null)
  expiry="${out#notAfter=}"

  local expiry_epoch
  if [[ -z "$out" || -z "$expiry" ]] || ! expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null); then
    print_row "ERROR" 31 "$url" "could not connect or read certificate"
    ANY_PROBLEM=true
    return 0
  fi

  local diff=$(( expiry_epoch - $(date +%s) ))
  local days=$(( diff / 86400 ))
  local expiry_date
  expiry_date=$(date -d "@$expiry_epoch" '+%Y-%m-%d')

  if [[ $diff -le 0 ]]; then
    print_row "EXPIRED" 31 "$url" "expired on $expiry_date"
    ANY_PROBLEM=true
  elif [[ $days -le $WARN_DAYS ]]; then
    print_row "WARNING" 33 "$url" "$days days left (expires $expiry_date)"
    ANY_PROBLEM=true
  else
    print_row "OK" 32 "$url" "$days days left (expires $expiry_date)"
  fi
}

main() {
  while getopts ":f:u:w:h" opt; do
    case "$opt" in
      f) SITE_CONF="$OPTARG" ;;
      u) SINGLE_URL="$OPTARG" ;;
      w) WARN_DAYS="$OPTARG" ;;
      h) usage; exit 0 ;;
      \?) echo "Error: Invalid option -$OPTARG" >&2; usage >&2; exit 1 ;;
      :)  echo "Error: Option -$OPTARG requires an argument." >&2; exit 1 ;;
    esac
  done

  if ! [[ "$WARN_DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: -w needs a whole number of days." >&2
    exit 1
  fi
  for tool in openssl date sed; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Error: $tool is required." >&2; exit 1; }
  done

  if [[ -n "$SINGLE_URL" ]]; then
    check_site "$SINGLE_URL"
  else
    if [[ ! -f "$SITE_CONF" ]]; then
      echo "Error: Sites file missing at: $SITE_CONF" >&2
      exit 1
    fi
    local raw url
    while IFS= read -r raw || [[ -n "$raw" ]]; do
      url="${raw%$'\r'}"
      url="${url#"${url%%[![:space:]]*}"}"
      url="${url%"${url##*[![:space:]]}"}"
      [[ -z "$url" || "$url" == \#* ]] && continue
      check_site "$url"
    done < "$SITE_CONF"
  fi

  [[ "$ANY_PROBLEM" == true ]] && exit 1
  exit 0
}

main "$@"
