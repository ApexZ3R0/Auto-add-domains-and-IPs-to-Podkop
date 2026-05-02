#!/bin/sh
# post-upgrade.sh — восстановление OpenWrt-роутера после обновления на OpenWrt 25.x
# Использует apk (не opkg)

LOG="/tmp/post-upgrade.log"
# exec disabled for busybox

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLD='\033[1m'; NC='\033[0m'
say()  { printf "${BLD}>>> %s${NC}\n" "$*" | tee /dev/stderr; }
ok()   { printf "${GRN}✓${NC} %s\n" "$*" | tee /dev/stderr; }
warn() { printf "${YLW}⚠${NC}  %s\n" "$*" | tee /dev/stderr; }
err()  { printf "${RED}✗${NC} %s\n" "$*" | tee /dev/stderr; }
line() { printf "────────────────────────────────────────\n" | tee /dev/stderr; }

install_pkg() {
    pkg="$1"
    if apk info "$pkg" >/dev/null 2>&1; then
        ok "Уже установлен: $pkg"
        return 0
    fi
    printf "  Устанавливаю: $pkg... "
    if apk add "$pkg" >/dev/null 2>&1; then
        printf "${GRN}OK${NC}\n"
    else
        printf "${RED}FAIL${NC}\n"
        err "Не удалось установить: $pkg"
    fi
}

# ── DNS ───────────────────────────────────────────────────────────────────────
fix_dns() {
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    ok "DNS: 8.8.8.8"
}

# ── Расширение раздела ────────────────────────────────────────────────────────
expand_partition() {
    say "Проверка размера раздела..."
    ROOT_SIZE=$(df / | tail -1 | awk '{print $2}')
    if [ "$ROOT_SIZE" -gt 10000000 ]; then
        ok "Раздел уже расширен ($(df -h / | tail -1 | awk '{print $2}'))"
        return 0
    fi
    warn "Раздел маленький — расширяю..."

    # Проверить есть ли parted
    if ! command -v parted >/dev/null 2>&1; then
        apk add parted resize2fs e2fsprogs losetup >/dev/null 2>&1
    fi

    # Расширить раздел
    parted -f -s /dev/mmcblk1 resizepart 2 100% && ok "Раздел расширен"

    # Расширить файловую систему
    if ! command -v losetup >/dev/null 2>&1; then
        apk add losetup >/dev/null 2>&1
    fi
    touch /etc/rootpt-resize
    sh /etc/uci-defaults/80-rootfs-resize && ok "Файловая система расширена"
    warn "Требуется перезагрузка для применения изменений"
    warn "После reboot запусти скрипт снова"
    reboot
}

# ── AmneziaWG ─────────────────────────────────────────────────────────────────
install_amneziawg() {
    say "AmneziaWG..."
    install_pkg amneziawg-tools
    install_pkg kmod-amneziawg

    if apk info luci-proto-amneziawg >/dev/null 2>&1; then
        ok "Уже установлен: luci-proto-amneziawg"
        return 0
    fi

    # Скачать через amneziawg-install.sh
    # Передаём 'n' через файл чтобы не настраивал интерфейс
    wget -q -O /tmp/awg-install.sh \
        https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh

    # Запустить скрипт с автоответом 'n' на настройку интерфейса
    # Скрипт читает ввод через read — используем echo через pipe
    (echo "n"; echo "n") | sh /tmp/awg-install.sh
    rm -f /tmp/awg-install.sh

    if apk info luci-proto-amneziawg >/dev/null 2>&1; then
        ok "luci-proto-amneziawg установлен"
    else
        err "luci-proto-amneziawg — ручная установка:"
        err "sh <(wget -O - https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh)"
    fi
}

# ── Podkop ────────────────────────────────────────────────────────────────────
install_podkop() {
    say "Podkop..."
    if apk info podkop >/dev/null 2>&1; then
        ok "Podkop установлен — проверяю обновления"
        wget -q -O /tmp/podkop-install.sh \
            https://raw.githubusercontent.com/itdoginfo/podkop/refs/heads/main/install.sh
        sh /tmp/podkop-install.sh
        rm -f /tmp/podkop-install.sh
    else
        wget -q -O /tmp/podkop-install.sh \
            https://raw.githubusercontent.com/itdoginfo/podkop/refs/heads/main/install.sh
        sh /tmp/podkop-install.sh
        rm -f /tmp/podkop-install.sh
    fi
}

# ── sing-box-extended ─────────────────────────────────────────────────────────
install_singbox_extended() {
    say "sing-box-extended..."
    SB_VERSION=$(sing-box version 2>/dev/null | grep -o 'extended' || echo "")
    if [ -n "$SB_VERSION" ]; then
        ok "sing-box-extended уже установлен"
        return 0
    fi
    warn "Устанавливаю sing-box-extended..."
    wget -q -O /tmp/install-sb.sh \
        https://raw.githubusercontent.com/EikeiDev/OpenWRT-sing-box-extended/refs/heads/main/install.sh
    # Автовыбор версии 1 (последняя стабильная)
    echo "1" | sh /tmp/install-sb.sh
    rm -f /tmp/install-sb.sh
}

