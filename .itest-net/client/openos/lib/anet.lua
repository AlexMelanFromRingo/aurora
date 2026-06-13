-- anet — LAN messaging over the OpenComputers modem, plus a small JSON-RPC 2.0
-- layer. The wire protocol (encode/decode, RPC envelopes) is pure and unit-
-- tested; the transport functions use component.modem + the event loop and are
-- exercised in-VM.
--
--   anet.open(port)
--   anet.send(addr, port, {hello = "world"})
--   local from, msg = anet.recv(port, 5)        -- 5s timeout
--
--   -- RPC server (blocking):
--   anet.rpc.serve(port, { add = function(a, b) return a + b end })
--   -- RPC client:
--   local sum = anet.rpc.call(addr, port, "add", {2, 3})
local anet = {}
local json = require("json")

local MAGIC = "ANET1"

-- ---- pure protocol ---------------------------------------------------------

-- encode(message) -> wire string. Messages are JSON objects under a magic tag
-- so unrelated modem traffic on the same port is ignored.
function anet.encode(message)
  return MAGIC .. json.encode({d = message})
end

-- decode(wire) -> message | nil (nil if not an anet frame / malformed)
function anet.decode(wire)
  if type(wire) ~= "string" or wire:sub(1, #MAGIC) ~= MAGIC then return nil end
  local ok, obj = pcall(json.decode, wire:sub(#MAGIC + 1))
  if not ok or type(obj) ~= "table" then return nil end
  return obj.d
end

-- JSON-RPC 2.0 envelope builders (pure)
local nextId = 0
function anet.rpcRequest(method, params, id)
  if id == nil then nextId = nextId + 1; id = nextId end
  return {jsonrpc = "2.0", method = method, params = params or json.null, id = id}
end

function anet.rpcResult(id, result)
  return {jsonrpc = "2.0", result = result == nil and json.null or result, id = id}
end

function anet.rpcError(id, code, message)
  return {jsonrpc = "2.0", error = {code = code, message = message}, id = id}
end

-- ---- transport (OpenOS only) ----------------------------------------------

local function modem()
  local component = require("component")
  if not component.isAvailable("modem") then
    error("no modem available", 2)
  end
  return component.modem
end

function anet.open(port)
  checkArg(1, port, "number")
  modem().open(port)
  return true
end

function anet.close(port) return modem().close(port) end

function anet.send(address, port, message)
  checkArg(1, address, "string")
  checkArg(2, port, "number")
  return modem().send(address, port, anet.encode(message))
end

function anet.broadcast(port, message)
  checkArg(1, port, "number")
  return modem().broadcast(port, anet.encode(message))
end

-- recv(port, timeout) -> fromAddress, message | nil, "timeout"
function anet.recv(port, timeout)
  local event = require("event")
  local deadline = timeout and (require("computer").uptime() + timeout)
  while true do
    local remaining = deadline and math.max(0, deadline - require("computer").uptime())
    local ev = {event.pull(remaining, "modem_message")}
    if ev[1] == "modem_message" then
      local from, p, payload = ev[3], ev[4], ev[6]
      if p == port then
        local msg = anet.decode(payload)
        if msg ~= nil then return from, msg end
      end
    elseif deadline and require("computer").uptime() >= deadline then
      return nil, "timeout"
    elseif remaining == 0 then
      return nil, "timeout"
    end
  end
end

-- ---- RPC -------------------------------------------------------------------

anet.rpc = {}

-- call(addr, port, method, params, timeout) -> result | nil, err
function anet.rpc.call(address, port, method, params, timeout)
  anet.open(port)
  local req = anet.rpcRequest(method, params)
  anet.send(address, port, req)
  local deadline = (require("computer").uptime()) + (timeout or 5)
  while require("computer").uptime() <= deadline do
    local from, msg = anet.recv(port, math.max(0, deadline - require("computer").uptime()))
    if from == address and type(msg) == "table" and msg.id == req.id then
      if msg.error then return nil, msg.error.message end
      return msg.result
    end
    if not from then break end
  end
  return nil, "rpc timeout"
end

-- serve(port, handlers, opts) — loop handling requests. opts.once stops after one.
function anet.rpc.serve(port, handlers, opts)
  opts = opts or {}
  anet.open(port)
  repeat
    local from, msg = anet.recv(port)
    if from and type(msg) == "table" and msg.method then
      local fn = handlers[msg.method]
      local reply
      if not fn then
        reply = anet.rpcError(msg.id, -32601, "method not found: " .. tostring(msg.method))
      else
        local params = msg.params
        if params == json.null then params = {} end
        local ok, res = pcall(fn, table.unpack(type(params) == "table" and params or {params}))
        if ok then reply = anet.rpcResult(msg.id, res)
        else reply = anet.rpcError(msg.id, -32000, tostring(res)) end
      end
      if msg.id ~= nil then anet.send(from, port, reply) end
    end
  until opts.once
end

return anet
