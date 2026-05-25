#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_root
require_command getent

ensure_domain_hosts_entry() {
  local host_name="$1"
  local fqdn="${host_name}.${DOMAIN}"
  local hosts_file="/etc/hosts"
  local entry="127.0.0.1 ${fqdn} ${host_name}"

  if grep -Eq "^[[:space:]]*127\\.0\\.0\\.1[[:space:]]+.*\\b${fqdn}\\b.*\\b${host_name}\\b" "$hosts_file"; then
    log "[DOMAIN] hosts entry already present: $entry"
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] append to $hosts_file: $entry"
    return 0
  fi

  printf '%s\n' "$entry" >>"$hosts_file"
  log "[DOMAIN] added hosts entry: $entry"
}

ensure_samba_include_files() {
  local smb_conf="/etc/samba/smb.conf"
  local usershares_conf="/etc/samba/usershares.conf"

  [ -f "$smb_conf" ] || return 0

  if ! grep -Eq '^[[:space:]]*include[[:space:]]*=[[:space:]]*/etc/samba/usershares\.conf([[:space:]]|$)' "$smb_conf"; then
    return 0
  fi

  if [ -f "$usershares_conf" ]; then
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] create missing Samba include file: $usershares_conf"
    return 0
  fi

  install -D -m 0644 /dev/null "$usershares_conf"
  log "[DOMAIN] created missing Samba include file: $usershares_conf"
}

read_secret() {
  local direct_value="$1"
  local file_path="$2"

  if [ -n "$direct_value" ]; then
    printf '%s\n' "$direct_value"
    return 0
  fi

  if [ -n "$file_path" ] && [ -r "$file_path" ]; then
    head -n 1 "$file_path"
    return 0
  fi

  return 1
}

if ! getent hosts "$DOMAIN"; then
  log "[DOMAIN] DNS ERROR"
  exit 1
fi

HOSTNAME="$(domain_hostname)"
validate_domain_hostname "$HOSTNAME" || exit 1
ensure_domain_hosts_entry "$HOSTNAME"
ensure_samba_include_files

if realm list 2>/dev/null | grep -Fq "$DOMAIN"; then
  log "[DOMAIN] already joined"
  exit 0
fi

DOMAIN_JOIN_PASSWORD="$(read_secret "$DOMAIN_PASSWORD" "$DOMAIN_PASSWORD_FILE" || true)"

if [ -n "$DOMAIN_JOIN_PASSWORD" ]; then
  require_command realm
  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] realm join $DOMAIN with stored credentials"
  else
    printf '%s\n' "$DOMAIN_JOIN_PASSWORD" | realm join "$DOMAIN" -U "$DOMAIN_USER" --stdin
  fi
elif command -v join-to-domain.sh >/dev/null 2>&1; then
  run_cmd join-to-domain.sh -d "$DOMAIN" -n "$HOSTNAME" -u "$DOMAIN_USER" -y -f
else
  require_command realm
  run_cmd realm join "$DOMAIN" -U "$DOMAIN_USER"
fi

if command_exists systemctl; then
  run_cmd systemctl restart sssd || true
fi

log "[DOMAIN] done"
