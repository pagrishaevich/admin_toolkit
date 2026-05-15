#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/common.sh"

DEFAULT_DOMAIN_GID=1965600513

BACKUP_DIR=""
TARGET_USER=""
TARGET_GID="$DEFAULT_DOMAIN_GID"
TARGET_HOME=""
RESTORE_LOG=""

usage() {
  cat <<EOF
Использование:
  sudo bash scripts/postinstall_restore.sh --backup /путь/redos-migration-host-date --target-user domain.user [--target-gid $DEFAULT_DOMAIN_GID] [--target-home /home/domain.user]

Назначение:
  Восстановить данные после установки РедОС 8.

Параметры:
  --backup DIR       Каталог backup, созданный preinstall_backup.sh
  --target-user USER Доменный пользователь, которому передаются пользовательские данные
  --target-gid GID   GID доменной группы. По умолчанию: $DEFAULT_DOMAIN_GID
  --target-home DIR  Домашний каталог. По умолчанию: /home/<target-user>
  -h, --help         Показать эту справку

Важно:
  Скрипт меняет владельца только у восстановленных пользовательских каталогов,
  а не выполняет chmod/chown по всему home без необходимости.
EOF
}

restore_hints_template() {
  cat <<'EOF'
Проверки после восстановления:
- Яндекс Браузер: проверить закладки, пароли, расширения и профили.
- Принтеры: выполнить lpstat -t и проверить печать тестовой страницы.
- Сканеры: выполнить scanimage -L и проверить обнаружение устройства.
- КриптоПро: проверить лицензию, контейнеры и токены штатными утилитами.
- Rutoken/Jacarta: проверить видимость токенов после установки драйверов.
- ViPNet: сначала установить ViPNet для РедОС 8, затем проверить настройки.
- Ассистент: сначала установить Ассистент для РедОС 8, затем проверить удаленное подключение.
- Сетевые папки: вручную сверить сохраненные отчеты из раздела mounts.
EOF
}

if [ "${RESTORE_TEST_PRINT_HINTS:-0}" = "1" ]; then
  restore_hints_template
  exit 0
fi

warn() {
  local message="$*"

  log_warn "$message"
  if [ -n "${RESTORE_LOG:-}" ]; then
    printf '[WARN] %s\n' "$message" >>"$RESTORE_LOG"
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --backup)
        BACKUP_DIR="${2:-}"
        shift 2
        ;;
      --target-user)
        TARGET_USER="${2:-}"
        shift 2
        ;;
      --target-gid)
        TARGET_GID="${2:-}"
        shift 2
        ;;
      --target-home)
        TARGET_HOME="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'Неизвестный параметр: %s\n\n' "$1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  if [ -z "$BACKUP_DIR" ] || [ -z "$TARGET_USER" ]; then
    usage >&2
    exit 2
  fi

  if [ -z "$TARGET_HOME" ]; then
    TARGET_HOME="/home/$TARGET_USER"
  fi
}

prepare_restore() {
  require_root
  require_command rsync

  if [ ! -d "$BACKUP_DIR" ]; then
    log "[ERROR] backup directory not found: $BACKUP_DIR"
    exit 1
  fi

  RESTORE_LOG="$BACKUP_DIR/restore.log"
  touch "$RESTORE_LOG"
  mkdir -p "$TARGET_HOME"

  log "[MIGRATION] restore from: $BACKUP_DIR"
  log "[MIGRATION] target user: $TARGET_USER"
  log "[MIGRATION] target gid: $TARGET_GID"
  log "[MIGRATION] target home: $TARGET_HOME"
}

backup_existing_path() {
  local path="$1"
  local backup

  if [ ! -e "$path" ]; then
    return 0
  fi

  backup="${path}.pre-redos-restore.$(date +%Y%m%d%H%M%S)"
  mv "$path" "$backup"
  log "[MIGRATION] existing path moved to: $backup"
}

restore_dir() {
  local src="$1"
  local dst="$2"

  if [ ! -d "$src" ]; then
    warn "Раздел backup отсутствует, пропущен: $src"
    return 0
  fi

  backup_existing_path "$dst"
  mkdir -p "$dst"
  rsync -a "$src/" "$dst/"
}

restore_file() {
  local src="$1"
  local dst="$2"

  if [ ! -f "$src" ]; then
    warn "Файл backup отсутствует, пропущен: $src"
    return 0
  fi

  backup_existing_path "$dst"
  mkdir -p "$(dirname "$dst")"
  rsync -a "$src" "$dst"
}

restore_user_dir() {
  local src="$1"
  local dst="$2"

  restore_dir "$src" "$dst"
  if [ -d "$dst" ]; then
    chown -R "$TARGET_USER:$TARGET_GID" "$dst"
  fi
}

restore_user_overlay() {
  local src="$1"

  if [ ! -d "$src" ]; then
    warn "Пользовательский раздел backup отсутствует, пропущен: $src"
    return 0
  fi

  mkdir -p "$TARGET_HOME"
  rsync -a --chown="$TARGET_USER:$TARGET_GID" "$src/" "$TARGET_HOME/"
}

