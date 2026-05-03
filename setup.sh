#!/bin/sh
# setup.sh — универсальный установщик AmneziaWG + podkop для OpenWrt
# Поддерживает OpenWrt 24.x (opkg) и 25.x (apk)
# Репо: https://github.com/ApexZ3R0/Auto-add-domains-and-IPs-to-Podkop

GRN='\033[0;32m'; YLW='\033[0;33m'; RED='\033[0;31m'; BLD='\033[1m'; NC='\033[0m'
say()  { printf "\n${BLD}%s${NC}\n" "$*"; }
ok()   { printf "${GRN}✓${NC} %s\n" "$*"; }
warn() { printf "${YLW}⚠${NC}  %s\n" "$*"; }
err()  { printf "${RED}✗${NC} %s\n" "$*"; }
ask()  { printf "${YLW}?${NC}  %s " "$*"; }
line() { printf "════════════════════════════════════════\n"; }

# ── Определить пакетный менеджер ──────────────────────────────────────────────
detect_pkg_manager() {
    if command -v apk >/dev/null 2>&1; then
        PKG_MGR="apk"
        PKG_UPDATE="apk update"
        PKG_INSTALL="apk add"
        PKG_CHECK="apk info"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MGR="opkg"
        PKG_UPDATE="opkg update"
        PKG_INSTALL="opkg install"
        PKG_CHECK="opkg list-installed | grep -q"
    else
        err "Не найден пакетный менеджер (apk/opkg)!"
        exit 1
    fi
    ok "Пакетный менеджер: $PKG_MGR"
}

# ── Проверка памяти ───────────────────────────────────────────────────────────
check_storage() {
    say "Проверка памяти..."

    ROOT_TOTAL=$(df / | tail -1 | awk '{print $2}')
    ROOT_FREE=$(df / | tail -1 | awk '{print $4}')
    ROOT_FREE_MB=$((ROOT_FREE / 1024))
    ROOT_TOTAL_MB=$((ROOT_TOTAL / 1024))
    RAM_FREE=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)

    ok "Диск: ${ROOT_FREE_MB}MB свободно из ${ROOT_TOTAL_MB}MB"
    ok "RAM: ${RAM_FREE}MB доступно"

    # Предупреждения по памяти
    if [ "$ROOT_FREE_MB" -lt 10 ]; then
        err "Критически мало места на диске (${ROOT_FREE_MB}MB)!"
        warn "Рекомендуется расширить раздел перед установкой"
        ask "Продолжить всё равно? [y/N]:"
        read -r ans
        [ "$ans" != "y" ] && [ "$ans" != "Y" ] && exit 1
    elif [ "$ROOT_FREE_MB" -lt 50 ]; then
        warn "Мало места (${ROOT_FREE_MB}MB) — устанавливай только базовые пакеты"
        STORAGE_LIMITED=1
    else
        STORAGE_LIMITED=0
    fi

    if [ "$RAM_FREE" -lt 64 ]; then
        warn "Мало RAM (${RAM_FREE}MB) — некоторые пакеты могут не запуститься"
    fi
}

# ── Установка пакета ──────────────────────────────────────────────────────────
install_pkg() {
    pkg="$1"
    if $PKG_CHECK "$pkg" >/dev/null 2>&1; then
        ok "Уже установлен: $pkg"
        return 0
    fi
    printf "  Устанавливаю %-30s " "$pkg..."
    if $PKG_INSTALL "$pkg" >/dev/null 2>&1; then
        printf "${GRN}OK${NC}\n"
        return 0
    else
        printf "${RED}FAIL${NC}\n"
        return 1
    fi
}

# ── DNS fix ───────────────────────────────────────────────────────────────────
fix_dns() {
    # Проверить доступность интернета
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        warn "Нет связи с интернетом — пробую исправить DNS"
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            err "Нет интернета! Проверь подключение WAN."
            exit 1
        fi
    fi
    ok "Интернет доступен"
}

# ── МОДУЛЬ 1: AmneziaWG ───────────────────────────────────────────────────────
install_amneziawg() {
    say "Установка AmneziaWG..."
    install_pkg amneziawg-tools
    install_pkg kmod-amneziawg

    # luci-proto-amneziawg — из внешнего репо
    if $PKG_CHECK luci-proto-amneziawg >/dev/null 2>&1; then
        ok "Уже установлен: luci-proto-amneziawg"
    else
        warn "Скачиваю luci-proto-amneziawg..."
        wget -q -O /tmp/awg-install.sh \
            https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh
        # Передаём 'n' чтобы не настраивал интерфейс
        printf "n\nn\n" | sh /tmp/awg-install.sh >/dev/null 2>&1
        rm -f /tmp/awg-install.sh
        $PKG_CHECK luci-proto-amneziawg >/dev/null 2>&1 \
            && ok "luci-proto-amneziawg установлен" \
            || err "Не удалось — установи вручную: sh <(wget -O - https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh)"
    fi
    /etc/init.d/network restart >/dev/null 2>&1
}

