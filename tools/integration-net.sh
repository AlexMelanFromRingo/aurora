#!/usr/bin/env bash
# Multi-node anet test: boot TWO OpenOS+Aurora VMs under ocvm that share a modem
# network (ocvm bridges modems via a localhost socket hub on system port 56000).
# The server answers a JSON-RPC "add" over the modem; the client calls it and
# verifies the result. Exit 0 if the client got 5, else nonzero.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAB="$(cd "$ROOT/.." && pwd)"
STOCK="${STOCK_OPENOS:-$LAB/emulator/instance}"
OCVM="${OCVM_BIN:-$LAB/../OCOS/reference/ocvm/ocvm}"
[[ -x "$OCVM" ]] || { echo "ocvm not found at $OCVM"; exit 1; }
command -v script >/dev/null || { echo "need 'script'"; exit 1; }

ITEST="$ROOT/.itest-net"
DATA_UUID="aabbccdd-0000-0000-0000-000000000099"
rm -rf "$ITEST"; mkdir -p "$ITEST"

# stage <name> <selftest-file> <modem-uuid>
stage() {
  local name="$1" selftest="$2" modem="$3"
  local inst="$ITEST/$name"
  mkdir -p "$inst"
  cp -r "$STOCK/openos" "$inst/openos"
  cp "$STOCK/bios.lua" "$inst/bios.lua"
  cp "$STOCK/data" "$inst/data" 2>/dev/null || true
  cp -r "$ROOT/overlay/." "$inst/openos/"
  while IFS= read -r -d '' p; do
    local rel="${p#"$ROOT"/patches/}"
    mkdir -p "$inst/openos/$(dirname "$rel")"; cp "$p" "$inst/openos/$rel"
  done < <(find "$ROOT/patches" -name '*.lua' ! -name '*.orig' -print0)
  cp "$selftest" "$inst/openos/bin/aurora-selftest.lua"
  printf 'aurora-selftest\n' > "$inst/openos/home/.shrc"
  cat > "$inst/client.cfg" <<CFG
{
  ["components"]={
    {"screen","a58b9479-05fa-4430-927d-4d269cc7455b",},
    {"gpu","afdadc8a-7d28-4551-bb0d-417c1cc691e0",44800,},
    {"eeprom","64dcf220-5f75-4e8d-a895-e29efc3c2c8e",4096,256,"OC-BIOS",},
    {"computer","f83d72fc-bd41-4728-ae8a-b7d5239f3a3a",2097152,},
    {"filesystem","20c9a62c-e1ea-41a3-b7a4-5b04c23dbff0","$inst/openos","openos",},
    {"filesystem","$DATA_UUID",false,"data",},
    {"filesystem","3344634b-d385-48dd-bb11-8b219e7a99d8",true,"tmpfs",},
    {"keyboard","fdbd6546-7858-7336-5191-eff6d47a68d0","a58b9479-05fa-4430-927d-4d269cc7455b",},
    {"modem","$modem",56000,8192,8,},
  },
  ["system"]={["allowBytecode"]=false,["allowGC"]=false,["maxTcpConnections"]=4,["timeout"]=5,},
}
CFG
}

stage server "$ROOT/tests/integration/netserver.lua" "5e54e000-0000-0000-0000-000000000001"
stage client "$ROOT/tests/integration/netclient.lua" "5e54e000-0000-0000-0000-000000000002"

echo "booting server + client (modem hub on :56000)..."
# server first so it binds the hub and opens its port before the client calls
( cd "$ITEST/server" && timeout 70 script -qc "$OCVM $ITEST/server --frame=basic" /tmp/aurora-net-srv.txt </dev/null >/dev/null 2>&1 ) &
SRV_PID=$!
sleep 7
( cd "$ITEST/client" && timeout 60 script -qc "$OCVM $ITEST/client --frame=basic" /tmp/aurora-net-cli.txt </dev/null >/dev/null 2>&1 ) || true
# client has halted; give the server a moment to finish + halt, then stop it
sleep 2
kill "$SRV_PID" >/dev/null 2>&1 || true
wait "$SRV_PID" 2>/dev/null || true

SRV_LOG="$ITEST/server/$DATA_UUID/selftest.log"
CLI_LOG="$ITEST/client/$DATA_UUID/selftest.log"
echo "--- server log ---"; cat "$SRV_LOG" 2>/dev/null || echo "(none)"
echo "--- client log ---"; cat "$CLI_LOG" 2>/dev/null || echo "(none)"

if [[ -f "$CLI_LOG" ]] && grep -q "^PASS client" "$CLI_LOG"; then
  echo "net integration: PASS (real RPC over modem between two VMs)"
  exit 0
fi
echo "net integration: FAILED"
exit 2
