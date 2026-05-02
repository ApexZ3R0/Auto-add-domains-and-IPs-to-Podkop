#!/bin/sh
# cleancheck.sh — ночная проверка: если ресурс доступен напрямую — убрать из podkop
# Запуск: cron 04:30 МСК (01:30 UTC)
# Проверяет только записи со статусом auto_added

CONF="/etc/podkop-monitor/podkop-monitor.conf"
[ -f "$CONF" ] && . "$CONF"

BASE_DIR="${BASE_DIR:-/etc/podkop-monitor}"
WAN_IFACE="${WAN_IFACE:-eth1}"
PODKOP_SECTION="${PODKOP_SECTION:-MY_VPN_SECTION}"
CURL_TIMEOUT="${CURL_TIMEOUT:-8}"
LOG_TAG="cleancheck"
# Сколько раз подряд должен быть доступен напрямую перед удалением из обхода
CLEAN_THRESHOLD="${CLEAN_THRESHOLD:-3}"

STATE_DB="$BASE_DIR/state.db"
CLEAN_DB="$BASE_DIR/clean.db"   # счётчики "доступен напрямую N ночей подряд"

log() { logger -t "$LOG_TAG" "$*"; }

touch "$CLEAN_DB"

is_ip() { echo "$1" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]+)?$'; }

# ── Проверка через WAN ────────────────────────────────────────────────────────
probe_wan() {
    host="$1"
    curl -sf \
        --interface "$WAN_IFACE" \
        --connect-timeout "$CURL_TIMEOUT" \
        --max-time $((CURL_TIMEOUT+3)) \
        -o /dev/null \
        "https://$host/" 2>/dev/null
    ec=$?
    [ "$ec" -eq 0 ] || [ "$ec" -eq 35 ] && return 0
    return 1
}

# ── Счётчики clean_db ─────────────────────────────────────────────────────────
get_clean_count() { grep "^$1 " "$CLEAN_DB" 2>/dev/null | awk '{print $2+0}'; }

set_clean_count() {
    host="$1"; n="$2"
    tmp=$(mktemp)
    grep -v "^$host " "$CLEAN_DB" > "$tmp" 2>/dev/null || true
    echo "$host $n" >> "$tmp"
    mv "$tmp" "$CLEAN_DB"
}

reset_clean() {
    tmp=$(mktemp)
    grep -v "^$1 " "$CLEAN_DB" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$CLEAN_DB"
}

# ── Удалить из podkop UCI ─────────────────────────────────────────────────────
remove_from_podkop() {
    host="$1"
    if is_ip "$host"; then
        uci_key="user_subnets"
    else
        uci_key="user_domains"
    fi

    # Читаем все значения, пересобираем без удаляемого
    all=$(uci get "podkop.$PODKOP_SECTION.$uci_key" 2>/dev/null)
    uci delete "podkop.$PODKOP_SECTION.$uci_key" 2>/dev/null || true
    changed=0
    echo "$all" | tr ' ' '\n' | while IFS= read -r v; do
        v=$(echo "$v" | tr -d "'\" \t\r\n")
        [ -z "$v" ] && continue
        if [ "$v" = "$host" ]; then
            changed=1
            continue
        fi
        uci add_list "podkop.$PODKOP_SECTION.$uci_key=$v"
    done
    uci commit podkop

    # Обновить state.db: вернуть в watching
    line=$(grep "^$host " "$STATE_DB" 2>/dev/null | head -1)
    total=$(echo "$line" | awk '{print $3+0}')
    tmp=$(mktemp)
    grep -v "^$host " "$STATE_DB" > "$tmp" 2>/dev/null || true
    echo "$host 0 $total watching" >> "$tmp"
    mv "$tmp" "$STATE_DB"

    reset_clean "$host"
    log "REMOVED $host из podkop (разблокирован)"
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
log "=== Ночная проверка auto_added записей ==="

removed=0

# Берём все хосты со статусом auto_added из state.db
grep " auto_added$" "$STATE_DB" 2>/dev/null | while IFS= read -r line; do
    host=$(echo "$line" | awk '{print $1}')
    [ -z "$host" ] && continue

    if probe_wan "$host"; then
        # Доступен напрямую
        clean_n=$(get_clean_count "$host")
        clean_n=$((clean_n+1))
        set_clean_count "$host" "$clean_n"
        log "DIRECT OK $host: доступен напрямую (${clean_n}/${CLEAN_THRESHOLD})"

        if [ "$clean_n" -ge "$CLEAN_THRESHOLD" ]; then
            log "UNBLOCK $host: доступен $clean_n ночей подряд — удаляю из обхода"
            remove_from_podkop "$host"
            removed=$((removed+1))
        fi
    else
        # Всё ещё недоступен — сбросить счётчик "доступен напрямую"
        old=$(get_clean_count "$host")
        [ "${old:-0}" -gt 0 ] && {
            log "STILL BLOCKED $host: снова недоступен, сброс clean счётчика"
            reset_clean "$host"
        }
    fi
done

if [ "$removed" -gt 0 ]; then
    log "Удалено $removed записей. Reload podkop."
    /etc/init.d/podkop reload 2>/dev/null || true
else
    log "Изменений нет."
fi
