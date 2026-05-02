# Post-upgrade package restore: OpenWrt 24.x → 25.x

> [Русская версия](README.md)

A script that automatically restores all packages and settings after upgrading OpenWrt from version 24.x to 25.x.

## Why you need it

When upgrading OpenWrt from 24.x to 25.x the firmware is fully replaced — all additionally installed packages are removed. This script restores everything needed in a single run.

## What it does

1. Configures DNS (8.8.8.8)
2. Expands the filesystem partition if needed
3. Updates `apk` package lists
4. Installs base utilities (curl, git, nano, tcpdump, rclone, qrencode, etc.)
5. Installs **AmneziaWG** (kmod + tools + luci-proto)
6. Installs and updates **podkop**
7. Installs **sing-box-extended** (VLESS/xhttp)
8. Installs **luci-theme-argon**
9. Restores **podkop-monitor** — if config found, updates scripts; otherwise runs fresh install
10. Restores cron jobs for podkop-monitor
11. Starts services

## Important: what to back up before upgrading

```sh
# Save podkop-monitor config
scp root@192.168.1.1:/etc/podkop-monitor/podkop-monitor.conf ./
scp root@192.168.1.1:/etc/podkop-monitor/manual.txt ./
```

After upgrading and running the script, restore the config:

```sh
scp ./podkop-monitor.conf root@192.168.1.1:/etc/podkop-monitor/
scp ./manual.txt root@192.168.1.1:/etc/podkop-monitor/
```

## Usage

```sh
wget -O /tmp/post-upgrade.sh "https://raw.githubusercontent.com/ApexZ3R0/auto-add-domains-and-ips-to-podkop/%D0%94%D0%BE%D1%83%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0%20%D0%BF%D0%B0%D0%BA%D0%B5%D1%82%D0%BE%D0%B2%20%D0%B8%20%D0%BD%D0%B0%D1%81%D1%82%D1%80%D0%BE%D0%B5%D0%BA%20%D0%BF%D0%BE%D1%81%D0%BB%D0%B5%20%D0%BE%D0%B1%D0%BD%D0%BE%D0%B2%D0%BB%D0%B5%D0%BD%D0%B8%D1%8F%20%D1%81%20OpenWRT%2024.x%20%D0%BD%D0%B0%2025.x/post-upgrade.sh"
sh /tmp/post-upgrade.sh
```

## Installed packages

**System utilities:**
`curl` `git` `git-http` `nano-full` `coreutils` `coreutils-base64` `tcpdump` `socat` `iperf3` `netperf` `bind-dig` `arp-scan` `arp-scan-database` `imagemagick` `qrencode` `rclone` `vnstat` `vnstati` `parted` `resize2fs` `e2fsprogs` `losetup` `avahi-utils` `hev-socks5-tunnel`

**LuCI / UI:**
`ttyd` `luci-app-ttyd` `banip` `luci-app-banip` `netdata` `collectd` `collectd-mod-cpu` `collectd-mod-interface` `collectd-mod-load` `collectd-mod-memory` `collectd-mod-rrdtool` `luci-app-statistics` `pbr` `luci-app-pbr` `luci-theme-material` `luci-app-filemanager` `luci-app-commands` `luci-mod-rpc` `luci-app-samba4` `luci-app-attendedsysupgrade` `samba4-server` `samba4-client` `luci-theme-argon`

**Tunnels/VPN:**
`amneziawg-tools` `kmod-amneziawg` `luci-proto-amneziawg` `podkop` `sing-box-extended`

## Uses apk

This script targets OpenWrt 25.x which migrated from `opkg` to **`apk`**.
It cannot be used on OpenWrt 24.x.

## Requirements

- OpenWrt 25.x (apk)
- Internet access
- 200+ MB free disk space recommended (after partition expansion)
