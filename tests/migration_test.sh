#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test_browser_excludes_exist() {
  local output

  output="$(BACKUP_TEST_PRINT_BROWSER_EXCLUDES=1 bash "$ROOT_DIR/scripts/preinstall_backup.sh" 2>/dev/null)"
  grep -Fxq "Cache" <<<"$output"
  grep -Fxq "Code Cache" <<<"$output"
  grep -Fxq "GPUCache" <<<"$output"
  grep -Fxq "Crashpad" <<<"$output"
}

test_restore_hints_template_mentions_required_checks() {
  local output

  output="$(RESTORE_TEST_PRINT_HINTS=1 bash "$ROOT_DIR/scripts/postinstall_restore.sh" 2>/dev/null)"
  grep -Fq "Яндекс Браузер" <<<"$output"
  grep -Fq "КриптоПро" <<<"$output"
  grep -Fq "ViPNet" <<<"$output"
  grep -Fq "Ассистент" <<<"$output"
}

test_usage_mentions_domain_gid_default() {
  local output
  local rc

  set +e
  output="$(bash "$ROOT_DIR/scripts/postinstall_restore.sh" --help 2>&1)"
  rc=$?
  set -e

  [ "$rc" -eq 0 ]
  grep -Fq "1965600513" <<<"$output"
}

test_browser_excludes_exist
test_restore_hints_template_mentions_required_checks
test_usage_mentions_domain_gid_default

echo "[migration_test] ok"
