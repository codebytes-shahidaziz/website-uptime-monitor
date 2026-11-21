# Website Uptime Monitor

A lightweight, modular website monitoring and alerting tool written in **Bash 4+**. It checks whether websites are up, measures response time in milliseconds, logs every check, sends alerts when a site goes down or recovers, checks SSL certificate expiry, and generates uptime reports. It only needs standard Linux tools.

## Features

- **Multi-site monitoring**: checks every URL listed in `config/sites.conf`, or a single URL with `-u`.
- **Response time in milliseconds**: measured with `curl` for every check.
- **Three states**: `UP`, `SLOW` (answered, but slower than `SLOW_THRESHOLD_MS`) and `DOWN` (error status or no answer).
- **Retry logic**: a failed check is retried up to `RETRIES` times before the site is marked DOWN, so one network glitch does not cause a false alarm.
- **State change alerts**: Email and Telegram alerts are sent **only** when a site changes state (UP to DOWN, or DOWN to UP). No spam while a site stays down.
- **Network outage detection**: if every site fails, the monitor checks its own internet connection first. If our internet is down, it logs `NETWORK_DOWN` and sends no alerts.
- **Lock file**: two monitors can never run at the same time.
- **Daemon mode**: `-d` keeps the monitor running and repeats every `CHECK_INTERVAL` seconds, without cron.
- **SSL certificate check**: `lib/ssl_check.sh` shows how many days are left on each certificate.
- **Reports**: `report.sh` shows uptime percentage, average and slowest response time and downtime events per site.
- **Log cleanup**: `cleanup.sh` removes old log lines after `LOG_RETENTION_DAYS`.

## Project Structure

```
website-uptime-monitor/
├── monitor.sh                 # Main monitoring script
├── report.sh                  # Uptime report generator
├── cleanup.sh                 # Log retention and cleanup
├── install.sh                 # Setup script (folders, permissions, cron)
├── LICENSE                    # MIT License
├── README.md                  # This file
├── config/
│   ├── monitor.conf           # Global settings
│   └── sites.conf             # URLs to monitor
├── lib/
│   ├── alert.sh               # Email and Telegram alerts
│   ├── help.sh                # Help text for all scripts
│   ├── ssl_check.sh           # SSL certificate expiry checker
│   └── utils.sh               # Shared helper functions
├── logs/                      # Created at runtime, not committed
│   ├── uptime.log             # Every check
│   ├── failure.log            # Only SLOW and DOWN checks
│   ├── cron.log               # Output of cron runs
│   ├── archive/               # Compressed old logs
│   └── state/                 # Last known state of each site
├── reports/                   # Saved reports
└── tests/
    ├── generate_sample_log.sh # Creates fake log data for testing
    ├── sample_uptime.log      # Generated sample data
    ├── test_cases.md          # Test table with results
    └── screenshots/           # Screenshots of the tests
```

## Installation

```
git clone https://github.com/your-username/website-uptime-monitor.git
cd website-uptime-monitor
chmod +x install.sh
./install.sh
```

The installer checks that `curl` and Bash 4+ are available, creates the folders, makes the scripts executable and (if you agree) adds the cron jobs. Use `./install.sh --yes` to skip the questions and `./install.sh --uninstall` to remove the cron jobs again.

## Configuration

### `config/sites.conf`

One URL per line. Empty lines and lines starting with `#` are ignored.

```
https://www.google.com
https://www.github.com
# https://disabled-site.example.com
```

### `config/monitor.conf`

```
TIMEOUT=10                 # Max seconds to wait for a response
RETRIES=3                  # Attempts before a site is marked DOWN
RETRY_DELAY=5              # Seconds between attempts
SLOW_THRESHOLD_MS=2000     # Slower than this is marked SLOW
CHECK_INTERVAL=300         # Seconds between checks in daemon mode (-d)
LOG_DIR="./logs"
LOG_RETENTION_DAYS=30      # cleanup.sh removes older log lines

# Alerts
ENABLE_EMAIL=false
ALERT_EMAIL="admin@example.com"
ENABLE_TELEGRAM=false
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
```

## Usage

### monitor.sh

```
./monitor.sh                      # one check of all sites
./monitor.sh -u https://example.com   # check one URL only
./monitor.sh -c my_monitor.conf   # use another settings file
./monitor.sh -s my_sites.conf     # use another sites file
./monitor.sh -d                   # daemon mode, repeat every CHECK_INTERVAL seconds
./monitor.sh -v                   # verbose, show every retry
./monitor.sh -h                   # help
```

### report.sh

```
./report.sh                       # all data
./report.sh -d 2026-03-31         # one day
./report.sh -w                    # last 7 days
./report.sh -s                    # also save to reports/report_YYYY-MM-DD.txt
./report.sh -f tests/sample_uptime.log   # use another log file
```

