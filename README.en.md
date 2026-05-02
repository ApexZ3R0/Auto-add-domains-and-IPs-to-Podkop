# Dynamic lists for podkop

> [Русская версия](README.md)

Automatic detection of blocked resources and adding them to bypass via [podkop](https://github.com/itdoginfo/podkop) on OpenWrt.

## How it works

```
cron every 5 minutes:
  curl --interface eth1 (clean WAN IP) → candidate
  ├── OK → reset fail counter
  └── FAIL × 3 in a row → SSH → overseas VPS → ping
        ├── ping OK → blocked by ISP
        │     → uci add_list user_domains → podkop reload
        └── ping FAIL → server is globally unavailable, skip

cron daily at 01:30 UTC:
  for each auto_added entry:
    curl --interface eth1 → OK × 3 nights in a row
    → remove from podkop UCI → podkop reload
```

**Key feature:** all checks go strictly through the WAN interface with a clean IP, bypassing any VPN tunnels — this eliminates false positives when a device on your network connects via VPN and accesses a blocked site.

## Quick install

```sh
sh <(wget -O - https://raw.githubusercontent.com/ApexZ3R0/Dynamic-lists-for-podkop/main/install.sh)
```

The script will ask a few questions:
- WAN interface (default: `eth1`)
- SSH target for overseas VPS (for ping verification)
- podkop section name to add domains to
- Fail/clean thresholds

If your section is in `text` mode (e.g. `user_domains_text`), install.sh will automatically migrate all existing entries to UCI dynamic format with a backup.

## Management

```sh
# Add a site to monitoring (blockcheck will watch it)
podkop-manage add candidate example.com

# Add directly to podkop (without waiting for 3 failures)
podkop-manage add domain example.com
podkop-manage add ip 1.2.3.0/24

# Check a site right now
podkop-manage check example.com

# Show all states
podkop-manage list state

# Status of a specific host
podkop-manage status example.com

# Remove from podkop and return to monitoring
podkop-manage remove domain example.com

# Add a remote candidate source
podkop-manage source add https://example.com/blocked-list.txt

# Reset fail counter (false positive)
podkop-manage reset example.com
```

## File structure

```
/etc/podkop-monitor/
├── podkop-monitor.conf   # config (WAN iface, VPS, thresholds, podkop section)
├── blockcheck.sh         # candidate checker (cron every 5 min)
├── cleancheck.sh         # nightly cleanup (cron 01:30 UTC)
├── migrate-to-dynamic.sh # one-time migration text→dynamic UCI
├── manual.txt            # manually added monitoring candidates
├── state.db              # fail counters and statuses
├── clean.db              # nightly direct-access counters
├── remote-sources.txt    # URLs of remote candidate lists
└── candidates.d/         # downloaded remote lists
    └── remote_1.txt
```

## Logs

```sh
logread | grep blockcheck    # check events
logread | grep cleancheck    # nightly cleanup
logread | grep "ADDED"       # what was added
logread | grep "REMOVED"     # what was removed
logread | grep "SUSPECT"     # accumulating fail count
```

## state.db statuses

| Status | Description |
|---|---|
| `watching` | Monitored, clean counter |
| `watching` + fails > 0 | Accumulating failures (shown in red in `list state`) |
| `auto_added` | Added automatically, checked nightly |
| `manual` | Added manually, ignored by cleancheck |

## Recovery after OpenWrt upgrade

```sh
# 1. Reinstall podkop-monitor
sh <(wget -O - https://raw.githubusercontent.com/ApexZ3R0/Dynamic-lists-for-podkop/main/install.sh)

# 2. Config /etc/podkop-monitor/podkop-monitor.conf can be restored from the repo
#    or copied manually from a backup made before the upgrade:
#    scp root@router:/etc/podkop-monitor/podkop-monitor.conf ./

# 3. Candidate lists:
#    scp root@router:/etc/podkop-monitor/manual.txt ./
```

> OpenWrt upgrade wipes `/etc/`. It is recommended to back up before upgrading:
> ```sh
> tar czf podkop-monitor-backup.tar.gz /etc/podkop-monitor/
> ```

## Other scripts in this repository

| Branch | Purpose |
|---|---|
| [Interactive-add-ons-installer](../../tree/%D0%98%D0%BD%D1%82%D0%B5%D1%80%D0%B0%D0%BA%D1%82%D0%B8%D0%B2%D0%BD%D0%B0%D1%8F-%D1%83%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0-%D0%B4%D0%BE%D0%BF%D0%BE%D0%BB%D0%BD%D0%B5%D0%BD%D0%B8%D0%B9) | Interactive installer: AmneziaWG + podkop + dynamic lists |
| [Post-upgrade-OpenWRT-24.x-to-25.x](../../tree/%D0%94%D0%BE%D1%83%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0-%D0%BF%D0%B0%D0%BA%D0%B5%D1%82%D0%BE%D0%B2-%D0%B8-%D0%BD%D0%B0%D1%81%D1%82%D1%80%D0%BE%D0%B5%D0%BA-%D0%BF%D0%BE%D1%81%D0%BB%D0%B5-%D0%BE%D0%B1%D0%BD%D0%BE%D0%B2%D0%BB%D0%B5%D0%BD%D0%B8%D1%8F-%D1%81-OpenWRT-24.x-%D0%BD%D0%B0-25.x) | System recovery after OpenWrt 25.x upgrade |

## Requirements

- OpenWrt 24.10+
- podkop 0.7.x with a section in `dynamic` mode
- `curl`, `ssh` (openssh-client), `nslookup`
- SSH key to overseas VPS (passwordless)
- VPS with internet access (for ping verification)
