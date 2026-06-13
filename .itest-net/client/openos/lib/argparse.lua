-- argparse — declarative command-line parsing for OpenOS programs.
--
--   local argparse = require("argparse")
--   local p = argparse("greet", "say hello")
--   p:positional("name", "who to greet")
--   p:flag("loud", "shout", {short = "l"})
--   p:option("times", "repeat count", {short = "n", default = "1"})
--   local a = p:parse(...)        -- a.name, a.loud (bool), a.times (string)
--
-- On `-h/--help` it prints usage and returns nil, "help". On error it prints the
-- message + usage and returns nil, errmsg. Callers: `if not a then return end`.
local argparse = {}
argparse.__index = argparse

local function new(name, description)
  return setmetatable({
    _name = name or "program",
    _desc = description or "",
    _positionals = {},
    _flags = {},        -- name -> {desc, short}
    _options = {},      -- name -> {desc, short, default}
    _byShort = {},      -- short -> {kind, name}
  }, argparse)
end

function argparse:positional(name, desc)
  self._positionals[#self._positionals + 1] = {name = name, desc = desc}
  return self
end

function argparse:flag(name, desc, opts)
  opts = opts or {}
  self._flags[name] = {desc = desc, short = opts.short}
  if opts.short then self._byShort[opts.short] = {kind = "flag", name = name} end
  return self
end

function argparse:option(name, desc, opts)
  opts = opts or {}
  self._options[name] = {desc = desc, short = opts.short, default = opts.default}
  if opts.short then self._byShort[opts.short] = {kind = "option", name = name} end
  return self
end

function argparse:usage()
  local parts = {"Usage: " .. self._name}
  if next(self._flags) or next(self._options) then parts[#parts + 1] = "[options]" end
  for _, p in ipairs(self._positionals) do parts[#parts + 1] = "<" .. p.name .. ">" end
  local lines = {table.concat(parts, " ")}
  if self._desc ~= "" then lines[#lines + 1] = "  " .. self._desc end
  local function row(flag, d)
    lines[#lines + 1] = string.format("  %-22s %s", flag, d or "")
  end
  if next(self._flags) or next(self._options) then lines[#lines + 1] = "Options:" end
  local names = {}
  for n in pairs(self._flags) do names[#names + 1] = {n, "flag"} end
  for n in pairs(self._options) do names[#names + 1] = {n, "option"} end
  table.sort(names, function(a, b) return a[1] < b[1] end)
  for _, e in ipairs(names) do
    local n, kind = e[1], e[2]
    local spec = kind == "flag" and self._flags[n] or self._options[n]
    local left = (spec.short and ("-" .. spec.short .. ", ") or "") .. "--" .. n
    if kind == "option" then left = left .. "=V" end
    row(left, spec.desc)
  end
  return table.concat(lines, "\n")
end

-- parse(...) — returns table of results or (nil, reason). Prints on help/error.
function argparse:parse(...)
  local argv = {...}
  local out = {}
  for n, spec in pairs(self._options) do out[n] = spec.default end
  for n in pairs(self._flags) do out[n] = false end

  local positionals = {}
  local i, n = 1, #argv
  local doneOpts = false
  while i <= n do
    local a = argv[i]
    if not doneOpts and (a == "-h" or a == "--help") then
      io.write(self:usage() .. "\n")
      return nil, "help"
    elseif not doneOpts and a == "--" then
      doneOpts = true
    elseif not doneOpts and a:sub(1, 2) == "--" then
      local key, val = a:match("^%-%-([%w%-_]+)=(.*)$")
      if not key then key = a:sub(3) end
      if self._flags[key] then
        out[key] = true
      elseif self._options[key] then
        if not val then i = i + 1; val = argv[i]
          if val == nil then return self:_err("--" .. key .. " needs a value") end
        end
        out[key] = val
      else
        return self:_err("unknown option --" .. key)
      end
    elseif not doneOpts and a:sub(1, 1) == "-" and #a > 1 then
      -- short flags, possibly clustered: -lv  or  -n 5
      for j = 2, #a do
        local sh = a:sub(j, j)
        local ref = self._byShort[sh]
        if not ref then return self:_err("unknown option -" .. sh) end
        if ref.kind == "flag" then
          out[ref.name] = true
        else
          local val = a:sub(j + 1)
          if val == "" then i = i + 1; val = argv[i]
            if val == nil then return self:_err("-" .. sh .. " needs a value") end
          end
          out[ref.name] = val
          break
        end
      end
    else
      positionals[#positionals + 1] = a
    end
    i = i + 1
  end

  for idx, p in ipairs(self._positionals) do
    if positionals[idx] == nil then
      return self:_err("missing argument <" .. p.name .. ">")
    end
    out[p.name] = positionals[idx]
  end
  -- extra positionals collected under .rest
  out.rest = {}
  for idx = #self._positionals + 1, #positionals do
    out.rest[#out.rest + 1] = positionals[idx]
  end
  return out
end

function argparse:_err(msg)
  io.stderr:write(self._name .. ": " .. msg .. "\n")
  io.stderr:write(self:usage() .. "\n")
  return nil, msg
end

return setmetatable(argparse, {__call = function(_, name, desc) return new(name, desc) end})
