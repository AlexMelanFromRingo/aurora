-- alint — lint one or more Lua files.
--   alint <file.lua> [more.lua ...]
-- Combines two engines: the fast regex linter (trailing whitespace, implicit
-- global writes) and the AST analyzer (undefined-name reads, unused locals).
-- Exit code: 0 clean, 1 warnings only, 2 errors.
local shell = require("shell")
local lint = require("aurora.lint")
local analyze = require("aurora.analyze")
local fsx = require("aurora.fsx")

local args = shell.parse(...)
if #args < 1 then io.write("Usage: alint <file.lua> [...]\n"); return end

-- merge findings, dropping exact (line+message) duplicates
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

local worst = 0
for _, arg in ipairs(args) do
  local path = shell.resolve(arg)
  local src = fsx.readAll(path)
  if not src then
    io.stderr:write("alint: cannot read " .. arg .. "\n"); worst = math.max(worst, 2)
  else
    local ast_findings = analyze.check(src)
    local findings
    if #ast_findings > 0 and ast_findings[1].severity == "error" then
      findings = ast_findings           -- syntax broken: report just that
    else
      findings = merge(lint.check(src), ast_findings)
    end
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
