# Текущее состояние проекта

Проект `admin_toolkit` — набор Bash-скриптов для первичной настройки Linux-хостов.

GitHub-репозиторий: `pagrishaevich/admin_toolkit` (переименован из `pagrishaevich/admin_toolkit_v3` без потери истории).
Актуальная версия опубликована в ветке `main` 2026-05-25.

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
- `scripts/software.sh` — установка Kaspersky, CryptoPro, ViPNet, Ассистент, Яндекс Браузера и Р7-Офис.
- `scripts/assistant.sh` — установка RPM Ассистент и идемпотентное добавление узлов из `redos_hosts.txt` в `/etc/hosts`.
- `scripts/postcheck.sh` — итоговая проверка состояния.
Документация для ручной настройки без bootstrap: `install.md`.
Миграционные скрипты backup/restore вынесены в отдельный локальный репозиторий `D:\Codex\backup_restore`.
Дизайн и план миграционных скриптов в истории этого проекта: `docs/superpowers/specs/2026-05-15-redos-reinstall-migration-design.md` и `docs/superpowers/plans/2026-05-15-redos-reinstall-migration-implementation.md`.

Текущая проверка выполнялась на удалённом тестовом сервере `10.82.100.36` с RED OS 8.0.

Проверено:

- `bash scripts/validate.sh` проходит.
- `bash scripts/bootstrap.sh --dry-run` проходит до `[RESULT] SUCCESS`.
- Реальный `bash scripts/bootstrap.sh --step time` успешно настраивает chrony и оставляет `server time.yanao.ru iburst`, `server 10.82.200.1` и один `makestep 1.0 3`.
- Kaspersky Endpoint Security и Network Agent на тестовом сервере уже установлены, активны и проходят `postcheck`.
- `kesl-gui` на тестовом сервере отсутствует; `software --dry-run` с текущей версией находит `kesl-gui-12.2.0-2412.x86_64.rpm` и планирует его установку.
- CIFS проверен на тестовом сервере: `/mnt/inv` монтируется с записью для обычного пользователя, `/mnt/distr` остаётся read-only.
- ViPNet устанавливается с автоматической подачей `YES` на лицензионный вопрос.
- Ассистент подключён после ViPNet в шаге `software`; `software --dry-run` на тестовом сервере находит `assistant-fstek-5.4-0.x86_64.rpm` и планирует добавить 7 узлов из `redos_hosts.txt` в `/etc/hosts`.
- Проверка CI настроена на `shellcheck` с разрешением локальных `source` и `shfmt -i 2`; строгий прогон на тестовом сервере проходит.
- DNS и поисковый домен не настраиваются bootstrap-скриптом; эти параметры задаются на этапе установки ОС.
- Шаг `repos` гарантирует внутренние RED OS baseurl для `RedOS-Base.repo` и `RedOS-Updates.repo`.
- Миграционные скрипты больше не входят в `admin_toolkit`; отдельный repo `D:\Codex\backup_restore` содержит backup сетевых папок, Яндекс Браузера без кэша, CUPS/SANE, сертификатов, КриптоПро/Rutoken/Jacarta, ViPNet и Ассистента; restore переносит данные локального пользователя в профиль доменного пользователя с gid по умолчанию `1965600513`.
