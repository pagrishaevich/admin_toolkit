# Ручная настройка хоста

Короткая инструкция для настройки компьютера вручную без запуска `scripts/bootstrap.sh`.

Примеры ниже ориентированы на RED OS / RHEL-подобные системы с `dnf`, `systemd`, `chrony`, `realm` и CIFS.

Перед началом откройте `scripts/common.sh` и сверяйте значения с вашей площадкой: домен, NTP, CIFS-шары, пути к дистрибутивам и сервер Kaspersky.

## 1. Предварительная проверка

Проверить ОС:

```bash
cat /etc/os-release
```

Проверить короткое имя хоста для домена:

```bash
hostname -s
```

Имя должно быть 3-15 символов и содержать только латинские буквы, цифры и `-`.

Проверить базовые команды:

```bash
command -v dnf hostname awk grep tee systemctl getent realm mount date
```

Проверить доступность домена:

```bash
getent hosts yg.loc
```

## 2. Репозитории

Если нужны локальные репозитории площадки, настройте файлы в `/etc/yum.repos.d/`.

Для RED OS добавить внутренние зеркала в стандартные repo-файлы.

```bash
cp -a /etc/yum.repos.d/RedOS-Base.repo /etc/yum.repos.d/RedOS-Base.repo.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true
cp -a /etc/yum.repos.d/RedOS-Updates.repo /etc/yum.repos.d/RedOS-Updates.repo.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true

grep -Fq 'http://redrepos.yanao.int/redos/8.0c/$basearch/os' /etc/yum.repos.d/RedOS-Base.repo || \
  sed -i 's|^baseurl=|baseurl=http://redrepos.yanao.int/redos/8.0c/$basearch/os,|' /etc/yum.repos.d/RedOS-Base.repo

grep -Fq 'http://redrepos.yanao.int/redos/8.0c/$basearch/updates' /etc/yum.repos.d/RedOS-Updates.repo || \
  sed -i 's|^baseurl=|baseurl=http://redrepos.yanao.int/redos/8.0c/$basearch/updates,|' /etc/yum.repos.d/RedOS-Updates.repo

dnf makecache
```

Если таких файлов нет, создайте их вручную с секциями `[base]` и `[updates]`.

## 3. Базовые пакеты

Установить системные пакеты:

```bash
dnf install -y join-to-domain realmd sssd adcli oddjob oddjob-mkhomedir firewalld chrony cifs-utils unzip
```

## 4. Синхронизация времени

Настроить `chrony` на нужный NTP-сервер:

```bash
cp -a /etc/chrony.conf /etc/chrony.conf.bak.$(date +%Y%m%d%H%M%S)
awk '/^[[:space:]]*(server|pool|makestep)[[:space:]]+/ { next } { print }' /etc/chrony.conf > /etc/chrony.conf.tmp
{
  echo "server time.yanao.ru iburst"
  echo "server 10.82.200.1"
  echo "makestep 1.0 3"
  cat /etc/chrony.conf.tmp
} > /etc/chrony.conf
rm -f /etc/chrony.conf.tmp
systemctl enable --now chronyd
systemctl restart chronyd
```

Проверить:

```bash
systemctl is-active chronyd
chronyc sources -v
grep -E '^server (time\.yanao\.ru|10\.82\.200\.1)' /etc/chrony.conf
```

## 5. Ввод в домен

Проверить DNS домена:

```bash
getent hosts yg.loc
```

Добавить локальную запись хоста, если её ещё нет:

```bash
HOSTNAME_SHORT="$(hostname -s)"
grep -q "${HOSTNAME_SHORT}.yg.loc" /etc/hosts || echo "127.0.0.1 ${HOSTNAME_SHORT}.yg.loc ${HOSTNAME_SHORT}" >> /etc/hosts
```

Если есть пароль доменной учётной записи:

```bash
realm join yg.loc -U DOMAIN_USER
```

Если пароль лежит в файле:

```bash
cat /root/.bootstrap/domain.pass | realm join yg.loc -U DOMAIN_USER --stdin
```

Если используется штатный `join-to-domain.sh`:

```bash
join-to-domain.sh -d yg.loc -n "$(hostname -s)" -u DOMAIN_USER -y -f
```

Перезапустить SSSD:

```bash
systemctl restart sssd
```

Проверить:

```bash
realm list
```

## 6. CIFS-монтирования

Создать каталоги:

```bash
mkdir -p /mnt/inv /mnt/distr /mnt/inv/AGPetrosyan/reports
install -d -m 700 /root/.bootstrap
```

