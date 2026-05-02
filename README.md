# Интерактивная установка дополнений

> [English version](README.en.md)

Интерактивный установщик для OpenWrt: выберите нужные компоненты из меню и установите всё за один запуск.

## Что устанавливает

| Компонент | Описание |
|---|---|
| **AmneziaWG** | Ядерный модуль + утилиты + luci-proto |
| **Podkop + sing-box-extended** | Обход блокировок с поддержкой VLESS/xhttp |
| **Dynamic lists** | Автодобавление заблокированных доменов в podkop |
| **Мониторинг** | banip, vnstat, netdata, collectd + luci-app-statistics |
| **Утилиты** | git, rclone, nano, tcpdump, qrencode, luci-theme-argon, pbr и др. |

## Поддерживаемые версии OpenWrt

- **24.x** — использует `opkg`
- **25.x** — использует `apk`

## Запуск

```sh
sh <(wget -O - "https://raw.githubusercontent.com/ApexZ3R0/auto-add-domains-and-ips-to-podkop/%D0%98%D0%BD%D1%82%D0%B5%D1%80%D0%B0%D0%BA%D1%82%D0%B8%D0%B2%D0%BD%D0%B0%D1%8F%20%D1%83%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0%20%D0%B4%D0%BE%D0%BF%D0%BE%D0%BB%D0%BD%D0%B5%D0%BD%D0%B8%D0%B9/setup.sh")
```

Или скачать и запустить вручную:

```sh
wget -O /tmp/setup.sh "https://raw.githubusercontent.com/ApexZ3R0/auto-add-domains-and-ips-to-podkop/%D0%98%D0%BD%D1%82%D0%B5%D1%80%D0%B0%D0%BA%D1%82%D0%B8%D0%B2%D0%BD%D0%B0%D1%8F%20%D1%83%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0%20%D0%B4%D0%BE%D0%BF%D0%BE%D0%BB%D0%BD%D0%B5%D0%BD%D0%B8%D0%B9/setup.sh"
sh /tmp/setup.sh
```

## Меню

```
  Обязательно:
    1) AmneziaWG (kmod + tools + luci-proto)
    2) Podkop + sing-box-extended

  Дополнительно:
    3) Dynamic lists (автодобавление заблокированных доменов)
    4) Мониторинг (banip, vnstat, netdata, collectd)
    5) Утилиты (git, rclone, nano, argon, pbr...)

  Пресеты:
    a) Базовый (1+2)
    b) Стандартный (1+2+3+4)
    c) Полный (всё)
```

## Что делает скрипт

1. Определяет пакетный менеджер (`apk` или `opkg`)
2. Проверяет интернет-соединение и исправляет DNS при необходимости
3. Проверяет свободное место на диске и RAM
4. Обновляет списки пакетов
5. Показывает интерактивное меню выбора компонентов
6. Устанавливает выбранные компоненты
7. Выводит список следующих шагов

## Требования

- OpenWrt 24.10+ или OpenWrt 25.x
- Доступ к интернету
- Минимум 10 МБ свободного места на диске
