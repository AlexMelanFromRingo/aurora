-- Multi-node test, SERVER node. Opens an anet port and answers one JSON-RPC
-- "add" request over the modem (ocvm bridges modems between VMs via a localhost
-- socket hub), logs the outcome to the writable disk, then halts.
local anet = require("anet")
local computer = require("computer")
local component = require("component")

local PORT = 4000

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

local result = "FAIL server: no request received"
local ok = pcall(function()
  anet.open(PORT)
  local deadline = computer.uptime() + 45
  while computer.uptime() < deadline do
    local from, msg = anet.recv(PORT, 5)
    if from and type(msg) == "table" and msg.method == "add" then
      local p = msg.params
      local sum = p[1] + p[2]
      anet.send(from, PORT, anet.rpcResult(msg.id, sum))
      result = "PASS server: handled add(" .. p[1] .. "," .. p[2] .. ") -> " .. sum
      break
    end
  end
end)
if not ok then result = "FAIL server: error during serve" end

writeLog(result .. "\n")
io.write("\n[netserver] " .. result .. "\n")
os.sleep(0.3)
computer.shutdown(false)
