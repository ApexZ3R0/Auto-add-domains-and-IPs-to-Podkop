#!/bin/sh
# install.sh — установка podkop-monitor
# Установка (OpenWrt / busybox):
#   wget -O /tmp/install.sh https://raw.githubusercontent.com/ApexZ3R0/Auto-add-domains-and-IPs-to-Podkop/main/install.sh && sh /tmp/install.sh

REPO_RAW="https://raw.githubusercontent.com/ApexZ3R0/Auto-add-domains-and-IPs-to-Podkop/main"
BASE_DIR="/etc/podkop-monitor"
BIN_DIR="/usr/bin"
CONF="$BASE_DIR/podkop-monitor.conf"

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLD='\033[1m'; NC='\033[0m'
say()  { printf "${BLD}%s${NC}\n" "$*"; }
ok()   { printf "${GRN}✓${NC} %s\n" "$*"; }
warn() { printf "${YLW}⚠${NC}  %s\n" "$*"; }
err()  { printf "${RED}✗${NC} %s\n" "$*"; }
ask()  { printf "${YLW}?${NC}  %s " "$*"; }
line() { printf "────────────────────────────────────────\n"; }
retry(){ printf "${RED}↩${NC}  %s\n" "$*"; }

# ── Зависимости ───────────────────────────────────────────────────────────────
check_deps() {
    say "Проверка зависимостей..."
    missing=""
    for cmd in curl ssh uci logger; do
        command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
    done
    if [ -n "$missing" ]; then
        warn "Отсутствуют:$missing"
        ask "Установить? [y/N]:"
        read -r ans
        if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
            opkg update >/dev/null 2>&1 || true
            for cmd in $missing; do
                case "$cmd" in
                    curl) opkg install curl ;;
                    ssh)  opkg install openssh-client ;;
                esac
            done
        fi
    else
        ok "Все зависимости на месте"
    fi
}

# ── ШАГ 1: WAN-интерфейс ─────────────────────────────────────────────────────
choose_wan() {
    say ""
    line
    say "ШАГ 1: WAN-интерфейс"
    line

    # Собираем список интерфейсов
    iface_list=$(ip link show 2>/dev/null \
        | awk -F': ' '/^[0-9]/{print $2}' \
        | tr -d ' @*' \
        | grep -v '^$')

    while true; do
        echo "Доступные интерфейсы:"
        echo ""
        i=1
        for iface in $iface_list; do
            printf "  %d) %s\n" "$i" "$iface"
            i=$((i+1))
        done
        echo ""
        ask "Номер или имя WAN-интерфейса с белым IP [eth1]:"
        read -r input
        input="${input:-eth1}"

        if echo "$input" | grep -qE '^[0-9]+$'; then
            WAN_IFACE=$(echo "$iface_list" | sed -n "${input}p")
            if [ -z "$WAN_IFACE" ]; then
                retry "Номер $input не существует — повтори ввод"
                continue
            fi
        else
            WAN_IFACE="$input"
        fi

        if ip link show "$WAN_IFACE" >/dev/null 2>&1; then
            ok "WAN-интерфейс: $WAN_IFACE"
            break
        else
            retry "Интерфейс '$WAN_IFACE' не найден — повтори ввод"
        fi
    done
}

# ── ШАГ 2: VPS SSH ────────────────────────────────────────────────────────────
setup_vps_ssh() {
    say ""
    line
    say "ШАГ 2: VPS для ping-проверки"
    line
    echo "Если сайт недоступен с роутера, но пингуется с VPS — провайдер блокирует."
    echo ""

    while true; do
        ask "SSH-цель VPS (user@host или user@ip, Enter = пропустить):"
        read -r VPS_HOST

        # Пропуск
        if [ -z "$VPS_HOST" ]; then
            warn "VPS не указан — ping-проверка отключена"
            break
        fi

        # Базовая валидация формата user@host
        if ! echo "$VPS_HOST" | grep -qE '^[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+$'; then
            retry "Неверный формат. Нужно: user@host или user@1.2.3.4"
            continue
        fi

        echo -n "  Тест SSH... "
        if ssh -i /root/.ssh/id_rsa -o ConnectTimeout=10 -o BatchMode=yes \
               -o StrictHostKeyChecking=no \
               "$VPS_HOST" "echo ok" 2>/dev/null | grep -q ok; then
            ok "SSH работает"
            break
        fi

        warn "SSH не отвечает"
        echo ""
        echo "  1) Повторить ввод адреса"
        echo "  2) Настроить SSH-ключ (сгенерировать и добавить на VPS)"
        echo "  3) Пропустить (SSH настрою позже)"
        echo ""
        ask "Выбор [1/2/3]:"
        read -r choice

        case "${choice:-1}" in
            1)
                continue
                ;;
            2)
                # Генерация ключа
                if [ ! -f /root/.ssh/id_ed25519 ] && [ ! -f /root/.ssh/id_rsa ]; then
                    mkdir -p /root/.ssh
                    chmod 700 /root/.ssh
                    ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N "" -q
                    ok "Ключ создан: /root/.ssh/id_ed25519"
                else
                    ok "SSH-ключ уже существует"
                fi

                pubkey=""
                [ -f /root/.ssh/id_ed25519.pub ] && pubkey=$(cat /root/.ssh/id_ed25519.pub)
                [ -z "$pubkey" ] && [ -f /root/.ssh/id_rsa.pub ] && pubkey=$(cat /root/.ssh/id_rsa.pub)

                if [ -n "$pubkey" ]; then
                    say ""
                    say "Выполни на VPS ($VPS_HOST):"
                    echo ""
                    printf "  echo '%s' >> ~/.ssh/authorized_keys\n" "$pubkey"
                    echo ""
                    ask "После добавления ключа нажми Enter..."
                    read -r _

                    echo -n "  Повторный тест SSH... "
                    if ssh -i /root/.ssh/id_rsa -o ConnectTimeout=10 -o BatchMode=yes \
                           -o StrictHostKeyChecking=no \
                           "$VPS_HOST" "echo ok" 2>/dev/null | grep -q ok; then
                        ok "SSH работает"
                        break
                    else
                        warn "Всё ещё не отвечает"
                        retry "Попробуй ещё раз или выбери пункт 3"
                        continue
                    fi
                fi
                ;;
            3)
                warn "SSH пропущен. После настройки проверь: ssh $VPS_HOST 'echo ok'"
                break
                ;;
            *)
                retry "Введи 1, 2 или 3"
                ;;
        esac
    done
}

