-- aurora.minify — shrink Lua source by removing comments and unnecessary
-- whitespace. Token-aware: a space is emitted between two tokens only when
-- their concatenation would lex differently, so the output is byte-for-byte
-- equivalent in meaning. Local renaming is intentionally NOT done (correctness
-- over a few extra bytes). Returns minified source.
local lexer = require("aurora.lua.lexer")

local DANGER = {}
for ch in ("+-*/%^#&~|<>=.:"):gmatch(".") do DANGER[ch] = true end

local function isWord(ch) return ch ~= nil and ch:match("[%w_]") ~= nil end

-- needSpace(a, b): do tokens a then b require a separating space?
local function needSpace(a, b)
  local la = a.value:sub(-1)
  local fb = b.value:sub(1, 1)
  if isWord(la) and isWord(fb) then return true end          -- name/num/keyword run
  if DANGER[la] and DANGER[fb] then return true end           -- e.g. .. :: <= --
  if a.type == "number" and fb == "." then return true end    -- 1..2 hazard
  return false
end

local function minify(src)
  checkArg(1, src, "string")
  local tokens = lexer.tokenize(src, {comments = false})
  local out, prev = {}, nil
  for _, tok in ipairs(tokens) do
    if tok.type ~= "eof" then
      if prev and needSpace(prev, tok) then out[#out + 1] = " " end
      out[#out + 1] = tok.value
      prev = tok
    end
  end
  return table.concat(out)
end

return minify
