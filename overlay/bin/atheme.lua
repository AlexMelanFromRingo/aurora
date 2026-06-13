-- atheme — manage Aurora shell color themes.
--   atheme              show the active/available themes
--   atheme list         list themes
--   atheme set <name>   apply a theme now and remember it across reboots
local shell = require("shell")
local theme = require("aurora.theme")

local args = shell.parse(...)
local cmd = args[1] or "list"

if cmd == "list" then
  io.write("Available themes:\n")
  for _, name in ipairs(theme.list()) do
    local th = theme.get(name)
    io.write(string.format("  %-10s %s\n", name, th.description))
  end
  io.write("\nUse: atheme set <name>\n")

elseif cmd == "set" then
  local name = args[2]
  if not name then io.stderr:write("atheme: set needs a theme name\n"); os.exit(1) end
  local ok, err = theme.apply(name)
  if not ok then io.stderr:write("atheme: " .. err .. "\n"); os.exit(1) end
  theme.persist(name)
  io.write("Applied theme '" .. name .. "'. (open a new shell or `source ~/.shrc` to refresh)\n")

else
  io.stderr:write("atheme: unknown command '" .. cmd .. "'\n")
  os.exit(1)
end
