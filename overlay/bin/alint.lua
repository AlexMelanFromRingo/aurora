-- alint — lint one or more Lua files.
--   alint <file.lua> [more.lua ...]
-- Exit code: 0 clean, 1 warnings only, 2 errors.
local shell = require("shell")
local lint = require("aurora.lint")
local fsx = require("aurora.fsx")

local args = shell.parse(...)
if #args < 1 then io.write("Usage: alint <file.lua> [...]\n"); return end

local worst = 0
for _, arg in ipairs(args) do
  local path = shell.resolve(arg)
  local src = fsx.readAll(path)
  if not src then
    io.stderr:write("alint: cannot read " .. arg .. "\n"); worst = math.max(worst, 2)
  else
    local findings = lint.check(src)
    if #findings == 0 then
      io.write("\27[32mok\27[m   " .. arg .. "\n")
    else
      for _, f in ipairs(findings) do
        local color = f.severity == "error" and "31" or "33"
        io.write(string.format("\27[%sm%-7s\27[m %s:%d  %s\n",
          color, f.severity, arg, f.line, f.message))
        worst = math.max(worst, f.severity == "error" and 2 or 1)
      end
    end
  end
end
os.exit(worst)
