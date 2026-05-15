#!/bin/bash

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$COMMON_DIR/.." && pwd)"
DRY_RUN="${DRY_RUN:-0}"

: "${DOMAIN:=yg.loc}"
: "${DOMAIN_USER:=}"
: "${DOMAIN_PASSWORD:=}"
: "${DOMAIN_PASSWORD_FILE:=}"
: "${DNS_SERVERS:=10.14.100.222 10.17.101.222}"
: "${NTP_SERVER:=time.yanao.ru}"
: "${NTP_EXTRA_SERVERS:=10.82.200.1}"
: "${PROXY:=10.82.200.1:8090}"
: "${ROLE:=workstation}"
: "${ADMIN_USB_SERIAL:=CHANGE_ME}"
: "${REPORTS_DIR:=/mnt/inv/AGPetrosyan/reports}"
: "${CIFS_SERVER:=10.82.107.5}"
: "${CIFS_INV_REMOTE:=//10.82.107.5/inv}"
: "${CIFS_DISTR_REMOTE:=//10.82.107.5/distr}"
: "${CIFS_USERNAME:=guest}"
: "${CIFS_PASSWORD:=}"
: "${CIFS_PASSWORD_FILE:=}"
: "${CIFS_DOMAIN:=}"
: "${CIFS_CREDENTIALS_FILE:=/root/.bootstrap/cifs.creds}"
: "${CIFS_MOUNT_OPTIONS:=iocharset=utf8,vers=3,_netdev,nofail,x-systemd.automount}"
: "${CIFS_INV_MOUNT_OPTIONS:=${CIFS_MOUNT_OPTIONS},rw,noperm,file_mode=0777,dir_mode=0777}"
: "${CIFS_DISTR_MOUNT_OPTIONS:=${CIFS_MOUNT_OPTIONS},ro}"
: "${REPO_DIR:=/opt/admin_toolkit}"
: "${SELF_UPDATE_ENABLED:=0}"
: "${AUTO_UPDATE_REMOTE:=origin}"
: "${AUTO_UPDATE_BRANCH:=main}"
: "${DNF_PROXY_CONFIG:=/etc/dnf/dnf.conf}"
: "${CHRONY_CONFIG_FILE:=/etc/chrony.conf}"
: "${DNF_AUTOMATIC_CONFIG:=/etc/dnf/automatic.conf}"
: "${DNF_AUTO_APPLY_UPDATES:=yes}"
: "${DNF_AUTO_DOWNLOAD_UPDATES:=yes}"
: "${TOOLKIT_LOG_FILE:=/var/log/bootstrap.log}"
: "${REPORT_ARCHIVE_DIR:=/var/log/bootstrap_reports}"
: "${CUSTOM_DIR:=$PROJECT_ROOT/custom}"
: "${SUPPORTED_DISTROS:=fedora rhel rocky almalinux centos redos}"
: "${FIREWALL_ENABLED:=1}"
: "${FIREWALL_SERVICES:=ssh}"
: "${FIREWALL_PORTS:=}"
: "${SSHD_HARDENING_ENABLED:=1}"
: "${SSHD_PERMIT_ROOT_LOGIN:=no}"
: "${SSHD_PASSWORD_AUTH:=yes}"
: "${SSH_CONFIG_FILE:=/etc/ssh/sshd_config}"
: "${KASPERSKY_ENABLED:=1}"
: "${KASPERSKY_SHARE_DIR:=/mnt/distr/linux/bootstrap/kesl}"
: "${KASPERSKY_INSTALL_GUI:=1}"
: "${KASPERSKY_INSTALL_NETWORK_AGENT:=1}"
: "${KASPERSKY_ADMIN_USER:=}"
: "${KASPERSKY_LOCALE:=ru_RU.UTF-8}"
: "${KASPERSKY_USE_KSN:=yes}"
: "${KASPERSKY_CONFIGURE_SELINUX:=yes}"
: "${KASPERSKY_UPDATER_SOURCE:=KLServers}"
: "${KASPERSKY_PROXY_SERVER:=}"
: "${KASPERSKY_UPDATE_EXECUTE:=yes}"
: "${KASPERSKY_LICENSE:=}"
: "${KASPERSKY_SETUP_TIMEOUT:=300}"
: "${KASPERSKY_SETUP_KILL_AFTER:=10}"
: "${KASPERSKY_AGENT_SERVER:=10.8.31.60}"
: "${KASPERSKY_AGENT_PORT:=14000}"
: "${KASPERSKY_AGENT_SSL_PORT:=13000}"
: "${KASPERSKY_AGENT_USE_SSL:=1}"
: "${KASPERSKY_AGENT_GW_MODE:=2}"
: "${CRYPTO_PRO_ENABLED:=1}"
: "${CRYPTO_PRO_DIST_DIR:=/mnt/distr/linux/bootstrap/cryptopro}"
: "${CRYPTO_PRO_ARCHIVE_PATTERN:=linux-amd64*.tgz}"
: "${CRYPTO_PRO_INSTALL_RUTOKEN_PKCS11:=1}"
: "${CRYPTO_PRO_INSTALL_RUTOKEN_DRIVER:=1}"
: "${CRYPTO_PRO_INSTALL_JACARTA_DRIVER:=0}"
: "${CRYPTO_PRO_LICENSE_KEY:=}"
: "${VIPNET_ENABLED:=1}"
: "${VIPNET_DIST_DIR:=/mnt/distr/linux/bootstrap/vipnet}"
: "${VIPNET_ARCHIVE_PATTERN:=ViPNet*.zip}"
: "${VIPNET_VARIANT:=gui}"
: "${YANDEX_BROWSER_ENABLED:=1}"
: "${YANDEX_BROWSER_RELEASE_PACKAGE:=yandex-browser-release}"
: "${YANDEX_BROWSER_PACKAGE:=yandex-browser-stable}"
: "${R7_OFFICE_ENABLED:=1}"
: "${R7_OFFICE_RELEASE_PACKAGE:=r7-release}"
: "${R7_OFFICE_PACKAGE:=r7-office}"
: "${R7_ORGANIZER_ENABLED:=0}"
: "${R7_ORGANIZER_PACKAGE:=r7organizer}"
: "${R7_GRAFIKA_ENABLED:=0}"
: "${R7_GRAFIKA_PACKAGE:=R7Grafika}"

