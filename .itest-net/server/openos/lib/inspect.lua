-- inspect — cycle-safe, human-readable rendering of any Lua value. Useful in the
-- REPL and for debugging. inspect(value [, {depth=N, newline="\n", indent="  "}])
local function isIdentifier(s)
  return type(s) == "string" and s:match("^[%a_][%w_]*$") and not ({
    ["and"]=1,["break"]=1,["do"]=1,["else"]=1,["elseif"]=1,["end"]=1,
    ["false"]=1,["for"]=1,["function"]=1,["goto"]=1,["if"]=1,["in"]=1,
    ["local"]=1,["nil"]=1,["not"]=1,["or"]=1,["repeat"]=1,["return"]=1,
    ["then"]=1,["true"]=1,["until"]=1,["while"]=1})[s]
end

local function quote(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
    local map = {['"']='\\"', ['\\']='\\\\', ['\n']='\\n', ['\t']='\\t',
                 ['\r']='\\r'}
    return map[c] or string.format("\\%d", string.byte(c))
  end) .. '"'
end

local function keyAscii(a, b)
  local ta, tb = type(a), type(b)
  if ta == tb then
    if ta == "number" or ta == "string" then return a < b end
    return tostring(a) < tostring(b)
  end
  return ta < tb
end

local function render(value, opts, depth, seen, buf)
  local tv = type(value)
  if tv == "string" then
    buf[#buf + 1] = quote(value)
  elseif tv == "number" or tv == "boolean" or tv == "nil" then
    buf[#buf + 1] = tostring(value)
  elseif tv ~= "table" then
    buf[#buf + 1] = "<" .. tv .. ">"
  else
    if seen[value] then buf[#buf + 1] = "<cycle>"; return end
    if depth > opts.depth then buf[#buf + 1] = "{...}"; return end
    seen[value] = true
    local nl, ind = opts.newline, opts.indent
    local pad = string.rep(ind, depth + 1)
    local pad0 = string.rep(ind, depth)
    -- gather keys
    local arrKeys, hashKeys = {}, {}
    local n = #value
    for k in pairs(value) do
      if type(k) == "number" and k % 1 == 0 and k >= 1 and k <= n then
        arrKeys[k] = true
      else
        hashKeys[#hashKeys + 1] = k
      end
    end
    table.sort(hashKeys, keyAscii)
    if n == 0 and #hashKeys == 0 then seen[value] = nil; buf[#buf + 1] = "{}"; return end
    buf[#buf + 1] = "{" .. nl
    for i = 1, n do
      buf[#buf + 1] = pad
      render(value[i], opts, depth + 1, seen, buf)
      buf[#buf + 1] = "," .. nl
    end
    for _, k in ipairs(hashKeys) do
      buf[#buf + 1] = pad
      if isIdentifier(k) then
        buf[#buf + 1] = k .. " = "
      else
        buf[#buf + 1] = "["
        render(k, opts, depth + 1, seen, buf)
        buf[#buf + 1] = "] = "
      end
      render(value[k], opts, depth + 1, seen, buf)
      buf[#buf + 1] = "," .. nl
    end
    buf[#buf + 1] = pad0 .. "}"
    seen[value] = nil
  end
end

local function inspect(value, opts)
  opts = opts or {}
  opts.depth = opts.depth or 8
  opts.newline = opts.newline or "\n"
  opts.indent = opts.indent or "  "
  local buf = {}
  render(value, opts, 0, {}, buf)
  return table.concat(buf)
end

return inspect
