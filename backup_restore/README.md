# backup_restore

Самостоятельный набор скриптов для переноса важных данных перед переустановкой РедОС 7.3 на РедОС 8.

## Что входит

- `scripts/preinstall_backup.sh` — собрать backup на старой системе.
- `scripts/postinstall_restore.sh` — восстановить backup на новой системе.
- `scripts/validate.sh` — проверить синтаксис и базовые тесты.

Backup собирает сетевые подключения, профиль Яндекс Браузера без кэша, принтеры, сканеры, сертификаты, КриптоПро/Rutoken/Jacarta, ViPNet и отдельные настройки Ассистента для удаленного подключения.

## Использование

На старой системе:

```bash
sudo bash scripts/preinstall_backup.sh --output /mnt/backup --user localuser
```

На новой системе:

```bash
sudo bash scripts/postinstall_restore.sh --backup /mnt/backup/redos-migration-host-date --target-user domain.user --target-gid 1965600513
```

При восстановлении скрипт меняет владельца только у восстановленных пользовательских каталогов и не выполняет общий `chmod -R 755 /home/<user>`.

## Проверка

```bash
bash scripts/validate.sh
```

## Безопасность

Backup содержит чувствительные данные: пароли браузера, cookies, сертификаты и настройки рабочих программ. Храните его в защищенном месте и удаляйте тестовые копии после проверки.
