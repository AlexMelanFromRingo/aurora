-- atpl — transpile Aurora sugar (compound assignment ops) to plain Lua.
--   atpl <in.lua> [out.lua]      (no out → stdout)
local shell = require("shell")
local transpile = require("aurora.transpile")
local fsx = require("aurora.fsx")

local args = shell.parse(...)
if #args < 1 then
  io.write("Usage: atpl <in.lua> [out.lua]\n")
  io.write("Adds += -= *= /= //= %= ^= ..= &= |= <<= >>=\n")
  return
end
local src, err = fsx.readAll(shell.resolve(args[1]))
if not src then io.stderr:write("atpl: " .. tostring(err) .. "\n"); os.exit(1) end
local out = transpile.run(src)
if args[2] then
  assert(fsx.atomicWrite(shell.resolve(args[2]), out))
  io.write("transpiled -> " .. args[2] .. "\n")
else
  io.write(out)
  if out:sub(-1) ~= "\n" then io.write("\n") end
end
