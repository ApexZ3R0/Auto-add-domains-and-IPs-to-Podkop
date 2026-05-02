# Доустановка пакетов и настроек после обновления с OpenWrt 24.x на 25.x

> [English version](README.en.md)

Скрипт автоматически восстанавливает все пакеты и настройки после системного обновления OpenWrt с версии 24.x на 25.x.

## Зачем нужен

После обновления OpenWrt с 24.x до 25.x прошивка записывается заново — все дополнительно установленные пакеты удаляются. Этот скрипт восстанавливает всё необходимое за один запуск.

## Что делает

1. Настраивает DNS (8.8.8.8)
2. Расширяет раздел файловой системы при необходимости
3. Обновляет списки пакетов `apk`
4. Устанавливает базовые утилиты (curl, git, nano, tcpdump, rclone, qrencode и др.)
5. Устанавливает **AmneziaWG** (kmod + tools + luci-proto)
6. Устанавливает и обновляет **podkop**
7. Устанавливает **sing-box-extended** (VLESS/xhttp)
8. Устанавливает **luci-theme-argon**
9. Восстанавливает **podkop-monitor** — если конфиг найден, обновляет скрипты; иначе запускает установку заново
10. Восстанавливает cron-задания для podkop-monitor
11. Запускает сервисы

## Важно: что сохранить перед обновлением

```sh
# Сохранить конфиг podkop-monitor
scp root@192.168.1.1:/etc/podkop-monitor/podkop-monitor.conf ./
scp root@192.168.1.1:/etc/podkop-monitor/manual.txt ./
```

После обновления и запуска скрипта восстановить конфиг:

```sh
scp ./podkop-monitor.conf root@192.168.1.1:/etc/podkop-monitor/
scp ./manual.txt root@192.168.1.1:/etc/podkop-monitor/
```

## Запуск

```sh
wget -O /tmp/post-upgrade.sh "https://raw.githubusercontent.com/ApexZ3R0/auto-add-domains-and-ips-to-podkop/%D0%94%D0%BE%D1%83%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0%20%D0%BF%D0%B0%D0%BA%D0%B5%D1%82%D0%BE%D0%B2%20%D0%B8%20%D0%BD%D0%B0%D1%81%D1%82%D1%80%D0%BE%D0%B5%D0%BA%20%D0%BF%D0%BE%D1%81%D0%BB%D0%B5%20%D0%BE%D0%B1%D0%BD%D0%BE%D0%B2%D0%BB%D0%B5%D0%BD%D0%B8%D1%8F%20%D1%81%20OpenWRT%2024.x%20%D0%BD%D0%B0%2025.x/post-upgrade.sh"
sh /tmp/post-upgrade.sh
```

## Устанавливаемые пакеты

**Системные утилиты:**
`curl` `git` `git-http` `nano-full` `coreutils` `coreutils-base64` `tcpdump` `socat` `iperf3` `netperf` `bind-dig` `arp-scan` `arp-scan-database` `imagemagick` `qrencode` `rclone` `vnstat` `vnstati` `parted` `resize2fs` `e2fsprogs` `losetup` `avahi-utils` `hev-socks5-tunnel`

**LuCI / интерфейс:**
`ttyd` `luci-app-ttyd` `banip` `luci-app-banip` `netdata` `collectd` `collectd-mod-cpu` `collectd-mod-interface` `collectd-mod-load` `collectd-mod-memory` `collectd-mod-rrdtool` `luci-app-statistics` `pbr` `luci-app-pbr` `luci-theme-material` `luci-app-filemanager` `luci-app-commands` `luci-mod-rpc` `luci-app-samba4` `luci-app-attendedsysupgrade` `samba4-server` `samba4-client` `luci-theme-argon`

**Туннели/VPN:**
`amneziawg-tools` `kmod-amneziawg` `luci-proto-amneziawg` `podkop` `sing-box-extended`

## Использует apk

Скрипт рассчитан на OpenWrt 25.x, который перешёл с `opkg` на **`apk`**.
На OpenWrt 24.x использовать нельзя.

## Требования

- OpenWrt 25.x (apk)
- Доступ к интернету
- Рекомендуется 200+ МБ свободного места (после расширения раздела)
