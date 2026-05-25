# RED OS Runbook (2026-04-20)

Этот документ фиксирует полный контекст сессии по адаптации `admin_toolkit_v3` под RED OS и по итогам реального прогона на хостах. Нужен для продолжения работы с нулевого контекста.

## 1. Цель сессии

- Привести bootstrap к рабочему состоянию на RED OS.
- Убрать лишние зависимости от `config.sh` и `install-host.sh`.
- Довести полный прогон до успешного `postcheck`.
- Зафиксировать реальные рабочие настройки для:
  - domain join
  - CIFS
  - Kaspersky + KSC
  - CryptoPro
  - ViPNet
  - Yandex Browser
  - R7 Office

## 2. Что поменяли концептуально

### 2.1. Конфигурация

- Отдельный `config.sh` исключён из проекта.
- Основной источник конфигурации теперь: `scripts/common.sh`.
- `config.sh.example` удалён.

### 2.2. Точка входа

- `install-host.sh` удалён.
- Основной и единственный рабочий entrypoint:

```bash
bash scripts/bootstrap.sh
```

### 2.3. Self-update

- `self-update` отключён по умолчанию.
- Причина: на целевых хостах не должно требоваться наличие `git`.
- Если когда-нибудь понадобится обратно включить автообновление:

```bash
SELF_UPDATE_ENABLED="1"
```

## 3. Подтверждённый рабочий порядок запуска

### 3.1. Базовый запуск

```bash
cd admin_toolkit_v3
bash scripts/bootstrap.sh
```

### 3.2. Продолжить с CIFS

```bash
cd admin_toolkit_v3/scripts
./bootstrap.sh --from-step cifs
```

Этот режим запускает:

- `cifs`
- `report`
- `software`
- `security`
- `postcheck`

### 3.3. Запустить только postcheck

```bash
./bootstrap.sh --step postcheck
```

## 4. Реальные проблемы, которые встретились, и как их закрыли

### 4.1. RED OS не проходил preflight

Симптом:

```text
[PREFLIGHT] unsupported distro: redos
```

Что сделали:

- Добавили `redos` в `SUPPORTED_DISTROS`.

### 4.2. Bootstrap требовал `git`

Симптом:

```text
[ERROR] missing command: git
```

Что сделали:

- `self-update` стал опциональным.
- По умолчанию он исключается из списка шагов.

### 4.3. Хост не вводился в домен из-за имени

Симптом:

`join-to-domain.sh` ругался на имя хоста длиннее 15 символов.

Что сделали:

- Добавили раннюю валидацию hostname в `preflight`.
- Добавили такую же проверку в `domain`.

Ограничение:

- только `A-Z`, `a-z`, `0-9`, `-`
- длина от 3 до 15 символов

### 4.4. Для domain join требовалась запись в `/etc/hosts`

Подтверждённый рабочий шаг перед join:

```text
127.0.0.1 <hostname>.<domain> <hostname>
```

Что сделали:

- В `scripts/domain.sh` добавили автоматическую запись этой строки.

### 4.5. Samba падала на include `usershares.conf`

Симптом:

```text
Can't find include file /etc/samba/usershares.conf
```

Что сделали:

- В `scripts/domain.sh` добавили автосоздание `/etc/samba/usershares.conf`, если он упомянут в `/etc/samba/smb.conf`.

### 4.6. Kaspersky зависал на `Activating the application`

Симптом:

```text
Activating the application
```

Что выяснили:

- На реальных хостах `kesl-setup.pl` мог зависать или очень долго ждать на этапе активации.
- Лицензия в этом контуре приходит из KSC, а не должна активироваться локально.

Что сделали:

- Убрали обязательную локальную активацию.
- Если локальная лицензия не задана, ошибка `kesl-setup.pl` больше не валит весь `software`.
- Установка `Network Agent` продолжается.
- Для setup добавили принудительный timeout.

Текущее дефолтное поведение:

- `KASPERSKY_SETUP_TIMEOUT=5`
- `KASPERSKY_SETUP_KILL_AFTER=5`

То есть Kaspersky ждём около 5 секунд и идём дальше.

### 4.7. Для Kaspersky не хватало SELinux-инструментов

Симптом:

- отсутствовали `checkmodule`
- отсутствовал `semanage`

Что сделали:

- При `KASPERSKY_CONFIGURE_SELINUX="yes"` bootstrap сам ставит:

