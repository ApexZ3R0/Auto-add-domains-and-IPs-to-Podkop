# Auto-add domains and IPs to Podkop

> [English version](README.en.md)

Автоматическое обнаружение заблокированных ресурсов и добавление их в обход через [podkop](https://github.com/itdoginfo/podkop) на OpenWrt.

## Как работает

```
dns-monitor (cron каждые 5 минут):
  Парсит DNS логи dnsmasq → находит новые домены
  Проверяет TCP 443/80 через eth1 (белый РФ IP)
  └── недоступен → добавить в кандидаты (manual.txt)

blockcheck (cron каждые 5 минут):
  curl через eth1 → кандидат
  ├── OK → сбросить счётчик неудач
  └── FAIL × 3 подряд → SSH → VPS → ping
        ├── ping OK → заблокирован провайдером
        │     → записать в auto-domains.lst / auto-subnets.lst
        │     → podkop reload
        └── ping FAIL → сервер глобально недоступен, пропуск

cleancheck (cron 04:30 МСК ежедневно):
  для каждого auto_added:
    curl через eth1 → OK × 3 ночи подряд
    → удалить из auto-domains.lst / auto-subnets.lst
    → podkop reload
```

**Ключевые особенности:**
- Проверки идут строго через `eth1` (WAN с белым IP) — исключает ложные срабатывания от VPN на устройствах
- Домены и IP пишутся в локальные файлы которые podkop читает напрямую — ручные списки не трогаются
- dns-monitor автоматически подхватывает домены к которым устройства в сети пытаются подключиться

## Установка

```sh
wget -O /tmp/install.sh https://raw.githubusercontent.com/ApexZ3R0/Auto-add-domains-and-IPs-to-Podkop/main/install.sh && sh /tmp/install.sh
```

Скрипт задаст несколько вопросов:
- WAN-интерфейс (по умолчанию `eth1`)
- SSH-цель VPS для ping-проверки
- Имя секции podkop
- Пороги срабатывания

После установки добавь в podkop локальные файлы (Services → Podkop → секция → Локальные списки):
- **Локальные списки доменов:** `/etc/podkop-monitor/auto-domains.lst`
- **Локальные списки подсетей:** `/etc/podkop-monitor/auto-subnets.lst`

## Управление

```sh
# Добавить сайт в мониторинг
podkop-manage add candidate filmix.ac

# Добавить напрямую в podkop (без ожидания 3 неудач)
podkop-manage add domain filmix.ac
podkop-manage add ip 1.2.3.0/24

# Проверить сайт прямо сейчас
podkop-manage check filmix.ac

# Посмотреть состояние мониторинга
podkop-manage list state

# Удалить из podkop и вернуть в мониторинг
podkop-manage remove domain filmix.ac

# Сбросить счётчик неудач
podkop-manage reset filmix.ac
```

## Просмотр автодобавленных записей

```sh
cat /etc/podkop-monitor/auto-domains.lst
cat /etc/podkop-monitor/auto-subnets.lst
podkop-manage list state
```

## Структура файлов

```
/etc/podkop-monitor/
├── podkop-monitor.conf    # конфиг
├── blockcheck.sh          # проверка кандидатов (cron 5 мин)
├── cleancheck.sh          # ночная очистка (cron 04:30 МСК)
├── dns-monitor.sh         # автодобавление из DNS логов (cron 5 мин)
├── manual.txt             # ручные кандидаты
├── auto-domains.lst       # → podkop: Локальные списки доменов
├── auto-subnets.lst       # → podkop: Локальные списки подсетей
├── state.db               # счётчики и статусы
├── clean.db               # счётчики ночей доступности
└── remote-sources.txt     # URL удалённых списков
```

## Логи

```sh
logread | grep blockcheck     # события проверки
logread | grep cleancheck     # ночная очистка
logread | grep dns-monitor    # автодобавление из DNS
logread | grep "ADDED"        # что добавилось
logread | grep "REMOVED"      # что удалилось
```

## Другие скрипты репозитория

| Ветка | Назначение |
|---|---|
| [Интерактивная-установка-дополнений](../../tree/Интерактивная-установка-дополнений) | Установка AmneziaWG + podkop + dynamic lists |
| [Доустановка-пакетов-и-настроек-после-обновления-с-OpenWRT-24.x-на-25.x](../../tree/Доустановка-пакетов-и-настроек-после-обновления-с-OpenWRT-24.x-на-25.x) | Восстановление после обновления OpenWrt 25.x |

## Требования

- OpenWrt 24.10+ или 25.x
- podkop 0.7.x
- `curl`, `ssh`, `nslookup`
- SSH-ключ до VPS (без пароля)
- VPS с доступом в интернет
- Включённое логирование dnsmasq (`logqueries=1`)
