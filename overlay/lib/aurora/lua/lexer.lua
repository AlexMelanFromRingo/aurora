-- aurora.lua.lexer — a tokenizer for Lua 5.3 source. Produces a flat list of
-- tokens {type, value, line} where type is one of: keyword, name, number,
-- string, op, comment, eof. Whitespace is dropped; comments are dropped unless
-- opts.comments is set. Long strings/comments, all numeric forms and string
-- escapes are handled. Pure and unit-tested; the minifier and transpiler build
-- on it.
local lexer = {}

local KEYWORDS = {}
for _, k in ipairs({
  "and","break","do","else","elseif","end","false","for","function","goto",
  "if","in","local","nil","not","or","repeat","return","then","true","until","while",
}) do KEYWORDS[k] = true end

-- Multi-char operators, longest first so matching is greedy.
local OPS = {
  "...", "..", "::", "<<", ">>", "//", "==", "~=", "<=", ">=",
  "+","-","*","/","%","^","#","&","~","|","<",">","=","(",")","{","}","[","]",
  ";",":",",",".",
}

local function lerror(line, msg)
  error(string.format("lexer: %s at line %d", msg, line), 0)
end

-- Try to read a long-bracket [[ ]] / [=[ ]=] starting at i. Returns text,nexti
-- or nil if i is not an opening long bracket.
local function readLongBracket(s, i)
  local eq = s:match("^%[(=*)%[", i)
  if not eq then return nil end
  local level = #eq
  local close = "]" .. string.rep("=", level) .. "]"
  local start = i + level + 2
  -- a newline immediately after the opening bracket is skipped by Lua
  if s:sub(start, start) == "\n" then start = start + 1 end
  local e = s:find(close, start, true)
  if not e then lerror(1, "unterminated long bracket") end
  return s:sub(i, e + #close - 1), e + #close
end

function lexer.tokenize(src, opts)
  checkArg(1, src, "string")
  opts = opts or {}
  local tokens = {}
  local i, n, line = 1, #src, 1
  local tokenStart = 1   -- byte offset where the current token began

  -- Each token records its byte span [pos, stop] in `src` so source-to-source
  -- tools (the transpiler) can splice replacements without losing formatting,
  -- strings or comments.
  local function push(type, value)
    tokens[#tokens + 1] = {
      type = type, value = value, line = line,
      pos = tokenStart, stop = tokenStart + #value - 1,
    }
  end

  while i <= n do
    tokenStart = i
    local c = src:sub(i, i)

    if c == "\n" then
      line = line + 1; i = i + 1
    elseif c:match("%s") then
      i = i + 1

    -- comments
    elseif src:sub(i, i + 1) == "--" then
      local j = i + 2
      local long = readLongBracket(src, j)
      if long then
        local txt = "--" .. long
        for _ in txt:gmatch("\n") do line = line + 1 end
        if opts.comments then push("comment", txt) end
        i = j + #long
      else
        local e = src:find("\n", j, true) or (n + 1)
        if opts.comments then push("comment", src:sub(i, e - 1)) end
        i = e
      end

    -- long strings
    elseif src:sub(i, i) == "[" and src:match("^%[=*%[", i) then
      local txt, nexti = readLongBracket(src, i)
      for _ in txt:gmatch("\n") do line = line + 1 end
      push("string", txt)
      i = nexti

    -- quoted strings
    elseif c == '"' or c == "'" then
      local quote = c
      local j = i + 1
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then
          j = j + 2
        elseif d == quote then
          j = j + 1; break
        elseif d == "\n" then
          lerror(line, "unterminated string")
        else
          j = j + 1
        end
      end
      push("string", src:sub(i, j - 1))
      i = j

    -- numbers (a sign is only part of an exponent, never bare — so 1+2 lexes
    -- as three tokens, not the number "1+2")
    elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
      local num
      if src:sub(i, i + 1):match("^0[xX]") then
        num = src:match("^0[xX]%x*%.?%x*", i)
        local exp = src:match("^[pP][%+%-]?%d+", i + #num)
        if exp then num = num .. exp end
      else
        num = src:match("^%d*%.?%d*", i)
        local exp = src:match("^[eE][%+%-]?%d+", i + #num)
        if exp then num = num .. exp end
      end
      push("number", num)
      i = i + #num

    -- names / keywords
    elseif c:match("[%a_]") then
      local word = src:match("^[%a_][%w_]*", i)
      push(KEYWORDS[word] and "keyword" or "name", word)
      i = i + #word

    -- operators
    else
      local matched
      for _, op in ipairs(OPS) do
        if src:sub(i, i + #op - 1) == op then matched = op; break end
      end
      if not matched then lerror(line, "unexpected character '" .. c .. "'") end
      push("op", matched)
      i = i + #matched
    end
  end

  push("eof", "")
  return tokens
end

lexer.KEYWORDS = KEYWORDS
return lexer
