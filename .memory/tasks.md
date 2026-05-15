# Задачи

## Активные

- Проверить на чистом хосте установку Kaspersky Endpoint Security с увеличенным таймаутом `KASPERSKY_SETUP_TIMEOUT`.
- Проверить реальную установку `kesl-gui` на тестовом или чистом хосте.

## Завершённые

- Добавлен `install.md` с ручными командами настройки по шагам проекта.
- Убран запуск шагов `self-update`, `proxy`, `autoupdate` из основного bootstrap-порядка.
- Убрана проверка `dnf-automatic.timer` из `postcheck`.
- Убрана установка `dnf-automatic` из базового шага `packages`.
- Исправлена команда chmod в быстрых инструкциях.
- На сервере `10.82.100.36` проверены `validate.sh`, полный `bootstrap.sh --dry-run` и реальный `bootstrap.sh --step time`.
- Исправлена обработка FQDN hostname: для доменной валидации используется short hostname.
- Исправлена идемпотентность `time`: старые строки `makestep` больше не накапливаются.
- Добавлен второй chrony-сервер `10.82.200.1`.
- Включена установка `kesl-gui` по умолчанию через `KASPERSKY_INSTALL_GUI=1`.
- Исправлены CIFS-права: `/mnt/inv` writable, `/mnt/distr` read-only.
- Исправлено автопринятие лицензии ViPNet через непрерывную подачу `YES`.
- Убран шаг `network` из bootstrap, чтобы скрипт не менял DNS и поисковый домен.
- Шаг `repos` теперь добавляет `redrepos.yanao.int` в `RedOS-Base.repo` и `RedOS-Updates.repo`.
- Добавлены `scripts/preinstall_backup.sh` и `scripts/postinstall_restore.sh` для миграции перед переустановкой РедОС 7.3 -> 8.
- Добавлены shell-тесты `tests/migration_test.sh` и их запуск из `scripts/validate.sh`.

## Известные проблемы

- `.memory/` была отсутствующей и создана только в текущей сессии.
- В рабочей копии до текущих изменений уже была локальная правка `scripts/common.sh`: `DOMAIN_USER` установлен пустым.
- `AGENTS.md` сейчас не отслеживается git.
- После успешного серверного теста backup на `10.82.100.36` SSH начал сбрасывать соединение; автоматическая очистка `/home/migration-test-backup` и `/tmp/admin_toolkit_migration_test` не подтверждена.
