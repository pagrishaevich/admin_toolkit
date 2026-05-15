#!/bin/bash

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$COMMON_DIR/.." && pwd)"
DRY_RUN="${DRY_RUN:-0}"

log() {
  local msg
  msg="[$(date '+%F %T')] $*"
  echo "$msg"
  logger -t REDOS-MIGRATION "$msg" 2>/dev/null || true
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

require_command() {
  if ! command_exists "$1"; then
    log "[ERROR] missing command: $1"
    exit 1
  fi
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
