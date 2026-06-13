-- aurora.doc — generate API documentation from Lua source. It parses the file
-- (real AST via aurora.lua.parser) to find top-level function definitions and
-- pairs each with the comment block immediately above it (from the lexer's
-- comment tokens). Produces a Markdown reference. Used by `adoc`.
local parser = require("aurora.lua.parser")
local lexer = require("aurora.lua.lexer")

local doc = {}

-- render a function-name target (Name / dotted Index of string keys), using ':'
-- for the trailing key when it is a method.
local function nameOf(node, method)
  if node.tag == "Name" then return node.name end
  if node.tag == "Index" and node.key.tag == "String" then
    local base = nameOf(node.obj)
    return base .. (method and ":" or ".") .. node.key.value
  end
  return "?"
end

local function signature(name, fn, dropSelf)
  local params = {}
  local start = dropSelf and 2 or 1
  for i = start, #fn.params do params[#params + 1] = fn.params[i] end
  if fn.vararg then params[#params + 1] = "..." end
  return name .. "(" .. table.concat(params, ", ") .. ")"
end

-- collect contiguous comment blocks, indexed by their last source line
local function commentBlocks(src)
  local toks = lexer.tokenize(src, {comments = true})
  local byLastLine = {}
  local cur = nil   -- {firstLine, lastLine, lines={}}
  for _, t in ipairs(toks) do
    if t.type == "comment" then
      -- strip leading --, optional [[..]], and one space
      local text = t.value:gsub("^%-%-%[=*%[", ""):gsub("%]=*%]$", "")
                          :gsub("^%-%-", ""):gsub("^ ", "")
      if cur and t.line == cur.lastLine + 1 then
        cur.lastLine = t.line; cur.lines[#cur.lines + 1] = text
      else
        if cur then byLastLine[cur.lastLine] = cur end
        cur = {lastLine = t.line, lines = {text}}
      end
    end
  end
  if cur then byLastLine[cur.lastLine] = cur end
  return byLastLine
end

-- extract(src) -> {items = { {name=, signature=, doc=, kind=, line=} , ... }}
function doc.extract(src)
  checkArg(1, src, "string")
  local ast, err = parser.parse(src)
  if not ast then return nil, err end
  local blocks = commentBlocks(src)
  local items = {}

  local function docFor(line)
    local b = blocks[line - 1]
    if not b then return nil end
    return table.concat(b.lines, "\n"):gsub("%s+$", "")
  end

  for _, stat in ipairs(ast.stmts) do
    local name, sig, kind
    if stat.tag == "Function" then
      name = nameOf(stat.target, stat.method)
      sig = signature(name, stat.func, stat.method)
      kind = "function"
    elseif stat.tag == "LocalFunction" then
      name = stat.name; sig = signature(name, stat.func); kind = "local function"
    elseif stat.tag == "Assign" and #stat.targets == 1
           and #stat.exprs == 1 and stat.exprs[1].tag == "FunctionExpr" then
      name = nameOf(stat.targets[1]); sig = signature(name, stat.exprs[1]); kind = "function"
    elseif stat.tag == "Local" and #stat.names == 1
           and #stat.exprs == 1 and stat.exprs[1].tag == "FunctionExpr" then
      name = stat.names[1]; sig = signature(name, stat.exprs[1]); kind = "local function"
    end
    if name then
      -- a function is "public" if it is a member of a table (has a . or :);
      -- bare `local function f` / `function f` helpers are private.
      items[#items + 1] = {name = name, signature = sig, kind = kind,
        line = stat.line, doc = docFor(stat.line),
        public = name:find("[%.:]") ~= nil}
    end
  end
  return {items = items}
end

-- markdown(src, opts) -> string | nil, err
function doc.markdown(src, opts)
  opts = opts or {}
  local api, err = doc.extract(src)
  if not api then return nil, err end
  local out = {}
  if opts.title then out[#out + 1] = "# " .. opts.title .. "\n" end
  -- leading file comment (block ending before the first line of code) as intro
  if opts.intro then out[#out + 1] = opts.intro .. "\n" end
  -- Make a doc comment safe to drop into Markdown prose: escape '|' (kramdown
  -- otherwise parses it as a table cell separator and mangles the line) and
  -- keep intended line breaks as hard breaks.
  local function mdSafe(text)
    return (text:gsub("|", "\\|"):gsub("\n", "  \n"))
  end

  local shown = 0
  for _, it in ipairs(api.items) do
    if not opts.publicOnly or it.public then
      shown = shown + 1
      out[#out + 1] = "### `" .. it.signature .. "`\n"
      if it.doc and it.doc ~= "" then out[#out + 1] = mdSafe(it.doc) .. "\n" end
    end
  end
  if shown == 0 then out[#out + 1] = "_No public functions found._\n" end
  return table.concat(out, "\n")
end

return doc
