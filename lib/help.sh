#!/usr/bin/env bash
# Help texts for all scripts in this project.
#
# Usage from any script:
#   source "$SCRIPT_DIR/lib/help.sh"
#   show_help "report.sh"

show_help() {
  # Accept "report.sh", "./report.sh" or "lib/ssl_check.sh"
  local name="${1##*/}"

  case "$name" in
    monitor.sh)
      cat <<'HELP'
monitor.sh - check if websites are up, log the result and alert on changes

Usage:
  ./monitor.sh [-u URL] [-c CONFIG] [-s SITES] [-d] [-v] [-h]

Options:
  -u URL      Check only this one URL instead of the sites file
  -c CONFIG   Path to monitor.conf   (default: ./config/monitor.conf)
  -s SITES    Path to sites.conf     (default: ./config/sites.conf)
  -d          Daemon mode, keep running and repeat every CHECK_INTERVAL seconds
  -v          Verbose, show every retry attempt
  -h          Show this help message

Examples:
  ./monitor.sh
  ./monitor.sh -u https://example.com -v
HELP
      ;;

    report.sh)
      cat <<'HELP'
report.sh - uptime report built from logs/uptime.log

Usage:
  ./report.sh [-d YYYY-MM-DD] [-w] [-s] [-f FILE] [-h]

Options:
  (no option) Report for all recorded data
  -d DATE     Report for one day only, for example 2026-03-31
  -w          Report for the last 7 days
  -s          Also save the report to reports/report_YYYY-MM-DD.txt
  -f FILE     Read this log file instead of logs/uptime.log
  -h          Show this help message

Examples:
  ./report.sh -w
  ./report.sh -f tests/sample_uptime.log -d 2026-03-31
HELP
      ;;

    cleanup.sh)
      cat <<'HELP'
cleanup.sh - remove log lines older than LOG_RETENTION_DAYS

Usage:
  ./cleanup.sh [--compress] [--dry-run] [-h]

Options:
  --compress  Save the removed lines in logs/archive/ as .gz instead of deleting
  --dry-run   Only show what would be removed, change nothing
  -h          Show this help message

Examples:
  ./cleanup.sh --dry-run
  ./cleanup.sh --compress
HELP
      ;;

    install.sh)
      cat <<'HELP'
install.sh - set up folders, permissions and cron jobs

Usage:
  ./install.sh [--yes] [--uninstall] [-h]

Options:
  --yes        Do not ask questions, install the cron jobs directly
  --uninstall  Remove the cron jobs added by this project
  -h           Show this help message

Examples:
  ./install.sh
  ./install.sh --uninstall
HELP
      ;;

    ssl_check.sh)
      cat <<'HELP'
ssl_check.sh - show how many days are left on each site's SSL certificate

Usage:
  ./lib/ssl_check.sh [-f SITES] [-u URL] [-w DAYS] [-h]

Options:
  -f SITES    Sites file to read (default: ./config/sites.conf)
  -u URL      Check only this one https URL
  -w DAYS     Show WARNING when fewer than DAYS are left (default: 14)
  -h          Show this help message

Examples:
  ./lib/ssl_check.sh
  ./lib/ssl_check.sh -u https://www.github.com -w 30
HELP
      ;;

    *)
      cat <<'HELP'
Website Uptime Monitor

Scripts:
  monitor.sh          Check the websites (main script)
  report.sh           Uptime report from the logs
  cleanup.sh          Remove old log lines
  install.sh          Setup and cron jobs
  lib/ssl_check.sh    SSL certificate expiry check

Run any of them with -h to see its options.
HELP
      return 1
      ;;
  esac
}
