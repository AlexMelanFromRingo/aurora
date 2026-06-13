-- aurora.theme — named color themes for the shell. A theme bundles a PS1 prompt
-- (built via aurora.prompt) and an LS_COLORS string. The registry is pure data
-- (host-testable); apply/persist touch the environment and disk.
local prompt = require("aurora.prompt")

local theme = {}
theme.activePath = "/etc/aurora/active-theme"

-- registry: name -> {ps1, ls_colors, description}
local THEMES = {
  default = {
    description = "Aurora default — green host, cyan path",
    ps1 = prompt.build({symbol = "# ", colors = {host = "green", path = "cyan"}}),
    ls_colors = "di=1;36:fi=0:ln=1;33:ex=1;32:*.lua=0;32:*.cfg=0;33",
  },
  dark = {
    description = "muted blues on dark terminals",
    ps1 = prompt.build({symbol = "» ", colors = {host = "blue", path = "white"}}),
    ls_colors = "di=1;34:fi=0:ln=1;36:*.lua=0;36",
  },
  mono = {
    description = "no colors — for monochrome screens (tier-1 GPU)",
    ps1 = prompt.build({hostname = true, cwd = true, symbol = "$ ",
                        colors = {host = "white", path = "white", symbol = "white"}}),
    ls_colors = "di=0:fi=0:ln=0",
  },
  matrix = {
    description = "all green, two-line prompt",
    ps1 = prompt.build({twoLine = true, symbol = "> ",
                        colors = {host = "green", path = "green", symbol = "green"}}),
    ls_colors = "di=1;32:fi=0;32:ln=1;32:*.lua=1;32",
  },
}

function theme.list()
  local names = {}
  for n in pairs(THEMES) do names[#names + 1] = n end
  table.sort(names)
  return names
end

function theme.get(name) return THEMES[name] end

-- apply(name) -> true | nil, err   (sets env for the current shell)
function theme.apply(name)
  local th = THEMES[name]
  if not th then return nil, "unknown theme: " .. tostring(name) end
  os.setenv("PS1", th.ps1)
  os.setenv("LS_COLORS", th.ls_colors)
  return true
end

-- persist(name)/loadPersisted() — remember the choice across reboots. The
-- Aurora .shrc snippet calls applyPersisted() at login.
function theme.persist(name)
  if not THEMES[name] then return nil, "unknown theme: " .. tostring(name) end
  return require("aurora.fsx").atomicWrite(theme.activePath, name .. "\n")
end

function theme.applyPersisted()
  local fsx = require("aurora.fsx")
  if not fsx.exists(theme.activePath) then return false end
  local name = (fsx.readAll(theme.activePath) or ""):gsub("%s+$", "")
  if THEMES[name] then return theme.apply(name) end
  return false
end

return theme
