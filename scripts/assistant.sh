#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

: "${ASSISTANT_ENABLED:=0}"
: "${ASSISTANT_DIST_DIR:=/mnt/distr/linux/bootstrap/assistant}"
: "${ASSISTANT_RPM_PATTERN:=assistant-fstek-*.x86_64.rpm}"
: "${ASSISTANT_HOSTS_FILE:=${ASSISTANT_DIST_DIR}/redos_hosts.txt}"

find_assistant_rpm() {
  find "$ASSISTANT_DIST_DIR" -maxdepth 1 -type f -name "$ASSISTANT_RPM_PATTERN" | sort | tail -n 1
}

append_assistant_hosts() {
  local line=""

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      ""|\#*)
        continue
        ;;
    esac
    append_if_missing "$line" /etc/hosts
  done < "$ASSISTANT_HOSTS_FILE"
}

install_assistant() {
  local assistant_rpm=""

  if [ "$ASSISTANT_ENABLED" != "1" ]; then
    log "[ASSISTANT] skipped"
    return 0
  fi

  require_root
  require_command dnf

  if [ ! -d "$ASSISTANT_DIST_DIR" ]; then
    log "[ERROR] ASSISTANT_DIST_DIR does not exist: $ASSISTANT_DIST_DIR"
    exit 1
  fi

  assistant_rpm="$(find_assistant_rpm)"
  [ -n "$assistant_rpm" ] || { log "[ERROR] Assistant RPM not found in $ASSISTANT_DIST_DIR"; exit 1; }
  [ -r "$ASSISTANT_HOSTS_FILE" ] || { log "[ERROR] Assistant hosts file not found: $ASSISTANT_HOSTS_FILE"; exit 1; }

  log "[ASSISTANT] selected RPM: $assistant_rpm"
  log "[ASSISTANT] installing Assistant"
  run_cmd dnf install -y "$assistant_rpm"

  log "[ASSISTANT] adding hosts entries from: $ASSISTANT_HOSTS_FILE"
  append_assistant_hosts

  log "[ASSISTANT] done"
}

install_assistant "$@"
