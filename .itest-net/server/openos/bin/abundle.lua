-- abundle — link a Lua project's require() graph into one file.
--   abundle <entry.lua> <out.lua> [--minify]
local shell = require("shell")
local bundle = require("aurora.bundle")
local fsx = require("aurora.fsx")

local args, options = shell.parse(...)
if #args < 2 then
  io.write("Usage: abundle <entry.lua> <out.lua> [--minify]\n")
  return
end
local out, info = bundle.build(shell.resolve(args[1]), {minify = options.minify})
if not out then io.stderr:write("abundle: " .. tostring(info) .. "\n"); os.exit(1) end
assert(fsx.atomicWrite(shell.resolve(args[2]), out))
io.write(string.format("bundled %d module(s) -> %s (%d bytes)\n",
  #info.modules, args[2], #out))