### cleanup.sh

```
./cleanup.sh                      # remove log lines older than LOG_RETENTION_DAYS
./cleanup.sh --dry-run            # only show what would be removed
./cleanup.sh --compress           # keep the removed lines in logs/archive/ as .gz
```

### lib/ssl_check.sh

```
./lib/ssl_check.sh                # check all https sites in sites.conf
./lib/ssl_check.sh -u https://www.github.com
./lib/ssl_check.sh -w 30          # warn when fewer than 30 days are left
```

Each site is shown as `OK`, `WARNING` (fewer than 14 days left by default), `EXPIRED` or `ERROR` (could not connect).

## Sample Output

### Console output of monitor.sh

```
====================================================
   WEBSITE UPTIME MONITOR  -  2026-11-21 14:30:02
====================================================
[ UP   ]  https://www.google.com          200    142ms
[ UP   ]  https://www.github.com          200    310ms
[ SLOW ]  https://example.com             200    2450ms
[ DOWN ]  https://broken-site.xyz         000    timeout
------------------------------------------
Checked: 4 | Up: 2 | Slow: 1 | Down: 1
```

### Log format (`logs/uptime.log`)

```
2026-11-21 14:30:02 | https://www.google.com | UP | 200 | 142ms
2026-11-21 14:30:09 | https://example.com | SLOW | 200 | 2450ms
2026-11-21 14:30:27 | https://broken-site.xyz | DOWN | 000 | timeout
2026-11-21 15:00:02 | NETWORK_DOWN | DOWN | 000 | timeout
```

The fields are timestamp, URL, status, HTTP code and response time. A `NETWORK_DOWN` line means our own internet was off during that check. It is not a website and is ignored by the report. `failure.log` has the same format but only contains SLOW and DOWN lines.

### Report from report.sh

<!-- Replace this block with the real output of: ./report.sh -f tests/sample_uptime.log -->

```
(paste the output of ./report.sh here)
```

## Cron Automation

`./install.sh` adds these three jobs for you. To add them by hand, run `crontab -e` and use your real path:

```
*/5 * * * * /bin/bash /path/to/website-uptime-monitor/monitor.sh >> /path/to/website-uptime-monitor/logs/cron.log 2>&1
0 0 * * * /bin/bash /path/to/website-uptime-monitor/cleanup.sh >> /path/to/website-uptime-monitor/logs/cron.log 2>&1
0 8 * * * /bin/bash /path/to/website-uptime-monitor/report.sh -d $(date -d yesterday +\%F)
```

## Alert System

The monitor remembers the last state of every site in `logs/state/`. A `SLOW` site still counts as up, because it answered. Alerts are sent in these cases only:

| Event | When | Alert |
|-------|------|-------|
| Site goes down | UP to DOWN, or the very first check fails | `DOWN` alert with status code and response time |
| Site recovers | DOWN to UP | `UP` alert with how long the site was down |

Alerts go out by email (`mail` or `msmtp`) and/or Telegram, depending on `ENABLE_EMAIL` and `ENABLE_TELEGRAM` in `monitor.conf`. If sending fails, the error is logged and monitoring continues.

## Testing

All test cases, the exact commands and the results are in [tests/test_cases.md](tests/test_cases.md). To create the fake data used for the report tests:

```
./tests/generate_sample_log.sh
```

## Screenshots

| Check of a working site | Recovery alert |
|-------------------------|----------------|
| ![Valid URL](tests/screenshots/01-valid-url.png) | ![Recovery alert](tests/screenshots/07-recovery-alert.png) |

| Report on sample data | SSL certificate check |
|-----------------------|-----------------------|
| ![Report](tests/screenshots/10-report.png) | ![SSL check](tests/screenshots/14-ssl-check.png) |

## Team

| Name | Role | Files |
|------|------|-------|
| Owais | Project lead, core engine | `monitor.sh`, `config/`, repository setup |
| <Name> | Reports | `report.sh` |
| <Name> | Alert system | `lib/alert.sh` |
| <Name> | Installer and log cleanup | `install.sh`, `cleanup.sh` |
| <Name> | Utilities and SSL checker | `lib/utils.sh`, `lib/ssl_check.sh` |
| <Name> | Testing, help text and documentation | `tests/`, `lib/help.sh`, `README.md` |

## Requirements

- **OS**: Linux or WSL. macOS works if Bash 4+ and GNU coreutils are installed (the default macOS Bash is too old).
- **Shell**: Bash 4.0 or newer
- **Tools**: `curl`, `awk`, `sed`, `grep`, `ping`, `openssl` (for the SSL check), `cron` (for scheduling)
- **Optional**: `mail` or `msmtp` for email alerts

## License

MIT License, see the [LICENSE](LICENSE) file.
