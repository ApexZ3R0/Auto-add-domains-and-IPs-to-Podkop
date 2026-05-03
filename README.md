# Dynamic lists for podkop

Автоматическое обнаружение заблокированных ресурсов и добавление их в обход через [podkop](https://github.com/itdoginfo/podkop) на OpenWrt.

## Как работает

```
cron каждые 5 минут:
  curl --interface eth1 (белый РФ IP) → кандидат
  ├── OK → сбросить счётчик неудач
  └── FAIL × 3 подряд → SSH → VPS в Германии → ping
        ├── ping OK → заблокирован провайдером
        │     → uci add_list user_domains → podkop reload
        └── ping FAIL → сервер глобально недоступен, пропуск

cron 04:30 МСК ежедневно:
  для каждого auto_added:
    curl --interface eth1 → OK × 3 ночи подряд
    → удалить из podkop UCI → podkop reload
```

**Ключевая особенность:** проверки идут строго через `eth1` (WAN с белым IP), а не через VPN-туннели устройств — это исключает ложные срабатывания когда ты включаешь VPN на телефоне и заходишь на заблокированный сайт.

## Установка

```sh
sh <(wget -O - https://raw.githubusercontent.com/ApexZ3R0/Dynamic-lists-for-podkop/main/install.sh)
```

Скрипт задаст несколько вопросов:
- WAN-интерфейс (по умолчанию `eth1`)
- SSH-цель VPS для ping-проверки
- Имя секции podkop для добавления доменов
- Пороги срабатывания

Если у тебя секция в `text`-режиме (как `user_domains_text`) — install.sh автоматически мигрирует все текущие записи в UCI dynamic-формат с бэкапом.

## Восстановление после обновления OpenWrt

```sh
# 1. Переустановить podkop-monitor
sh <(wget -O - https://raw.githubusercontent.com/ApexZ3R0/Dynamic-lists-for-podkop/main/install.sh)

# 2. Конфиг /etc/podkop-monitor/podkop-monitor.conf восстанавливается из репо
#    или можно скопировать вручную из бэкапа перед обновлением:
#    scp root@router:/etc/podkop-monitor/podkop-monitor.conf ./

# 3. Списки кандидатов:
#    scp root@router:/etc/podkop-monitor/manual.txt ./
```

> При обновлении OpenWrt `/etc/` очищается. Рекомендую перед обновлением:
> ```sh
> tar czf podkop-monitor-backup.tar.gz /etc/podkop-monitor/
> ```

## Управление

```sh
# Добавить сайт в мониторинг (blockcheck будет проверять)
podkop-manage add candidate filmix.ac

# Добавить напрямую в podkop (без ожидания 3 неудач)
podkop-manage add domain filmix.ac
podkop-manage add ip 1.2.3.0/24

# Проверить сайт прямо сейчас
podkop-manage check filmix.ac

# Посмотреть все состояния
podkop-manage list state

# Статус конкретного хоста
podkop-manage status filmix.ac

# Удалить из podkop и вернуть в мониторинг
podkop-manage remove domain filmix.ac

# Добавить remote-источник кандидатов
podkop-manage source add https://example.com/blocked-list.txt

# Сбросить счётчик неудач (false positive)
podkop-manage reset filmix.ac
```

## Структура файлов

```
/etc/podkop-monitor/
├── podkop-monitor.conf   # конфиг (WAN iface, VPS, пороги, секция podkop)
├── blockcheck.sh         # проверка кандидатов (cron 5 мин)
├── cleancheck.sh         # ночная очистка (cron 04:30 МСК)
├── migrate-to-dynamic.sh # одноразовая миграция text→dynamic UCI
├── manual.txt            # ручные кандидаты для мониторинга
├── state.db              # счётчики неудач и статусы
├── clean.db              # счётчики ночей доступности напрямую
├── remote-sources.txt    # URL удалённых списков кандидатов
└── candidates.d/         # загруженные remote-списки
    └── remote_1.txt
```

## Логи

```sh
logread | grep blockcheck    # события проверки
logread | grep cleancheck    # ночная очистка
logread | grep "ADDED"       # что добавилось
logread | grep "REMOVED"     # что удалилось
logread | grep "SUSPECT"     # подозрительные (накапливают счётчик)
```

## Статусы в state.db

| Статус | Описание |
|---|---|
| `watching` | В мониторинге, счётчик чистый |
| `watching` + fails > 0 | Накапливает неудачи (красный в `list state`) |
| `auto_added` | Добавлен автоматически, проверяется ночью |
| `manual` | Добавлен вручную, не трогается cleancheck |

## Требования

- OpenWrt 24.10+
- podkop 0.7.x с секцией в `dynamic`-режиме
- `curl`, `ssh` (openssh-client), `nslookup`
- SSH-ключ до VPS (без пароля)
- VPS с доступом в интернет (для ping-проверки)
