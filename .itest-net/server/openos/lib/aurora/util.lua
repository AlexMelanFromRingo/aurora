-- aurora.util — small, pure string/table helpers used across Aurora. No OC deps.
local util = {}

function util.trim(s)
  checkArg(1, s, "string")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- split("a,b,,c", ",") -> {"a","b","","c"}. If plain is false, sep is a pattern.
function util.split(s, sep, plain)
  checkArg(1, s, "string")
  sep = sep or "%s+"
  local out = {}
  if plain then
    local start = 1
    while true do
      local i, j = s:find(sep, start, true)
      if not i then out[#out + 1] = s:sub(start); break end
      out[#out + 1] = s:sub(start, i - 1)
      start = j + 1
    end
  else
    local last = 1
    for piece, nxt in s:gmatch("(.-)" .. sep .. "()") do
      out[#out + 1] = piece
      last = nxt
    end
    out[#out + 1] = s:sub(last)
  end
  return out
end

function util.startsWith(s, prefix)
  return s:sub(1, #prefix) == prefix
end

function util.endsWith(s, suffix)
  return suffix == "" or s:sub(-#suffix) == suffix
end

function util.keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  return out
end

function util.values(t)
  local out = {}
  for _, v in pairs(t) do out[#out + 1] = v end
  return out
end

function util.map(t, fn)
  local out = {}
  for i, v in ipairs(t) do out[i] = fn(v, i) end
  return out
end

function util.filter(t, pred)
  local out = {}
  for _, v in ipairs(t) do if pred(v) then out[#out + 1] = v end end
  return out
end

function util.contains(t, value)
  for _, v in pairs(t) do if v == value then return true end end
  return false
end

-- merge(a, b) -> new table with b's keys overriding a's (shallow).
function util.merge(a, b)
  local out = {}
  for k, v in pairs(a or {}) do out[k] = v end
  for k, v in pairs(b or {}) do out[k] = v end
  return out
end

-- humanBytes(1536) -> "1.5K"
function util.humanBytes(n)
  local units = {"B", "K", "M", "G", "T"}
  local i = 1
  while n >= 1024 and i < #units do n = n / 1024; i = i + 1 end
  if i == 1 then return string.format("%d%s", n, units[i]) end
  return string.format("%.1f%s", n, units[i])
end

return util