# ── ШАГ 3: Секция podkop ─────────────────────────────────────────────────────
choose_section() {
    say ""
    line
    say "ШАГ 3: Секция podkop"
    line

    section_list=$(uci show podkop 2>/dev/null \
        | grep "=section" \
        | cut -d. -f2 \
        | cut -d= -f1)

    while true; do
        echo "Доступные секции:"
        echo ""
        i=1
        for s in $section_list; do
            conn=$(uci get "podkop.$s.connection_type" 2>/dev/null || echo "?")
            printf "  %d) %s (%s)\n" "$i" "$s" "$conn"
            i=$((i+1))
        done
        echo ""
        ask "Номер или имя секции для добавления доменов:"
        read -r input

        if [ -z "$input" ]; then
            retry "Секция не выбрана — повтори ввод"
            continue
        fi

        if echo "$input" | grep -qE '^[0-9]+$'; then
            PODKOP_SECTION=$(echo "$section_list" | sed -n "${input}p")
            if [ -z "$PODKOP_SECTION" ]; then
                retry "Номер $input не существует — повтори ввод"
                continue
            fi
        else
            PODKOP_SECTION="$input"
        fi

        if uci get "podkop.$PODKOP_SECTION" >/dev/null 2>&1; then
            ok "Секция: $PODKOP_SECTION"
            break
        else
            retry "Секция '$PODKOP_SECTION' не найдена в UCI — повтори ввод"
        fi
    done
}

# ── ШАГ 4: Пороги ────────────────────────────────────────────────────────────
choose_thresholds() {
    say ""
    line
    say "ШАГ 4: Пороги срабатывания"
    line

    while true; do
        ask "Неудач подряд до VPS-проверки [3]:"
        read -r FAIL_THRESHOLD
        FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"
        echo "$FAIL_THRESHOLD" | grep -qE '^[0-9]+$' && [ "$FAIL_THRESHOLD" -ge 1 ] && break
        retry "Введи число ≥ 1"
    done

    while true; do
        ask "Ночей доступности напрямую до удаления из обхода [3]:"
        read -r CLEAN_THRESHOLD
        CLEAN_THRESHOLD="${CLEAN_THRESHOLD:-3}"
        echo "$CLEAN_THRESHOLD" | grep -qE '^[0-9]+$' && [ "$CLEAN_THRESHOLD" -ge 1 ] && break
        retry "Введи число ≥ 1"
    done

    while true; do
        ask "Таймаут curl в секундах [8]:"
        read -r CURL_TIMEOUT
        CURL_TIMEOUT="${CURL_TIMEOUT:-8}"
        echo "$CURL_TIMEOUT" | grep -qE '^[0-9]+$' && [ "$CURL_TIMEOUT" -ge 1 ] && break
        retry "Введи число ≥ 1"
    done

    ok "Пороги: fails=$FAIL_THRESHOLD clean=$CLEAN_THRESHOLD timeout=${CURL_TIMEOUT}s"
}

