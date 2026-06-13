-- aurora.lua.gen — render an aurora.lua.parser AST back into clean, consistently
-- formatted Lua source. Used by `afmt`. Parentheses are added only where
-- precedence/associativity requires them (so the output is minimal but always
-- semantically identical), and explicit Paren nodes are preserved (they can
-- matter, e.g. truncating multiple return values).
local parser = require("aurora.lua.parser")

local gen = {}

local PREC = {
  ["or"] = 1, ["and"] = 2,
  ["<"] = 3, [">"] = 3, ["<="] = 3, [">="] = 3, ["~="] = 3, ["=="] = 3,
  ["|"] = 4, ["~"] = 5, ["&"] = 6, ["<<"] = 7, [">>"] = 7,
  [".."] = 9, ["+"] = 10, ["-"] = 10,
  ["*"] = 11, ["/"] = 11, ["//"] = 11, ["%"] = 11, ["^"] = 14,
}
local RIGHT = {[".."] = true, ["^"] = true}
local UNARY = 12

local function precOf(node)
  if node.tag == "Binop" then return PREC[node.op] end
  if node.tag == "Unop" then return UNARY end
  return 1000   -- atoms / primaries never need wrapping as operands
end

local function isIdent(s)
  return type(s) == "string" and s:match("^[%a_][%w_]*$") ~= nil
end

local INDENT = "  "
local function pad(n) return string.rep(INDENT, n) end

local E, genBlock, genStat

