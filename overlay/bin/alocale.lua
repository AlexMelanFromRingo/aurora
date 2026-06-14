-- alocale — show or change the Aurora interface language.
--   alocale              show the current locale
--   alocale list         list available locales
--   alocale set <code>   switch language and remember it across reboots
local shell = require("shell")
local lang = require("aurora.lang")

lang.loadDir("/etc/locale")
lang.applyPersisted()

local args = shell.parse(...)
local cmd = args[1]

if cmd == nil then
  io.write(lang.t("locale.current", {code = lang.getLocale()}) .. "\n")

elseif cmd == "list" then
  io.write(lang.t("locale.available") .. "\n")
  for _, code in ipairs(lang.locales()) do
    io.write("  " .. code .. (code == lang.getLocale() and " *" or "") .. "\n")
  end

elseif cmd == "set" then
  local code = args[2]
  if not code or not lang.has(code) then
    io.stderr:write(lang.t("locale.unknown", {code = tostring(code)}) .. "\n")
    os.exit(1)
  end
  lang.setLocale(code)
  lang.persist(code)
  io.write(lang.t("locale.set", {code = code}) .. "\n")

else
  io.write(lang.t("locale.usage") .. "\n")
end
