#!/usr/bin/env bash
# Regenerate Aurora's generated artifacts: the install manifest (checksums of
# every overlay/patch file) and the opm registry index. Run after changing any
# shipped file. Both are committed so installs work straight from GitHub.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
LUA="${LUA:-lua5.3}"
"$LUA" tools/gen-manifest.lua
"$LUA" tools/build-registry.lua
"$LUA" tools/gen-apidocs.lua
echo "build: manifest + registry regenerated"