log() {
  local msg
  msg="[$(date '+%F %T')] $*"
  echo "$msg"
  logger -t BOOTSTRAP "$msg"
}

log_warn() {
  log "[WARN] $*"
}

require_root() {
  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] root check skipped"
    return 0
  fi

  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    log "[ERROR] run as root"
    exit 1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

cpconfig_cmd() {
  if [ -x /opt/cprocsp/sbin/amd64/cpconfig ]; then
    printf '%s\n' /opt/cprocsp/sbin/amd64/cpconfig
    return 0
  fi

  if [ -x /opt/cprocsp/sbin/cpconfig ]; then
    printf '%s\n' /opt/cprocsp/sbin/cpconfig
    return 0
  fi

  return 1
}

require_command() {
  if ! command_exists "$1"; then
    log "[ERROR] missing command: $1"
    exit 1
  fi
}

validate_domain_hostname() {
  local host_name="$1"

  if ! printf '%s' "$host_name" | grep -Eq '^[A-Za-z0-9-]{3,15}$'; then
    log "[ERROR] invalid hostname for domain join: $host_name"
    log "[ERROR] hostname must be 3-15 chars and contain only A-Z, a-z, 0-9, or -"
    return 1
  fi

  return 0
}

domain_hostname() {
  hostname -s 2>/dev/null || hostname
}

run_cmd() {
  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] $*"
    return 0
  fi

  "$@"
}

backup_file() {
  local file="$1"
  local backup

  [ -f "$file" ] || return 0

  backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
  run_cmd cp -a "$file" "$backup"
}

append_if_missing() {
  local line="$1"
  local file="$2"

  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] ensure line in $file: $line"
    return 0
  fi

  touch "$file"
  grep -Fqx "$line" "$file" || printf '%s\n' "$line" >> "$file"
}

replace_or_append_kv() {
  local key="$1"
  local value="$2"
  local file="$3"

  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] set ${key} in $file to $value"
    return 0
  fi

  touch "$file"

  if grep -Eq "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

replace_or_append_setting() {
  local key="$1"
  local value="$2"
  local file="$3"

  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] set ${key} in $file to $value"
    return 0
  fi

  touch "$file"

  if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$file"; then
    sed -i "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$file"
  else
    printf '%s %s\n' "$key" "$value" >> "$file"
  fi
}

run_local_hook() {
  local hook_name="$1"
  local hook_file="$CUSTOM_DIR/${hook_name}.local.sh"

  if [ -f "$hook_file" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "[DRY-RUN] local hook skipped: $hook_file"
      return 0
    fi

    log "[HOOK] running $hook_file"
    # shellcheck source=/dev/null
    source "$hook_file"
  else
    log "[HOOK] skipped: $hook_file not found"
  fi
}

read_os_release_field() {
  local field="$1"

  if [ -r /etc/os-release ]; then
    awk -F= -v key="$field" '$1 == key { gsub(/"/, "", $2); print $2 }' /etc/os-release
  fi
}
