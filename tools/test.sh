#!/usr/bin/env bash
# Aurora canonical test signal: lint -> host unit tests -> (optional) integration.
# Usage: tools/test.sh [--no-integration]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUA="${LUA:-lua5.3}"
command -v "$LUA" >/dev/null || { echo "need $LUA" >&2; exit 127; }

# Modules resolve from the overlay; the OC shim and test files from tests/.
export LUA_PATH="$ROOT/overlay/lib/?.lua;$ROOT/overlay/lib/?/init.lua;$ROOT/tests/?.lua;$ROOT/tests/?/init.lua;;"
export AURORA_ROOT="$ROOT"

echo "== lint =="
"$ROOT/tools/lint.sh"

echo ""
echo "== unit =="
fail=0
shopt -s nullglob
for f in "$ROOT"/tests/unit/*.lua; do
  echo "--- $(basename "$f") ---"
  if ! "$LUA" "$f"; then
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo ""
  echo "UNIT TESTS FAILED"
  exit 1
fi

if [[ "${1:-}" != "--no-integration" && -x "$ROOT/tools/integration.sh" ]]; then
  echo ""
  echo "== integration =="
  "$ROOT/tools/integration.sh" || { echo "INTEGRATION FAILED"; exit 2; }
fi

echo ""
echo "ALL TESTS PASSED"