# ── Загрузка скриптов ─────────────────────────────────────────────────────────
download_scripts() {
    say ""
    line
    say "Загрузка скриптов..."
    line
    mkdir -p "$BASE_DIR/candidates.d"
    touch "$BASE_DIR/manual.txt" "$BASE_DIR/state.db" \
          "$BASE_DIR/clean.db" "$BASE_DIR/remote-sources.txt"

    for script in blockcheck.sh cleancheck.sh dns-monitor.sh migrate-to-dynamic.sh; do
        if curl -sf "$REPO_RAW/scripts/$script" -o "$BASE_DIR/$script"; then
            chmod +x "$BASE_DIR/$script"
            ok "Загружен: $script"
        else
            err "Ошибка загрузки: $script"
        fi
    done

    if curl -sf -H "Accept: text/plain" "$REPO_RAW/scripts/podkop-manage" -o "$BIN_DIR/podkop-manage"; then
        chmod +x "$BIN_DIR/podkop-manage"
        ok "Загружен: podkop-manage"
    else
        err "Ошибка загрузки: podkop-manage"
    fi
}

# ── Конфиг ───────────────────────────────────────────────────────────────────
write_config() {
    say ""
    say "Запись конфига..."
    mkdir -p "$BASE_DIR"
    cat > "$CONF" << CONFEOF
# podkop-monitor.conf — сгенерирован $(date)
WAN_IFACE="$WAN_IFACE"
VPS_HOST="$VPS_HOST"
DNS_TRUSTED="8.8.8.8"
FAIL_THRESHOLD="$FAIL_THRESHOLD"
CLEAN_THRESHOLD="$CLEAN_THRESHOLD"
CURL_TIMEOUT="$CURL_TIMEOUT"
VPS_SSH_TIMEOUT="15"
SSH_KEY="/root/.ssh/id_rsa"
PODKOP_SECTION="$PODKOP_SECTION"
BASE_DIR="$BASE_DIR"
CONFEOF
    ok "Конфиг: $CONF"
}

# ── Миграция ─────────────────────────────────────────────────────────────────
run_migration() {
    current_type=$(uci get "podkop.$PODKOP_SECTION.user_domain_list_type" 2>/dev/null || echo "")
    say ""
    if [ "$current_type" != "dynamic" ]; then
        warn "Секция '$PODKOP_SECTION' в режиме '$current_type' (нужен 'dynamic')"
        ask "Мигрировать записи? Бэкап сохранится. [Y/n]:"
        read -r ans
        if [ "${ans:-y}" != "n" ]; then
            sh "$BASE_DIR/migrate-to-dynamic.sh" \
                && ok "Миграция завершена" \
                || warn "Ошибка — запусти вручную: sh $BASE_DIR/migrate-to-dynamic.sh"
        else
            warn "Пропущено. Вручную: uci set podkop.$PODKOP_SECTION.user_domain_list_type=dynamic"
        fi
    else
        ok "UCI уже в dynamic-режиме"
    fi
}

# ── Cron ─────────────────────────────────────────────────────────────────────
setup_cron() {
    say ""
    say "Настройка cron..."
    CRON_FILE="/etc/crontabs/root"
    touch "$CRON_FILE"
    if grep -qF "blockcheck.sh" "$CRON_FILE" 2>/dev/null; then
        ok "Cron blockcheck уже настроен"
    else
        echo "*/5 * * * * $BASE_DIR/blockcheck.sh" >> "$CRON_FILE"
        ok "Cron: blockcheck каждые 5 минут"
    fi
    if grep -qF "dns-monitor.sh" "$CRON_FILE" 2>/dev/null; then
        ok "Cron dns-monitor уже настроен"
    else
        echo "*/5 * * * * $BASE_DIR/dns-monitor.sh" >> "$CRON_FILE"
        ok "Cron: dns-monitor каждые 5 минут"
    fi
    if grep -qF "cleancheck.sh" "$CRON_FILE" 2>/dev/null; then
        ok "Cron cleancheck уже настроен"
    else
        echo "30 1 * * * $BASE_DIR/cleancheck.sh" >> "$CRON_FILE"
        ok "Cron: cleancheck 04:30 МСК"
    fi
    /etc/init.d/cron restart 2>/dev/null || true
}

# ── Итог ─────────────────────────────────────────────────────────────────────
print_summary() {
    say ""
    line
    say "  podkop-monitor установлен!"
    line
    echo ""
    echo "Конфиг:  $CONF"
    echo "Логи:    logread | grep -E 'blockcheck|dns-monitor|cleancheck'"
    echo ""
    say "Команды:"
    echo "  podkop-manage add candidate site.com   # в мониторинг"
    echo "  podkop-manage add domain site.com       # сразу в podkop"
    echo "  podkop-manage check site.com            # проверить сейчас"
    echo "  podkop-manage list state                # состояние"
    echo ""
    say "Обновление:"
    echo "  wget -O /tmp/install.sh $REPO_RAW/install.sh && sh /tmp/install.sh"
}

# ─── MAIN ────────────────────────────────────────────────────────────────────
say "podkop-monitor — установка"
say "https://github.com/ApexZ3R0/Auto-add-domains-and-IPs-to-Podkop"

check_deps
choose_wan
setup_vps_ssh
choose_section
choose_thresholds
download_scripts
write_config
run_migration
setup_cron
print_summary
