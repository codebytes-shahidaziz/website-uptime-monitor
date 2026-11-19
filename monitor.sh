#!/usr/bin/env bash

# Resolve absolute project root so script works from cron or any directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default paths & runtime flags
MONITOR_CONF="$SCRIPT_DIR/config/monitor.conf"
SITE_CONF="$SCRIPT_DIR/config/sites.conf"
LOCK_FILE="$SCRIPT_DIR/logs/monitor.lock"

SINGLE_URL=""
DAEMON_MODE=false
VERBOSE=false

# Cycle counters
COUNT_TOTAL=0
COUNT_UP=0
COUNT_SLOW=0
COUNT_DOWN=0

load_config() {
  local target_conf="$1"

  if [[ ! -f "$target_conf" ]]; then
    echo "Error: Configuration file missing at: $target_conf" >&2
    exit 1
  fi

  source "$target_conf"

  if [[ "${LOG_DIR:-./logs}" != /* ]]; then
    LOG_DIR="$SCRIPT_DIR/${LOG_DIR#./}"
  fi
}

source_libraries() {
  local libs=("$SCRIPT_DIR/lib/utils.sh" "$SCRIPT_DIR/lib/alert.sh" "$SCRIPT_DIR/lib/help.sh")
  for lib in "${libs[@]}"; do
    if [[ ! -f "$lib" ]]; then
      echo "Error: Required library missing at: $lib" >&2
      exit 1
    fi
    source "$lib"
  done
}

check_dependencies() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required but not installed." >&2
    exit 1
  fi
}

acquire_lock() {
  mkdir -p "$(dirname "$LOCK_FILE")"

  if [[ -f "$LOCK_FILE" ]]; then
    local old_pid
    old_pid=$(cat "$LOCK_FILE" 2>/dev/null)

    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      echo "Error: Monitor is already running (PID: $old_pid). Exiting." >&2
      exit 1
    else
      rm -f "$LOCK_FILE"
    fi
  fi

  echo "$$" > "$LOCK_FILE"
  trap release_lock EXIT INT
}

release_lock() {
  rm -f "$LOCK_FILE"
}

# Input & URL Checking Functions
read_sites() {
  local site_file="$1"
  VALID_SITES=()

  if [[ ! -f "$site_file" ]]; then
    echo "Error: Sites file missing at: $site_file" >&2
    exit 1
  fi

  shopt -s extglob
  while IFS= read -r raw_url || [[ -n "$raw_url" ]]; do
    local url="${raw_url%$'\r'}"
    url="${url##*([[:space:]])}"
    url="${url%%*([[:space:]])}"

    # Skip blank lines and comments
    [[ -z "$url" || "$url" == \#* ]] && continue

    if ! validate_url "$url"; then
      log_warn "Skipping invalid URL in $site_file: $url"
      continue
    fi

    VALID_SITES+=("$url")
  done < "$site_file"
  shopt -u extglob
}

check_url() {
  local url="$1"
  local raw_output
  raw_output=$(curl -o /dev/null -s -w "%{http_code} %{time_total}" --connect-timeout 5 --max-time "${TIMEOUT:-10}" "$url" 2>/dev/null)

  local code raw_time
  code=$(echo "$raw_output" | awk '{print $1}')
  raw_time=$(echo "$raw_output" | awk '{print $2}')

  # Fallback if curl completely failed to output
  [[ -z "$code" ]] && code="000"

  local time_formatted
  if [[ "$code" == "000" || -z "$raw_time" ]]; then
    time_formatted="timeout"
  else
    time_formatted=$(awk -v t="$raw_time" 'BEGIN { printf "%.0fms", t * 1000 }')
  fi

  echo "$code $time_formatted"
}

evaluate() {
  local url="$1"
  local max_retries="${RETRIES:-3}"
  local retry_delay="${RETRY_DELAY:-5}"
  local slow_limit="${SLOW_THRESHOLD_MS:-2000}"

  local code="000"
  local time_str="timeout"
  local attempt=1

  while [[ $attempt -le $max_retries ]]; do
    [[ "$VERBOSE" == true ]] && echo "Checking $url (Attempt $attempt/$max_retries)..." >&2

    local result
    result=$(check_url "$url")
    code=$(echo "$result" | awk '{print $1}')
    time_str=$(echo "$result" | awk '{print $2}')

    # Exit retry loop immediately on 2xx or 3xx
    if [[ "$code" =~ ^[23][0-9]{2}$ ]]; then
      break
    fi

    if [[ $attempt -lt $max_retries ]]; then
      sleep "$retry_delay"
    fi
    ((attempt++))
  done

  # Determine final status: DOWN, SLOW, or UP
  local status="DOWN"
  if [[ "$code" =~ ^[23][0-9]{2}$ ]]; then
    local numeric_ms="${time_str%ms}"
    if [[ "$numeric_ms" -gt "$slow_limit" ]]; then
      status="SLOW"
    else
      status="UP"
    fi
  else
    status="DOWN"
    [[ "$code" == "000" ]] && time_str="timeout"
  fi

  echo "$status $code $time_str"
}

# Logging, State & Alert Transitions
write_log() {
  local ts="$1"
  local url="$2"
  local status="$3"
  local code="$4"
  local time_str="$5"

  mkdir -p "$LOG_DIR"
  local log_line="$ts | $url | $status | $code | $time_str"

  echo "$log_line" >> "$LOG_DIR/uptime.log"

  if [[ "$status" != "UP" ]]; then
    echo "$log_line" >> "$LOG_DIR/failure.log"
  fi
}

get_state_file() {
  local url="$1"
  local safe_name
  safe_name=$(echo "$url" | sed 's/[^A-Za-z0-9]/_/g')
  echo "$LOG_DIR/state/${safe_name}.state"
}

get_state() {
  local url="$1"
  local state_file
  state_file=$(get_state_file "$url")

  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo ""
  fi
}

set_state() {
  local url="$1"
  local status="$2"
  local epoch="$3"
  local state_file
  state_file=$(get_state_file "$url")

  mkdir -p "$LOG_DIR/state"
  echo "${status}|${epoch}" > "$state_file"
}

format_duration() {
  local total_sec="$1"
  local hours=$((total_sec / 3600))
  local mins=$(((total_sec % 3600) / 60))
  local secs=$((total_sec % 60))

  if [[ $hours -gt 0 ]]; then
    echo "${hours}h ${mins}m ${secs}s"
  elif [[ $mins -gt 0 ]]; then
    echo "${mins}m ${secs}s"
  else
    echo "${secs}s"
  fi
}

handle_transition() {
  local url="$1"
  local new_status="$2"
  local code="$3"
  local time_str="$4"
  local now_epoch
  now_epoch=$(date +%s)

  # Normalize SLOW to UP for availability transition tracking (SLOW means site answered)
  local effective_new="UP"
  [[ "$new_status" == "DOWN" ]] && effective_new="DOWN"

  local prev_record
  prev_record=$(get_state "$url")

  if [[ -z "$prev_record" ]]; then
    set_state "$url" "$effective_new" "$now_epoch"
    if [[ "$effective_new" == "DOWN" ]]; then
      send_alert "DOWN" "$url" "Initial check failed (Status: $code, Time: $time_str)."
    fi
    return
  fi

  local old_status old_epoch
  old_status=$(echo "$prev_record" | cut -d'|' -f1)
  old_epoch=$(echo "$prev_record" | cut -d'|' -f2)

  if [[ "$old_status" == "UP" && "$effective_new" == "DOWN" ]]; then
    set_state "$url" "DOWN" "$now_epoch"
    send_alert "DOWN" "$url" "Site went DOWN (Status: $code, Time: $time_str)."
  elif [[ "$old_status" == "DOWN" && "$effective_new" == "UP" ]]; then
    local downtime_sec=$((now_epoch - old_epoch))
    local duration_str
    duration_str=$(format_duration "$downtime_sec")
    set_state "$url" "UP" "$now_epoch"
    send_alert "UP" "$url" "Site recovered after ${duration_str} of downtime (Status: $code, Time: $time_str)."
  fi
}

# Output & Cycle Execution
print_summary() {
  echo "------------------------------------------"
  echo "Checked: $COUNT_TOTAL | Up: $COUNT_UP | Slow: $COUNT_SLOW | Down: $COUNT_DOWN"
}

run_cycle() {
  COUNT_TOTAL=0
  COUNT_UP=0
  COUNT_SLOW=0
  COUNT_DOWN=0

  local targets=()
  if [[ -n "$SINGLE_URL" ]]; then
    if ! validate_url "$SINGLE_URL"; then
      log_error "Invalid URL passed to -u: $SINGLE_URL"
      exit 1
    fi
    targets=("$SINGLE_URL")
  else
    read_sites "$SITE_CONF"
    targets=("${VALID_SITES[@]}")
  fi

  if [[ ${#targets[@]} -eq 0 ]]; then
    log_warn "No valid URLs to check."
    return 0
  fi

  local cycle_ts
  cycle_ts=$(timestamp)

  echo "===================================================="
  echo "   WEBSITE UPTIME MONITOR  -  $cycle_ts"
  echo "===================================================="

  # Store results in memory first to verify if ALL sites failed (internet outage check)
  local results_ts=()
  local results_url=()
  local results_status=()
  local results_code=()
  local results_time=()

  for url in "${targets[@]}"; do
    local eval_out status code time_str ts
    eval_out=$(evaluate "$url")
    ts=$(timestamp)

    status=$(echo "$eval_out" | awk '{print $1}')
    code=$(echo "$eval_out" | awk '{print $2}')
    time_str=$(echo "$eval_out" | awk '{print $3}')

    results_ts+=("$ts")
    results_url+=("$url")
    results_status+=("$status")
    results_code+=("$code")
    results_time+=("$time_str")

    ((COUNT_TOTAL++))
    case "$status" in
      UP)   ((COUNT_UP++)) ;;
      SLOW) ((COUNT_SLOW++)) ;;
      DOWN) ((COUNT_DOWN++)) ;;
    esac
  done

  # If EVERY site failed, check internet connectivity before logging or alerting
  if [[ $COUNT_TOTAL -gt 0 && $COUNT_DOWN -eq $COUNT_TOTAL ]]; then
    if ! check_internet; then
      mkdir -p "$LOG_DIR"
      echo "$(timestamp) | NETWORK_DOWN | DOWN | 000 | timeout" >> "$LOG_DIR/uptime.log"
      log_error "Local internet connection appears offline (NETWORK_DOWN). Skipping alerts and state updates."
      return 1
    fi
  fi

  # Process validated results: print colored row, write logs, and evaluate state transitions
  for i in "${!results_url[@]}"; do
    local ts="${results_ts[$i]}"
    local url="${results_url[$i]}"
    local status="${results_status[$i]}"
    local code="${results_code[$i]}"
    local time_str="${results_time[$i]}"

    case "$status" in
      UP)   print_up "$url" "$code" "$time_str" ;;
      SLOW) print_slow "$url" "$code" "$time_str" ;;
      DOWN) print_down "$url" "$code" "$time_str" ;;
    esac

    write_log "$ts" "$url" "$status" "$code" "$time_str"
    handle_transition "$url" "$status" "$code" "$time_str"
  done

  print_summary
}

main() {
  while getopts ":u:c:s:dvh" opt; do
    case ${opt} in
      u) SINGLE_URL="$OPTARG" ;;
      c) MONITOR_CONF="$OPTARG" ;;
      s) SITE_CONF="$OPTARG" ;;
      d) DAEMON_MODE=true ;;
      v) VERBOSE=true ;;
      h)
        load_config "$MONITOR_CONF" 2>/dev/null || true
        source_libraries 2>/dev/null || true
        if declare -f show_help >/dev/null 2>&1; then
          show_help "monitor.sh"
        else
          echo "Usage: ./monitor.sh [-u URL] [-c CONFIG] [-s SITES] [-d] [-v] [-h]"
        fi
        exit 0
        ;;
      \?)
        echo "Error: Invalid option -$OPTARG" >&2
        exit 1
        ;;
      :)
        echo "Error: Option -$OPTARG requires an argument." >&2
        exit 1
        ;;
    esac
  done

  check_dependencies
  load_config "$MONITOR_CONF"
  source_libraries
  acquire_lock

  if [[ "$DAEMON_MODE" == true ]]; then
    local interval="${CHECK_INTERVAL:-300}"
    [[ "$VERBOSE" == true ]] && echo "Starting daemon mode (interval: ${interval}s)..."
    while true; do
      run_cycle
      sleep "$interval"
    done
  else
    run_cycle
  fi
}

main "$@"
