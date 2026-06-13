-- afmt — format Lua source from its AST (consistent indentation, spacing and
-- minimal parentheses). Meaning-preserving and idempotent.
--   afmt <file.lua>          print formatted source to stdout
--   afmt -w <file.lua> ...    rewrite files in place (atomic)
--   afmt -c <file.lua> ...    check only; exit 1 if a file is not formatted
local shell = require("shell")
local gen = require("aurora.lua.gen")
local fsx = require("aurora.fsx")

local args, options = shell.parse(...)
if #args < 1 then
  io.write("Usage: afmt [-w | -c] <file.lua> [...]\n")
  io.write("  -w  rewrite files in place\n")
  io.write("  -c  check only (exit 1 if any file is not formatted)\n")
  return
end

local exit = 0
for _, arg in ipairs(args) do
  local path = shell.resolve(arg)
  local src = fsx.readAll(path)
  if not src then
    io.stderr:write("afmt: cannot read " .. arg .. "\n"); exit = 2
  else
    local out, err = gen.format(src)
    if not out then
      io.stderr:write("afmt: " .. arg .. ": " .. tostring(err) .. "\n"); exit = math.max(exit, 2)
    elseif options.c then
      if out ~= src then io.write("not formatted: " .. arg .. "\n"); exit = math.max(exit, 1) end
    elseif options.w then
      if out ~= src then
        assert(fsx.atomicWrite(path, out))
        io.write("formatted " .. arg .. "\n")
      end
    else
      io.write(out)
    end
  end
end
os.exit(exit)
