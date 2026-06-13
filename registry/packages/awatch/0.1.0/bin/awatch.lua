-- awatch — run a command repeatedly, showing its latest output (like `watch`).
--   awatch [-n SECONDS] <command...>
-- Press Ctrl-Alt-C (in ocvm) or interrupt to stop.
local shell = require("shell")
local args, options = shell.parse(...)

if #args < 1 then
  io.write("Usage: awatch [-n SECONDS] <command...>\n")
  return
end

local interval = tonumber(options.n) or 2
local command = table.concat(args, " ")

while true do
  os.execute("clear")
  io.write(string.format("Every %ss: %s\n\n", interval, command))
  shell.execute(command)
  os.sleep(interval)
end
