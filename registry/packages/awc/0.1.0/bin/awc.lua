-- awc — count lines, words and bytes (like wc).
--   awc [-l] [-w] [-c] <file> ...   (no flags = all three; no file = stdin)
local shell = require("shell")
local args, options = shell.parse(...)

local showL = options.l or not (options.l or options.w or options.c)
local showW = options.w or not (options.l or options.w or options.c)
local showC = options.c or not (options.l or options.w or options.c)

local function counts(data)
  local lines = select(2, data:gsub("\n", ""))
  local words = select(2, data:gsub("%S+", ""))
  return lines, words, #data
end

local function row(l, w, c, name)
  local parts = {}
  if showL then parts[#parts + 1] = string.format("%7d", l) end
  if showW then parts[#parts + 1] = string.format("%7d", w) end
  if showC then parts[#parts + 1] = string.format("%7d", c) end
  io.write(table.concat(parts, " ") .. (name and ("  " .. name) or "") .. "\n")
end

if #args == 0 then
  local l, w, c = counts(io.read("*a") or "")
  row(l, w, c)
else
  local tl, tw, tc = 0, 0, 0
  for _, arg in ipairs(args) do
    local f, err = io.open(shell.resolve(arg), "rb")
    if not f then
      io.stderr:write("awc: " .. arg .. ": " .. tostring(err) .. "\n")
    else
      local data = f:read("*a") or ""; f:close()
      local l, w, c = counts(data)
      tl, tw, tc = tl + l, tw + w, tc + c
      row(l, w, c, arg)
    end
  end
  if #args > 1 then row(tl, tw, tc, "total") end
end
