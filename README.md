# admin_toolkit_v2

Набор скриптов для первичной настройки Linux-хостов: пакетная инициализация, репозитории, синхронизация времени, ввод в домен, CIFS-монтирования, отчётность, установка базового ПО и итоговая проверка состояния.

![CI](https://github.com/pagrishaevich/admin_toolkit_v3/actions/workflows/shell-ci.yml/badge.svg)

## Для чего нужен проект

Проект помогает стандартизировать первичную настройку рабочих станций и управляемых хостов с помощью небольшого набора Bash-скриптов, которые можно адаптировать под конкретную инфраструктуру без постоянной переработки основной логики.

Ключевые цели:

- предсказуемый порядок bootstrap-настройки
- более безопасный повторный запуск и идемпотентное поведение
- разделение базового toolkit и локальной логики площадки

## Структура проекта

```text
scripts/
  bootstrap.sh      # основной оркестратор
  common.sh         # общий конфиг и helper-функции
  validate.sh       # локальная проверка качества
custom/
  *.local.sh        # локальные расширения под инфраструктуру
```

## Порядок выполнения

`scripts/bootstrap.sh` запускает шаги в таком порядке:

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

## Быстрый старт

1. Заполните параметры под свою инфраструктуру в `scripts/common.sh`.

2. При необходимости включите локальные расширения:

```bash
cp custom/repos.local.sh.example custom/repos.local.sh
cp custom/software.local.sh.example custom/software.local.sh
cp custom/security.local.sh.example custom/security.local.sh
```

3. Выдайте права на запуск shell-скриптам:

```bash
chmod +x scripts/*.sh
```

4. Подготовьте файлы секретов для безынтерактивного ввода в домен и монтирования CIFS:

```bash
install -d -m 700 /root/.bootstrap
printf '%s\n' 'DOMAIN_PASSWORD' > /root/.bootstrap/domain.pass
chmod 600 /root/.bootstrap/domain.pass
```

Для гостевого CIFS-доступа по умолчанию используются `CIFS_USERNAME="guest"` и разные права для шар: `/mnt/inv` монтируется с записью через `rw,noperm,file_mode=0777,dir_mode=0777`, а `/mnt/distr` остаётся только для чтения через `ro`. Если на площадке требуется пароль, дополнительно создайте `/root/.bootstrap/cifs.pass` и задайте `CIFS_PASSWORD_FILE`.

5. Запустите bootstrap от `root`:

```bash
bash scripts/bootstrap.sh
```

Полезные режимы запуска:

```bash
bash scripts/bootstrap.sh --dry-run
bash scripts/bootstrap.sh --step report
bash scripts/bootstrap.sh --from-step time
bash scripts/bootstrap.sh --list-steps
```

## Конфигурация

Основные параметры находятся в `scripts/common.sh`.

Чаще всего используются:

- `DOMAIN`, `DOMAIN_USER`, `DOMAIN_PASSWORD_FILE`
- `NTP_SERVER`, `NTP_EXTRA_SERVERS`
- `REPORTS_DIR`, `CIFS_SERVER`, `CIFS_INV_REMOTE`, `CIFS_DISTR_REMOTE`, `CIFS_USERNAME`, `CIFS_PASSWORD_FILE`, `CIFS_INV_MOUNT_OPTIONS`, `CIFS_DISTR_MOUNT_OPTIONS`
- `TOOLKIT_LOG_FILE`, `REPORT_ARCHIVE_DIR`
- `SUPPORTED_DISTROS`
- `FIREWALL_ENABLED`, `FIREWALL_SERVICES`, `FIREWALL_PORTS`
- `SSHD_HARDENING_ENABLED`, `SSHD_PERMIT_ROOT_LOGIN`, `SSHD_PASSWORD_AUTH`
- `KASPERSKY_*` для автоматической установки Kaspersky Endpoint Security из локальной папки/сетевой шары
- `CRYPTO_PRO_*` для тихой установки КриптоПро CSP из папки с дистрибутивами
- `VIPNET_*` для тихой установки ViPNet Client без импорта ключей
- `YANDEX_BROWSER_*` для установки Яндекс Браузера из подключаемого репозитория
- `R7_*` для установки Р7-Офис и опциональных пакетов из подключаемого репозитория

## Модель расширения

Базовые скрипты остаются универсальными, а логика, завязанная на конкретную площадку, выносится в локальные hooks:

- `custom/repos.local.sh`
- `custom/software.local.sh`
- `custom/security.local.sh`

Эти файлы подключаются только если существуют, поэтому core-часть проекта можно переиспользовать в разных окружениях.

Шаг `repos` дополнительно гарантирует, что в стандартных RED OS repo-файлах есть внутренние зеркала:

- `/etc/yum.repos.d/RedOS-Base.repo`: `http://redrepos.yanao.int/redos/8.0c/$basearch/os`
- `/etc/yum.repos.d/RedOS-Updates.repo`: `http://redrepos.yanao.int/redos/8.0c/$basearch/updates`

## Проверка

Локальная валидация:

```bash
bash scripts/validate.sh
```

Скрипт всегда запускает `bash -n`, а `shellcheck` и `shfmt` использует только если они установлены в системе.

Также в GitHub Actions настроена автоматическая проверка shell-скриптов на `push` и `pull request`.

## Миграция перед переустановкой РедОС

Для переноса важных данных перед установкой РедОС 8 используются отдельные скрипты:

- `scripts/preinstall_backup.sh` — собрать backup на старой системе;
- `scripts/postinstall_restore.sh` — восстановить backup на новой системе.

Backup собирает сетевые подключения, профиль Яндекс Браузера без кэша, принтеры, сканеры, сертификаты, КриптоПро/Rutoken/Jacarta, ViPNet и отдельные настройки Ассистента для удаленного подключения.

Пример:

```bash
sudo bash scripts/preinstall_backup.sh --output /mnt/backup --user localuser
sudo bash scripts/postinstall_restore.sh --backup /mnt/backup/redos-migration-host-date --target-user domain.user --target-gid 1965600513
```

При восстановлении пользовательские данные переносятся в профиль целевого доменного пользователя. Скрипт меняет владельца только у восстановленных каталогов и не выполняет общий `chmod -R 755 /home/<user>`.

## Автоустановка Kaspersky

Toolkit умеет автоматически установить Kaspersky Endpoint Security из уже смонтированной папки, если включить параметры в `scripts/common.sh`.

Минимальный пример:

```bash
KASPERSKY_ENABLED="1"
KASPERSKY_SHARE_DIR="/mnt/distr/linux/bootstrap/kesl"
KASPERSKY_INSTALL_GUI="1"
KASPERSKY_INSTALL_NETWORK_AGENT="1"
KASPERSKY_AGENT_SERVER="ksc.example.local"
# optional: set KASPERSKY_LICENSE only when activation should be performed locally
# KASPERSKY_LICENSE="/mnt/distr/linux/bootstrap/kesl/license.key"
```

Ожидается, что в `KASPERSKY_SHARE_DIR` лежат RPM-файлы вида:

- `kesl-*.rpm`
- `klnagent64-*.rpm` при включённом `KASPERSKY_INSTALL_NETWORK_AGENT="1"`
- `kesl-gui-*.rpm` при включённом `KASPERSKY_INSTALL_GUI="1"`; по умолчанию GUI включён

Шаг установки выполняется в `software` и использует штатные silent-механизмы Kaspersky:

- `kesl-setup.pl --autoinstall=...` для KESL
- `KLAUTOANSWERS=... dnf install ...` для Network Agent

## Тихая установка КриптоПро CSP

Toolkit умеет установить КриптоПро CSP 5.0 из локальной папки без графического мастера.

Минимальный пример:

```bash
CRYPTO_PRO_ENABLED="1"
CRYPTO_PRO_DIST_DIR="/mnt/distr/linux/bootstrap/cryptopro"
CRYPTO_PRO_LICENSE_KEY=""
```

Ожидается, что в `CRYPTO_PRO_DIST_DIR` лежат:

- архив `linux-amd64*.tgz`
- RPM-пакеты КриптоПро CSP x64
- опционально `librtpkcs11ecp-*.rpm` для Рутокен PKCS#11
- опционально `cprocsp-rdr-jacarta*.rpm` для JaCarta

По умолчанию модуль ставит основной набор пакетов для сценария из инструкции РЕД ОС:

- КС1
- графические диалоги
- поддержку токенов и смарт-карт
- `cptools`
- PKCS#11
- TLS-туннели (`cprocsp-stunnel-64`)

Дополнительные драйверы и лицензия включаются параметрами `CRYPTO_PRO_*`.

## Тихая установка ViPNet Client

Toolkit умеет установить ViPNet Client из локальной папки без последующей загрузки ключей.
Лицензионный вопрос установщика автоматически подтверждается ответом `YES`.

Минимальный пример:

```bash
VIPNET_ENABLED="1"
VIPNET_DIST_DIR="/mnt/distr/linux/bootstrap/vipnet"
VIPNET_VARIANT="gui"
```

Ожидается, что в `VIPNET_DIST_DIR` лежит архив `ViPNet*.zip` или уже распакованный каталог с RPM.

Варианты установки:

- `VIPNET_VARIANT="gui"` для GUI-версии
- `VIPNET_VARIANT="cli"` для консольной версии

Импорт ключей `*.dst` модуль намеренно не выполняет.

## Установка Яндекс Браузера из репозитория

Toolkit умеет автоматически подключить репозиторий Яндекс Браузера и установить сам браузер в шаге `software`.

Минимальный пример:

```bash
YANDEX_BROWSER_ENABLED="1"
YANDEX_BROWSER_RELEASE_PACKAGE="yandex-browser-release"
YANDEX_BROWSER_PACKAGE="yandex-browser-stable"
```

По инструкции РЕД ОС используется стандартная схема:

- `dnf install yandex-browser-release`
- `dnf install yandex-browser-stable`

## Установка Р7-Офис из репозитория

Toolkit умеет автоматически подключить репозиторий Р7 и установить офисный пакет в шаге `software`.

Минимальный пример:

```bash
R7_OFFICE_ENABLED="1"
R7_OFFICE_RELEASE_PACKAGE="r7-release"
R7_OFFICE_PACKAGE="r7-office"
R7_ORGANIZER_ENABLED="0"
R7_GRAFIKA_ENABLED="0"
```

По инструкции РЕД ОС используется стандартная схема:

- `dnf install r7-release`
- `dnf install r7-office`

Дополнительно можно включить:

- `r7organizer`
- `R7Grafika`

## Текущее состояние

Что уже улучшено:

- шаги `self-update`, `proxy`, `autoupdate` и `network` исключены из основного bootstrap-порядка
- DNS и поисковый домен не перезаписываются bootstrap-скриптом
- `repos` добавляет внутренние RED OS зеркала в стандартные repo-файлы
- `time` настраивает `time.yanao.ru` и `10.82.200.1`
- `cifs` монтирует `/mnt/inv` с записью, а `/mnt/distr` только для чтения
- Kaspersky GUI включён по умолчанию
- ViPNet автоматически принимает лицензионный вопрос `YES`
- добавлен `install.md` для ручной настройки без bootstrap
- конфигурация вынесена в `scripts/common.sh`
- bootstrap стал безопаснее с точки зрения lock-механизма
- для скриптов унифицирован `set -euo pipefail`
- добавлены `dry-run`, запуск отдельных шагов и `preflight`
- шаги domain и CIFS сделаны более идемпотентными
- расширен инвентаризационный отчёт в CSV и JSON
- добавлен базовый hardening для SSH и firewalld
- добавлены локальные hooks для кастомизации
- добавлены локальная валидация и CI-проверка

Что пока остаётся намеренно простым:

- `software` и часть `security` оставлены как точки расширения
- пока нет отдельной упаковки или инсталлятора
- пока нет полноценного интеграционного тестового окружения
