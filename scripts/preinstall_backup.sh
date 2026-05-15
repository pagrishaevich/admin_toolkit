#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/common.sh"

BACKUP_ROOT=""
BACKUP_DIR=""
SOURCE_USER=""
SOURCE_HOME=""
WARNINGS_FILE=""

usage() {
  cat <<'EOF'
Использование:
  sudo bash scripts/preinstall_backup.sh --output /путь/к/папке --user localuser

Назначение:
  Собрать backup важных данных перед переустановкой РедОС 7.3 на РедОС 8.

Параметры:
  --output DIR   Папка, внутри которой будет создан redos-migration-<host>-<date>
  --user USER    Локальный пользователь, чей профиль нужно сохранить
  -h, --help     Показать эту справку

Важно:
  Backup содержит чувствительные данные: пароли браузера, cookies, сертификаты
  и настройки рабочих программ. Храните его в защищенном месте.
EOF
}

browser_exclude_patterns() {
  cat <<'EOF'
Cache
Code Cache
GPUCache
ShaderCache
GrShaderCache
DawnCache
Crashpad
BrowserMetrics
*.log
*.tmp
EOF
}

if [ "${BACKUP_TEST_PRINT_BROWSER_EXCLUDES:-0}" = "1" ]; then
  browser_exclude_patterns
  exit 0
fi

warn() {
  local message="$*"

  log_warn "$message"
  if [ -n "${WARNINGS_FILE:-}" ]; then
    printf '%s\n' "$message" >>"$WARNINGS_FILE"
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --output)
        BACKUP_ROOT="${2:-}"
        shift 2
        ;;
      --user)
        SOURCE_USER="${2:-}"
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

  if [ -z "$BACKUP_ROOT" ] || [ -z "$SOURCE_USER" ]; then
    usage >&2
    exit 2
  fi
}

prepare_backup_dir() {
  local host
  local stamp

  require_root
  require_command rsync

  SOURCE_HOME="$(getent passwd "$SOURCE_USER" | awk -F: '{print $6}')"
  if [ -z "$SOURCE_HOME" ] || [ ! -d "$SOURCE_HOME" ]; then
    log "[ERROR] home directory not found for user: $SOURCE_USER"
    exit 1
  fi

  host="$(hostname -s 2>/dev/null || hostname)"
  stamp="$(date +%Y%m%d-%H%M%S)"
  BACKUP_DIR="${BACKUP_ROOT%/}/redos-migration-${host}-${stamp}"
  WARNINGS_FILE="$BACKUP_DIR/warnings.txt"

  mkdir -p "$BACKUP_DIR"
  touch "$WARNINGS_FILE"
  chmod 700 "$BACKUP_DIR"

  log "[MIGRATION] backup directory: $BACKUP_DIR"
  log "[MIGRATION] source user: $SOURCE_USER ($SOURCE_HOME)"
  log "[MIGRATION] backup contains sensitive data; protect this directory"
}

save_command_output() {
  local output_file="$1"
  shift

  mkdir -p "$(dirname "$output_file")"

  if command_exists "$1"; then
    {
      printf '$'
      printf ' %q' "$@"
      printf '\n\n'
      "$@" 2>&1 || true
    } >"$output_file"
  else
    printf 'Команда недоступна: %s\n' "$1" >"$output_file"
  fi
}

copy_path() {
  local src="$1"
  local dst="$2"
  shift 2

  if [ ! -e "$src" ]; then
    warn "Путь не найден, пропущен: $src"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  rsync -a "$@" "$src" "$dst"
}

copy_dir_contents() {
  local src="$1"
  local dst="$2"
  shift 2

  if [ ! -d "$src" ]; then
    warn "Каталог не найден, пропущен: $src"
    return 0
  fi

  mkdir -p "$dst"
  rsync -a "$@" "$src/" "$dst/"
}

collect_manifest() {
  {
    printf 'created_at=%s\n' "$(date -Is)"
    printf 'hostname=%s\n' "$(hostname)"
    printf 'source_user=%s\n' "$SOURCE_USER"
    printf 'source_home=%s\n' "$SOURCE_HOME"
    printf 'os_release=\n'
    [ -r /etc/os-release ] && sed 's/^/  /' /etc/os-release
  } >"$BACKUP_DIR/manifest.txt"
}

