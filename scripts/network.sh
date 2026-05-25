#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root
require_command nmcli
CONN=$(nmcli -t -f NAME connection show --active | head -1)
[ -n "$CONN" ] || {
  log "[NETWORK] no active connection"
  exit 1
}
run_cmd nmcli con mod "$CONN" ipv4.dns "$DNS_SERVERS"
run_cmd nmcli con up "$CONN" || true
log "[NETWORK] done"
