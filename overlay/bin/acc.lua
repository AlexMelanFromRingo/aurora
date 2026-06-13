-- acc — the Aurora compiler/build tool. Pipelines a project entry file through
-- transpile -> lint -> bundle -> (optional) minify into one runnable Lua file.
--   acc <entry.lua> -o <out.lua> [--no-transpile] [--no-minify] [--strict]
-- --strict fails the build on any lint warning; by default only lint errors fail.
local shell = require("shell")
local fsx = require("aurora.fsx")
local transpile = require("aurora.transpile")
local lint = require("aurora.lint")
local bundle = require("aurora.bundle")
local minify = require("aurora.minify")

local args, options = shell.parse(...)
local out = options.o or options.output
if #args < 1 or not out then
  io.write("Usage: acc <entry.lua> -o <out.lua> [--no-transpile] [--no-minify] [--strict]\n")
  return
end

local entry = shell.resolve(args[1])
local src, err = fsx.readAll(entry)
if not src then io.stderr:write("acc: cannot read " .. entry .. ": " .. tostring(err) .. "\n"); os.exit(1) end

-- 1) transpile sugar (in place to a temp the bundler can still resolve siblings)
if not options["no-transpile"] then
  src = transpile.run(src)
end

-- 2) lint the (transpiled) entry
local findings = lint.check(src)
local hadError = false
for _, f in ipairs(findings) do
  io.write(string.format("  %s:%d %s: %s\n", fsx.basename(entry), f.line, f.severity, f.message))
  if f.severity == "error" then hadError = true end
  if options.strict and f.severity == "warning" then hadError = true end
end
if hadError then io.stderr:write("acc: lint failed\n"); os.exit(2) end

-- 3) write transpiled entry to a temp so the bundler links the real graph,
--    then bundle + optional minify.
local tmp = entry .. ".acc.tmp"
assert(fsx.atomicWrite(tmp, src))
local bundled, info = bundle.build(tmp, {minify = not options["no-minify"]})
os.remove(tmp)
if not bundled then io.stderr:write("acc: " .. tostring(info) .. "\n"); os.exit(1) end

assert(fsx.atomicWrite(shell.resolve(out), bundled))
io.write(string.format("acc: built %s (%d module(s), %d bytes)\n",
  out, #info.modules, #bundled))
