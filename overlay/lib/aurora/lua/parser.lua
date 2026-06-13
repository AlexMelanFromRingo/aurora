-- aurora.lua.parser — a recursive-descent parser for the full Lua 5.3 grammar.
-- Consumes tokens from aurora.lua.lexer and produces an AST. Used by the
-- analyzer (scope-aware lint) and available for any tool that needs real
-- structure rather than regexes.
--
--   local parser = require("aurora.lua.parser")
--   local ast, err = parser.parse(source)   -- ast is a Block node, or nil,err
--
-- Node tags: Block, Local, Assign, CallStat, Do, While, Repeat, If,
-- NumericFor, GenericFor, Function, LocalFunction, Return, Break, Goto, Label,
-- and expressions: Nil, True, False, Number, String, Vararg, Name, Index, Call,
-- MethodCall, FunctionExpr, Table, Binop, Unop, Paren.
local lexer = require("aurora.lua.lexer")

local parser = {}

-- binary operator precedence {left, right}; right<left means right-associative
local BINPRI = {
  ["or"] = {1, 1}, ["and"] = {2, 2},
  ["<"] = {3, 3}, [">"] = {3, 3}, ["<="] = {3, 3}, [">="] = {3, 3},
  ["~="] = {3, 3}, ["=="] = {3, 3},
  ["|"] = {4, 4}, ["~"] = {5, 5}, ["&"] = {6, 6},
  ["<<"] = {7, 7}, [">>"] = {7, 7},
  [".."] = {9, 8},
  ["+"] = {10, 10}, ["-"] = {10, 10},
  ["*"] = {11, 11}, ["/"] = {11, 11}, ["//"] = {11, 11}, ["%"] = {11, 11},
  ["^"] = {14, 13},
}
local UNARY_PRI = 12
local UNARY = {["not"] = true, ["-"] = true, ["#"] = true, ["~"] = true}

local function new(src)
  local toks = lexer.tokenize(src)
  return {toks = toks, pos = 1}
end

local P = {}
P.__index = P

function P:peek() return self.toks[self.pos] end
function P:next() local t = self.toks[self.pos]; self.pos = self.pos + 1; return t end

function P:err(msg, tok)
  tok = tok or self:peek()
  error(string.format("parse: %s at line %d (near '%s')",
    msg, tok.line or 0, tok.value == "" and "<eof>" or tok.value), 0)
end

-- is the current token op/keyword equal to v?
function P:is(v)
  local t = self:peek()
  return (t.type == "op" or t.type == "keyword") and t.value == v
end

function P:accept(v)
  if self:is(v) then return self:next() end
  return nil
end

function P:expect(v)
  if not self:is(v) then self:err("expected '" .. v .. "'") end
  return self:next()
end

function P:expectName()
  local t = self:peek()
  if t.type ~= "name" then self:err("expected a name") end
  return self:next().value
end

-- ---- expressions -----------------------------------------------------------

function P:primaryExpr()
  local t = self:peek()
  if self:accept("(") then
    local e = self:expr()
    self:expect(")")
    return {tag = "Paren", expr = e, line = t.line}
  elseif t.type == "name" then
    self:next()
    return {tag = "Name", name = t.value, line = t.line}
  end
  self:err("unexpected symbol")
end

function P:args()
  local t = self:peek()
  if t.type == "string" then
    self:next(); return {{tag = "String", value = t.value, line = t.line}}
  elseif self:is("{") then
    return {self:tableConstructor()}
  elseif self:accept("(") then
    local list = {}
    if not self:is(")") then list = self:exprList() end
    self:expect(")")
    return list
  end
  self:err("function arguments expected")
end

function P:suffixedExpr()
  local e = self:primaryExpr()
  while true do
    local t = self:peek()
    if self:accept(".") then
      local name = self:expectName()
      e = {tag = "Index", obj = e, key = {tag = "String", value = name}, line = t.line}
    elseif self:accept("[") then
      local k = self:expr(); self:expect("]")
      e = {tag = "Index", obj = e, key = k, line = t.line}
    elseif self:accept(":") then
      local m = self:expectName()
      e = {tag = "MethodCall", obj = e, method = m, args = self:args(), line = t.line}
    elseif t.type == "string" or self:is("(") or self:is("{") then
      e = {tag = "Call", func = e, args = self:args(), line = t.line}
    else
      return e
    end
  end
