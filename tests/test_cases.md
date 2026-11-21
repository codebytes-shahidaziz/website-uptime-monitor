# Test Cases

All commands are run from the project folder, on the latest `main`.

## Setup (do this once before testing)

```
git checkout main && git pull
chmod +x *.sh lib/*.sh tests/*.sh
rm -rf logs
```

Until the real alert system is merged, an "alert" shows up as a line like `[STUB ALERT - DOWN] ...`. That counts as an alert being sent.

## Summary

| # | Test case | Result |
|---|-----------|--------|
| 1 | Valid working URL is marked UP and logged | |
| 2 | Non-existent domain is marked DOWN after retries | |
| 3 | URL that returns 404 is marked DOWN with the code | |
| 4 | Very low timeout is detected | |
| 5 | Empty and commented lines in sites.conf are ignored | |
| 6 | Internet disconnected gives no false alerts | |
| 7 | Site goes DOWN then UP sends one recovery alert | |
| 8 | Site stays DOWN sends only one alert | |
| 9 | Two instances at once, the second one exits | |
| 10 | Report on sample data gives correct percentages | |
| 11 | Report with a date that has no data | |
| 12 | Installer run twice | |
| 13 | Cleanup with --dry-run | |
| 14 | SSL check on an expired site | |

Passed: ___ / 14

---

## Test 1: Valid working URL is marked UP and logged

Commands:

```
./monitor.sh -u https://www.google.com
tail -n 1 logs/uptime.log
```

Expected: one row starting with `[ UP   ]` with code 200 and a time in ms. The summary says `Checked: 1 | Up: 1 | Slow: 0 | Down: 0`. The last log line ends with `UP | 200 | <number>ms`.

Actual:

Result:

## Test 2: Non-existent domain is marked DOWN after retries

Commands:

```
./monitor.sh -v -u https://this-domain-does-not-exist-12345.com
tail -n 1 logs/uptime.log
```

Expected: it takes about 10 seconds. With `-v` you see attempts 1/3, 2/3 and 3/3. Then a `[ DOWN ]` row with code 000 and `timeout`. The last log line ends with `DOWN | 000 | timeout`. One alert line appears (first check of a new site that fails).

Actual:

Result:

## Test 3: URL that returns 404 is marked DOWN with the code

Commands:

```
./monitor.sh -u https://github.com/this-page-does-not-exist-12345
tail -n 1 logs/uptime.log
tail -n 1 logs/failure.log
```

Expected: a `[ DOWN ]` row with code 404. Both log files have a last line ending with `DOWN | 404 | <number>ms`.

Actual:

Result:

## Test 4: Very low timeout is detected

Commands:

```
sed -e 's/^TIMEOUT=.*/TIMEOUT=0.01/' -e 's/^RETRIES=.*/RETRIES=1/' config/monitor.conf > /tmp/low.conf
./monitor.sh -c /tmp/low.conf -u https://www.google.com
```

Expected: google.com, which normally works, shows `[ DOWN ]` with code 000 and `timeout`, because 0.01 seconds is too short for any answer.

Actual:

Result:

## Test 5: Empty and commented lines in sites.conf are ignored

Commands:

```
printf 'https://www.google.com\n\n# https://www.github.com\n   \nnotaurl\nhttps://example.com\n' > /tmp/sites_test.conf
./monitor.sh -s /tmp/sites_test.conf
```

Expected: only google.com and example.com are checked (`Checked: 2`). The empty lines and the `#` line are skipped without any message. `notaurl` prints `WARNING: Skipping invalid URL`. Nothing crashes.

Actual:

Result:

## Test 6: Internet disconnected gives no false alerts

Turn Wi-Fi off first. Commands:

```
./monitor.sh
tail -n 1 logs/uptime.log
```

Expected: it takes about 20 seconds. The message `Local internet connection appears offline (NETWORK_DOWN)` is shown. No alert lines and no DOWN rows for the sites. The last log line ends with `NETWORK_DOWN | DOWN | 000 | timeout`. Turn Wi-Fi back on after this test.