```bash
dnf install -y checkpolicy policycoreutils-python-utils
```

### 4.8. CIFS не монтировался

Сначала была гипотеза, что нужен `guest/guest`. Она оказалась неверной.

По реальному тесту на хосте рабочий вариант такой:

```bash
mount -t cifs //10.82.107.5/inv /mnt/inv -o username=guest,password=,iocharset=utf8,vers=3
mount -t cifs //10.82.107.5/distr /mnt/distr -o username=guest,password=,iocharset=utf8,vers=3
```

Важно:

- `guest/guest` давал `STATUS_LOGON_FAILURE`
- `-o guest` давал `Invalid argument`
- `vers=3.0` для этого окружения не подходил
- рабочий вариант: `username=guest,password=,vers=3`

Что сделали:

- В `scripts/common.sh`:
  - `CIFS_USERNAME="guest"`
  - `CIFS_PASSWORD=""`
  - `CIFS_MOUNT_OPTIONS="iocharset=utf8,vers=3,_netdev,nofail,x-systemd.automount"`
- В `scripts/cifs.sh`:
  - guest mount больше не требует пароль-файл
  - credentials-файл пишется с пустым `password=`

### 4.9. ViPNet просил вручную ввести `YES`

Что сделали в stable `main`:

- попытались передавать `YES` через pipe в `dnf install`

Статус:

- на одном хосте этого оказалось недостаточно: ViPNet читает EULA через TTY

Отдельный эксперимент:

- создана отдельная ветка `vipnet-tty-eula`
- в ней ViPNet ставится через pseudo-TTY:

```bash
printf 'YES\nYES\n' | script -qec "dnf install -y <rpm>" /dev/null
```

Это изменение НЕ включено в `main`.

### 4.10. Postcheck ложно падал на ViPNet

Симптом:

```text
VIPNET RPM FAIL
```

Хотя пакет был установлен.

Что выяснили:

- проблема была не только в regex, а в `pipefail`
- конвейер `rpm -qa | grep ...` мог давать ложный FAIL

Что сделали:

- в `check_ok()` временно отключили `pipefail`
- после этого `postcheck` стал корректно показывать `SUCCESS`

## 5. Подтверждённый успешный итог

Успешный финальный `postcheck` подтверждал:

- `DOMAIN OK`
- `CIFS OK`
- `TIME OK`
- `AUTOUPDATE OK`
- `KASPERSKY RPM OK`
- `KASPERSKY SERVICE OK`
- `KASPERSKY AGENT RPM OK`
- `KASPERSKY AGENT SERVICE OK`
- `KASPERSKY AGENT SERVER OK`
- `CRYPTO_PRO RPM OK`
- `CRYPTO_PRO TUNNELS OK`
- `CRYPTO_PRO CPCONFIG OK`
- `CRYPTO_PRO RUTOKEN DRIVER OK`
- `VIPNET RPM OK`
- `VIPNET COMMAND OK`
- `YANDEX BROWSER RPM OK`
- `R7 OFFICE RPM OK`
- `[RESULT] SUCCESS`

## 6. Что в итоге уже лежит в stable `main`

Рабочая стабильная ветка на момент фиксации этого документа:

- `main`
- `origin/main`

Последний подтверждённый stable commit:

- `77fc99d` — `Reduce default Kaspersky setup wait to 5 seconds`

Примечание:

- В этой рабочей копии также существует отдельная экспериментальная ветка:
  - `vipnet-tty-eula`
  - commit: `599d868`
  - назначение: альтернативная установка ViPNet через TTY для обхода EULA prompt

## 7. Полезные команды для продолжения

### 7.1. Прогон с CIFS и дальше

```bash
cd admin_toolkit_v3/scripts
./bootstrap.sh --from-step cifs
```

### 7.2. Только software

```bash
./bootstrap.sh --step software
```

### 7.3. Только postcheck

```bash
./bootstrap.sh --step postcheck
```

### 7.4. Если остался lock bootstrap

```bash
rm -f /var/run/bootstrap.lock
```

И при необходимости проверить зависшие процессы:

```bash
ps -ef | grep -E "bootstrap.sh|kesl-setup|timeout|setsid"
```

## 8. Что ещё осталось потенциально улучшить

- Решить, нужен ли merge ветки `vipnet-tty-eula` в `main`
- При желании добавить ещё более подробный operational runbook для техников
- При желании привести `README` к более краткой форме, а этот документ оставить как memory/runbook

