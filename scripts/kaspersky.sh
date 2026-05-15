#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

: "${KASPERSKY_ENABLED:=0}"
: "${KASPERSKY_SHARE_DIR:=}"
: "${KASPERSKY_INSTALL_GUI:=0}"
: "${KASPERSKY_INSTALL_NETWORK_AGENT:=0}"
: "${KASPERSKY_ADMIN_USER:=}"
: "${KASPERSKY_LOCALE:=ru_RU.UTF-8}"
: "${KASPERSKY_USE_KSN:=yes}"
: "${KASPERSKY_CONFIGURE_SELINUX:=yes}"
: "${KASPERSKY_UPDATER_SOURCE:=KLServers}"
: "${KASPERSKY_PROXY_SERVER:=}"
: "${KASPERSKY_UPDATE_EXECUTE:=yes}"
: "${KASPERSKY_LICENSE:=}"
: "${KASPERSKY_AGENT_SERVER:=}"
: "${KASPERSKY_AGENT_PORT:=14000}"
: "${KASPERSKY_AGENT_SSL_PORT:=13000}"
: "${KASPERSKY_AGENT_USE_SSL:=1}"
: "${KASPERSKY_AGENT_GW_MODE:=2}"

find_single_rpm() {
  local search_dir="$1"
  local pattern="$2"

  find "$search_dir" -maxdepth 1 -type f -name "$pattern" | sort | tail -n 1
}

dnf_package_available() {
  local package_name="$1"

  dnf list --available "$package_name" >/dev/null 2>&1 || dnf list --installed "$package_name" >/dev/null 2>&1
}

write_kesl_autoinstall() {
  local outfile="$1"

  cat >"$outfile" <<EOF
KSVLA_MODE=no
EULA_AGREED=yes
PRIVACY_POLICY_AGREED=yes
USE_KSN=${KASPERSKY_USE_KSN}
GROUP_CLEAN=no
LOCALE=${KASPERSKY_LOCALE}
UPDATER_SOURCE=${KASPERSKY_UPDATER_SOURCE}
UPDATE_EXECUTE=${KASPERSKY_UPDATE_EXECUTE}
CONFIGURE_SELINUX=${KASPERSKY_CONFIGURE_SELINUX}
DISABLE_PROTECTION=no
EOF

  if [ -n "$KASPERSKY_LICENSE" ]; then
    printf 'INSTALL_LICENSE=%s\n' "$KASPERSKY_LICENSE" >>"$outfile"
  fi

  if [ -n "$KASPERSKY_ADMIN_USER" ]; then
    printf 'ADMIN_USER=%s\n' "$KASPERSKY_ADMIN_USER" >>"$outfile"
  fi

  if [ -n "$KASPERSKY_PROXY_SERVER" ]; then
    printf 'PROXY_SERVER=%s\n' "$KASPERSKY_PROXY_SERVER" >>"$outfile"
  fi
}

write_klnagent_answers() {
  local outfile="$1"

  cat >"$outfile" <<EOF
KLNAGENT_SERVER=${KASPERSKY_AGENT_SERVER}
KLNAGENT_AUTOINSTALL=1
EULA_ACCEPTED=1
KLNAGENT_PORT=${KASPERSKY_AGENT_PORT}
KLNAGENT_SSLPORT=${KASPERSKY_AGENT_SSL_PORT}
KLNAGENT_USESSL=${KASPERSKY_AGENT_USE_SSL}
KLNAGENT_GW_MODE=${KASPERSKY_AGENT_GW_MODE}
EOF
}