Actual:

Result:

## Test 7: Site goes DOWN then UP sends one recovery alert

Commands (run them in this order):

```
rm -f logs/state/https___www_google_com.state
./monitor.sh -u https://www.google.com
echo "DOWN|$(( $(date +%s) - 120 ))" > logs/state/https___www_google_com.state
./monitor.sh -u https://www.google.com
./monitor.sh -u https://www.google.com
```

The `echo` line pretends google was down for 2 minutes.

Expected: the first run shows no alert. The second run shows exactly one recovery alert, with a message like `Site recovered after 2m 0s of downtime`. The third run shows no alert.

Actual:

Result:

## Test 8: Site stays DOWN sends only one alert

Commands:

```
rm -f logs/state/https___this_domain_does_not_exist_12345_com.state
./monitor.sh -u https://this-domain-does-not-exist-12345.com
./monitor.sh -u https://this-domain-does-not-exist-12345.com
./monitor.sh -u https://this-domain-does-not-exist-12345.com
```

Expected: the first run shows one DOWN alert. The second and third runs show the `[ DOWN ]` row but no new alert. All three runs add a line to `logs/uptime.log`.

Actual:

Result:

## Test 9: Two instances at once, the second one exits

Commands:

```
./monitor.sh -d &
sleep 2
./monitor.sh
kill $(cat logs/monitor.lock)
```

Expected: the second `./monitor.sh` prints `Error: Monitor is already running (PID: <number>). Exiting.` and stops. The `kill` command stops the first one.

Actual:

Result:

## Test 10: Report on sample data gives correct percentages

Commands:

```
./tests/generate_sample_log.sh
./report.sh -f tests/sample_uptime.log
grep -c 'stable-site' tests/sample_uptime.log
grep -c 'stable-site.* DOWN ' tests/sample_uptime.log
```

Expected: the report shows these things.
- stable-site uptime % equals (total - DOWN) / total x 100, using the two numbers from the `grep` commands (calculate it by hand)
- slow-site shows 100% uptime, because SLOW counts as available
- outage-site shows exactly 1 downtime event
- `NETWORK_DOWN` does not appear as a website

Actual:

Result:

## Test 11: Report with a date that has no data

Commands:

```
./report.sh -f tests/sample_uptime.log -d 2000-01-01
echo $?
```

Expected: a clear message that there is no data for that date, with no empty table. The `echo $?` line prints `1`.

Actual:

Result:

## Test 12: Installer run twice

Commands:

```
./install.sh --yes
./install.sh --yes
crontab -l
./install.sh --uninstall
crontab -l
```

Expected: after two installs, `crontab -l` shows exactly 3 lines containing `website-uptime-monitor` (monitor, cleanup, report), not 6. After `--uninstall` there are none. The folders `logs`, `logs/state`, `logs/archive` and `reports` exist.

Actual:

Result:

## Test 13: Cleanup with --dry-run

Commands:

```
mkdir -p logs
cp tests/sample_uptime.log logs/uptime.log
wc -l logs/uptime.log
sed -i 's/^LOG_RETENTION_DAYS=.*/LOG_RETENTION_DAYS=3/' config/monitor.conf
./cleanup.sh --dry-run
wc -l logs/uptime.log
git checkout config/monitor.conf
```

Expected: `./cleanup.sh --dry-run` says what it would remove (the lines older than 3 days). The two `wc -l` numbers are the same, so nothing was changed. The last command puts the config back.

Actual:

Result:

## Test 14: SSL check on an expired site

Commands:

```
./lib/ssl_check.sh -u https://expired.badssl.com
echo $?
./lib/ssl_check.sh -u https://www.github.com
echo $?
```

Expected: expired.badssl.com shows `EXPIRED` and the exit code is `1`. github.com shows `OK` with a number of days left and the exit code is `0`.

Actual:

Result:

---

## Bugs found

| Test # | File | What went wrong | Owner | Fixed? |
|--------|------|-----------------|-------|--------|
| | | | | |