collect_network_mounts() {
  local dir="$BACKUP_DIR/mounts"

  mkdir -p "$dir"
  [ -r /etc/fstab ] && cp -a /etc/fstab "$dir/fstab"

  if [ -r /etc/fstab ]; then
    awk '
      /^[[:space:]]*#/ || NF < 3 { next }
      $1 ~ /^(\/\/|[A-Za-z0-9._-]+:|davfs|sshfs|smb:|afp:)/ || $3 ~ /^(cifs|smb3|nfs|nfs4|davfs|fuse.sshfs|fuse.gvfsd-fuse)$/ {
        print
      }
    ' /etc/fstab >"$dir/fstab-network.txt"
  fi

  save_command_output "$dir/findmnt-all.txt" findmnt
  if command_exists findmnt; then
    findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS |
      awk '$3 ~ /^(cifs|smb3|nfs|nfs4|davfs|fuse.sshfs|fuse.gvfsd-fuse)$/ || $2 ~ /^\/(media|run\/media|mnt)\// { print }' \
        >"$dir/active-network-mounts.txt" || true
  fi

  {
    find /media /run/media /mnt -mindepth 1 -maxdepth 3 -print 2>/dev/null || true
    find /run/user -path '*/gvfs/*' -maxdepth 5 -print 2>/dev/null || true
  } >"$dir/media-and-gvfs-paths.txt"
}

collect_yandex_browser() {
  local src="$SOURCE_HOME/.config/yandex-browser"
  local dst="$BACKUP_DIR/browser/$SOURCE_USER/yandex-browser"
  local exclude_file="$BACKUP_DIR/browser/yandex-browser-excludes.txt"

  mkdir -p "$(dirname "$exclude_file")"
  browser_exclude_patterns >"$exclude_file"

  if [ -d "$src" ]; then
    copy_dir_contents "$src" "$dst" --exclude-from="$exclude_file"
  else
    warn "Профиль Яндекс Браузера не найден: $src"
  fi
}

copy_detected_paths() {
  local section="$1"
  local label="$2"
  shift 2
  local dst_root="$BACKUP_DIR/$section"
  local detected="$dst_root/detected-paths.txt"
  local path

  mkdir -p "$dst_root/configs"
  : >"$detected"

  for path in "$@"; do
    if [ -e "$path" ]; then
      printf '%s\n' "$path" >>"$detected"
      copy_path "$path" "$dst_root/configs${path}"
    fi
  done

  if [ ! -s "$detected" ]; then
    warn "$label: типовые пути не найдены"
  fi
}

collect_named_app_data() {
  local section="$1"
  local label="$2"
  local dst_root="$BACKUP_DIR/$section"
  local detected="$dst_root/detected-paths.txt"

  mkdir -p "$dst_root/configs" "$dst_root/user-data"
  : >"$detected"

  case "$section" in
    vipnet)
      copy_detected_paths "$section" "$label" \
        /etc/vipnet /etc/infotecs /opt/vipnet /opt/infotecs /var/opt/vipnet /var/opt/infotecs
      ;;
    assistant)
      copy_detected_paths "$section" "$label" \
        /etc/assistant /etc/Ассистент /opt/assistant /opt/Ассистент /var/opt/assistant /usr/share/assistant
      ;;
  esac

  find "$SOURCE_HOME/.config" "$SOURCE_HOME/.local/share" \
    -maxdepth 3 \( -iname "*$section*" -o -iname '*assistant*' -o -iname '*ассистент*' -o -iname '*vipnet*' -o -iname '*infotecs*' \) \
    -print 2>/dev/null | while IFS= read -r path; do
      case "$section:$path" in
        vipnet:*assistant*|vipnet:*Ассистент*|vipnet:*ассистент*)
          continue
          ;;
        assistant:*vipnet*|assistant:*infotecs*)
          continue
          ;;
      esac
      printf '%s\n' "$path" >>"$detected"
      copy_path "$path" "$dst_root/user-data${path#$SOURCE_HOME}"
    done
}

collect_printers() {
  local dir="$BACKUP_DIR/printers"

  mkdir -p "$dir"
  [ -d /etc/cups ] && copy_path /etc/cups "$dir/etc/cups"
  [ -e /etc/printcap ] && copy_path /etc/printcap "$dir/etc/printcap"
  save_command_output "$dir/lpstat.txt" lpstat -t
  save_command_output "$dir/lpinfo.txt" lpinfo -v
}

