-- aurora.analyze — scope-aware static analysis built on the real Lua AST
-- (aurora.lua.parser). Catches two classes of bug the regex linter cannot:
--   * reads of an undefined name (typo'd identifier never bound anywhere), and
--   * locals that are declared but never used.
-- Returns findings {line, severity, message}. A parse error is reported as an
-- error finding (and stops analysis).
local parser = require("aurora.lua.parser")

local analyze = {}

local KNOWN = {}
for _, g in ipairs({
  "_G","_ENV","_OSVERSION","_VERSION","string","table","math","os","io",
  "coroutine","utf8","debug","bit32","require","print","pairs","ipairs","type",
  "tostring","tonumber","pcall","xpcall","error","assert","select","setmetatable",
  "getmetatable","next","rawget","rawset","rawequal","rawlen","load","loadfile",
  "dofile","collectgarbage","unpack","component","computer","unicode","checkArg",
  "package","arg",
}) do KNOWN[g] = true end

-- ---- pass 1: every name that is bound or assigned anywhere -----------------
-- Reading a name that is bound/assigned somewhere in the file is never an
-- "undefined" typo (it may be a forward-declared global function). Collecting
-- these conservatively keeps false positives near zero.
local function gatherAssigned(n, set)
  if type(n) ~= "table" then return end
  local tag = n.tag
  if tag == "Local" then for _, nm in ipairs(n.names) do set[nm] = true end
  elseif tag == "LocalFunction" then set[n.name] = true
  elseif tag == "NumericFor" then set[n.var] = true
  elseif tag == "GenericFor" then for _, nm in ipairs(n.names) do set[nm] = true end
  elseif tag == "FunctionExpr" then for _, p in ipairs(n.params) do set[p] = true end
  elseif tag == "Assign" then
    for _, t in ipairs(n.targets) do if t.tag == "Name" then set[t.name] = true end end
  elseif tag == "Function" then
    local r = n.target
    while r and r.tag == "Index" do r = r.obj end
    if r and r.tag == "Name" then set[r.name] = true end
  end
  for _, v in pairs(n) do
    if type(v) == "table" then
      if v.tag then gatherAssigned(v, set)
      else for _, item in ipairs(v) do gatherAssigned(item, set) end end
    end
  end
end

-- ---- pass 2: scoped walk ---------------------------------------------------

function analyze.check(src)
  checkArg(1, src, "string")
  local ast, perr = parser.parse(src)
  local findings = {}
  if not ast then
    local line = tonumber(tostring(perr):match("line (%d+)"))
    findings[#findings + 1] = {line = line or 0, severity = "error",
      message = (tostring(perr):gsub("^parse: ", ""))}
    return findings
  end

  local everAssigned = {}
  gatherAssigned(ast, everAssigned)

  local function newScope(parent) return {vars = {}, parent = parent} end
  local function declare(scope, name, line, kind)
    scope.vars[name] = {used = false, line = line, kind = kind}
  end
  local function resolve(scope, name)
    local s = scope
    while s do if s.vars[name] then return s.vars[name] end; s = s.parent end
    return nil
  end
  local function useName(scope, name, line)
    local v = resolve(scope, name)
    if v then v.used = true
    elseif KNOWN[name] or everAssigned[name] then -- fine
    else
      findings[#findings + 1] = {line = line or 0, severity = "warning",
        message = "undefined name '" .. name .. "' (typo or missing require?)"}
    end
  end

  local visitExpr, visitStat, visitBlock

  local function reportUnused(scope)
    for name, info in pairs(scope.vars) do
      if not info.used and info.kind == "local"
         and name ~= "_" and name:sub(1, 1) ~= "_" then
        findings[#findings + 1] = {line = info.line, severity = "warning",
          message = "unused local '" .. name .. "'"}
      end
    end
  end

  visitExpr = function(node, scope)
    if type(node) ~= "table" then return end
    local tag = node.tag
    if tag == "Name" then
      useName(scope, node.name, node.line)
    elseif tag == "Index" then
      visitExpr(node.obj, scope); visitExpr(node.key, scope)
    elseif tag == "Call" then
      visitExpr(node.func, scope)
      for _, a in ipairs(node.args) do visitExpr(a, scope) end
    elseif tag == "MethodCall" then
      visitExpr(node.obj, scope)
      for _, a in ipairs(node.args) do visitExpr(a, scope) end
    elseif tag == "Binop" then
      visitExpr(node.lhs, scope); visitExpr(node.rhs, scope)
    elseif tag == "Unop" then
      visitExpr(node.operand, scope)
    elseif tag == "Paren" then
      visitExpr(node.expr, scope)
    elseif tag == "Table" then
      for _, f in ipairs(node.fields) do
        if f.tag == "Pair" and f.key.tag ~= "String" then visitExpr(f.key, scope) end
        visitExpr(f.value, scope)
      end
    elseif tag == "FunctionExpr" then
      local fnScope = newScope(scope)
      for _, p in ipairs(node.params) do declare(fnScope, p, node.line, "param") end
      visitBlock(node.body, fnScope)
      reportUnused(fnScope)
    end
    -- literals (Nil/True/False/Number/String/Vararg): nothing to do
  end

  visitStat = function(stat, scope)
    local tag = stat.tag
    if tag == "Local" then
      for _, e in ipairs(stat.exprs) do visitExpr(e, scope) end
      for _, nm in ipairs(stat.names) do declare(scope, nm, stat.line, "local") end
    elseif tag == "LocalFunction" then
      declare(scope, stat.name, stat.line, "local")
      visitExpr(stat.func, scope)
    elseif tag == "Assign" then
      for _, e in ipairs(stat.exprs) do visitExpr(e, scope) end
      for _, t in ipairs(stat.targets) do
        if t.tag == "Name" then
          local v = resolve(scope, t.name)
          if v then v.used = true end   -- assigning a captured local counts as touching it
        else
          visitExpr(t, scope)            -- index target: obj/key are reads
        end
      end
    elseif tag == "CallStat" then
      visitExpr(stat.call, scope)
    elseif tag == "Do" then
      local s = newScope(scope); visitBlock(stat.body, s); reportUnused(s)
    elseif tag == "While" then
      visitExpr(stat.cond, scope)
      local s = newScope(scope); visitBlock(stat.body, s); reportUnused(s)
    elseif tag == "Repeat" then
      local s = newScope(scope)
      visitBlock(stat.body, s)
      visitExpr(stat.cond, s)           -- until-cond sees body locals
      reportUnused(s)
    elseif tag == "If" then
      for _, c in ipairs(stat.clauses) do
        visitExpr(c.cond, scope)
        local s = newScope(scope); visitBlock(c.body, s); reportUnused(s)
      end
      if stat.elseBody then
        local s = newScope(scope); visitBlock(stat.elseBody, s); reportUnused(s)
      end
    elseif tag == "NumericFor" then
      visitExpr(stat.from, scope); visitExpr(stat.to, scope)
      if stat.step then visitExpr(stat.step, scope) end
      local s = newScope(scope); declare(s, stat.var, stat.line, "loop")
      visitBlock(stat.body, s); reportUnused(s)
    elseif tag == "GenericFor" then
      for _, e in ipairs(stat.exprs) do visitExpr(e, scope) end
      local s = newScope(scope)
      for _, nm in ipairs(stat.names) do declare(s, nm, stat.line, "loop") end
      visitBlock(stat.body, s); reportUnused(s)
    elseif tag == "Function" then
      if stat.target.tag == "Index" then visitExpr(stat.target, scope) end
      visitExpr(stat.func, scope)
    elseif tag == "Return" then
      for _, e in ipairs(stat.exprs) do visitExpr(e, scope) end
    end
    -- Break / Goto / Label: nothing to resolve
  end

  visitBlock = function(block, scope)
    for _, s in ipairs(block.stmts) do visitStat(s, scope) end
  end

  local top = newScope(nil)
  visitBlock(ast, top)
  reportUnused(top)

  table.sort(findings, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.message < b.message
  end)
  return findings
end

return analyze
