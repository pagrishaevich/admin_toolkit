# Текущее состояние проекта

Проект `admin_toolkit_v3` — набор Bash-скриптов для первичной настройки Linux-хостов.

Основной оркестратор: `scripts/bootstrap.sh`.

Текущий порядок bootstrap:

1. `preflight`
2. `repos`
3. `packages`
4. `time`
5. `domain`
6. `cifs`
7. `report`
8. `software`
9. `security`
10. `postcheck`

Удалены из основного порядка запуска: `self-update`, `proxy`, `autoupdate`, `network`.

Ключевые модули:

- `scripts/common.sh` — общая конфигурация и helper-функции.
- `scripts/preflight.sh` — ранняя проверка ОС и обязательных команд.
- `scripts/time.sh` — настройка chrony/NTP.
- `scripts/software.sh` — установка Kaspersky, CryptoPro, ViPNet, Яндекс Браузера и Р7-Офис.
- `scripts/postcheck.sh` — итоговая проверка состояния.
- `scripts/preinstall_backup.sh` — сбор backup перед переустановкой РедОС.
- `scripts/postinstall_restore.sh` — восстановление backup после установки РедОС 8.

Документация для ручной настройки без bootstrap: `install.md`.
Дизайн и план миграционных скриптов: `docs/superpowers/specs/2026-05-15-redos-reinstall-migration-design.md` и `docs/superpowers/plans/2026-05-15-redos-reinstall-migration-implementation.md`.

Текущая проверка выполнялась на удалённом тестовом сервере `10.82.100.36` с RED OS 8.0.

Проверено:

- `bash scripts/validate.sh` проходит.
- `bash scripts/bootstrap.sh --dry-run` проходит до `[RESULT] SUCCESS`.
- Реальный `bash scripts/bootstrap.sh --step time` успешно настраивает chrony и оставляет `server time.yanao.ru iburst`, `server 10.82.200.1` и один `makestep 1.0 3`.
- Kaspersky Endpoint Security и Network Agent на тестовом сервере уже установлены, активны и проходят `postcheck`.
- `kesl-gui` на тестовом сервере отсутствует; `software --dry-run` с текущей версией находит `kesl-gui-12.2.0-2412.x86_64.rpm` и планирует его установку.
- CIFS проверен на тестовом сервере: `/mnt/inv` монтируется с записью для обычного пользователя, `/mnt/distr` остаётся read-only.
- ViPNet устанавливается с автоматической подачей `YES` на лицензионный вопрос.
- DNS и поисковый домен не настраиваются bootstrap-скриптом; эти параметры задаются на этапе установки ОС.
- Шаг `repos` гарантирует внутренние RED OS baseurl для `RedOS-Base.repo` и `RedOS-Updates.repo`.
- Добавлены скрипты миграции перед переустановкой: backup собирает сетевые папки, Яндекс Браузер без кэша, CUPS/SANE, сертификаты, КриптоПро/Rutoken/Jacarta, ViPNet и отдельный Ассистент; restore переносит данные локального пользователя в профиль доменного пользователя с gid по умолчанию `1965600513`.
