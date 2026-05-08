#!/bin/sh
# blockcheck.sh — проверка кандидатов через белый WAN IP
# Запуск: cron каждые 5 минут
# Логика: curl через eth1 (белый РФ IP) → 3 неудачи подряд → SSH ping с VPS
#         → если пинг ОК → добавить в podkop UCI → reload

CONF="/etc/podkop-monitor/podkop-monitor.conf"
[ -f "$CONF" ] && . "$CONF"

# ── Значения по умолчанию (переопределяются через .conf) ──────────────────────
BASE_DIR="${BASE_DIR:-/etc/podkop-monitor}"
WAN_IFACE="${WAN_IFACE:-eth1}"             # WAN-интерфейс с белым IP
PODKOP_SECTION="${PODKOP_SECTION:-MY_VPN_SECTION}"
VPS_HOST="${VPS_HOST:-root@vps}"           # SSH-цель в Германии
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"      # неудач подряд до VPS-проверки
CURL_TIMEOUT="${CURL_TIMEOUT:-8}"          # секунд на TCP
VPS_SSH_TIMEOUT="${VPS_SSH_TIMEOUT:-15}"
SSH_KEY="${SSH_KEY:-/root/.ssh/id_rsa}"
DNS_TRUSTED="${DNS_TRUSTED:-8.8.8.8}"
LOG_TAG="blockcheck"
OUT_DOMAINS="${OUT_DOMAINS:-/etc/podkop-monitor/auto-domains.lst}"
OUT_SUBNETS="${OUT_SUBNETS:-/etc/podkop-monitor/auto-subnets.lst}"
# ─────────────────────────────────────────────────────────────────────────────

STATE_DB="$BASE_DIR/state.db"
MANUAL="$BASE_DIR/manual.txt"
CANDIDATES_DIR="$BASE_DIR/candidates.d"
LOCK_FILE="/tmp/blockcheck.lock"

log() { logger -t "$LOG_TAG" "$*"; }

# ── Защита от параллельного запуска ───────────────────────────────────────────
if [ -f "$LOCK_FILE" ]; then
    pid=$(cat "$LOCK_FILE")
    kill -0 "$pid" 2>/dev/null && { log "SKIP: уже запущен (pid $pid)"; exit 0; }
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# ── State DB ──────────────────────────────────────────────────────────────────
# Формат строки: "<host> <consecutive_fails> <total_added> <status>"
# status: watching | added | auto_added

_state_line() { grep "^$1 " "$STATE_DB" 2>/dev/null | head -1; }
get_fails()   { _state_line "$1" | awk '{print $2+0}'; }
get_status()  { _state_line "$1" | awk '{print $4}'; }

set_state() {
    host="$1"; fails="$2"; total="$3"; status="$4"
    tmp=$(mktemp)
    grep -v "^$host " "$STATE_DB" > "$tmp" 2>/dev/null || true
    echo "$host $fails $total $status" >> "$tmp"
    mv "$tmp" "$STATE_DB"
}

inc_fails() {
    host="$1"
    line=$(_state_line "$host")
    f=$(echo "$line" | awk '{print $2+0}'); f=$((f+1))
    total=$(echo "$line" | awk '{print $3+0}')
    s=$(echo "$line" | awk '{print $4}'); s="${s:-watching}"
    set_state "$host" "$f" "$total" "$s"
    echo "$f"
}

reset_fails() {
    host="$1"
    line=$(_state_line "$host")
    total=$(echo "$line" | awk '{print $3+0}')
    s=$(echo "$line" | awk '{print $4}'); s="${s:-watching}"
    set_state "$host" 0 "$total" "$s"
}

# ── Тип хоста ─────────────────────────────────────────────────────────────────
is_ip() { echo "$1" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]+)?$'; }

# ── Проверка через WAN (белый IP) ─────────────────────────────────────────────
probe_wan() {
    host="$1"
    # Пробуем порт 443 (HTTPS) и 80 (HTTP)
    # Если хотя бы один отвечает — сервер доступен
    # exit 0/35 = TCP работает, exit 7 = refused (но сервер ответил!), exit 28/6 = недоступен
    for port in 443 80; do
        if [ "$port" -eq 443 ]; then
            url="https://$host/"
        else
            url="http://$host/"
        fi
        curl -s \
            --max-redirs 0 \
            --interface "$WAN_IFACE" \
            --connect-timeout "$CURL_TIMEOUT" \
            --max-time $((CURL_TIMEOUT+3)) \
            -o /dev/null \
            "$url" 2>/dev/null
        ec=$?
        case "$ec" in
            0|35|22) return 0 ;;  # OK / SSL error / HTTP error — TCP работает
            7)       return 0 ;;  # Connection refused — но TCP дошёл до сервера
        esac
    done
    return 1  # Оба порта недоступны — заблокирован или не существует
}

