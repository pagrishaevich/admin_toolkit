#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$DIR/common.sh"

STEPS=(preflight repos packages time domain cifs report software security postcheck)

usage() {
  cat <<'EOF'
Usage: bash scripts/bootstrap.sh [options]

Options:
  --dry-run           show planned actions without changing the system
  --step NAME         run only a specific step; can be repeated
  --from-step NAME    run from the specified step to the end
  --list-steps        print available steps
  -h, --help          show this help
EOF
}

step_exists() {
  local target="$1"
  local step

  for step in "${STEPS[@]}"; do
    if [ "$step" = "$target" ]; then
      return 0
    fi
  done

  return 1
}

collect_steps() {
  local from_step="${1:-}"
  shift || true
  local selected=("$@")
  local candidates=()
  local result=()
  local step
  local seen_from=0

  if [ -n "$from_step" ]; then
    for step in "${STEPS[@]}"; do
      if [ "$step" = "$from_step" ]; then
        seen_from=1
      fi
      if [ "$seen_from" -eq 1 ]; then
        candidates+=("$step")
      fi
    done
  else
    candidates=("${STEPS[@]}")
  fi

  if [ "${#selected[@]}" -eq 0 ]; then
    printf '%s\n' "${candidates[@]}"
    return 0
  fi

  for step in "${candidates[@]}"; do
    if printf '%s\n' "${selected[@]}" | grep -Fxq "$step"; then
      result+=("$step")
    fi
  done

  if [ "${#result[@]}" -eq 0 ]; then
    return 0
  fi

  printf '%s\n' "${result[@]}"
}

SELECTED_STEPS=()
FROM_STEP=""

while [ "$#" -gt 0 ]; do
  case "$1" in
  --dry-run)
    export DRY_RUN=1
    ;;
  --step)
    shift
    [ "$#" -gt 0 ] || {
      echo "missing value for --step" >&2
      exit 1
    }
    step_exists "$1" || {
      echo "unknown step: $1" >&2
      exit 1
    }
    SELECTED_STEPS+=("$1")
    ;;
  --from-step)
    shift
    [ "$#" -gt 0 ] || {
      echo "missing value for --from-step" >&2
      exit 1
    }
    step_exists "$1" || {
      echo "unknown step: $1" >&2
      exit 1
    }
    FROM_STEP="$1"
    ;;
  --list-steps)
    printf '%s\n' "${STEPS[@]}"
    exit 0
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
  esac
  shift
done

require_root

if [ "$DRY_RUN" = "1" ]; then
  LOCK="/tmp/bootstrap.lock"
  BOOTSTRAP_LOG_FILE="/tmp/bootstrap.log"
else
  LOCK="/var/run/bootstrap.lock"
  BOOTSTRAP_LOG_FILE="$TOOLKIT_LOG_FILE"
fi

if command_exists flock; then
  exec 9>"$LOCK"
  flock -n 9 || {
    log "[BOOTSTRAP] already running"
    exit 1
  }
else
  log_warn "flock not found, lock disabled"
fi

exec > >(tee -a "$BOOTSTRAP_LOG_FILE") 2>&1

STEPS_TO_RUN=()
if [ "${#SELECTED_STEPS[@]}" -gt 0 ]; then
  while IFS= read -r step; do
    [ -n "$step" ] && STEPS_TO_RUN+=("$step")
  done < <(collect_steps "$FROM_STEP" "${SELECTED_STEPS[@]}")
else
  while IFS= read -r step; do
    [ -n "$step" ] && STEPS_TO_RUN+=("$step")
  done < <(collect_steps "$FROM_STEP")
fi
[ "${#STEPS_TO_RUN[@]}" -gt 0 ] || {
  log "[BOOTSTRAP] no steps selected"
  exit 1
}
export BOOTSTRAP_SELECTED_STEPS="${STEPS_TO_RUN[*]}"

[ "$DRY_RUN" = "1" ] && log "[BOOTSTRAP] dry-run enabled"
log "[BOOTSTRAP] steps: ${STEPS_TO_RUN[*]}"

run_step() {
  local step="$1"
  log "[BOOTSTRAP] running $step"
  bash "$DIR/$step.sh"
}

for f in "${STEPS_TO_RUN[@]}"; do
  run_step "$f"
done

echo "=== FINISHED ==="
