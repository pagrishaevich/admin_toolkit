#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$DIR/.." && pwd)"

echo "[validate] bash -n"
bash -n "$DIR"/*.sh

if command -v shellcheck >/dev/null 2>&1; then
  echo "[validate] shellcheck"
  shellcheck -x -P "$DIR" "$DIR"/*.sh
else
  echo "[validate] shellcheck not installed, skipping"
fi

if command -v shfmt >/dev/null 2>&1; then
  echo "[validate] shfmt"
  shfmt -d -i 2 "$DIR"/*.sh
else
  echo "[validate] shfmt not installed, skipping"
fi

if [ -d "$PROJECT_ROOT/custom" ]; then
  echo "[validate] custom hooks"
  find "$PROJECT_ROOT/custom" -type f -name '*.sh' -print0 | while IFS= read -r -d '' file; do
    bash -n "$file"
  done
fi

if [ -d "$PROJECT_ROOT/tests" ]; then
  echo "[validate] tests"
  find "$PROJECT_ROOT/tests" -type f -name '*_test.sh' -print0 | while IFS= read -r -d '' file; do
    bash "$file"
  done
fi

echo "[validate] ok"
