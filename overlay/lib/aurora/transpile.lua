-- aurora.transpile — a small source-to-source compiler adding compound
-- assignment operators to Lua: += -= *= /= //= %= ^= ..= &= |= <<= >>=
--
--   count += 1            -->  count = count + (1)
--   t[i] ..= "x"          -->  t[i] = t[i] .. ("x")
--
-- It is line-oriented: the left-hand side is a variable or table access and the
-- statement must fit on one line (the common case). The LHS is duplicated, so
-- side-effecting index expressions are evaluated twice — same caveat as the
-- equivalent macro in C. Lines without a compound operator pass through
-- unchanged, so any valid Lua file is already valid input.
local transpile = {}

-- operators, longest first so // and .. and << win over / and . and <
local OPS = {"<<", ">>", "//", "..", "+", "-", "*", "/", "%", "^", "&", "|"}

local function escape(op) return (op:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")) end

-- LHS: a name, with any chain of .name or [ ... ] (no nested brackets).
local LHS = "[%a_][%w_]*[%w_%.%[%]]*"

local function transpileLine(line)
  for _, op in ipairs(OPS) do
    -- match:  <indent><lhs> <op>= <rhs>
    local pat = "^(%s*)(" .. LHS .. ")%s*" .. escape(op) .. "=%s*(.+)$"
    local indent, lhs, rhs = line:match(pat)
    if indent then
      -- guard against matching comparison/`==` style tokens: the char right
      -- after the operator must have been '=' (consumed by pattern) and the
      -- operator itself is arithmetic, so this is unambiguous.
      return string.format("%s%s = %s %s (%s)", indent, lhs, lhs, op, rhs)
    end
  end
  return line
end

-- transpile(src) -> compiled Lua source
function transpile.run(src)
  checkArg(1, src, "string")
  local out = {}
  local i = 1
  for line in (src .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = transpileLine(line)
    i = i + 1
  end
  -- drop the trailing empty element introduced by the sentinel newline
  if out[#out] == "" then out[#out] = nil end
  return table.concat(out, "\n")
end

transpile.line = transpileLine
return transpile