Создать файл учётных данных:

```bash
cat > /root/.bootstrap/cifs.creds <<'EOF'
username=guest
password=
EOF
chmod 600 /root/.bootstrap/cifs.creds
```

Добавить записи в `/etc/fstab`:

```bash
cp -a /etc/fstab /etc/fstab.bak.$(date +%Y%m%d%H%M%S)
echo "//10.82.107.5/inv /mnt/inv cifs guest,iocharset=utf8,vers=3,noperm,file_mode=0777,dir_mode=0777,_netdev,nofail,x-systemd.automount 0 0" >> /etc/fstab
echo "//10.82.107.5/distr /mnt/distr cifs guest,iocharset=utf8,vers=3,_netdev,nofail,x-systemd.automount,ro 0 0" >> /etc/fstab
```

Смонтировать:

```bash
mount -a
```

Проверить:

```bash
mount | grep -E '/mnt/inv|/mnt/distr'
touch /mnt/inv/write_test && rm -f /mnt/inv/write_test
touch /mnt/distr/write_test 2>/dev/null && echo "ОШИБКА: /mnt/distr доступен на запись" || echo "/mnt/distr только для чтения"
```

## 7. Инвентаризационный отчёт

Собрать основные данные:

```bash
HOST="$(hostname)"
FQDN="$(hostname -f 2>/dev/null || hostname)"
DATE="$(date +%F)"
IP="$(hostname -I | awk '{print $1}')"
OS_ID="$(. /etc/os-release && echo "$ID")"
OS_VERSION_ID="$(. /etc/os-release && echo "$VERSION_ID")"
SERIAL="$(cat /sys/class/dmi/id/product_serial 2>/dev/null || echo unknown)"
```

Создать CSV:

```bash
REPORT="/tmp/${HOST}_${DATE}.csv"
echo "hostname,fqdn,date,ip,os_id,os_version,serial" > "$REPORT"
echo "$HOST,$FQDN,$DATE,$IP,$OS_ID,$OS_VERSION_ID,$SERIAL" >> "$REPORT"
cp "$REPORT" /mnt/inv/AGPetrosyan/reports/ 2>/dev/null || true
```

## 8. Kaspersky Endpoint Security

Проверить наличие RPM:

```bash
ls /mnt/distr/linux/bootstrap/kesl/kesl-*.rpm
ls /mnt/distr/linux/bootstrap/kesl/klnagent64-*.rpm
```

Установить зависимости:

```bash
dnf install -y perl-Getopt-Long perl-File-Copy checkpolicy policycoreutils-python-utils
dnf install -y libxcrypt-compat || true
```

Установить KESL:

```bash
dnf install -y /mnt/distr/linux/bootstrap/kesl/kesl-*.rpm
```

Установить графический пакет KESL:

```bash
dnf install -y /mnt/distr/linux/bootstrap/kesl/kesl-gui-*.rpm
```

Создать файл silent-настройки:

```bash
cat > /tmp/kesl-autoinstall <<'EOF'
KSVLA_MODE=no
EULA_AGREED=yes
PRIVACY_POLICY_AGREED=yes
USE_KSN=yes
GROUP_CLEAN=no
LOCALE=ru_RU.UTF-8
UPDATER_SOURCE=KLServers
UPDATE_EXECUTE=yes
CONFIGURE_SELINUX=yes
DISABLE_PROTECTION=no
EOF
```

Запустить настройку:

```bash
timeout -k 10 300 setsid /opt/kaspersky/kesl/bin/kesl-setup.pl --autoinstall=/tmp/kesl-autoinstall
rm -f /tmp/kesl-autoinstall
```

Настроить Network Agent:

```bash
cat > /tmp/klnagent-answers <<'EOF'
KLNAGENT_SERVER=10.8.31.60
KLNAGENT_AUTOINSTALL=1
EULA_ACCEPTED=1
KLNAGENT_PORT=14000
KLNAGENT_SSLPORT=13000
KLNAGENT_USESSL=1
KLNAGENT_GW_MODE=2
EOF

KLAUTOANSWERS=/tmp/klnagent-answers dnf install -y /mnt/distr/linux/bootstrap/kesl/klnagent64-*.rpm
rm -f /tmp/klnagent-answers
systemctl restart kesl || true
```

Проверить:

```bash
rpm -q kesl
rpm -q kesl-gui
systemctl is-active kesl
rpm -q klnagent64
systemctl is-active klnagent64
/opt/kaspersky/klnagent64/bin/klnagchk
```

