-- OpenComputers host shim: lets pure-Lua Aurora modules run under stock lua5.3
-- so they can be unit-tested off-emulator. Installs the globals OpenOS provides
-- (checkArg, unicode, os.sleep) and mockable `component`/`computer` tables.
-- Idempotent: requiring it twice is harmless.
local M = {}

-- checkArg: OpenOS-style argument validator (global in OpenOS).
if not _G.checkArg then
  function _G.checkArg(n, have, ...)
    have = type(have)
    local function check(want, ...)
      if not want then
        return false
      else
        return want == have or check(...)
      end
    end
    if not check(...) then
      local msg = string.format("bad argument #%d (%s expected, got %s)",
        n, table.concat({...}, " or "), have)
      error(msg, 3)
    end
  end
end

-- unicode: OpenOS exposes a UTF-8-aware library. For host tests we provide a
-- faithful UTF-8 implementation (Lua 5.3 has utf8 builtin) so length/sub on
-- multibyte strings behave like in-VM.
if not _G.unicode then
  local u = {}
  function u.len(s)
    local ok, n = pcall(utf8.len, s)
    return (ok and n) or #s
  end
  function u.char(...) return utf8.char(...) end
  function u.sub(s, i, j)
    local n = u.len(s)
    if i < 0 then i = n + i + 1 end
    if j == nil then j = n elseif j < 0 then j = n + j + 1 end
    if i < 1 then i = 1 end
    if j > n then j = n end
    if i > j then return "" end
    local bi = utf8.offset(s, i)
    local bj = utf8.offset(s, j + 1)
    return string.sub(s, bi, (bj or 0) - 1)
  end
  function u.upper(s) return string.upper(s) end
  function u.lower(s) return string.lower(s) end
  function u.wlen(s) return u.len(s) end
  _G.unicode = u
end

-- os.sleep: cooperative yield in OpenOS; a no-op on host.
if not os.sleep then
  function os.sleep(_) end
end

-- A mockable component registry. Tests call M.set("internet", fakeTable).
local components = {}
local primary = {}
local component = {
  list = function(filter)
    local out = setmetatable({}, {__call = function(self, ...) return next(self, ...) end})
    for addr, c in pairs(components) do
      if not filter or c.type == filter then out[addr] = c.type end
    end
    return out
  end,
  isAvailable = function(kind) return primary[kind] ~= nil end,
  getPrimary = function(kind) return primary[kind] end,
  proxy = function(addr) return components[addr] and components[addr].proxy end,
  invoke = function(addr, method, ...)
    return components[addr].proxy[method](...)
  end,
}
setmetatable(component, {__index = function(_, kind)
  return primary[kind]
end})

local computer = {
  _uptime = 0,
  uptime = function() return os.clock() end,
  pullSignal = function(_) return nil end,
  pushSignal = function() end,
  address = function() return "00000000-0000-0000-0000-000000000000" end,
  totalMemory = function() return 1048576 end,
  freeMemory = function() return 524288 end,
}

_G.component = _G.component or component
_G.computer = _G.computer or computer

-- Register a fake component proxy and make it the primary of its kind.
function M.set(kind, proxy, addr)
  addr = addr or (kind .. "-0000")
  components[addr] = {type = kind, proxy = proxy}
  primary[kind] = proxy
  return addr
end

function M.clear()
  for k in pairs(components) do components[k] = nil end
  for k in pairs(primary) do primary[k] = nil end
end

function M.component() return _G.component end
function M.computer() return _G.computer end

return M
