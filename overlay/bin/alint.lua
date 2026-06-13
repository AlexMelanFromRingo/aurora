-- alint — lint one or more Lua files.
--   alint <file.lua> [...]      report findings
--   alint --fix <file.lua> ...  auto-format the file in place, then report what
--                               still needs manual attention
--   alint --watch <file> ...    re-lint on every change (Ctrl-Alt-C to stop)
-- Combines the regex linter (trailing whitespace, implicit global writes) and
-- the AST analyzer (undefined-name reads, unused locals).
-- Exit code: 0 clean, 1 warnings only, 2 errors.
local shell = require("shell")
local lint = require("aurora.lint")
local analyze = require("aurora.analyze")
local gen = require("aurora.lua.gen")
local fsx = require("aurora.fsx")

local args, options = shell.parse(...)
if #args < 1 then
  io.write("Usage: alint [--fix] [--watch] <file.lua> [...]\n")
  io.write("  --fix   auto-format the file in place, then report the rest\n")
  io.write("  --watch re-lint whenever a file changes\n")
  return
end

local function merge(a, b)
  local seen, out = {}, {}
  for _, list in ipairs({a, b}) do
    for _, f in ipairs(list) do
      local key = f.line .. ":" .. f.message
      if not seen[key] then seen[key] = true; out[#out + 1] = f end
    end
  end
  table.sort(out, function(x, y)
    if x.line ~= y.line then return x.line < y.line end
    return x.message < y.message
  end)
  return out
end

local function findingsFor(src)
  local ast_findings = analyze.check(src)
  if #ast_findings > 0 and ast_findings[1].severity == "error" then
    return ast_findings
  end
  return merge(lint.check(src), ast_findings)
end

-- process one file; returns exit contribution (0/1/2)
local function process(arg)
  local path = shell.resolve(arg)
  local src = fsx.readAll(path)
  if not src then io.stderr:write("alint: cannot read " .. arg .. "\n"); return 2 end

  if options.fix then
    local out = gen.format(src)
    if out and out ~= src then
      assert(fsx.atomicWrite(path, out))
      io.write("\27[36mfixed\27[m " .. arg .. " (formatted)\n")
      src = out
    end
  end

  local findings = findingsFor(src)
  if #findings == 0 then
    io.write("\27[32mok\27[m   " .. arg .. "\n")
    return 0
  end
  local worst = 0
  for _, f in ipairs(findings) do
    local color = f.severity == "error" and "31" or "33"
    io.write(string.format("\27[%sm%-7s\27[m %s:%d  %s\n",
      color, f.severity, arg, f.line, f.message))
    worst = math.max(worst, f.severity == "error" and 2 or 1)
  end
  return worst
end

if options.watch then
  local watch = require("aurora.watch")
  local paths = {}
  for _, a in ipairs(args) do paths[#paths + 1] = shell.resolve(a) end
  io.write("alint: watching " .. #paths .. " file(s); press Ctrl-Alt-C to stop\n")
  watch.loop(paths, function(p)
    io.write("\27[2m-- " .. p .. " --\27[m\n")
    process(p)
  end, {runFirst = true})
  return
end

local worst = 0
for _, arg in ipairs(args) do worst = math.max(worst, process(arg)) end
os.exit(worst)
