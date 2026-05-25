#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root
require_command systemctl
require_command awk

configure_chrony() {
  local chrony_dir=""
  local chrony_dropin=""
  local server

  if [ -d /etc/chrony.conf.d ] && [ -f "$CHRONY_CONFIG_FILE" ] && grep -Eq '^[[:space:]]*(confdir|include)[[:space:]]+/etc/chrony\.conf\.d' "$CHRONY_CONFIG_FILE"; then
    chrony_dir="/etc/chrony.conf.d"
    chrony_dropin="$chrony_dir/admin_toolkit.conf"
  else
    chrony_dropin="$CHRONY_CONFIG_FILE"
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] configure chrony with server $NTP_SERVER and extra servers: ${NTP_EXTRA_SERVERS:-none}"
    return 0
  fi

  if [ "$chrony_dropin" = "$CHRONY_CONFIG_FILE" ]; then
    backup_file "$CHRONY_CONFIG_FILE"
    if [ -f "$CHRONY_CONFIG_FILE" ]; then
      awk '
        /^[[:space:]]*(server|pool|makestep)[[:space:]]+/ { next }
        { print }
      ' "$CHRONY_CONFIG_FILE" >"${CHRONY_CONFIG_FILE}.tmp"
    else
      : >"${CHRONY_CONFIG_FILE}.tmp"
    fi
    {
      printf "server %s iburst\n" "$NTP_SERVER"
      for server in $NTP_EXTRA_SERVERS; do
        printf "server %s\n" "$server"
      done
      printf "makestep 1.0 3\n"
      cat "${CHRONY_CONFIG_FILE}.tmp"
    } >"${CHRONY_CONFIG_FILE}.new"
    mv "${CHRONY_CONFIG_FILE}.new" "$CHRONY_CONFIG_FILE"
    rm -f "${CHRONY_CONFIG_FILE}.tmp"
  else
    mkdir -p "$chrony_dir"
    cat >"$chrony_dropin" <<EOF
server ${NTP_SERVER} iburst
$(for server in $NTP_EXTRA_SERVERS; do printf "server %s\n" "$server"; done)
makestep 1.0 3
EOF
  fi
}

configure_chrony
run_cmd systemctl enable --now chronyd
run_cmd systemctl restart chronyd
log "[TIME] done"
