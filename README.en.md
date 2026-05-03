# Auto-add domains and IPs to Podkop

> [Русская версия](README.md)

Automatic detection of blocked resources and adding them to bypass via [podkop](https://github.com/itdoginfo/podkop) on OpenWrt.

## How it works

```
dns-monitor (cron every 5 minutes):
  Parses dnsmasq DNS logs → finds new domains
  Checks TCP 443/80 via eth1 (clean WAN IP)
  └── unreachable → add to candidates (manual.txt)

blockcheck (cron every 5 minutes):
  curl via eth1 → candidate
  ├── OK → reset fail counter
  └── FAIL × 3 in a row → SSH → VPS → ping
        ├── ping OK → blocked by ISP
        │     → write to auto-domains.lst / auto-subnets.lst
        │     → podkop reload
        └── ping FAIL → server globally unavailable, skip

cleancheck (cron daily at 01:30 UTC):
  for each auto_added entry:
    curl via eth1 → OK × 3 nights in a row
    → remove from auto-domains.lst / auto-subnets.lst
    → podkop reload
```

**Key features:**
- All checks go strictly through `eth1` (WAN with clean IP) — eliminates false positives from VPN on devices
- Domains and IPs are written to local files that podkop reads directly — manual lists are not touched
- dns-monitor automatically picks up domains that devices on the network try to connect to

## Installation

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/ApexZ3R0/Auto-add-domains-and-IPs-to-Podkop/main/install.sh && sh /tmp/install.sh
```

The script will ask:
- WAN interface (default: `eth1`)
- SSH target for overseas VPS (for ping verification)
- podkop section name
- Fail/clean thresholds

After installation, add local files to podkop (Services → Podkop → section → Local lists):
- **Local domain lists:** `/etc/podkop-monitor/auto-domains.lst`
- **Local subnet lists:** `/etc/podkop-monitor/auto-subnets.lst`

## Management

```sh
# Add a site to monitoring
podkop-manage add candidate filmix.ac

# Add directly to podkop (without waiting for 3 failures)
podkop-manage add domain filmix.ac
podkop-manage add ip 1.2.3.0/24

# Check a site right now
podkop-manage check filmix.ac

# Show all states
podkop-manage list state

# Remove from podkop and return to monitoring
podkop-manage remove domain filmix.ac

# Reset fail counter (false positive)
podkop-manage reset filmix.ac
```

## View auto-added entries

```sh
cat /etc/podkop-monitor/auto-domains.lst
cat /etc/podkop-monitor/auto-subnets.lst
podkop-manage list state
```

## File structure

```
/etc/podkop-monitor/
├── podkop-monitor.conf    # config
├── blockcheck.sh          # candidate checker (cron every 5 min)
├── cleancheck.sh          # nightly cleanup (cron 01:30 UTC)
├── dns-monitor.sh         # auto-add from DNS logs (cron every 5 min)
├── manual.txt             # manual candidates
├── auto-domains.lst       # → podkop: Local domain lists
├── auto-subnets.lst       # → podkop: Local subnet lists
├── state.db               # counters and statuses
├── clean.db               # nightly direct-access counters
└── remote-sources.txt     # remote candidate list URLs
```

## Logs

```sh
logread | grep blockcheck     # check events
logread | grep cleancheck     # nightly cleanup
logread | grep dns-monitor    # auto-add from DNS
logread | grep "ADDED"        # what was added
logread | grep "REMOVED"      # what was removed
```

## Other scripts in this repository

| Branch | Purpose |
|---|---|
| [Interactive-add-ons-installer](../../tree/Интерактивная-установка-дополнений) | Install AmneziaWG + podkop + dynamic lists |
| [Post-upgrade-OpenWRT-24.x-to-25.x](../../tree/Доустановка-пакетов-и-настроек-после-обновления-с-OpenWRT-24.x-на-25.x) | System recovery after OpenWrt 25.x upgrade |

## Requirements

- OpenWrt 24.10+ or 25.x
- podkop 0.7.x
- `curl`, `ssh`, `nslookup`
- SSH key to overseas VPS (passwordless)
- VPS with internet access
- dnsmasq query logging enabled (`logqueries=1`)
