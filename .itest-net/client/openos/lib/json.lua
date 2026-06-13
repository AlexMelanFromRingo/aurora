-- json — strict, dependency-free JSON encode/decode for OpenOS / Lua 5.3.
--
--   json.encode(value [, {pretty=true, indent="  "}]) -> string
--   json.decode(string) -> value            (errors on malformed input)
--
-- Conventions: Lua `nil` cannot live in tables, so JSON `null` decodes to
-- `json.null` (a unique sentinel) and encodes back. Empty tables encode as
-- `[]`; pass `json.object{}` (or a table with the `__json="object"` mark) to
-- force `{}`.
local json = {}

json.null = setmetatable({}, {__tostring = function() return "null" end})

function json.object(t)
  t = t or {}
  return setmetatable(t, {__json = "object"})
end

-- ---- encode ----------------------------------------------------------------

local escapes = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function encode_string(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
    return escapes[c] or string.format('\\u%04x', string.byte(c))
  end) .. '"'
end

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k % 1 ~= 0 or k < 1 then return false end
    n = n + 1
  end
  return n == #t, #t
end

local function encode_value(v, opts, depth)
  local tv = type(v)
  if v == json.null then
    return "null"
  elseif tv == "nil" then
    return "null"
  elseif tv == "boolean" then
    return tostring(v)
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      error("cannot encode non-finite number")
    end
    if math.type(v) == "integer" then return tostring(v) end
    return string.format("%.17g", v)
  elseif tv == "string" then
    return encode_string(v)
  elseif tv == "table" then
    local mt = getmetatable(v)
    local forceObj = (mt and mt.__json == "object")
    local nl, pad, pad2, colon = "", "", "", ":"
    if opts.pretty then
      local ind = opts.indent or "  "
      nl = "\n"
      pad = string.rep(ind, depth + 1)
      pad2 = string.rep(ind, depth)
      colon = ": "
    end
    local arr, n = is_array(v)
    if arr and not forceObj then
      if n == 0 then return "[]" end
      local parts = {}
      for i = 1, n do parts[i] = pad .. encode_value(v[i], opts, depth + 1) end
      return "[" .. nl .. table.concat(parts, "," .. nl) .. nl .. pad2 .. "]"
    else
      local keys = {}
      for k in pairs(v) do
        if type(k) ~= "string" and type(k) ~= "number" then
          error("cannot encode table with " .. type(k) .. " key")
        end
        keys[#keys + 1] = k
      end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      if #keys == 0 then return "{}" end
      local parts = {}
      for _, k in ipairs(keys) do
        parts[#parts + 1] = pad .. encode_string(tostring(k)) .. colon
          .. encode_value(v[k], opts, depth + 1)
      end
      return "{" .. nl .. table.concat(parts, "," .. nl) .. nl .. pad2 .. "}"
    end
  else
    error("cannot encode " .. tv)
  end
end

function json.encode(value, opts)
  return encode_value(value, opts or {}, 0)
end

-- ---- decode ----------------------------------------------------------------

local function decode_error(s, i, msg)
  local line = 1
  for _ in s:sub(1, i):gmatch("\n") do line = line + 1 end
  error(string.format("json: %s at byte %d (line %d)", msg, i, line), 0)
end

local function skip_ws(s, i)
  local _, j = s:find("^[ \t\r\n]*", i)
  return j + 1
end

local decode_value  -- forward

local function decode_string(s, i)
  -- s:sub(i) starts at the opening quote
  local buf, j = {}, i + 1
  while true do
    local c = s:byte(j)
    if not c then decode_error(s, j, "unterminated string") end
    if c == 34 then -- "
      return table.concat(buf), j + 1
    elseif c == 92 then -- backslash
      local e = s:sub(j + 1, j + 1)
      local map = {['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f',
                   n='\n', r='\r', t='\t'}
      if map[e] then
        buf[#buf + 1] = map[e]; j = j + 2
      elseif e == "u" then
        local hex = s:sub(j + 2, j + 5)
        if not hex:match("^%x%x%x%x$") then decode_error(s, j, "bad \\u escape") end
        local cp = tonumber(hex, 16)
        buf[#buf + 1] = utf8.char(cp); j = j + 6
      else
        decode_error(s, j, "bad escape \\" .. tostring(e))
      end
    elseif c < 32 then
      decode_error(s, j, "control char in string")
    else
      buf[#buf + 1] = string.char(c); j = j + 1
    end
  end
end

local function decode_number(s, i)
  local num = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
  local val = tonumber(num)
  if not val then decode_error(s, i, "invalid number") end
  return val, i + #num
end

decode_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local obj = json.object({})
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while true do
      i = skip_ws(s, i)
      if s:sub(i, i) ~= '"' then decode_error(s, i, "expected string key") end
      local key; key, i = decode_string(s, i)
      i = skip_ws(s, i)
      if s:sub(i, i) ~= ":" then decode_error(s, i, "expected ':'") end
      local val; val, i = decode_value(s, i + 1)
      obj[key] = val
      i = skip_ws(s, i)
      local d = s:sub(i, i)
      if d == "," then i = i + 1
      elseif d == "}" then return obj, i + 1
      else decode_error(s, i, "expected ',' or '}'") end
    end
  elseif c == "[" then
    local arr = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == "]" then return arr, i + 1 end
    while true do
      local val; val, i = decode_value(s, i)
      arr[#arr + 1] = val
      i = skip_ws(s, i)
      local d = s:sub(i, i)
      if d == "," then i = i + 1
      elseif d == "]" then return arr, i + 1
      else decode_error(s, i, "expected ',' or ']'") end
    end
  elseif c == '"' then
    return decode_string(s, i)
  elseif c == "t" and s:sub(i, i + 3) == "true" then
    return true, i + 4
  elseif c == "f" and s:sub(i, i + 4) == "false" then
    return false, i + 5
  elseif c == "n" and s:sub(i, i + 3) == "null" then
    return json.null, i + 4
  elseif c:match("[%-%d]") then
    return decode_number(s, i)
  else
    decode_error(s, i, "unexpected character " .. (c == "" and "<eof>" or c))
  end
end

function json.decode(s)
  checkArg(1, s, "string")
  local val, i = decode_value(s, 1)
  i = skip_ws(s, i)
  if i <= #s then decode_error(s, i, "trailing garbage") end
  return val
end

return json