-- e(node, ind): render an expression; ind is the indent for any line breaks
-- (function literals, multiline tables).
local function paramList(params, vararg)
  local p = {}
  for _, x in ipairs(params) do p[#p + 1] = x end
  if vararg then p[#p + 1] = "..." end
  return table.concat(p, ", ")
end

-- render `obj.a.b` for function-name targets (keys are identifier strings)
local function dottedName(node)
  if node.tag == "Name" then return node.name end
  if node.tag == "Index" and node.key.tag == "String" then
    return dottedName(node.obj) .. "." .. node.key.value
  end
  return E(node, 0)   -- fallback (shouldn't happen for funcnames)
end

E = function(node, ind)
  local tag = node.tag
  if tag == "Nil" then return "nil"
  elseif tag == "True" then return "true"
  elseif tag == "False" then return "false"
  elseif tag == "Vararg" then return "..."
  elseif tag == "Number" then return node.value
  elseif tag == "String" then return node.value
  elseif tag == "Name" then return node.name
  elseif tag == "Paren" then return "(" .. E(node.expr, ind) .. ")"
  elseif tag == "Index" then
    local obj = E(node.obj, ind)
    if node.key.tag == "String" and isIdent(node.key.value) then
      return obj .. "." .. node.key.value
    end
    return obj .. "[" .. E(node.key, ind) .. "]"
  elseif tag == "Call" then
    return E(node.func, ind) .. "(" .. gen.exprList(node.args, ind) .. ")"
  elseif tag == "MethodCall" then
    return E(node.obj, ind) .. ":" .. node.method
      .. "(" .. gen.exprList(node.args, ind) .. ")"
  elseif tag == "Unop" then
    local operand = E(node.operand, ind)
    if precOf(node.operand) < UNARY then operand = "(" .. operand .. ")" end
    local sep = node.op:match("%a") and " " or ""   -- `not x`, but `-x`
    return node.op .. sep .. operand
  elseif tag == "Binop" then
    local p = PREC[node.op]
    local l = E(node.lhs, ind)
    if precOf(node.lhs) < p or (precOf(node.lhs) == p and RIGHT[node.op]) then
      l = "(" .. l .. ")"
    end
    local r = E(node.rhs, ind)
    if precOf(node.rhs) < p or (precOf(node.rhs) == p and not RIGHT[node.op]) then
      r = "(" .. r .. ")"
    end
    return l .. " " .. node.op .. " " .. r
  elseif tag == "FunctionExpr" then
    return "function(" .. paramList(node.params, node.vararg) .. ")\n"
      .. genBlock(node.body, ind + 1) .. pad(ind) .. "end"
  elseif tag == "Table" then
    return gen.table(node, ind)
  end
  return "--[[?" .. tostring(tag) .. "]]"
end

function gen.exprList(list, ind)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = E(e, ind) end
  return table.concat(out, ", ")
end

function gen.table(node, ind)
  if #node.fields == 0 then return "{}" end
  local parts = {}
  local hasFn = false
  for _, f in ipairs(node.fields) do
    if f.tag == "Pair" then
      local key
      if f.key.tag == "String" and isIdent(f.key.value) then
        key = f.key.value
      else
        key = "[" .. E(f.key, ind + 1) .. "]"
      end
      parts[#parts + 1] = {kv = true, text = key .. " = " .. E(f.value, ind + 1)}
    else
      parts[#parts + 1] = {kv = false, text = E(f.value, ind + 1)}
    end
    if f.value.tag == "FunctionExpr" then hasFn = true end
  end
  -- try inline
  local inline = {}
  for _, p in ipairs(parts) do inline[#inline + 1] = p.text end
  local oneLine = "{" .. table.concat(inline, ", ") .. "}"
  if not hasFn and not oneLine:find("\n", 1, true) and #oneLine <= 72 then
    return oneLine
  end
  -- multiline
  local lines = {"{"}
  for _, p in ipairs(parts) do
    lines[#lines + 1] = pad(ind + 1) .. p.text .. ","
  end
  lines[#lines + 1] = pad(ind) .. "}"
  return table.concat(lines, "\n")
end

-- ---- statements ------------------------------------------------------------

genStat = function(stat, ind)
  local tag = stat.tag
  local P = pad(ind)
  if tag == "Local" then
    local s = P .. "local " .. table.concat(stat.names, ", ")
    if #stat.exprs > 0 then s = s .. " = " .. gen.exprList(stat.exprs, ind) end
    return s
  elseif tag == "Assign" then
    local targets = {}
    for _, t in ipairs(stat.targets) do targets[#targets + 1] = E(t, ind) end
    return P .. table.concat(targets, ", ") .. " = " .. gen.exprList(stat.exprs, ind)
  elseif tag == "CallStat" then
    return P .. E(stat.call, ind)
  elseif tag == "LocalFunction" then
    return P .. "local function " .. stat.name
      .. "(" .. paramList(stat.func.params, stat.func.vararg) .. ")\n"
      .. genBlock(stat.func.body, ind + 1) .. P .. "end"
  elseif tag == "Function" then
    local params = stat.func.params
    local name = dottedName(stat.target)
    if stat.method then
      -- name is obj.method; convert last '.' to ':' and drop the self param
      name = name:gsub("%.([%w_]+)$", ":%1")
      params = {}
      for i = 2, #stat.func.params do params[#params + 1] = stat.func.params[i] end
    end
    return P .. "function " .. name
      .. "(" .. paramList(params, stat.func.vararg) .. ")\n"
      .. genBlock(stat.func.body, ind + 1) .. P .. "end"
  elseif tag == "Do" then
    return P .. "do\n" .. genBlock(stat.body, ind + 1) .. P .. "end"
  elseif tag == "While" then
    return P .. "while " .. E(stat.cond, ind) .. " do\n"
      .. genBlock(stat.body, ind + 1) .. P .. "end"
  elseif tag == "Repeat" then
    return P .. "repeat\n" .. genBlock(stat.body, ind + 1)
      .. P .. "until " .. E(stat.cond, ind)
  elseif tag == "If" then
    local out = {}
    for i, clause in ipairs(stat.clauses) do
      local kw = i == 1 and "if" or "elseif"
      out[#out + 1] = P .. kw .. " " .. E(clause.cond, ind) .. " then\n"
        .. genBlock(clause.body, ind + 1)
    end
    if stat.elseBody then
      out[#out + 1] = P .. "else\n" .. genBlock(stat.elseBody, ind + 1)
    end
    return table.concat(out) .. P .. "end"
  elseif tag == "NumericFor" then
    local head = P .. "for " .. stat.var .. " = "
      .. E(stat.from, ind) .. ", " .. E(stat.to, ind)
    if stat.step then head = head .. ", " .. E(stat.step, ind) end
    return head .. " do\n" .. genBlock(stat.body, ind + 1) .. P .. "end"
  elseif tag == "GenericFor" then
    return P .. "for " .. table.concat(stat.names, ", ") .. " in "
      .. gen.exprList(stat.exprs, ind) .. " do\n"
      .. genBlock(stat.body, ind + 1) .. P .. "end"
  elseif tag == "Return" then
    if #stat.exprs == 0 then return P .. "return" end
    return P .. "return " .. gen.exprList(stat.exprs, ind)
  elseif tag == "Break" then
    return P .. "break"
  elseif tag == "Goto" then
    return P .. "goto " .. stat.label
  elseif tag == "Label" then
    return P .. "::" .. stat.name .. "::"
  end
  return P .. "--[[?stat " .. tostring(tag) .. "]]"
end

genBlock = function(block, ind)
  local out = {}
  for _, stat in ipairs(block.stmts) do
    local line = genStat(stat, ind)
    -- guard the rare `(...)` statement-start ambiguity with a leading ';'
    if line:match("^%s*%(") then line = pad(ind) .. ";" .. line:gsub("^%s*", "") end
    out[#out + 1] = line
  end
  if #out == 0 then return "" end
  return table.concat(out, "\n") .. "\n"
end

-- format(src [, opts]) -> formatted source | nil, err
function gen.format(src, opts)
  checkArg(1, src, "string")
  local ast, err = parser.parse(src)
  if not ast then return nil, err end
  local out = genBlock(ast, 0)
  -- normalise to exactly one trailing newline
  return (out:gsub("\n+$", "\n"))
end

gen.fromAst = function(ast) return genBlock(ast, 0) end

return gen
