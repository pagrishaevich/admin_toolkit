#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

FAIL=0

check_ok() {
  local label="$1"
  local cmd="$2"

  if (set +o pipefail; eval "$cmd") >/dev/null 2>&1; then
    log "$label OK"
  else
    log "$label FAIL"
    FAIL=1
  fi
}

check_kaspersky() {
  local agent_status_output=""

  if [ "$KASPERSKY_ENABLED" != "1" ]; then
    return 0
  fi

  check_ok "KASPERSKY RPM" "rpm -q kesl"
  check_ok "KASPERSKY SERVICE" "systemctl is-active kesl"

  if [ "$KASPERSKY_INSTALL_GUI" = "1" ]; then
    check_ok "KASPERSKY GUI RPM" "rpm -q kesl-gui"
  fi

  if [ "$KASPERSKY_INSTALL_NETWORK_AGENT" = "1" ]; then
    check_ok "KASPERSKY AGENT RPM" "rpm -q klnagent64"
    check_ok "KASPERSKY AGENT SERVICE" "systemctl is-active klnagent64"

    if [ -x /opt/kaspersky/klnagent64/bin/klnagchk ]; then
      agent_status_output="$(/opt/kaspersky/klnagent64/bin/klnagchk 2>/dev/null || true)"

      if printf '%s\n' "$agent_status_output" | grep -Fq "$KASPERSKY_AGENT_SERVER"; then
        log "KASPERSKY AGENT SERVER OK"
      else
        log "KASPERSKY AGENT SERVER FAIL"
        FAIL=1
      fi
    else
      log "[WARN] KASPERSKY AGENT SERVER check skipped: klnagchk not found"
    fi
  fi
}

check_cryptopro() {
  local cpconfig_path=""

  if [ "$CRYPTO_PRO_ENABLED" != "1" ]; then
    return 0
  fi

  check_ok "CRYPTO_PRO RPM" "rpm -q lsb-cprocsp-kc1-64"
  check_ok "CRYPTO_PRO TUNNELS" "rpm -q cprocsp-stunnel-64"

  cpconfig_path="$(cpconfig_cmd || true)"
  if [ -n "$cpconfig_path" ]; then
    check_ok "CRYPTO_PRO CPCONFIG" "\"$cpconfig_path\" -license -view"
  else
    log "CRYPTO_PRO CPCONFIG FAIL"
    FAIL=1
  fi

  if [ "$CRYPTO_PRO_INSTALL_RUTOKEN_DRIVER" = "1" ]; then
    check_ok "CRYPTO_PRO RUTOKEN DRIVER" "rpm -q ifd-rutokens"
  fi

  if [ "$CRYPTO_PRO_INSTALL_JACARTA_DRIVER" = "1" ]; then
    check_ok "CRYPTO_PRO JACARTA DRIVER" "rpm -qa | grep -Eq '^cprocsp-rdr-jacarta'"
  fi
}

check_vipnet() {
  if [ "$VIPNET_ENABLED" != "1" ]; then
    return 0
  fi

  if [ "$VIPNET_VARIANT" = "gui" ]; then
    check_ok "VIPNET RPM" "rpm -qa | grep -Eq '^vipnetclient-gui([-_]|$)'"
  else
    check_ok "VIPNET RPM" "rpm -qa | grep -Eq '^vipnetclient($|[-_])'"
  fi

  check_ok "VIPNET COMMAND" "command -v vipnetclient"
}

check_yandex_browser() {
  if [ "$YANDEX_BROWSER_ENABLED" != "1" ]; then
    return 0
  fi

  check_ok "YANDEX BROWSER RPM" "rpm -q \"$YANDEX_BROWSER_PACKAGE\""
}

check_r7office() {
  if [ "$R7_OFFICE_ENABLED" != "1" ]; then
    return 0
  fi

  check_ok "R7 OFFICE RPM" "rpm -q \"$R7_OFFICE_PACKAGE\""

  if [ "$R7_ORGANIZER_ENABLED" = "1" ]; then
    check_ok "R7 ORGANIZER RPM" "rpm -q \"$R7_ORGANIZER_PACKAGE\""
  fi

  if [ "$R7_GRAFIKA_ENABLED" = "1" ]; then
    check_ok "R7 GRAFIKA RPM" "rpm -q \"$R7_GRAFIKA_PACKAGE\""
  fi
}

realm list | grep -q "$DOMAIN" && log "DOMAIN OK" || { log "DOMAIN FAIL"; FAIL=1; }
mount | grep -Fq "$CIFS_SERVER" && log "CIFS OK" || { log "CIFS FAIL"; FAIL=1; }
check_ok "CIFS INV WRITE" "test_file=\"/mnt/inv/.bootstrap_write_test_\$\$\"; touch \"\$test_file\" && rm -f \"\$test_file\""
systemctl is-active chronyd >/dev/null && log "TIME OK" || { log "TIME FAIL"; FAIL=1; }
check_kaspersky
check_cryptopro
check_vipnet
check_yandex_browser
check_r7office

if [ "$FAIL" -eq 0 ]; then
  log "[RESULT] SUCCESS"
else
  log "[RESULT] FAIL"
  exit 1
fi
