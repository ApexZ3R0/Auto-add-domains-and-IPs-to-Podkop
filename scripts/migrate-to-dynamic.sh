#!/bin/sh
# migrate-to-dynamic.sh — одноразовая миграция text → dynamic для podkop UCI
# Переносит user_domains_text и user_subnets_text в list user_domains / user_subnets
# Запускается автоматически из install.sh если нужно

CONF="/etc/podkop-monitor/podkop-monitor.conf"
[ -f "$CONF" ] && . "$CONF"
SECTION="${PODKOP_SECTION:-MY_VPN_SECTION}"

log() { echo "$*"; logger -t "migrate-podkop" "$*" 2>/dev/null || true; }

current_type=$(uci get "podkop.$SECTION.user_domain_list_type" 2>/dev/null)

if [ "$current_type" = "dynamic" ]; then
    count=$(uci get "podkop.$SECTION.user_domains" 2>/dev/null | wc -w)
    log "Уже dynamic, доменов в UCI: $count"
    [ "$1" != "--force" ] && exit 0
fi

log "Миграция секции $SECTION: $current_type → dynamic"

# Бэкап
backup="/etc/podkop-monitor/podkop.uci.bak.$(date +%Y%m%d_%H%M%S)"
mkdir -p /etc/podkop-monitor
uci export podkop > "$backup"
log "Бэкап: $backup"

domains_text=$(uci get "podkop.$SECTION.user_domains_text" 2>/dev/null || true)
subnets_text=$(uci get "podkop.$SECTION.user_subnets_text" 2>/dev/null || true)

# Переключаем тип
uci set "podkop.$SECTION.user_domain_list_type=dynamic"
uci set "podkop.$SECTION.user_subnet_list_type=dynamic"

# Очищаем старые list (если были)
uci delete "podkop.$SECTION.user_domains" 2>/dev/null || true
uci delete "podkop.$SECTION.user_subnets" 2>/dev/null || true

# Переносим домены
echo "$domains_text" | while IFS= read -r line; do
    d=$(echo "$line" | tr -d ' \t\r\n')
    [ -z "$d" ] && continue
    uci add_list "podkop.$SECTION.user_domains=$d"
    log "  + domain: $d"
done

# Переносим подсети
echo "$subnets_text" | while IFS= read -r line; do
    s=$(echo "$line" | tr -d ' \t\r\n')
    [ -z "$s" ] && continue
    uci add_list "podkop.$SECTION.user_subnets=$s"
    log "  + subnet: $s"
done

# Удаляем text-поля
uci delete "podkop.$SECTION.user_domains_text" 2>/dev/null || true
uci delete "podkop.$SECTION.user_subnets_text" 2>/dev/null || true

uci commit podkop
log "Миграция завершена. Перезапустите podkop: /etc/init.d/podkop restart"
