#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

OS_ID="$(read_os_release_field ID)"
OS_VERSION_ID="$(read_os_release_field VERSION_ID)"
SELECTED_STEPS=(${BOOTSTRAP_SELECTED_STEPS:-})

[ -n "$OS_ID" ] || { log "[PREFLIGHT] unable to detect OS"; exit 1; }

if ! printf '%s\n' $SUPPORTED_DISTROS | grep -Fxq "$OS_ID"; then
  log "[PREFLIGHT] unsupported distro: $OS_ID"
  exit 1
fi

log "[PREFLIGHT] detected ${OS_ID:-unknown} ${OS_VERSION_ID:-unknown}"

validate_domain_hostname "$(domain_hostname)" || exit 1

for cmd in hostname awk grep tee; do
  require_command "$cmd"
done

if ! command_exists flock; then
  log "[PREFLIGHT] warning: flock not found, bootstrap lock will be disabled"
fi

for step in "${SELECTED_STEPS[@]}"; do
  case "$step" in
    packages|repos)
      require_command dnf
      ;;
    time|security|postcheck)
      require_command systemctl
      ;;
    domain)
      require_command getent
      require_command realm
      ;;
    cifs)
      require_command mount
      ;;
    report)
      require_command hostname
      require_command date
      ;;
  esac
done

log "[PREFLIGHT] ok"
