# RED OS Reinstall Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить пару root-скриптов для backup перед переустановкой РедОС и restore после установки РедОС 8 с переносом данных локального пользователя в доменный профиль.

**Architecture:** Реализация остается в стиле текущего проекта: отдельные Bash-скрипты в `scripts/`, общие helper-функции из `scripts/common.sh`, проверка через `scripts/validate.sh`. Backup создает самодостаточный каталог с данными и отчетами, restore читает этот каталог и осторожно переносит только поддерживаемые разделы.

**Tech Stack:** Bash, GNU coreutils, `rsync`, `findmnt`, CUPS/SANE/CryptoPro CLI при наличии, существующий `validate.sh`.

---

## Файлы

- Create: `backup_restore/tests/migration_test.sh` — быстрые shell-тесты поведения без реальной РедОС: проверяют exclude-файл браузера, генерацию hints и restore владельцев через dry-run/stub.
- Create: `backup_restore/scripts/preinstall_backup.sh` — сбор backup на старой системе.
- Create: `backup_restore/scripts/postinstall_restore.sh` — восстановление backup на новой системе.
- Modify: `scripts/validate.sh` — запуск shell-тестов, если они есть.
- Modify: `README.md` — краткая ссылка на новые скрипты.
- Modify: `.memory/current_state.md`, `.memory/tasks.md`, `.memory/session_logs/2026-05-15.md` — итоговое состояние после реализации.

## Task 1: Тестовый каркас миграции

**Files:**
- Create: `backup_restore/tests/migration_test.sh`
- Modify: `scripts/validate.sh`

- [ ] **Step 1: Write the failing test**

Создать `backup_restore/tests/migration_test.sh`:

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test_browser_excludes_exist() {
  local output
  output="$(BACKUP_TEST_PRINT_BROWSER_EXCLUDES=1 bash "$ROOT_DIR/backup_restore/scripts/preinstall_backup.sh" 2>/dev/null)"
  grep -Fxq "Cache" <<<"$output"
  grep -Fxq "Code Cache" <<<"$output"
  grep -Fxq "GPUCache" <<<"$output"
  grep -Fxq "Crashpad" <<<"$output"
}

test_restore_hints_template_mentions_required_checks() {
  local output
  output="$(RESTORE_TEST_PRINT_HINTS=1 bash "$ROOT_DIR/backup_restore/scripts/postinstall_restore.sh" 2>/dev/null)"
  grep -Fq "Яндекс Браузер" <<<"$output"
  grep -Fq "КриптоПро" <<<"$output"
  grep -Fq "ViPNet" <<<"$output"
  grep -Fq "Ассистент" <<<"$output"
}

test_usage_mentions_domain_gid_default() {
  local output
  set +e
  output="$(bash "$ROOT_DIR/backup_restore/scripts/postinstall_restore.sh" --help 2>&1)"
  local rc=$?
  set -e
  [ "$rc" -eq 0 ]
  grep -Fq "1965600513" <<<"$output"
}

test_browser_excludes_exist
test_restore_hints_template_mentions_required_checks
test_usage_mentions_domain_gid_default

echo "[migration_test] ok"
```

Добавить в `scripts/validate.sh` после проверки custom hooks:

```bash
if [ -d "$PROJECT_ROOT/tests" ]; then
  echo "[validate] tests"
  find "$PROJECT_ROOT/tests" -type f -name '*_test.sh' -print0 | while IFS= read -r -d '' file; do
    bash "$file"
  done
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/validate.sh`

Expected: FAIL, потому что `backup_restore/scripts/preinstall_backup.sh` и `backup_restore/scripts/postinstall_restore.sh` еще не существуют.

- [ ] **Step 3: Commit failing test**

```bash
git add backup_restore/tests/migration_test.sh scripts/validate.sh
git commit -m "test: add migration script behavior checks"
```

## Task 2: Backup script

**Files:**
- Create: `backup_restore/scripts/preinstall_backup.sh`
- Test: `backup_restore/tests/migration_test.sh`

- [ ] **Step 1: Implement minimal backup helpers for tests**

Создать `backup_restore/scripts/preinstall_backup.sh` с:

- `set -euo pipefail`;
- source `common.sh`;
- `browser_exclude_patterns`;
- test hook `BACKUP_TEST_PRINT_BROWSER_EXCLUDES=1`.

Minimum required code:

```bash
browser_exclude_patterns() {
  cat <<'EOF'
Cache
Code Cache
GPUCache
ShaderCache
GrShaderCache
DawnCache
Crashpad
BrowserMetrics
*.log
*.tmp
EOF
}

if [ "${BACKUP_TEST_PRINT_BROWSER_EXCLUDES:-0}" = "1" ]; then
  browser_exclude_patterns
  exit 0