install_kaspersky() {
  local kesl_rpm=""
  local gui_rpm=""
  local agent_rpm=""
  local kesl_autoinstall=""
  local agent_answers=""
  local kesl_setup_rc=0
  local kesl_setup_timeout="${KASPERSKY_SETUP_TIMEOUT:-300}"
  local kesl_setup_kill_after="${KASPERSKY_SETUP_KILL_AFTER:-10}"

  if [ "$KASPERSKY_ENABLED" != "1" ]; then
    log "[KASPERSKY] skipped"
    return 0
  fi

  require_root
  require_command dnf

  if [ -z "$KASPERSKY_SHARE_DIR" ]; then
    log "[ERROR] KASPERSKY_SHARE_DIR is not set"
    exit 1
  fi

  if [ ! -d "$KASPERSKY_SHARE_DIR" ]; then
    log "[ERROR] KASPERSKY_SHARE_DIR does not exist: $KASPERSKY_SHARE_DIR"
    exit 1
  fi

  kesl_rpm="$(find_single_rpm "$KASPERSKY_SHARE_DIR" 'kesl-[0-9]*.rpm')"
  [ -n "$kesl_rpm" ] || { log "[ERROR] kesl RPM not found in $KASPERSKY_SHARE_DIR"; exit 1; }
  log "[KASPERSKY] found KESL RPM: $kesl_rpm"

  if [ "$KASPERSKY_INSTALL_GUI" = "1" ]; then
    gui_rpm="$(find_single_rpm "$KASPERSKY_SHARE_DIR" 'kesl-gui-*.rpm')"
    [ -n "$gui_rpm" ] || { log "[ERROR] kesl-gui RPM not found in $KASPERSKY_SHARE_DIR"; exit 1; }
    log "[KASPERSKY] found GUI RPM: $gui_rpm"
  fi

  if [ "$KASPERSKY_INSTALL_NETWORK_AGENT" = "1" ]; then
    [ -n "$KASPERSKY_AGENT_SERVER" ] || { log "[ERROR] KASPERSKY_AGENT_SERVER is not set"; exit 1; }
    agent_rpm="$(find_single_rpm "$KASPERSKY_SHARE_DIR" 'klnagent64-*.rpm')"
    [ -n "$agent_rpm" ] || { log "[ERROR] klnagent64 RPM not found in $KASPERSKY_SHARE_DIR"; exit 1; }
    log "[KASPERSKY] found Network Agent RPM: $agent_rpm"
  fi

  log "[KASPERSKY] installing dependencies"
  run_cmd dnf install -y perl-Getopt-Long perl-File-Copy

  if [ "$KASPERSKY_CONFIGURE_SELINUX" = "yes" ]; then
    log "[KASPERSKY] installing SELinux dependencies"
    run_cmd dnf install -y checkpolicy policycoreutils-python-utils
  fi

  if [ "$KASPERSKY_INSTALL_NETWORK_AGENT" = "1" ] && dnf_package_available libxcrypt-compat; then
    run_cmd dnf install -y libxcrypt-compat
  fi

  log "[KASPERSKY] installing KESL package: $kesl_rpm"
  run_cmd dnf install -y "$kesl_rpm"

  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] prepare KESL autoinstall config"
  else
    kesl_autoinstall="$(mktemp /tmp/kesl-autoinstall.XXXXXX)"
    write_kesl_autoinstall "$kesl_autoinstall"
    log "[KASPERSKY] running silent initial configuration"
    set +e
    timeout -k "$kesl_setup_kill_after" "$kesl_setup_timeout" setsid /opt/kaspersky/kesl/bin/kesl-setup.pl --autoinstall="$kesl_autoinstall"
    kesl_setup_rc=$?
    set -e
    if [ "$kesl_setup_rc" -ne 0 ]; then
      if [ -z "$KASPERSKY_LICENSE" ]; then
        log_warn "[KASPERSKY] kesl-setup.pl exited with code $kesl_setup_rc without local license; continuing for KSC-managed activation"
      else
        rm -f "$kesl_autoinstall"
        exit "$kesl_setup_rc"
      fi
    fi
    rm -f "$kesl_autoinstall"
  fi

  if [ "$KASPERSKY_INSTALL_NETWORK_AGENT" = "1" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "[DRY-RUN] install Network Agent package: $agent_rpm"
    else
      agent_answers="$(mktemp /tmp/klnagent-answers.XXXXXX)"
      write_klnagent_answers "$agent_answers"
      export KLAUTOANSWERS="$agent_answers"
      log "[KASPERSKY] installing Network Agent package: $agent_rpm"
      dnf install -y "$agent_rpm"
      unset KLAUTOANSWERS
      rm -f "$agent_answers"
    fi
  fi

  if [ "$KASPERSKY_INSTALL_GUI" = "1" ]; then
    log "[KASPERSKY] installing GUI package: $gui_rpm"
    run_cmd dnf install -y "$gui_rpm"
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] verify Kaspersky status"
  else
    systemctl restart kesl || true
    kesl-control --app-info >/dev/null 2>&1 || true
  fi

  if [ "$kesl_setup_rc" -ne 0 ] && [ -z "$KASPERSKY_LICENSE" ]; then
    log_warn "[KASPERSKY] local activation/update did not finish during setup; complete activation and policy from KSC"
  fi

  log "[KASPERSKY] done"
}

install_kaspersky "$@"
