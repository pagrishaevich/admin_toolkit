#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_root

REPORT="/tmp/$(hostname)_$(date +%F).csv"
REPORT_JSON="/tmp/$(hostname)_$(date +%F).json"

HOST=$(hostname)
FQDN=$(hostname -f 2>/dev/null || hostname)
DATE=$(date +%F)
IP=""
MAC=""
OS_ID=$(read_os_release_field ID)
OS_VERSION_ID=$(read_os_release_field VERSION_ID)
TIMEZONE="unknown"
DOMAIN_STATUS="not_joined"
CIFS_STATUS="not_mounted"
SERIAL=$(cat /sys/class/dmi/id/product_serial 2>/dev/null || echo unknown)

if hostname -I >/dev/null 2>&1; then
  IP=$(hostname -I 2>/dev/null | awk '{print $1}')
elif command_exists ip; then
  IP=$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
fi

if command_exists ip; then
  MAC=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $5; exit}' | xargs -I{} cat "/sys/class/net/{}/address" 2>/dev/null || true)
fi

if command_exists timedatectl; then
  TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo unknown)
elif [ -r /etc/timezone ]; then
  TIMEZONE=$(cat /etc/timezone)
fi

if command_exists realm; then
  realm list 2>/dev/null | grep -Fq "$DOMAIN" && DOMAIN_STATUS="joined"
fi

mount | grep -Fq "$CIFS_SERVER" && CIFS_STATUS="mounted"

if [ "$DRY_RUN" = "1" ]; then
  log "[DRY-RUN] report would be written to $REPORT and $REPORT_JSON"
  log "[REPORT] hostname=$HOST fqdn=$FQDN ip=$IP os=${OS_ID:-unknown} ${OS_VERSION_ID:-unknown}"
  exit 0
fi

printf "hostname,fqdn,date,ip,mac,os_id,os_version,role,domain_status,cifs_status,timezone,serial\n" >"$REPORT"
printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
  "$HOST" "$FQDN" "$DATE" "$IP" "$MAC" "$OS_ID" "$OS_VERSION_ID" "$ROLE" "$DOMAIN_STATUS" "$CIFS_STATUS" "$TIMEZONE" "$SERIAL" >>"$REPORT"

cat >"$REPORT_JSON" <<EOF
{
  "hostname": "$HOST",
  "fqdn": "$FQDN",
  "date": "$DATE",
  "ip": "$IP",
  "mac": "$MAC",
  "os_id": "$OS_ID",
  "os_version": "$OS_VERSION_ID",
  "role": "$ROLE",
  "domain_status": "$DOMAIN_STATUS",
  "cifs_status": "$CIFS_STATUS",
  "timezone": "$TIMEZONE",
  "serial": "$SERIAL"
}
EOF

run_cmd mkdir -p "$REPORTS_DIR" "$REPORT_ARCHIVE_DIR"

run_cmd cp "$REPORT" "$REPORTS_DIR/" || true
run_cmd cp "$REPORT" "$REPORT_ARCHIVE_DIR/"
run_cmd cp "$REPORT_JSON" "$REPORTS_DIR/" || true
run_cmd cp "$REPORT_JSON" "$REPORT_ARCHIVE_DIR/"

log "[REPORT] done"