restore_yandex_browser() {
  local browser_root="$BACKUP_DIR/browser"
  local src
  local dst="$TARGET_HOME/.config/yandex-browser"

  src="$(find "$browser_root" -mindepth 2 -maxdepth 2 -type d -name yandex-browser 2>/dev/null | head -n 1 || true)"
  if [ -z "$src" ]; then
    warn "Профиль Яндекс Браузера в backup не найден"
    return 0
  fi

  mkdir -p "$TARGET_HOME/.config"
  restore_user_dir "$src" "$dst"
}

restore_system_dir() {
  local src="$1"
  local dst="$2"
  local required_path="$3"
  local label="$4"

  if [ ! -e "$required_path" ]; then
    warn "$label не найден на новой системе; сначала установите ПО, затем повторите восстановление раздела"
    return 0
  fi

  restore_dir "$src" "$dst"
}

restore_printers() {
  restore_system_dir "$BACKUP_DIR/printers/etc/cups" /etc/cups /etc/cups CUPS
  [ -e "$BACKUP_DIR/printers/etc/printcap" ] && restore_file "$BACKUP_DIR/printers/etc/printcap" /etc/printcap

  if command_exists systemctl; then
    systemctl restart cups 2>/dev/null || warn "Не удалось перезапустить cups"
  fi
}

restore_scanners() {
  restore_system_dir "$BACKUP_DIR/scanners/etc/sane.d" /etc/sane.d /etc/sane.d SANE

  if [ -d "$BACKUP_DIR/scanners/udev-rules" ] && [ -d /etc/udev/rules.d ]; then
    rsync -a "$BACKUP_DIR/scanners/udev-rules/" /etc/udev/rules.d/
    if command_exists udevadm; then
      udevadm control --reload-rules 2>/dev/null || warn "Не удалось перечитать udev rules"
    fi
  fi
}

restore_certificates() {
  [ -d "$BACKUP_DIR/certificates/etc/pki" ] && restore_system_dir "$BACKUP_DIR/certificates/etc/pki" /etc/pki /etc/pki "/etc/pki"

  if [ -d "$BACKUP_DIR/certificates/user-nss" ]; then
    restore_user_overlay "$BACKUP_DIR/certificates/user-nss"
  fi
}

restore_cryptopro_tokens() {
  [ -d "$BACKUP_DIR/cryptopro/configs/etc/opt/cprocsp" ] &&
    restore_system_dir "$BACKUP_DIR/cryptopro/configs/etc/opt/cprocsp" /etc/opt/cprocsp /opt/cprocsp "КриптоПро"
  [ -d "$BACKUP_DIR/cryptopro/configs/var/opt/cprocsp" ] &&
    restore_system_dir "$BACKUP_DIR/cryptopro/configs/var/opt/cprocsp" /var/opt/cprocsp /opt/cprocsp "КриптоПро"
  [ -d "$BACKUP_DIR/cryptopro/user-data" ] &&
    restore_user_overlay "$BACKUP_DIR/cryptopro/user-data"
}

restore_named_app_data() {
  local section="$1"
  local label="$2"

  if [ ! -d "$BACKUP_DIR/$section" ]; then
    warn "$label: раздел backup отсутствует"
    return 0
  fi

  case "$section" in
    vipnet)
      [ -d "$BACKUP_DIR/$section/configs/etc/vipnet" ] && restore_system_dir "$BACKUP_DIR/$section/configs/etc/vipnet" /etc/vipnet /opt/vipnet "$label"
      [ -d "$BACKUP_DIR/$section/configs/etc/infotecs" ] && restore_system_dir "$BACKUP_DIR/$section/configs/etc/infotecs" /etc/infotecs /opt/infotecs "$label"
      [ -d "$BACKUP_DIR/$section/user-data" ] && restore_user_overlay "$BACKUP_DIR/$section/user-data"
      ;;
    assistant)
      [ -d "$BACKUP_DIR/$section/configs/etc/assistant" ] && restore_system_dir "$BACKUP_DIR/$section/configs/etc/assistant" /etc/assistant /opt/assistant "$label"
      [ -d "$BACKUP_DIR/$section/user-data" ] && restore_user_overlay "$BACKUP_DIR/$section/user-data"
      ;;
  esac
}

write_restore_hints() {
  {
    restore_hints_template
    printf '\nBackup с исходными подсказками: %s/restore-hints.txt\n' "$BACKUP_DIR"
    printf 'Лог восстановления: %s\n' "$RESTORE_LOG"
  } >"$BACKUP_DIR/restore-after-run-hints.txt"
}

main() {
  parse_args "$@"
  prepare_restore
  restore_yandex_browser
  restore_named_app_data vipnet "ViPNet"
  restore_named_app_data assistant "Ассистент"
  restore_printers
  restore_scanners
  restore_certificates
  restore_cryptopro_tokens
  write_restore_hints

  log "[MIGRATION] restore completed with warnings file: $RESTORE_LOG"
}

main "$@"
