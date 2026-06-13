#!/usr/bin/env bash
# Syntax-lint every Lua file shipped in the overlay, installer, registry and
# tests using luac5.3 -p (parse only). Exit nonzero on the first error.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUAC="${LUAC:-luac5.3}"
command -v "$LUAC" >/dev/null || { echo "need $LUAC" >&2; exit 127; }

fail=0
count=0
while IFS= read -r -d '' f; do
  count=$((count + 1))
  if ! out="$("$LUAC" -p "$f" 2>&1)"; then
    echo "LINT FAIL: $f"
    echo "$out"
    fail=1
  fi
done < <(find "$ROOT/overlay" "$ROOT/install" "$ROOT/registry" "$ROOT/tests" "$ROOT/tools" \
           -name '*.lua' -print0 2>/dev/null)

if [[ $fail -eq 0 ]]; then
  echo "lint ok: $count files"
fi
exit $fail
