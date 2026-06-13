-- Multi-node test, CLIENT node. Makes a real JSON-RPC call to the SERVER node
-- over the modem and verifies the result, then logs and halts.
local anet = require("anet")
local computer = require("computer")
local component = require("component")

local PORT = 4000
local SERVER = "5e54e000-0000-0000-0000-000000000001"  -- server modem address

local function writeLog(text)
  for addr in component.list("filesystem") do
    local p = component.proxy(addr)
    if p.getLabel() == "data" and not p.isReadOnly() then
      local h = p.open("/selftest.log", "w")
      if h then p.write(h, text); p.close(h) end
      return
    end
  end
end

-- give the server a moment to come up and open its port
os.sleep(3)

local line
local res, err = anet.rpc.call(SERVER, PORT, "add", {2, 3}, 15)
if res == 5 then
  line = "PASS client: 2+3 over modem RPC = 5"
else
  line = "FAIL client: got " .. tostring(res) .. " (err=" .. tostring(err) .. ")"
end

writeLog(line .. "\n")
io.write("\n[netclient] " .. line .. "\n")
os.sleep(0.3)
computer.shutdown(false)
