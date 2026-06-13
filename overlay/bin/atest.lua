-- atest — run aurora.test suites. Each file should register cases with
-- describe/it (and must NOT call test.run itself).
--   atest <suite.lua> [more.lua ...]
local shell = require("shell")
local test = require("aurora.test")

local args, options = shell.parse(...)
if #args < 1 then io.write("Usage: atest <suite.lua> [...]\n"); return end

for _, arg in ipairs(args) do
  local path = shell.resolve(arg)
  local chunk, err = loadfile(path)
  if not chunk then
    io.stderr:write("atest: cannot load " .. arg .. ": " .. tostring(err) .. "\n")
    os.exit(2)
  end
  local ok, lerr = pcall(chunk)
  if not ok then
    io.stderr:write("atest: error registering " .. arg .. ": " .. tostring(lerr) .. "\n")
    os.exit(2)
  end
end

os.exit((test.run({quiet = options.q or options.quiet})))
