-- aurora.sysinfo — gather and format a system summary (powers `afetch`). The
-- collection takes its providers as arguments so it can be unit-tested with
-- fakes; rendering is pure.
local util = require("aurora.util")

local sysinfo = {}

-- collect(env) -> info. env = {computer=, component=, osversion=}
function sysinfo.collect(env)
  local computer = env.computer
  local component = env.component
  local total = computer.totalMemory()
  local free = computer.freeMemory()
  local comps = {}
  for _, ctype in component.list() do
    comps[ctype] = (comps[ctype] or 0) + 1
  end
  return {
    os = env.osversion or "OpenOS",
    address = computer.address(),
    uptime = math.floor(computer.uptime()),
    totalMem = total,
    freeMem = free,
    usedMem = total - free,
    components = comps,
  }
end

local function fmtUptime(sec)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then return string.format("%dh %dm", h, m) end
  if m > 0 then return string.format("%dm %ds", m, s) end
  return string.format("%ds", s)
end

local LOGO = {
  "  \27[36m/\\\27[m   ",
  " \27[36m/  \\\27[m  ",
  "\27[36m/____\\\27[m ",
  "\27[36m\\    /\27[m ",
  " \27[36m\\  /\27[m  ",
  "  \27[36m\\/\27[m   ",
}

-- render(info, opts) -> array of lines. opts.labels may localize the row labels:
-- {os=, uptime=, memory=, address=, hardware=}; English defaults otherwise.
function sysinfo.render(info, opts)
  opts = opts or {}
  local L = opts.labels or {}
  local rows = {
    {L.os or "OS", info.os},
    {L.uptime or "Uptime", fmtUptime(info.uptime)},
    {L.memory or "Memory", string.format("%s / %s used",
      util.humanBytes(info.usedMem), util.humanBytes(info.totalMem))},
    {L.address or "Address", (info.address or ""):sub(1, 8)},
  }
  -- components summary
  local parts = {}
  local names = util.keys(info.components)
  table.sort(names)
  for _, n in ipairs(names) do parts[#parts + 1] = n .. "×" .. info.components[n] end
  rows[#rows + 1] = {L.hardware or "Hardware", table.concat(parts, " ")}

  local lines = {}
  local maxRows = math.max(#LOGO, #rows)
  for i = 1, maxRows do
    local logo = LOGO[i] or "       "
    local row = rows[i]
    if row then
      lines[#lines + 1] = string.format("%s \27[1m%-9s\27[m %s", logo, row[1], row[2])
    else
      lines[#lines + 1] = logo
    end
  end
  return lines
end

return sysinfo