fi
```

- [ ] **Step 2: Run test to verify partial pass/fail**

Run: `bash scripts/validate.sh`

Expected: still FAIL because restore script is missing.

- [ ] **Step 3: Implement full backup behavior**

Add functions:

- `usage`;
- `warn`;
- `copy_path`;
- `copy_user_named_paths`;
- `save_command_output`;
- `collect_manifest`;
- `collect_network_mounts`;
- `collect_yandex_browser`;
- `collect_named_app_data` for `vipnet` and `assistant`;
- `collect_printers`;
- `collect_scanners`;
- `collect_certificates`;
- `collect_cryptopro_tokens`;
- `write_restore_hints`.

Expected CLI:

```bash
bash backup_restore/scripts/preinstall_backup.sh --output /path/to/backup-parent --user localuser
```

Expected output tree:

```text
redos-migration-<hostname>-<timestamp>/
  manifest.txt
  restore-hints.txt
  mounts/
  browser/<user>/yandex-browser/
  vipnet/
  assistant/
  printers/
  scanners/
  certificates/
  cryptopro/
```

- [ ] **Step 4: Run tests**

Run: `bash scripts/validate.sh`

Expected: FAIL only if restore script is still missing; backup syntax should pass.

## Task 3: Restore script

**Files:**
- Create: `backup_restore/scripts/postinstall_restore.sh`
- Test: `backup_restore/tests/migration_test.sh`

- [ ] **Step 1: Implement minimal restore helpers for tests**

Создать `backup_restore/scripts/postinstall_restore.sh` с:

- `set -euo pipefail`;
- source `common.sh`;
- `DEFAULT_DOMAIN_GID=1965600513`;
- `restore_hints_template`;
- test hook `RESTORE_TEST_PRINT_HINTS=1`;
- `--help`.

- [ ] **Step 2: Run test to verify it passes minimum checks**

Run: `bash scripts/validate.sh`

Expected: PASS for current `backup_restore/tests/migration_test.sh`.

- [ ] **Step 3: Implement full restore behavior**

Add functions:

- `usage`;
- `warn`;
- `backup_existing_path`;
- `restore_dir`;
- `restore_user_dir`;
- `restore_yandex_browser`;
- `restore_system_dir_if_installed`;
- `restore_printers`;
- `restore_scanners`;
- `restore_certificates`;
- `restore_cryptopro_tokens`;
- `restore_named_app_data` for `vipnet` and `assistant`;
- `write_restore_hints`.

Expected CLI:

```bash
bash backup_restore/scripts/postinstall_restore.sh --backup /path/to/redos-migration-host-date --target-user 'DOMAIN\\user' --target-gid 1965600513
```

Restore must:

- create `/home/<target-user>` if it does not exist;
- restore browser profile to `/home/<target-user>/.config/yandex-browser`;
- run `chown -R <target-user>:<target-gid>` only for restored user directories;
- back up existing target paths before replacing;
- skip missing optional sections with warnings.

- [ ] **Step 4: Run tests**

Run: `bash scripts/validate.sh`

Expected: PASS.

## Task 4: Documentation and memory

**Files:**
- Modify: `README.md`
- Modify: `.memory/current_state.md`
- Modify: `.memory/tasks.md`
- Modify: `.memory/session_logs/2026-05-15.md`

- [ ] **Step 1: Update README**

Add a short section:

```markdown
## Миграция перед переустановкой РедОС

Для переноса настроек перед установкой РедОС 8 используются:

- `backup_restore/scripts/preinstall_backup.sh` — собрать backup на старой системе;
- `backup_restore/scripts/postinstall_restore.sh` — восстановить backup на новой системе.

Пример:

```bash
sudo bash backup_restore/scripts/preinstall_backup.sh --output /mnt/backup --user localuser
sudo bash backup_restore/scripts/postinstall_restore.sh --backup /mnt/backup/redos-migration-host-date --target-user domain.user --target-gid 1965600513
```
```

- [ ] **Step 2: Update memory**

Record:

- added migration scripts;
- separate ViPNet and Ассистент handling;
- no RPM list, NetworkManager, domain state, SSH keys;
- tests run and result.

## Task 5: Final verification

**Files:**
- All touched files

- [ ] **Step 1: Syntax and tests**

Run:

```bash
bash scripts/validate.sh
```

Expected: `[validate] ok`.

- [ ] **Step 2: Manual help checks**

Run:

```bash
bash backup_restore/scripts/preinstall_backup.sh --help
bash backup_restore/scripts/postinstall_restore.sh --help
```

Expected: both commands exit `0` and show Russian usage text.

- [ ] **Step 3: Inspect final diff**

Run:

```bash
git diff --stat
git diff -- backup_restore/scripts/preinstall_backup.sh backup_restore/scripts/postinstall_restore.sh backup_restore/tests/migration_test.sh scripts/validate.sh README.md
```

Expected: changes are scoped to migration scripts, tests, validation and docs.

- [ ] **Step 4: Commit**

```bash
git add backup_restore/scripts/preinstall_backup.sh backup_restore/scripts/postinstall_restore.sh backup_restore/tests/migration_test.sh scripts/validate.sh README.md .memory/current_state.md .memory/tasks.md .memory/session_logs/2026-05-15.md
git commit -m "feat: add redos reinstall migration scripts"
```

## Self-review

- Spec coverage: backup/restore, local-to-domain migration, Yandex Browser, network mounts, ViPNet, Ассистент, CUPS, SANE, certificates, CryptoPro/Rutoken/Jacarta and restore hints are covered.
- Exclusions: RPM list, NetworkManager, domain state and SSH keys are excluded by design.
- Placeholder scan: no TODO/TBD placeholders.
- Type consistency: script names and CLI flags are consistent across tasks.

