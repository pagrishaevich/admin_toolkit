# Deploy Checklist

Короткая памятка для подготовки новой машины и сетевого хранилища перед запуском `admin_toolkit`.

## Подготовка новой машины

1. Скопировать проект на машину.
2. Убедиться, что в `scripts/common.sh` заданы актуальные параметры.
3. Проверить, что настроено монтирование сетевого хранилища через `mount -a`.
4. Проверить, что после монтирования доступны:
   - `/mnt/inv`
   - `/mnt/distr`
5. Выполнить тестовый прогон:

```bash
bash scripts/bootstrap.sh --dry-run
```

6. Если ошибок по путям и пакетам нет, выполнить:

```bash
bash scripts/bootstrap.sh
```

## Что должно лежать на шаре

Должны существовать каталоги:

```text
/mnt/distr/linux/bootstrap/kesl
/mnt/distr/linux/bootstrap/cryptopro
/mnt/distr/linux/bootstrap/vipnet
/mnt/distr/linux/bootstrap/assistant
```

### Kaspersky

В `/mnt/distr/linux/bootstrap/kesl`:

- `kesl-*.rpm`
- `klnagent64-*.rpm`
- `kesl-gui-*.rpm`

Не требуется заранее класть локальный ключ лицензии, если лицензия выдаётся через KSC.

### CryptoPro

В `/mnt/distr/linux/bootstrap/cryptopro` рекомендуется положить:

- `linux-amd64*.tgz`
- `librtpkcs11ecp-*.rpm`

Если архив не используется, тогда рядом должны лежать RPM:

- `lsb-cprocsp-base-*.rpm`
- `lsb-cprocsp-rdr-64-*.rpm`
- `lsb-cprocsp-kc1-64-*.rpm`
- `lsb-cprocsp-capilite-64-*.rpm`
- `cprocsp-curl-64-*.rpm`
- `lsb-cprocsp-ca-certs-*.rpm`
- `cprocsp-rdr-gui-gtk-64-*.rpm`
- `cprocsp-cptools-gtk-64-*.rpm`
- `lsb-cprocsp-pkcs11-64-*.rpm`
- `cprocsp-rdr-pcsc-64-*.rpm`
- `cprocsp-stunnel-64-*.rpm`

Лицензию CryptoPro можно ввести позже.

### ViPNet

В `/mnt/distr/linux/bootstrap/vipnet`:

- `ViPNet*.zip`

или уже распакованный GUI RPM:

- `vipnetclient-gui*_x86-64_*.rpm`

Ключи ViPNet (`*.dst`) и пароли к ним заранее класть не нужно, потому что импорт ключей выполняется позже вручную.

### Ассистент

В `/mnt/distr/linux/bootstrap/assistant`:

- `assistant-fstek-*.x86_64.rpm`
- `redos_hosts.txt`

## Что должен сделать toolkit

После запуска `bash scripts/bootstrap.sh` toolkit должен:

- смонтировать `inv` и `distr`
- установить Kaspersky Endpoint Security и Network Agent
- подключить Kaspersky Agent к серверу `10.8.31.60`
- установить CryptoPro CSP с Rutoken PKCS#11, драйвером Rutoken и TLS-туннелями
- установить ViPNet Client GUI
- не импортировать ключи ViPNet
- установить Ассистент и добавить узлы из `redos_hosts.txt` в `/etc/hosts`
- выполнить итоговую проверку в `postcheck`
