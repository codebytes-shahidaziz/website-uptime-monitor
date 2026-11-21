#!/usr/bin/env bash
#!/usr/bin/env bash
# Generates fake log data in the same format monitor.sh writes.
# Used to test report.sh and cleanup.sh without waiting a week for real logs.
#
# Usage: ./tests/generate_sample_log.sh [-d DAYS] [-i MINUTES] [-o OUTPUT_FILE] [-s SEED] [-h]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DAYS=7
INTERVAL=5
OUTPUT="$SCRIPT_DIR/sample_uptime.log"
SEED=42

# The four fake sites, each one behaves differently
SITE_STABLE="https://stable-site.example.com"   # almost always UP
SITE_OUTAGE="https://outage-site.example.com"   # one long DOWN stretch
SITE_SLOW="https://slow-site.example.com"       # often SLOW
SITE_FLAKY="https://flaky-site.example.com"     # random failures

usage() {
  echo "Usage: $0 [-d DAYS] [-i MINUTES] [-o OUTPUT_FILE] [-s SEED] [-h]"
  echo ""
  echo "  -d    Number of days of data to generate (default: 7)"
  echo "  -i    Minutes between checks (default: 5)"
  echo "  -o    Output file (default: tests/sample_uptime.log)"
  echo "  -s    Random seed, same seed gives the same pattern (default: 42)"
  echo "  -h    Show this help"
}

while getopts ":d:i:o:s:h" opt; do
  case "$opt" in
    d) DAYS="$OPTARG" ;;
    i) INTERVAL="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    s) SEED="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "Error: Invalid option -$OPTARG" >&2; usage >&2; exit 1 ;;
    :)  echo "Error: Option -$OPTARG needs a value" >&2; usage >&2; exit 1 ;;
  esac
done

if ! [[ "$DAYS" =~ ^[1-9][0-9]*$ && "$INTERVAL" =~ ^[1-9][0-9]*$ && "$SEED" =~ ^[0-9]+$ ]]; then
  echo "Error: -d, -i and -s must be positive whole numbers" >&2
  exit 1
fi

if ! date -d "1 day ago" +%s >/dev/null 2>&1; then
  echo "Error: this script needs GNU date (Linux or WSL)" >&2
  exit 1
fi

RANDOM=$SEED

# rand_between MIN MAX  ->  result in $REPLY (no subshell, so it stays fast)
rand_between() {
  REPLY=$(( $1 + RANDOM % ($2 - $1 + 1) ))
}

# fmt_ts EPOCH  ->  result in $TS as "YYYY-MM-DD HH:MM:SS"
if printf '%(%s)T' -1 >/dev/null 2>&1; then
  fmt_ts() { printf -v TS '%(%Y-%m-%d %H:%M:%S)T' "$1"; }
else
  fmt_ts() { TS=$(date -d "@$1" '+%Y-%m-%d %H:%M:%S'); }
fi

# emit URL STATUS CODE TIME OFFSET_SECONDS  -> prints one log line
emit() {
  fmt_ts $(( CYCLE_TIME + $5 ))
  echo "$TS | $1 | $2 | $3 | $4"
}

START=$(date -d "$DAYS days ago" +%s)
TOTAL_CYCLES=$(( DAYS * 1440 / INTERVAL ))

# outage-site is DOWN for 4 hours, starting halfway through the data
OUTAGE_LEN=$(( 240 / INTERVAL ))
(( OUTAGE_LEN < 1 )) && OUTAGE_LEN=1
OUTAGE_START=$(( TOTAL_CYCLES / 2 ))

# our own internet is "off" for 3 checks, like monitor.sh would log it
NET_LEN=3
NET_START=$(( TOTAL_CYCLES * 3 / 4 ))

mkdir -p "$(dirname "$OUTPUT")" || exit 1

for (( c = 0; c < TOTAL_CYCLES; c++ )); do
  CYCLE_TIME=$(( START + c * INTERVAL * 60 ))

  # When the local internet is down monitor.sh writes only this one line
  if (( c >= NET_START && c < NET_START + NET_LEN )); then
    fmt_ts "$CYCLE_TIME"
    echo "$TS | NETWORK_DOWN | DOWN | 000 | timeout"
    continue
  fi

  # 1) stable-site: UP almost every time, one failure in about 1000 checks
  rand_between 1 1000
  if (( REPLY == 1 )); then
    emit "$SITE_STABLE" DOWN 000 timeout 0
  else
    rand_between 80 350
    emit "$SITE_STABLE" UP 200 "${REPLY}ms" 0
  fi

  # 2) outage-site: one continuous DOWN stretch, UP the rest of the time
  if (( c >= OUTAGE_START && c < OUTAGE_START + OUTAGE_LEN )); then
    emit "$SITE_OUTAGE" DOWN 000 timeout 2
  else
    rand_between 120 500
    emit "$SITE_OUTAGE" UP 200 "${REPLY}ms" 2
  fi

  # 3) slow-site: SLOW (over 2000ms) in more than half of the checks
  rand_between 1 100
  if (( REPLY <= 55 )); then
    rand_between 2100 4500
    emit "$SITE_SLOW" SLOW 200 "${REPLY}ms" 4
  else
    rand_between 900 1900
    emit "$SITE_SLOW" UP 200 "${REPLY}ms" 4
  fi

  # 4) flaky-site: about 6 in 100 checks fail, either a timeout or a 500
  rand_between 1 100
  if (( REPLY <= 6 )); then
    rand_between 1 2
    if (( REPLY == 1 )); then
      emit "$SITE_FLAKY" DOWN 000 timeout 6
    else
      rand_between 200 900
      emit "$SITE_FLAKY" DOWN 500 "${REPLY}ms" 6
    fi
  else
    rand_between 150 800
    emit "$SITE_FLAKY" UP 200 "${REPLY}ms" 6
  fi
done > "$OUTPUT"

echo "Created $OUTPUT ($(wc -l < "$OUTPUT") lines, $DAYS days, every $INTERVAL minutes)"
