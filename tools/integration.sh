#!/usr/bin/env bash
# Boot a throwaway OpenOS+Aurora instance under ocvm and run the in-VM self-test.
# Builds .itest/instance from stock OpenOS, overlays Aurora, applies patches,
# wires the self-test to run at login, boots with a real PTY (script), then
# reads /selftest.log back. Exit: 0 all pass, 2 any FAIL, 1 boot stalled.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAB="$(cd "$ROOT/.." && pwd)"                       # OpenOSLab
STOCK="${STOCK_OPENOS:-$LAB/emulator/instance}"     # stock instance (bios, openos, data)
OCVM="${OCVM_BIN:-$LAB/../OCOS/reference/ocvm/ocvm}"

[[ -x "$OCVM" ]] || { echo "ocvm not found at $OCVM (set OCVM_BIN)"; exit 1; }
[[ -d "$STOCK/openos" ]] || { echo "stock OpenOS not found at $STOCK/openos"; exit 1; }
command -v script >/dev/null || { echo "need 'script' (util-linux) for a PTY"; exit 1; }

ITEST="$ROOT/.itest"
INST="$ITEST/instance"
rm -rf "$ITEST"
mkdir -p "$INST"

# 1) stage stock OpenOS + EEPROM + nvram
cp -r "$STOCK/openos" "$INST/openos"
cp "$STOCK/bios.lua" "$INST/bios.lua"
cp "$STOCK/data" "$INST/data" 2>/dev/null || true

# 2) overlay Aurora files
cp -r "$ROOT/overlay/." "$INST/openos/"

# 3) apply patches (every *.lua that is not a *.orig)
while IFS= read -r -d '' p; do
  rel="${p#"$ROOT"/patches/}"
  mkdir -p "$INST/openos/$(dirname "$rel")"
  cp "$p" "$INST/openos/$rel"
done < <(find "$ROOT/patches" -name '*.lua' ! -name '*.orig' -print0)

# 4) wire the self-test to run at login, then halt
SELFTEST="${SELFTEST:-$ROOT/tests/integration/selftest.lua}"
cp "$SELFTEST" "$INST/openos/bin/aurora-selftest.lua"
printf 'aurora-selftest\n' > "$INST/openos/home/.shrc"

# 5) client.cfg: stock components, openos boot fs (our staged copy), data card
cat > "$INST/client.cfg" <<CFG
{
  ["components"]={
    {"screen","a58b9479-05fa-4430-927d-4d269cc7455b",},
    {"gpu","afdadc8a-7d28-4551-bb0d-417c1cc691e0",44800,},
    {"eeprom","64dcf220-5f75-4e8d-a895-e29efc3c2c8e",4096,256,"OC-BIOS",},
    {"computer","f83d72fc-bd41-4728-ae8a-b7d5239f3a3a",2097152,},
    {"filesystem","20c9a62c-e1ea-41a3-b7a4-5b04c23dbff0","$INST/openos","openos",},
    {"filesystem","aabbccdd-0000-0000-0000-000000000001",false,"data",},
    {"filesystem","3344634b-d385-48dd-bb11-8b219e7a99d8",true,"tmpfs",},
    {"keyboard","fdbd6546-7858-7336-5191-eff6d47a68d0","a58b9479-05fa-4430-927d-4d269cc7455b",},
    {"internet","9490410c-e8b5-4239-4632-301aac98eabf",true,true,},
    {"data","4bbd54f1-6ba4-e136-2e51-6c2c289727bc",["tier"]=1,},
  },
  ["system"]={["allowBytecode"]=false,["allowGC"]=false,["maxTcpConnections"]=4,["timeout"]=5,},
}
CFG

# 6) boot with a real PTY; the OS halts itself, the timeout guards a stuck boot
echo "booting ocvm (timeout 120s)..."
( cd "$INST" && timeout 120 script -qc "$OCVM $INST --frame=basic" /tmp/aurora-itest.txt </dev/null >/dev/null 2>&1 ) || true

LOG="$INST/aabbccdd-0000-0000-0000-000000000001/selftest.log"
if [[ ! -f "$LOG" ]]; then
  echo "selftest.log not written — boot likely stalled"
  echo "--- ocvm console tail ---"
  tail -25 /tmp/aurora-itest.txt 2>/dev/null || true
  exit 1
fi

echo "--- selftest.log ---"
cat "$LOG"
if grep -q "^FAIL " "$LOG"; then exit 2; fi
echo "integration: all in-VM checks passed"
