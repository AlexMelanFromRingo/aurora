-- aurora.transpile — a source-to-source compiler adding compound assignment
-- operators to Lua: += -= *= /= //= %= ^= ..= &= |= <<= >>=
--
--   count += 1            -->  count = count +(1)
--   t[i] ..= f(x) or "y"  -->  t[i] = t[i] ..(f(x) or "y")
--
-- v2 is lexer-driven: it tokenizes the source, finds `<lvalue> <op>= <expr>`
-- patterns and splices replacements back into the *original* text, so it is
-- robust where the old line-based version was not:
--   * occurrences inside strings/comments are never touched (they are single
--     tokens to the lexer),
--   * the statement may span multiple lines,
--   * several compound statements may share a line (separated by `;` or simply
--     by being adjacent), and
--   * the right-hand side is wrapped in parentheses, preserving precedence
--     (`a += b or c` becomes `a = a +(b or c)`, not `(a+b) or c`).
-- The lvalue is duplicated, so an index expression with side effects is
-- evaluated twice — the same caveat as the equivalent C macro. Any valid Lua
-- file is already valid input (files with no compound operator pass through
-- byte-for-byte).
local lexer = require("aurora.lua.lexer")

local transpile = {}

-- operator tokens that, when immediately followed by '=', form a compound op
local COMPOUND = {}
for _, op in ipairs({"+", "-", "*", "/", "//", "%", "^", "..", "&", "|", "<<", ">>"}) do
  COMPOUND[op] = true
end

-- tokens whose presence means "the previous token finished a value"
local function endsValue(t)
  if t.type == "name" or t.type == "number" or t.type == "string" then return true end
  if t.type == "keyword" then
    return t.value == "true" or t.value == "false" or t.value == "nil"
  end
  if t.type == "op" then
    return t.value == ")" or t.value == "]" or t.value == "}" or t.value == "..."
  end
  return false
end

-- tokens that *continue* a value when they follow one (call/index/method/op)
local function continuesValue(t)
  if t.type == "op" then
    local v = t.value
    return v == "." or v == ":" or v == "(" or v == "[" or v == "{"
      or v == "+" or v == "-" or v == "*" or v == "/" or v == "//" or v == "%"
      or v == "^" or v == ".." or v == "&" or v == "|" or v == "~" or v == "<<"
      or v == ">>" or v == "<" or v == ">" or v == "<=" or v == ">=" or v == "=="
      or v == "~="
  end
  if t.type == "string" then return true end          -- f"x" call
  if t.type == "keyword" then return t.value == "and" or t.value == "or" end
  return false
end

-- keywords that, at bracket depth 0, terminate the current expression
local TERMINATOR_KW = {}
for _, k in ipairs({"end", "else", "elseif", "until", "then", "do", "return",
  "local", "if", "while", "for", "repeat", "break", "goto", "in", "function"}) do
  TERMINATOR_KW[k] = true
end

local OPEN = {["("] = true, ["["] = true, ["{"] = true}
local CLOSE = {[")"] = true, ["]"] = true, ["}"] = true}

-- Find the index of the last token of the right-hand side, starting at `k`.
local function scanRHS(toks, k)
  local depth = 0
  local prevEnds = false
  local last = k - 1
  local i = k
  while toks[i] and toks[i].type ~= "eof" do
    local t = toks[i]
    if t.type == "op" and OPEN[t.value] then
      depth = depth + 1
    elseif t.type == "op" and CLOSE[t.value] then
      if depth == 0 then break end       -- a closer we don't own ends the RHS
      depth = depth - 1
    elseif depth == 0 then
      if t.type == "op" and t.value == ";" then break end
      if t.type == "op" and t.value == "," then break end
      if t.type == "keyword" and TERMINATOR_KW[t.value] then break end
      -- two values in a row with nothing linking them = statement boundary
      if prevEnds and not continuesValue(t)
         and (t.type == "name" or t.type == "number" or t.type == "string"
              or (t.type == "keyword" and (t.value == "true" or t.value == "false"
                  or t.value == "nil" or t.value == "function" or t.value == "not"))) then
        break
      end
    end
    last = i
    prevEnds = endsValue(t)
    i = i + 1
  end
  return last
end

-- Walk backwards from the compound operator to find the first token of the
-- lvalue. An lvalue is `Name { '.' Name | '[' exp ']' }`, so backward it is a
-- name optionally preceded by '.' (more prefix) or a balanced index group (and
-- the name it indexes). Critically, a bare root name with no '.' before it ends
-- the lvalue — so we never wander into the previous statement.
local function scanLHS(toks, opIdx)
  local start = nil
  local i = opIdx - 1
  while i >= 1 do
    local t = toks[i]
    if t.type == "op" and CLOSE[t.value] then
      -- consume a balanced [...] / (...) / {...} suffix group
      local depth = 1
      start = i; i = i - 1
      while i >= 1 and depth > 0 do
        local tv = toks[i]
        if tv.type == "op" and CLOSE[tv.value] then depth = depth + 1
        elseif tv.type == "op" and OPEN[tv.value] then depth = depth - 1 end
        start = i; i = i - 1
      end
      if depth ~= 0 then return nil end   -- unbalanced; bail
      -- the group must be indexing a name/suffix to its left: keep scanning
    elseif t.type == "name" then
      start = i
      -- continue only if this name is a field access (preceded by '.')
      if i - 1 >= 1 and toks[i - 1].type == "op" and toks[i - 1].value == "." then
        i = i - 2   -- skip the '.' and keep walking
      else
        break       -- root name reached
      end
    else
      break
    end
  end
  if start and toks[start] and toks[start].type == "name" then return start end
  return nil
end

function transpile.run(src)
  checkArg(1, src, "string")
  local toks = lexer.tokenize(src)
  local edits = {}   -- {from, to, text} byte spans in src

  local i = 1
  while toks[i] and toks[i].type ~= "eof" do
    local t = toks[i]
    local nxt = toks[i + 1]
    if t.type == "op" and COMPOUND[t.value]
       and nxt and nxt.type == "op" and nxt.value == "=" then
      local lhsStart = scanLHS(toks, i)
      if lhsStart then
        local rhsStart = i + 2
        local rhsLast = scanRHS(toks, rhsStart)
        if rhsLast >= rhsStart then
          local lhsText = src:sub(toks[lhsStart].pos, toks[i - 1].stop)
          local rhsText = src:sub(toks[rhsStart].pos, toks[rhsLast].stop)
          local replacement = string.format("%s = %s %s(%s)",
            lhsText, lhsText, t.value, rhsText)
          edits[#edits + 1] = {
            from = toks[lhsStart].pos, to = toks[rhsLast].stop, text = replacement,
          }
          i = rhsLast + 1
        else
          i = i + 1
        end
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end

  if #edits == 0 then return src end
  -- apply edits right-to-left so earlier byte offsets stay valid
  local out = src
  for j = #edits, 1, -1 do
    local e = edits[j]
    out = out:sub(1, e.from - 1) .. e.text .. out:sub(e.to + 1)
  end
  return out
end

return transpile
