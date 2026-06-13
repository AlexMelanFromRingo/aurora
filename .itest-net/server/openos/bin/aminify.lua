-- aminify — minify a Lua file (strip comments + needless whitespace).
--   aminify <in.lua> [out.lua]    (no out → stdout)
local shell = require("shell")
local minify = require("aurora.minify")
local fsx = require("aurora.fsx")

local args = shell.parse(...)
if #args < 1 then
  io.write("Usage: aminify <in.lua> [out.lua]\n")
  return
end
local src, err = fsx.readAll(shell.resolve(args[1]))
if not src then io.stderr:write("aminify: " .. tostring(err) .. "\n"); os.exit(1) end

local ok, out = pcall(minify, src)
if not ok then io.stderr:write("aminify: " .. tostring(out) .. "\n"); os.exit(1) end

if args[2] then
  assert(fsx.atomicWrite(shell.resolve(args[2]), out))
  io.write(string.format("minified %d -> %d bytes (%.0f%%)\n",
    #src, #out, 100 * #out / math.max(#src, 1)))
else
  io.write(out)
  if out:sub(-1) ~= "\n" then io.write("\n") end
end