# ── luci-theme-argon ──────────────────────────────────────────────────────────
install_argon() {
    say "luci-theme-argon..."
    if apk info luci-theme-argon >/dev/null 2>&1; then
        ok "Уже установлен: luci-theme-argon"
        return 0
    fi
    ARGON_VER="2.4.3"
    ARGON_DATE="r20250722"
    ARGON_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v${ARGON_VER}/luci-theme-argon-${ARGON_VER}-${ARGON_DATE}.apk"
    wget -q -O /tmp/argon.apk "$ARGON_URL"
    if apk add --allow-untrusted /tmp/argon.apk >/dev/null 2>&1; then
        ok "luci-theme-argon установлен"
        uci set luci.main.mediaurlbase='/luci-static/argon' 2>/dev/null
        uci commit luci 2>/dev/null
    else
        err "Не удалось установить luci-theme-argon"
    fi
    rm -f /tmp/argon.apk
}

# ── podkop-monitor ────────────────────────────────────────────────────────────
install_podkop_monitor() {
    say "podkop-monitor..."
    REPO="https://raw.githubusercontent.com/ApexZ3R0/Dynamic-lists-for-podkop/main"
    if [ -f /etc/podkop-monitor/podkop-monitor.conf ]; then
        ok "Конфиг найден — обновляю скрипты"
        wget -q "${REPO}/scripts/blockcheck.sh?$(date +%s)" \
            -O /etc/podkop-monitor/blockcheck.sh && chmod +x /etc/podkop-monitor/blockcheck.sh && ok "blockcheck.sh"
        wget -q "${REPO}/scripts/cleancheck.sh?$(date +%s)" \
            -O /etc/podkop-monitor/cleancheck.sh && chmod +x /etc/podkop-monitor/cleancheck.sh && ok "cleancheck.sh"
        wget -q "${REPO}/scripts/podkop-manage?$(date +%s)" \
            -O /usr/bin/podkop-manage && chmod +x /usr/bin/podkop-manage && ok "podkop-manage"
    else
        warn "Конфиг не найден — запускаю установку"
        wget -q -O /tmp/install-monitor.sh "${REPO}/install.sh"
        sh /tmp/install-monitor.sh
        rm -f /tmp/install-monitor.sh
    fi
}

# ── Cron ──────────────────────────────────────────────────────────────────────
setup_cron() {
    say "Cron..."
    CRON_FILE="/etc/crontabs/root"
    touch "$CRON_FILE"
    grep -qF "blockcheck.sh" "$CRON_FILE" || {
        echo "*/5 * * * * /etc/podkop-monitor/blockcheck.sh" >> "$CRON_FILE"
        ok "Cron blockcheck добавлен"
    }
    grep -qF "cleancheck.sh" "$CRON_FILE" || {
        echo "30 1 * * * /etc/podkop-monitor/cleancheck.sh" >> "$CRON_FILE"
        ok "Cron cleancheck добавлен"
    }
    /etc/init.d/cron restart 2>/dev/null && ok "Cron перезапущен"
}

# ── Запуск сервисов ───────────────────────────────────────────────────────────
start_services() {
    say "Запуск сервисов..."
    for svc in podkop banip vnstat netdata; do
        /etc/init.d/$svc enable 2>/dev/null
        /etc/init.d/$svc start 2>/dev/null && ok "$svc запущен" || warn "$svc — не запустился"
    done
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
say "post-upgrade.sh — OpenWrt 25.x"
say "$(date)"
line

fix_dns
expand_partition
apk update && ok "Списки обновлены" || warn "Ошибка обновления списков"

say "Основные утилиты..."
for pkg in curl git git-http nano-full coreutils coreutils-base64 \
    tcpdump socat iperf3 netperf bind-dig arp-scan arp-scan-database \
    imagemagick qrencode rclone vnstat vnstati parted resize2fs \
    e2fsprogs losetup avahi-utils hev-socks5-tunnel ttyd luci-app-ttyd \
    banip luci-app-banip netdata collectd collectd-mod-cpu \
    collectd-mod-interface collectd-mod-load collectd-mod-memory \
    collectd-mod-rrdtool luci-app-statistics pbr luci-app-pbr \
    luci-theme-material luci-app-filemanager luci-app-commands \
    luci-mod-rpc luci-app-samba4 luci-app-attendedsysupgrade \
    samba4-server samba4-client; do
    install_pkg "$pkg"
done

install_amneziawg
install_podkop
install_singbox_extended
install_argon
install_podkop_monitor
setup_cron
start_services

line
say "Готово!"
line
