-- abase64 — Base64 encode/decode. Uses the data card when present, otherwise a
-- pure-Lua implementation.
--   abase64 [file]        encode (stdin if no file)
--   abase64 -d [file]     decode
local shell = require("shell")
local args, options = shell.parse(...)

local B = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function enc_pure(data)
  return ((data:gsub(".", function(x)
    local r, b = "", x:byte()
    for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
    return r
  end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
    if #x < 6 then return "" end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
    return B:sub(c + 1, c + 1)
  end) .. ({"", "==", "="})[#data % 3 + 1])
end

local function dec_pure(data)
  data = data:gsub("[^" .. B .. "=]", "")
  return (data:gsub("=", ""):gsub(".", function(x)
    local r, f = "", (B:find(x, 1, true) - 1)
    for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0") end
    return r
  end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
    if #x ~= 8 then return "" end
    local c = 0
    for i = 1, 8 do c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0) end
    return string.char(c)
  end))
end

-- prefer the data card
local function via_card(method, data)
  local ok, component = pcall(require, "component")
  if ok and component.isAvailable("data") then
    local good, res = pcall(component.data[method], data)
    if good and type(res) == "string" then return res end
  end
  return nil
end

local input
if args[1] then
  local f, err = io.open(shell.resolve(args[1]), "rb")
  if not f then io.stderr:write("abase64: " .. tostring(err) .. "\n"); os.exit(1) end
  input = f:read("*a"); f:close()
else
  input = io.read("*a") or ""
end

local out
if options.d then
  out = via_card("decode64", input) or dec_pure(input)
else
  out = via_card("encode64", input) or enc_pure(input)
  out = out .. "\n"
end
io.write(out)
