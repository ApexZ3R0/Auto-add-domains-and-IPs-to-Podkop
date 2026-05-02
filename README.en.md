# Interactive Add-ons Installer

> [Русская версия](README.md)

An interactive OpenWrt installer: choose the components you need from a menu and install everything in a single run.

## What it installs

| Component | Description |
|---|---|
| **AmneziaWG** | Kernel module + tools + luci-proto |
| **Podkop + sing-box-extended** | Traffic bypass with VLESS/xhttp support |
| **Dynamic lists** | Auto-add blocked domains to podkop |
| **Monitoring** | banip, vnstat, netdata, collectd + luci-app-statistics |
| **Utilities** | git, rclone, nano, tcpdump, qrencode, luci-theme-argon, pbr, etc. |

## Supported OpenWrt versions

- **24.x** — uses `opkg`
- **25.x** — uses `apk`

## Usage

```sh
sh <(wget -O - "https://raw.githubusercontent.com/ApexZ3R0/auto-add-domains-and-ips-to-podkop/%D0%98%D0%BD%D1%82%D0%B5%D1%80%D0%B0%D0%BA%D1%82%D0%B8%D0%B2%D0%BD%D0%B0%D1%8F%20%D1%83%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0%20%D0%B4%D0%BE%D0%BF%D0%BE%D0%BB%D0%BD%D0%B5%D0%BD%D0%B8%D0%B9/setup.sh")
```

Or download and run manually:

```sh
wget -O /tmp/setup.sh "https://raw.githubusercontent.com/ApexZ3R0/auto-add-domains-and-ips-to-podkop/%D0%98%D0%BD%D1%82%D0%B5%D1%80%D0%B0%D0%BA%D1%82%D0%B8%D0%B2%D0%BD%D0%B0%D1%8F%20%D1%83%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0%20%D0%B4%D0%BE%D0%BF%D0%BE%D0%BB%D0%BD%D0%B5%D0%BD%D0%B8%D0%B9/setup.sh"
sh /tmp/setup.sh
```

## Menu

```
  Required:
    1) AmneziaWG (kmod + tools + luci-proto)
    2) Podkop + sing-box-extended

  Optional:
    3) Dynamic lists (auto-add blocked domains)
    4) Monitoring (banip, vnstat, netdata, collectd)
    5) Utilities (git, rclone, nano, argon, pbr...)

  Presets:
    a) Basic (1+2)
    b) Standard (1+2+3+4)
    c) Full (everything)
```

## What the script does

1. Detects the package manager (`apk` or `opkg`)
2. Checks internet connectivity and fixes DNS if needed
3. Checks available disk space and RAM
4. Updates package lists
5. Shows an interactive component selection menu
6. Installs selected components
7. Prints next steps

## Requirements

- OpenWrt 24.10+ or OpenWrt 25.x
- Internet access
- At least 10 MB free disk space
