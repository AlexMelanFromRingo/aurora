-- /etc/aurora/login.lua — Aurora's per-login customization. Sourced in-process
-- by /etc/profile.lua (via the installer's guarded hook) so os.setenv and
-- aliases persist into the interactive shell. Everything is defensive: a
-- failure here must never block login.
local shell = require("shell")

-- 1) apply the remembered color theme (falls back to default)
do
  local ok, theme = pcall(require, "aurora.theme")
  if ok then
    if not pcall(theme.applyPersisted) then pcall(theme.apply, "default") end
  end
end

-- 2) load message catalogs and apply the remembered language
do
  local ok, lang = pcall(require, "aurora.lang")
  if ok then
    pcall(lang.loadDir, "/etc/locale")
    pcall(lang.applyPersisted)
  end
end

-- 3) convenient aliases (do not clobber user-defined ones)
local aliases = {
  ll = "ls -lhp",
  la = "ls -ap",
  fetch = "afetch",
  pkg = "opm",
  ["opm-up"] = "opm update",
}
for name, value in pairs(aliases) do
  if not shell.getAlias(name) then pcall(shell.setAlias, name, value) end
end