collect_scanners() {
  local dir="$BACKUP_DIR/scanners"

  mkdir -p "$dir"
  [ -d /etc/sane.d ] && copy_path /etc/sane.d "$dir/etc/sane.d"
  save_command_output "$dir/scanimage.txt" scanimage -L
  save_command_output "$dir/lsusb.txt" lsusb

  mkdir -p "$dir/udev-rules"
  find /etc/udev/rules.d /lib/udev/rules.d /usr/lib/udev/rules.d \
    -maxdepth 1 -type f \( -iname '*scan*' -o -iname '*sane*' -o -iname '*rutoken*' -o -iname '*jacarta*' \) \
    -exec cp -a -t "$dir/udev-rules" {} + 2>/dev/null || true
}

collect_certificates() {
  local dir="$BACKUP_DIR/certificates"

  mkdir -p "$dir"
  [ -d /etc/pki ] && copy_path /etc/pki "$dir/etc/pki"

  find "$SOURCE_HOME" -maxdepth 5 \( -name cert9.db -o -name key4.db -o -name pkcs11.txt -o -name cert8.db -o -name key3.db \) \
    -print 2>/dev/null | while IFS= read -r path; do
      copy_path "$path" "$dir/user-nss${path#$SOURCE_HOME}"
    done
}

collect_cryptopro_tokens() {
  local dir="$BACKUP_DIR/cryptopro"

  mkdir -p "$dir/diagnostics"
  copy_detected_paths cryptopro "КриптоПро/Rutoken/Jacarta" \
    /etc/opt/cprocsp /var/opt/cprocsp /opt/cprocsp \
    /etc/rutoken /etc/jacarta /opt/aktiv /opt/jacarta

  save_command_output "$dir/diagnostics/cpconfig-hardware.txt" "$(cpconfig_cmd 2>/dev/null || printf cpconfig)" -hardware
  save_command_output "$dir/diagnostics/cpconfig-license.txt" "$(cpconfig_cmd 2>/dev/null || printf cpconfig)" -license -view
  save_command_output "$dir/diagnostics/csptest-keyset.txt" csptest -keyset -enum_cont -verifycontext -fqcn

  find "$SOURCE_HOME" -maxdepth 5 \( -iname '*cprocsp*' -o -iname '*cryptopro*' -o -iname '*rutoken*' -o -iname '*jacarta*' \) \
    -print 2>/dev/null | while IFS= read -r path; do
      copy_path "$path" "$dir/user-data${path#$SOURCE_HOME}"
    done
}

write_restore_hints() {
  cat >"$BACKUP_DIR/restore-hints.txt" <<'EOF'
Проверки после восстановления на РедОС 8:

1. Яндекс Браузер:
   yandex-browser --version
   Проверить закладки, пароли, расширения и профили.

2. Принтеры:
   lpstat -t
   systemctl status cups

3. Сканеры:
   scanimage -L
   lsusb

4. КриптоПро, Rutoken, Jacarta:
   /opt/cprocsp/sbin/amd64/cpconfig -license -view
   csptest -keyset -enum_cont -verifycontext -fqcn
   Проверить доступность контейнеров и токенов.

5. ViPNet:
   Установить ViPNet для РедОС 8, затем восстановить настройки и проверить запуск клиента.

6. Ассистент:
   Установить Ассистент для РедОС 8, затем восстановить настройки и проверить удаленное подключение.

7. Сетевые папки:
   Сверить mounts/fstab-network.txt и mounts/active-network-mounts.txt.
   Автоматически сетевые папки не монтируются.
EOF
}

main() {
  parse_args "$@"
  prepare_backup_dir
  collect_manifest
  collect_network_mounts
  collect_yandex_browser
  collect_named_app_data vipnet "ViPNet"
  collect_named_app_data assistant "Ассистент"
  collect_printers
  collect_scanners
  collect_certificates
  collect_cryptopro_tokens
  write_restore_hints

  log "[MIGRATION] backup completed: $BACKUP_DIR"
  log "[MIGRATION] read restore hints: $BACKUP_DIR/restore-hints.txt"
}

main "$@"
