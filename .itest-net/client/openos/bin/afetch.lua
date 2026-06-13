-- afetch — a compact, neofetch-style system summary for OpenOS.
local sysinfo = require("aurora.sysinfo")
local component = require("component")
local computer = require("computer")

local info = sysinfo.collect({
  computer = computer,
  component = component,
  osversion = _OSVERSION,
})
io.write("\n")
for _, line in ipairs(sysinfo.render(info)) do
  io.write(line, "\n")
end
io.write("\n")
