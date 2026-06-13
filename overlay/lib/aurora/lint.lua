-- aurora.lint — static checks for Lua source. Two layers:
--   1. a real syntax check via load() (precise line + message), and
--   2. a conservative "implicit global" heuristic that flags top-of-line
--      assignments to names that are never declared local and are not known
--      globals — the classic forgotten-`local` bug.
-- Returns a list of {line, severity ("error"|"warning"), message}.
local lint = {}

local KNOWN = {}
for _, g in ipairs({
  "_G","_ENV","_OSVERSION","string","table","math","os","io","coroutine","utf8",
  "debug","bit32","require","print","pairs","ipairs","type","tostring","tonumber",
  "pcall","xpcall","error","assert","select","setmetatable","getmetatable","next",
  "rawget","rawset","rawequal","rawlen","load","loadfile","dofile","collectgarbage",
  "unpack","component","computer","unicode","checkArg","package",
}) do KNOWN[g] = true end

local function declaredLocals(src)
  local set = {}
  -- local a, b = ...   and   local function f
  for names in src:gmatch("local%s+([%w_%s,]+)") do
    for n in names:gmatch("[%a_][%w_]*") do
      if n ~= "function" then set[n] = true end
    end
  end
  for names in src:gmatch("local%s+function%s+([%a_][%w_]*)") do set[names] = true end
  -- for i, v in ...   /  for i = ...
  for names in src:gmatch("for%s+([%w_%s,]+)") do
    for n in names:gmatch("[%a_][%w_]*") do set[n] = true end
  end
  -- function params and named functions (treated as in-scope to reduce noise)
  for params in src:gmatch("function[^\n%(]*%(([^%)]*)%)") do
    for n in params:gmatch("[%a_][%w_]*") do set[n] = true end
  end
  for n in src:gmatch("function%s+([%a_][%w_]*)") do set[n] = true end
  return set
end

-- check(src) -> list of findings
function lint.check(src)
  checkArg(1, src, "string")
  local findings = {}

  local chunk, err = load(src, "=lint", "t")
  if not chunk then
    local line = tonumber(err and err:match(":(%d+):"))
    findings[#findings + 1] = {
      line = line or 0, severity = "error",
      message = (err and err:gsub("^.-:%d+:%s*", "")) or "syntax error",
    }
    -- a syntax error makes the heuristic pass unreliable; stop here
    return findings
  end

  local locals = declaredLocals(src)
  local lineNo = 0
  for line in (src .. "\n"):gmatch("(.-)\n") do
    lineNo = lineNo + 1
    -- skip comment lines
    if not line:match("^%s*%-%-") then
      -- assignment at start of a line:  name = (but not ==),  name, x = ...
      local name = line:match("^%s*([%a_][%w_]*)%s*=%s*[^=]")
        or line:match("^%s*([%a_][%w_]*)%s*,")
      if name and not locals[name] and not KNOWN[name] then
        findings[#findings + 1] = {
          line = lineNo, severity = "warning",
          message = "implicit global '" .. name .. "' (missing 'local'?)",
        }
      end
      -- trailing whitespace
      if line:match("%s+$") then
        findings[#findings + 1] = {
          line = lineNo, severity = "warning", message = "trailing whitespace",
        }
      end
    end
  end
  return findings
end

return lint
