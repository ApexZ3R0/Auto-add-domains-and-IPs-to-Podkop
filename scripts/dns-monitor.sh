#!/bin/sh
BASE_DIR="/etc/podkop-monitor"
MANUAL="$BASE_DIR/manual.txt"
STATE_DB="$BASE_DIR/state.db"
SEEN_FILE="/tmp/dns-monitor-seen"
LOG_TAG="dns-monitor"
CONF="$BASE_DIR/podkop-monitor.conf"
[ -f "$CONF" ] && . "$CONF"
WAN_IFACE="${WAN_IFACE:-eth1}"
CURL_TIMEOUT="${CURL_TIMEOUT:-8}"
VPS_HOST="${VPS_HOST:-root@vps}"

log() { logger -t "$LOG_TAG" "$*"; }

is_excluded_prefix() {
    domain="$1"
    echo "$domain" | grep -qiE \
        '^(imap|smtp|mail|pop|pop3|ntp|time|clock|push|apns|mtalk|stun|turn|voip|sip|mqtt|iot-mqtt|ocsp|crl|pki|certs|telemetry|metrics|analytics|stats?|logs?|logging|supl|geo|gps|loc)\.' \
        && return 0
    echo "$domain" | grep -qiE \
        '\.(akamai\.net|fastly\.net|samsungotn\.net|samsungcloudsolution\.net|pool\.ntp\.org)$' \
        && return 0
    return 1
}

is_fakeip() { echo "$1" | grep -qE '^198\.1[89]\.'; }

already_known() {
    domain="$1"
    grep -qxF "$domain" "$MANUAL" 2>/dev/null && return 0
    grep -qxF "$domain" "$BASE_DIR/auto-domains.lst" 2>/dev/null && return 0
    grep -q "^$domain " "$STATE_DB" 2>/dev/null && return 0
    uci get podkop.AmneziaWG_Ultahost.user_domains 2>/dev/null \
        | tr ' ' '\n' | grep -qxF "$domain" && return 0
    uci get podkop.AmneziaWG_Ultahost.user_domains_text 2>/dev/null \
        | tr ' ' '\n' | grep -qxF "$domain" && return 0
    return 1
}

probe_wan() {
    host="$1"
    curl -s --max-redirs 0 \
        --interface "$WAN_IFACE" \
        --connect-timeout "$CURL_TIMEOUT" \
        --max-time $((CURL_TIMEOUT+3)) \
        -o /dev/null \
        "https://$host/" 2>/dev/null
    ec=$?
    case "$ec" in
        0|22|35|56) return 0 ;;
        7) curl -s --max-redirs 0 --interface "$WAN_IFACE" \
               --connect-timeout "$CURL_TIMEOUT" \
               --max-time $((CURL_TIMEOUT+3)) \
               -o /dev/null "http://$host/" 2>/dev/null
           ec2=$?
           [ $ec2 -eq 0 ] || [ $ec2 -eq 22 ] || [ $ec2 -eq 35 ] && return 0
           return 1 ;;
        *) return 1 ;;
    esac
}

mkdir -p "$BASE_DIR"

# Expire SEEN_FILE after 30 minutes so re-checking happens within reasonable time
if [ -f "$SEEN_FILE" ]; then
    now=$(date +%s)
    mtime=$(stat -c %Y "$SEEN_FILE" 2>/dev/null || echo 0)
    age=$((now - mtime))
    [ "$age" -gt 1800 ] && rm -f "$SEEN_FILE"
fi

touch "$MANUAL" "$SEEN_FILE"

logread | grep "dnsmasq" | grep -E "query\[A\]|query\[HTTPS\]" | while IFS= read -r line; do
    domain=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="query[A]"||$i=="query[HTTPS]") {print $(i+1); exit}}')
    domain=$(echo "$domain" | sed 's/\.$//')
    [ -z "$domain" ] && continue
    echo "$domain" | grep -qv '\.' && continue
    grep -qxF "$domain" "$SEEN_FILE" && continue
    echo "$domain" >> "$SEEN_FILE"

    if already_known "$domain"; then
        log "SKIP known: $domain"
        continue
    fi
    if is_excluded_prefix "$domain"; then
        log "SKIP excluded: $domain"
        continue
    fi

    resolved=$(nslookup "$domain" 2>/dev/null \
        | awk '/^Address/{print $2}' | grep -v ':' | grep -v '^127\.' | head -1)
    if [ -z "$resolved" ]; then
        log "SKIP no-resolve: $domain"
        continue
    fi
    if is_fakeip "$resolved"; then
        log "SKIP fakeip: $domain ($resolved)"
        continue
    fi

    if ! probe_wan "$domain"; then
        log "BLOCKED locally: $domain ($resolved) — checking VPS"
        target="$resolved"
        vps_ok=$(ssh -i /root/.ssh/id_rsa -o ConnectTimeout=10 \
            -o BatchMode=yes -o StrictHostKeyChecking=no \
            "$VPS_HOST" "timeout 3 bash -c \"echo >/dev/tcp/$target/443\" 2>/dev/null && echo ok || echo fail" 2>/dev/null)
        if [ "$vps_ok" = "ok" ]; then
            echo "$domain" >> "$MANUAL"
            log "AUTO-CANDIDATE: $domain ($resolved) — недоступен локально, доступен с VPS"
        else
            log "VPS-FAIL: $domain ($resolved) vps_ok=${vps_ok:-empty}"
        fi
    else
        log "ACCESSIBLE: $domain — пропускаем"
    fi
done

sort -u "$MANUAL" > "$MANUAL.tmp" && mv "$MANUAL.tmp" "$MANUAL"
tail -10000 "$SEEN_FILE" > "$SEEN_FILE.tmp" && mv "$SEEN_FILE.tmp" "$SEEN_FILE"
