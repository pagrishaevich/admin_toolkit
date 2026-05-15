#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root
require_command mount
run_cmd mkdir -p /mnt/inv /mnt/distr "$REPORTS_DIR"

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

ensure_fstab_entry() {
  local remote_path="$1"
  local mount_point="$2"
  local options="$3"
  local tmp_file=""

  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] ensure fstab entry for $mount_point -> $remote_path"
    return 0
  fi

  touch /etc/fstab

  tmp_file="$(mktemp /tmp/fstab.XXXXXX)"
  awk -v mount_point="$mount_point" '
    $0 ~ /^[[:space:]]*#/ { print; next }
    $2 == mount_point { next }
    { print }
  ' /etc/fstab > "$tmp_file"
  printf '%s %s cifs %s 0 0\n' "$remote_path" "$mount_point" "$options" >> "$tmp_file"
  cat "$tmp_file" > /etc/fstab
  rm -f "$tmp_file"
}

configure_cifs_mounts() {
  local cifs_password=""
  local inv_options=""
  local distr_options=""
  local guest_mode=0

  if [ -z "$CIFS_INV_REMOTE" ] || [ -z "$CIFS_DISTR_REMOTE" ] || [ -z "$CIFS_USERNAME" ]; then
    log "[CIFS] fstab autoconfig skipped: remote paths or username are not set"
    return 0
  fi

  if [ "$CIFS_USERNAME" = "guest" ]; then
    guest_mode=1
  fi

  cifs_password="$(read_secret "$CIFS_PASSWORD" "$CIFS_PASSWORD_FILE" || true)"
  if [ "$guest_mode" -ne 1 ] && [ -z "$cifs_password" ]; then
    log "[CIFS] fstab autoconfig skipped: CIFS password is not set"
    return 0
  fi

  if [ "$guest_mode" -eq 1 ]; then
    inv_options="guest,${CIFS_INV_MOUNT_OPTIONS}"
    distr_options="guest,${CIFS_DISTR_MOUNT_OPTIONS}"
  else
    inv_options="credentials=${CIFS_CREDENTIALS_FILE},${CIFS_INV_MOUNT_OPTIONS}"
    distr_options="credentials=${CIFS_CREDENTIALS_FILE},${CIFS_DISTR_MOUNT_OPTIONS}"
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] write CIFS credentials file $CIFS_CREDENTIALS_FILE"
  else
    mkdir -p "$(dirname "$CIFS_CREDENTIALS_FILE")"
    cat > "$CIFS_CREDENTIALS_FILE" <<EOF
username=${CIFS_USERNAME}
EOF
    printf 'password=%s\n' "$cifs_password" >> "$CIFS_CREDENTIALS_FILE"
    if [ -n "$CIFS_DOMAIN" ]; then
      printf 'domain=%s\n' "$CIFS_DOMAIN" >> "$CIFS_CREDENTIALS_FILE"
    fi
    chmod 600 "$CIFS_CREDENTIALS_FILE"
  fi

  ensure_fstab_entry "$CIFS_INV_REMOTE" /mnt/inv "$inv_options"
  ensure_fstab_entry "$CIFS_DISTR_REMOTE" /mnt/distr "$distr_options"
}

configure_cifs_mounts

if mount | grep -Eq '[[:space:]]/mnt/inv[[:space:]]'; then
  run_cmd umount /mnt/inv
fi

if mount | grep -Eq '[[:space:]]/mnt/distr[[:space:]]'; then
  run_cmd umount /mnt/distr
fi

run_cmd mount -a

log "[CIFS] done"
