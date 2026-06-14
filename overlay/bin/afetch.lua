-- afetch — a compact, neofetch-style system summary for OpenOS (localized).
local sysinfo = require("aurora.sysinfo")
local component = require("component")
local computer = require("computer")
local lang = require("aurora.lang")

pcall(lang.loadDir, "/etc/locale")
pcall(lang.applyPersisted)

local info = sysinfo.collect({
  computer = computer,
  component = component,
  osversion = _OSVERSION,
})
local labels = {
  os = lang.t("sys.os"), uptime = lang.t("sys.uptime"),
  memory = lang.t("sys.memory"), address = lang.t("sys.address"),
  hardware = lang.t("sys.hardware"),
}
io.write("\n")
for _, line in ipairs(sysinfo.render(info, {labels = labels})) do
  io.write(line, "\n")
end
io.write("\n")
