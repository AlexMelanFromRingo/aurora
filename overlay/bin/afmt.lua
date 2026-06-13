-- afmt — format Lua source from its AST (consistent indentation, spacing and
-- minimal parentheses). Meaning-preserving and idempotent.
--   afmt <file.lua>            print formatted source to stdout
--   afmt -w <file.lua> ...     rewrite files in place (atomic)
--   afmt -c <file.lua> ...     check only; exit 1 if a file is not formatted
--   afmt --watch -w <file> ... reformat on every change (Ctrl-Alt-C to stop)
local shell = require("shell")
local gen = require("aurora.lua.gen")
local fsx = require("aurora.fsx")

local args, options = shell.parse(...)
if #args < 1 then
  io.write("Usage: afmt [-w | -c] [--watch] <file.lua> [...]\n")
  io.write("  -w  rewrite in place   -c  check only   --watch  re-run on change\n")
  return
end

-- process one file; returns the exit contribution (0/1/2)
local function process(arg)
  local path = shell.resolve(arg)
  local src = fsx.readAll(path)
  if not src then io.stderr:write("afmt: cannot read " .. arg .. "\n"); return 2 end
  local out, err = gen.format(src)
  if not out then io.stderr:write("afmt: " .. arg .. ": " .. tostring(err) .. "\n"); return 2 end
  if options.c then
    if out ~= src then io.write("not formatted: " .. arg .. "\n"); return 1 end
  elseif options.w then
    if out ~= src then assert(fsx.atomicWrite(path, out)); io.write("formatted " .. arg .. "\n") end
  else
    io.write(out)
  end
  return 0
end

if options.watch then
  local watch = require("aurora.watch")
  local paths = {}
  for _, a in ipairs(args) do paths[#paths + 1] = shell.resolve(a) end
  io.write("afmt: watching " .. #paths .. " file(s); press Ctrl-Alt-C to stop\n")
  watch.loop(paths, function(p)
    io.write("\27[2m-- " .. p .. " changed --\27[m\n")
    process(p)
  end, {runFirst = true})
  return
end

local exit = 0
for _, arg in ipairs(args) do exit = math.max(exit, process(arg)) end
os.exit(exit)