end

function P:tableConstructor()
  local line = self:peek().line
  self:expect("{")
  local fields = {}
  while not self:is("}") do
    if self:is("[") then
      self:next(); local k = self:expr(); self:expect("]"); self:expect("=")
      fields[#fields + 1] = {tag = "Pair", key = k, value = self:expr()}
    elseif self:peek().type == "name" and self.toks[self.pos + 1]
           and self.toks[self.pos + 1].type == "op"
           and self.toks[self.pos + 1].value == "=" then
      local key = self:next().value; self:next() -- name, '='
      fields[#fields + 1] = {tag = "Pair",
        key = {tag = "String", value = key}, value = self:expr()}
    else
      fields[#fields + 1] = {tag = "Item", value = self:expr()}
    end
    if not (self:accept(",") or self:accept(";")) then break end
  end
  self:expect("}")
  return {tag = "Table", fields = fields, line = line}
end

function P:functionBody(line)
  self:expect("(")
  local params, vararg = {}, false
  if not self:is(")") then
    repeat
      if self:accept("...") then vararg = true; break end
      params[#params + 1] = self:expectName()
    until not self:accept(",")
  end
  self:expect(")")
  local body = self:block()
  self:expect("end")
  return {tag = "FunctionExpr", params = params, vararg = vararg, body = body, line = line}
end

function P:simpleExpr()
  local t = self:peek()
  if t.type == "number" then self:next(); return {tag = "Number", value = t.value, line = t.line} end
  if t.type == "string" then self:next(); return {tag = "String", value = t.value, line = t.line} end
  if self:accept("nil") then return {tag = "Nil", line = t.line} end
  if self:accept("true") then return {tag = "True", line = t.line} end
  if self:accept("false") then return {tag = "False", line = t.line} end
  if self:accept("...") then return {tag = "Vararg", line = t.line} end
  if self:is("{") then return self:tableConstructor() end
  if self:accept("function") then return self:functionBody(t.line) end
  return self:suffixedExpr()
end

function P:subExpr(limit)
  local t = self:peek()
  local e
  if (t.type == "op" or t.type == "keyword") and UNARY[t.value] then
    self:next()
    e = {tag = "Unop", op = t.value, operand = self:subExpr(UNARY_PRI), line = t.line}
  else
    e = self:simpleExpr()
  end
  while true do
    local o = self:peek()
    local pri = (o.type == "op" or o.type == "keyword") and BINPRI[o.value]
    if not pri or pri[1] <= limit then break end
    self:next()
    local rhs = self:subExpr(pri[2])
    e = {tag = "Binop", op = o.value, lhs = e, rhs = rhs, line = o.line}
  end
  return e
end

function P:expr() return self:subExpr(0) end

function P:exprList()
  local list = {self:expr()}
  while self:accept(",") do list[#list + 1] = self:expr() end
  return list
end

-- ---- statements ------------------------------------------------------------

local BLOCK_END = {["end"] = true, ["else"] = true, ["elseif"] = true,
  ["until"] = true, [""] = true}  -- "" = eof token value

function P:block()
  local stmts = {}
  while true do
    local t = self:peek()
    if t.type == "eof" or BLOCK_END[t.value] and (t.type == "keyword" or t.type == "eof") then
      break
    end
    if self:is("return") then
      stmts[#stmts + 1] = self:returnStat()
      break
    end
    local s = self:statement()
    if s then stmts[#stmts + 1] = s end
  end
  return {tag = "Block", stmts = stmts}
end

function P:returnStat()
  local line = self:next().line  -- 'return'
  local exprs = {}
  local t = self:peek()
  if not (t.type == "eof" or (t.type == "keyword" and BLOCK_END[t.value]) or self:is(";")) then
    exprs = self:exprList()
  end
  self:accept(";")
  return {tag = "Return", exprs = exprs, line = line}
end

function P:ifStat()
  local line = self:next().line  -- 'if'
  local clauses = {}
  local cond = self:expr(); self:expect("then")
  clauses[#clauses + 1] = {cond = cond, body = self:block()}
  while self:accept("elseif") do
    local c = self:expr(); self:expect("then")
    clauses[#clauses + 1] = {cond = c, body = self:block()}
  end
  local elseBody
  if self:accept("else") then elseBody = self:block() end
  self:expect("end")
  return {tag = "If", clauses = clauses, elseBody = elseBody, line = line}
end

function P:forStat()
  local line = self:next().line  -- 'for'
  local first = self:expectName()
  if self:accept("=") then
    local from = self:expr(); self:expect(",")
    local to = self:expr()
    local step; if self:accept(",") then step = self:expr() end
    self:expect("do"); local body = self:block(); self:expect("end")
    return {tag = "NumericFor", var = first, from = from, to = to, step = step,
            body = body, line = line}
  end
  local names = {first}
  while self:accept(",") do names[#names + 1] = self:expectName() end
  self:expect("in")
  local exprs = self:exprList()
  self:expect("do"); local body = self:block(); self:expect("end")
  return {tag = "GenericFor", names = names, exprs = exprs, body = body, line = line}
end

function P:funcStat()
  local line = self:next().line  -- 'function'
  -- funcname: Name {'.' Name} [':' Name]
  local target = {tag = "Name", name = self:expectName(), line = line}
  local isMethod = false
  while self:accept(".") do
    target = {tag = "Index", obj = target,
      key = {tag = "String", value = self:expectName()}, line = line}
  end
  if self:accept(":") then
    target = {tag = "Index", obj = target,
      key = {tag = "String", value = self:expectName()}, line = line}
    isMethod = true
  end
  local fn = self:functionBody(line)
  if isMethod then table.insert(fn.params, 1, "self") end
  return {tag = "Function", target = target, func = fn, method = isMethod, line = line}
end

function P:localStat()
  local line = self:next().line  -- 'local'
  if self:accept("function") then
    local name = self:expectName()
    local fn = self:functionBody(line)
    return {tag = "LocalFunction", name = name, func = fn, line = line}
  end
  local names = {self:expectName()}
  self:acceptAttrib()
  while self:accept(",") do names[#names + 1] = self:expectName(); self:acceptAttrib() end
  local exprs = {}
  if self:accept("=") then exprs = self:exprList() end
  return {tag = "Local", names = names, exprs = exprs, line = line}
end

-- Lua 5.4 <const>/<close> attributes — tolerated for forward compatibility.
function P:acceptAttrib()
  if self:accept("<") then self:expectName(); self:expect(">") end
end

function P:exprStat()
  local line = self:peek().line
  local first = self:suffixedExpr()
  if self:is("=") or self:is(",") then
    local targets = {first}
    while self:accept(",") do targets[#targets + 1] = self:suffixedExpr() end
    self:expect("=")
    local exprs = self:exprList()
    return {tag = "Assign", targets = targets, exprs = exprs, line = line}
  end
  if first.tag ~= "Call" and first.tag ~= "MethodCall" then
    self:err("syntax error (expected statement)")
  end
  return {tag = "CallStat", call = first, line = line}
end

function P:statement()
  local t = self:peek()
  if self:accept(";") then return nil end
  if self:accept("::") then
    local name = self:expectName(); self:expect("::")
    return {tag = "Label", name = name, line = t.line}
  end
  if t.type == "keyword" then
    local v = t.value
    if v == "if" then return self:ifStat() end
    if v == "while" then
      self:next(); local c = self:expr(); self:expect("do")
      local b = self:block(); self:expect("end")
      return {tag = "While", cond = c, body = b, line = t.line}
    end
    if v == "do" then
      self:next(); local b = self:block(); self:expect("end")
      return {tag = "Do", body = b, line = t.line}
    end
    if v == "for" then return self:forStat() end
    if v == "repeat" then
      self:next(); local b = self:block(); self:expect("until")
      local c = self:expr()
      return {tag = "Repeat", body = b, cond = c, line = t.line}
    end
    if v == "function" then return self:funcStat() end
    if v == "local" then return self:localStat() end
    if v == "break" then self:next(); return {tag = "Break", line = t.line} end
    if v == "goto" then
      self:next(); return {tag = "Goto", label = self:expectName(), line = t.line}
    end
  end
  return self:exprStat()
end

function parser.parse(src)
  checkArg(1, src, "string")
  local self = setmetatable(new(src), P)
  local ok, result = pcall(function()
    local block = self:block()
    if self:peek().type ~= "eof" then self:err("unexpected token") end
    return block
  end)
  if not ok then return nil, result end
  return result
end

return parser