# ── МОДУЛЬ 2: Podkop + sing-box ───────────────────────────────────────────────
install_podkop() {
    say "Установка podkop..."
    wget -q -O /tmp/podkop-install.sh \
        https://raw.githubusercontent.com/itdoginfo/podkop/refs/heads/main/install.sh
    sh /tmp/podkop-install.sh
    rm -f /tmp/podkop-install.sh

    # sing-box-extended нужен для xhttp транспорта
    if sing-box version 2>/dev/null | grep -q "extended"; then
        ok "sing-box-extended уже установлен"
    else
        warn "Устанавливаю sing-box-extended (поддержка xhttp/VLESS)..."
        wget -q -O /tmp/install-sb.sh \
            https://raw.githubusercontent.com/EikeiDev/OpenWRT-sing-box-extended/refs/heads/main/install.sh
        echo "1" | sh /tmp/install-sb.sh >/dev/null 2>&1
        rm -f /tmp/install-sb.sh
        ok "sing-box-extended установлен"
    fi
}

# ── МОДУЛЬ 3: Dynamic lists (podkop-monitor) ──────────────────────────────────
install_dynamic_lists() {
    say "Установка dynamic lists для podkop..."
    wget -q -O /tmp/dl-install.sh \
        https://raw.githubusercontent.com/ApexZ3R0/Auto-add-domains-and-IPs-to-Podkop/main/install.sh
    sh /tmp/dl-install.sh
    rm -f /tmp/dl-install.sh
}

# ── МОДУЛЬ 4: Мониторинг ─────────────────────────────────────────────────────
install_monitoring() {
    say "Установка мониторинга..."
    install_pkg banip
    install_pkg luci-app-banip
    install_pkg vnstat
    install_pkg vnstati
    [ "$STORAGE_LIMITED" -eq 0 ] && install_pkg netdata
    install_pkg collectd
    install_pkg collectd-mod-cpu
    install_pkg collectd-mod-interface
    install_pkg collectd-mod-load
    install_pkg collectd-mod-memory
    install_pkg collectd-mod-rrdtool
    install_pkg luci-app-statistics
}

# ── МОДУЛЬ 5: Доп. утилиты ───────────────────────────────────────────────────
install_extras() {
    say "Установка дополнительных утилит..."
    install_pkg git
    install_pkg git-http
    install_pkg curl
    install_pkg nano-full
    install_pkg tcpdump
    install_pkg socat
    install_pkg rclone
    install_pkg imagemagick
    install_pkg qrencode
    install_pkg pbr
    install_pkg luci-app-pbr
    install_pkg ttyd
    install_pkg luci-app-ttyd
    install_pkg luci-theme-material
    install_pkg luci-app-filemanager
    install_pkg luci-app-commands
    install_pkg luci-mod-rpc
    install_pkg luci-app-samba4

    # luci-theme-argon — только если достаточно места
    if [ "$STORAGE_LIMITED" -eq 0 ]; then
        if $PKG_CHECK luci-theme-argon >/dev/null 2>&1; then
            ok "Уже установлен: luci-theme-argon"
        else
            ARGON_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.3/luci-theme-argon-2.4.3-r20250722.apk"
            wget -q -O /tmp/argon.apk "$ARGON_URL" 2>/dev/null
            if [ -s /tmp/argon.apk ]; then
                $PKG_INSTALL --allow-untrusted /tmp/argon.apk >/dev/null 2>&1 \
                    && ok "luci-theme-argon установлен" \
                    || err "Не удалось установить luci-theme-argon"
                rm -f /tmp/argon.apk
            fi
        fi
    else
        warn "Пропускаю luci-theme-argon (мало места)"
    fi
}

