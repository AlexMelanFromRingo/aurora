-- asandbox — run a Lua file in a restricted sandbox: no io, filesystem,
-- component/computer, require or load. Only the pure stdlib plus a safe `print`
-- is available, so untrusted scripts can compute but cannot touch the system.
--   asandbox [--steps=N] <file.lua> [args...]
local shell = require("shell")
local sandbox = require("aurora.sandbox")
local fsx = require("aurora.fsx")

local args, options = shell.parse(...)
if #args < 1 then
  io.write("Usage: asandbox [--steps=N] <file.lua> [args...]\n")
  io.write("  runs the file with no system access; --steps caps execution\n")
  return
end

local path = shell.resolve(args[1])
local src = fsx.readAll(path)
if not src then io.stderr:write("asandbox: cannot read " .. args[1] .. "\n"); os.exit(1) end

local passthrough = {}
for i = 2, #args do passthrough[#passthrough + 1] = args[i] end

local ok, res = sandbox.run(src, {
  name = "=" .. args[1],
  steps = tonumber(options.steps),
  args = passthrough,
  env = {
    -- a controlled output capability for the sandboxed program
    print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      io.write(table.concat(parts, "\t") .. "\n")
    end,
  },
})

if not ok then
  io.stderr:write("asandbox: " .. tostring(res) .. "\n")
  os.exit(1)
end
