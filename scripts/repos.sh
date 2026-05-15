#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_root

REDOS_BASE_REPO_FILE="/etc/yum.repos.d/RedOS-Base.repo"
REDOS_UPDATES_REPO_FILE="/etc/yum.repos.d/RedOS-Updates.repo"
REDOS_BASE_URL='http://redrepos.yanao.int/redos/8.0c/$basearch/os'
REDOS_UPDATES_URL='http://redrepos.yanao.int/redos/8.0c/$basearch/updates'

ensure_repo_baseurl() {
  local file="$1"
  local section="$2"
  local name="$3"
  local url="$4"
  local tmp_file=""

  if [ "$DRY_RUN" = "1" ]; then
    log "[DRY-RUN] ensure $url in $file"
    return 0
  fi

  mkdir -p "$(dirname "$file")"

  if [ ! -f "$file" ]; then
    cat > "$file" <<EOF
[$section]
name=$name
baseurl=$url
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-RED-SOFT
enabled=1
EOF
    log "[REPOS] created $file"
    return 0
  fi

  if grep -Fq "$url" "$file"; then
    log "[REPOS] already configured: $file"
    return 0
  fi

  backup_file "$file"
  tmp_file="$(mktemp /tmp/repo.XXXXXX)"
  awk -v section="$section" -v name="$name" -v url="$url" '
    BEGIN {
      in_section = 0
      saw_section = 0
      done = 0
    }
    $0 == "[" section "]" {
      in_section = 1
      saw_section = 1
      print
      next
    }
    /^\[/ {
      if (in_section && !done) {
        print "baseurl=" url
        done = 1
      }
      in_section = 0
      print
      next
    }
    in_section && /^[[:space:]]*baseurl[[:space:]]*=/ && !done {
      line = $0
      sub(/^[[:space:]]*baseurl[[:space:]]*=/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "") {
        print "baseurl=" url
      } else {
        print "baseurl=" url "," line
      }
      done = 1
      next
    }
    { print }
    END {
      if (!saw_section) {
        print ""
        print "[" section "]"
        print "name=" name
        print "baseurl=" url
        print "gpgcheck=1"
        print "gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-RED-SOFT"
        print "enabled=1"
      } else if (in_section && !done) {
        print "baseurl=" url
      }
    }
  ' "$file" > "$tmp_file"
  cat "$tmp_file" > "$file"
  rm -f "$tmp_file"
  log "[REPOS] updated $file"
}

run_local_hook repos
ensure_repo_baseurl "$REDOS_BASE_REPO_FILE" base "RedOS - Base" "$REDOS_BASE_URL"
ensure_repo_baseurl "$REDOS_UPDATES_REPO_FILE" updates "RedOS - Updates" "$REDOS_UPDATES_URL"
log "[REPOS] done"