# ── Интерактивное меню ────────────────────────────────────────────────────────
interactive_menu() {
    line
    say "Выбери что установить:"
    line
    echo ""
    echo "  Обязательно:"
    echo "    1) AmneziaWG (kmod + tools + luci-proto)"
    echo "    2) Podkop + sing-box-extended"
    echo ""
    echo "  Дополнительно:"
    echo "    3) Dynamic lists (автодобавление заблокированных доменов)"
    echo "    4) Мониторинг (banip, vnstat, netdata, collectd)"
    echo "    5) Утилиты (git, rclone, nano, argon, pbr...)"
    echo "    6) Вспомогательные скрипты (awg_sync, bot_daemon)"
    echo ""
    echo "  Пресеты:"
    echo "    a) Базовый (1+2)"
    echo "    b) Стандартный (1+2+3+4)"
    echo "    c) Полный (всё)"
    echo ""

    while true; do
        ask "Выбор (1-5, a/b/c) [a]:"
        read -r choice
        choice="${choice:-a}"
        case "$choice" in
            1) DO_AWG=1 ;;
            2) DO_PODKOP=1 ;;
            3) DO_DYNLISTS=1 ;;
            4) DO_MONITORING=1 ;;
            5) DO_EXTRAS=1 ;;
            a)
                DO_AWG=1; DO_PODKOP=1
                break ;;
            b)
                DO_AWG=1; DO_PODKOP=1; DO_DYNLISTS=1; DO_MONITORING=1
                break ;;
            c)
                DO_AWG=1; DO_PODKOP=1; DO_DYNLISTS=1; DO_MONITORING=1; DO_EXTRAS=1
                break ;;
            *)
                warn "Введи 1-5 или a/b/c"
                continue ;;
        esac
        # При ручном выборе спрашиваем продолжать или выбрать ещё
        ask "Добавить ещё? [y/N]:"
        read -r more
        [ "$more" != "y" ] && [ "$more" != "Y" ] && break
    done

    # Если мало места — предупредить
    if [ "${STORAGE_LIMITED:-0}" -eq 1 ]; then
        [ "${DO_EXTRAS:-0}" -eq 1 ] && warn "Мало места — extras могут не поместиться"
        [ "${DO_MONITORING:-0}" -eq 1 ] && warn "Мало места — netdata будет пропущен"
    fi

    echo ""
    say "Будет установлено:"
    [ "${DO_AWG:-0}"        -eq 1 ] && echo "  ✓ AmneziaWG"
    [ "${DO_PODKOP:-0}"     -eq 1 ] && echo "  ✓ Podkop + sing-box-extended"
    [ "${DO_DYNLISTS:-0}"   -eq 1 ] && echo "  ✓ Dynamic lists"
    [ "${DO_MONITORING:-0}" -eq 1 ] && echo "  ✓ Мониторинг"
    [ "${DO_EXTRAS:-0}"     -eq 1 ] && echo "  ✓ Утилиты"
    echo ""
    ask "Начать установку? [Y/n]:"
    read -r confirm
    [ "$confirm" = "n" ] || [ "$confirm" = "N" ] && { warn "Отменено."; exit 0; }
}


# ── МОДУЛЬ 6: Бот и AWG sync ─────────────────────────────────────────────────
setup_bot_helpers() {
    say "Настройка вспомогательных скриптов..."

    # awg_sync.sh
    cat > /usr/bin/awg_sync.sh << 'AWGSYNC'
#!/bin/sh
IFACE="awg_server"
awg show "$IFACE" allowed-ips 2>/dev/null | while read -r pubkey ip; do
    [ -z "$ip" ] && continue
    ip route add "$ip" dev "$IFACE" 2>/dev/null || true
done
AWGSYNC
    chmod +x /usr/bin/awg_sync.sh
    ok "awg_sync.sh создан"

    # router_bot_daemon.sh — опрос каждые 2 сек
    cat > /usr/bin/router_bot_daemon.sh << 'BOTDAEMON'
#!/bin/sh
PIDFILE="/tmp/router_bot.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT
while true; do
    /usr/bin/router_bot.sh >/dev/null 2>&1
    sleep 2
done
BOTDAEMON
    chmod +x /usr/bin/router_bot_daemon.sh
    ok "router_bot_daemon.sh создан"

    # Прописать в sysupgrade.conf
    [ -f /etc/sysupgrade.conf ] && {
        grep -qF "awg_sync" /etc/sysupgrade.conf || echo "/usr/bin/awg_sync.sh" >> /etc/sysupgrade.conf
        grep -qF "router_bot_daemon" /etc/sysupgrade.conf || echo "/usr/bin/router_bot_daemon.sh" >> /etc/sysupgrade.conf
    }
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
line
say "  OpenWrt Setup — AmneziaWG + podkop"
say "  https://github.com/ApexZ3R0/Auto-add-domains-and-IPs-to-Podkop"
line

detect_pkg_manager
fix_dns
check_storage
$PKG_UPDATE >/dev/null 2>&1 && ok "Списки пакетов обновлены"

interactive_menu

[ "${DO_AWG:-0}"        -eq 1 ] && install_amneziawg
[ "${DO_PODKOP:-0}"     -eq 1 ] && install_podkop
[ "${DO_DYNLISTS:-0}"   -eq 1 ] && install_dynamic_lists
[ "${DO_MONITORING:-0}" -eq 1 ] && install_monitoring
[ "${DO_EXTRAS:-0}"     -eq 1 ] && install_extras
[ "${DO_EXTRAS:-0}"     -eq 1 ] && setup_bot_helpers

line
say "  Установка завершена!"
line
echo ""
echo "Следующие шаги:"
[ "${DO_AWG:-0}"    -eq 1 ] && echo "  • Настрой AmneziaWG: Network → Interfaces → awg"
[ "${DO_PODKOP:-0}" -eq 1 ] && echo "  • Настрой podkop: Services → Podkop"
[ "${DO_DYNLISTS:-0}" -eq 1 ] && echo "  • Добавь кандидатов: podkop-manage add candidate site.com"
echo ""