## 9. КриптоПро CSP

Проверить дистрибутив:

```bash
ls /mnt/distr/linux/bootstrap/cryptopro
```

Установить зависимости и драйверы:

```bash
dnf install -y pcsc-tools
dnf install -y ifd-rutokens
```

Если есть архив:

```bash
mkdir -p /tmp/cryptopro
tar -xf /mnt/distr/linux/bootstrap/cryptopro/linux-amd64*.tgz -C /tmp/cryptopro
```

Установить основные RPM из каталога с дистрибутивом или распакованного архива:

```bash
dnf install -y /tmp/cryptopro/*/*.rpm
```

Установить Rutoken PKCS#11, если пакет лежит отдельно:

```bash
dnf install -y /mnt/distr/linux/bootstrap/cryptopro/librtpkcs11ecp-*.rpm
```

Включить PC/SC:

```bash
systemctl enable --now pcscd.socket || systemctl enable --now pcscd.service
```

Проверить:

```bash
rpm -q lsb-cprocsp-kc1-64
rpm -q cprocsp-stunnel-64
/opt/cprocsp/sbin/amd64/cpconfig -license -view
```

## 10. ViPNet Client

Проверить дистрибутив:

```bash
ls /mnt/distr/linux/bootstrap/vipnet
```

Если лежит архив:

```bash
mkdir -p /tmp/vipnet
unzip -q /mnt/distr/linux/bootstrap/vipnet/ViPNet*.zip -d /tmp/vipnet
```

Установить GUI-вариант:

```bash
VIPNET_RPM="$(find /tmp/vipnet -type f -name 'vipnetclient-gui*_x86-64_*.rpm' | sort | tail -n 1)"
yes YES | dnf install -y "$VIPNET_RPM"
```

Если RPM лежит сразу в каталоге:

```bash
yes YES | dnf install -y /mnt/distr/linux/bootstrap/vipnet/vipnetclient-gui*_x86-64_*.rpm
```

Ключи `*.dst` вручную на этом шаге не импортируются.

Проверить:

```bash
rpm -qa | grep -E '^vipnetclient'
command -v vipnetclient
```

## 11. Ассистент

Установить пакет:

```bash
dnf install -y /mnt/distr/linux/bootstrap/assistant/assistant-fstek-5.4-0.x86_64.rpm
```

Добавить отсутствующие узлы из файла дистрибутива в конец `/etc/hosts`:

```bash
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  case "$line" in ""|\#*) continue ;; esac
  grep -Fqx "$line" /etc/hosts || printf '%s\n' "$line" >> /etc/hosts
done < /mnt/distr/linux/bootstrap/assistant/redos_hosts.txt
```

Проверить:

```bash
rpm -q assistant-fstek
grep -Fxf /mnt/distr/linux/bootstrap/assistant/redos_hosts.txt /etc/hosts
```

## 12. Яндекс Браузер

Установить пакет репозитория и браузер:

```bash
dnf install -y yandex-browser-release
dnf install -y yandex-browser-stable
```

Проверить:

```bash
rpm -q yandex-browser-stable
```

## 13. Р7-Офис

Установить пакет репозитория и офис:

```bash
dnf install -y r7-release
dnf install -y r7-office
```

Опционально:

```bash
dnf install -y r7organizer
dnf install -y R7Grafika
```

Проверить:

```bash
rpm -q r7-office
```

## 14. Безопасность

Включить firewalld:

```bash
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload
```

Настроить SSH:

```bash
cp -a /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)
grep -q '^PermitRootLogin' /etc/ssh/sshd_config && sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config || echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
grep -q '^PasswordAuthentication' /etc/ssh/sshd_config && sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
systemctl reload sshd || systemctl reload ssh || true
```

## 15. Итоговая проверка

Проверить домен, CIFS и время:

```bash
realm list | grep yg.loc
mount | grep 10.82.107.5
systemctl is-active chronyd
```

Проверить установленное ПО:

```bash
rpm -q kesl
systemctl is-active kesl
rpm -q klnagent64
systemctl is-active klnagent64
rpm -q lsb-cprocsp-kc1-64
rpm -q cprocsp-stunnel-64
rpm -qa | grep -E '^vipnetclient'
rpm -q assistant-fstek
grep -Fxf /mnt/distr/linux/bootstrap/assistant/redos_hosts.txt /etc/hosts
rpm -q yandex-browser-stable
rpm -q r7-office
```

Если все команды возвращают корректный результат, ручная настройка соответствует основному сценарию `bootstrap`.