# ── Ping с VPS через SSH ───────────────────────────────────────────────────────
probe_vps_tcp() {
    host="$1"
    if is_ip "$host"; then
        target="$host"
    else
        target=$(nslookup "$host" "$DNS_TRUSTED" 2>/dev/null \
            | awk '/^Address/{print $2}' | grep -v ':' | grep -v '^127\.' | head -1)
        [ -z "$target" ] && { log "VPS TCP SKIP $host: не резолвится"; return 1; }
    fi

    result=$(ssh -i "$SSH_KEY" -o ConnectTimeout="$VPS_SSH_TIMEOUT" \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        "$VPS_HOST" \
        "timeout 3 bash -c \"echo >/dev/tcp/$target/443\" 2>/dev/null && echo ok || echo fail" \
        2>/dev/null)
    [ "$result" = "ok" ]
}

# ── Добавить в podkop ─────────────────────────────────────────────────────────
add_to_podkop() {
    host="$1"
    if is_ip "$host"; then
        grep -qxF "$host" "$OUT_SUBNETS" 2>/dev/null || echo "$host" >> "$OUT_SUBNETS"
        log "ADDED subnet: $host → $OUT_SUBNETS"
    else
        grep -qxF "$host" "$OUT_DOMAINS" 2>/dev/null || echo "$host" >> "$OUT_DOMAINS"
        log "ADDED domain: $host → $OUT_DOMAINS"
    fi

    # Записать с пометкой auto_added (для ночной очистки)
    line=$(_state_line "$host")
    total=$(echo "$line" | awk '{print $3+0}'); total=$((total+1))
    set_state "$host" 0 "$total" "auto_added"
}

# ── Уже в UCI? ────────────────────────────────────────────────────────────────
in_podkop() {
    host="$1"
    # Проверить в файлах автодобавления
    grep -qxF "$host" "$OUT_DOMAINS" 2>/dev/null && return 0
    grep -qxF "$host" "$OUT_SUBNETS" 2>/dev/null && return 0
    # Проверить в ручном текстовом списке podkop
    uci get "podkop.$PODKOP_SECTION.user_domains_text" 2>/dev/null \
        | grep -qxF "$host" && return 0
    uci get "podkop.$PODKOP_SECTION.user_subnets_text" 2>/dev/null \
        | grep -qxF "$host" && return 0
    return 1
}

# ── Проверка одного хоста ─────────────────────────────────────────────────────
check_host() {
    host=$(echo "$1" | tr -d ' 	
')
    [ -z "$host" ] && return
    echo "$host" | grep -q '^#' && return

    # Пропускаем если уже в podkop (добавлен вручную или ранее)
    # Статус auto_added проверяем ниже в cleancheck.sh
    status=$(get_status "$host")
    if [ "$status" = "auto_added" ] || [ "$status" = "manual" ]; then
        return
    fi
    in_podkop "$host" && return

    # Если домен резолвится в FakeIP (198.18.x.x) — он уже обрабатывается podkop
    # Не трогаем, не добавляем, просто пропускаем
    if ! is_ip "$host"; then
        resolved=$(nslookup "$host" 2>/dev/null | awk '/^Address/{print $2}' | grep -v ':' | head -1)
        echo "$resolved" | grep -qE '^198\.1[89]\.' && return
    fi

    # Curl через WAN
    if probe_wan "$host"; then
        # Доступен — сбрасываем счётчик
        old_fails=$(get_fails "$host")
        [ "${old_fails:-0}" -gt 0 ] && log "OK $host: сброс счётчика (было $old_fails)"
        reset_fails "$host"
        return
    fi

    # Недоступен через WAN
    log "FAIL wan: $host"
    consec=$(inc_fails "$host")
    log "SUSPECT $host: consecutive_fails=$consec/$FAIL_THRESHOLD"

    if [ "$consec" -ge "$FAIL_THRESHOLD" ]; then
        log "Threshold reached for $host — проверяю VPS ping..."
        if probe_vps_tcp "$host"; then
            log "VPS TCP OK: $host — добавляю в podkop"
            add_to_podkop "$host"
            /etc/init.d/podkop reload 2>/dev/null || true
            log "podkop reload после добавления $host"
        else
            log "VPS TCP FAIL: $host — сервер глобально недоступен, пропускаю"
            # Сбрасываем счётчик — это не блокировка
            reset_fails "$host"
        fi
    fi
}

# ── Загрузка remote-кандидатов ────────────────────────────────────────────────
fetch_remote() {
    SOURCES_FILE="$BASE_DIR/remote-sources.txt"
    [ -f "$SOURCES_FILE" ] || return
    idx=0
    while IFS= read -r url; do
        [ -z "$url" ] && continue
        echo "$url" | grep -q '^#' && continue
        idx=$((idx+1))
        curl -sf --connect-timeout 15 \
            -o "$CANDIDATES_DIR/remote_${idx}.txt.tmp" "$url" 2>/dev/null \
            && mv "$CANDIDATES_DIR/remote_${idx}.txt.tmp" \
                  "$CANDIDATES_DIR/remote_${idx}.txt" \
            || log "WARN: не загрузился $url"
    done < "$SOURCES_FILE"
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
fetch_remote

{
    [ -f "$MANUAL" ] && cat "$MANUAL"
    for f in "$CANDIDATES_DIR"/*.txt; do
        [ -f "$f" ] && cat "$f"
    done
} | sort -u | while IFS= read -r host; do
    check_host "$host"
done
