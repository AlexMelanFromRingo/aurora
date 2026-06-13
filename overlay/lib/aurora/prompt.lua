-- aurora.prompt — compose a PS1 string for the OpenOS shell. The shell expands
-- $VAR at render time, so the builder just lays out ANSI colors and $HOSTNAME /
-- $PWD placeholders. Pure (no I/O) and unit-tested.
local prompt = {}

-- 16-color ANSI foreground helpers
local FG = {
  black = 30, red = 31, green = 32, yellow = 33, blue = 34,
  magenta = 35, cyan = 36, white = 37, reset = 39,
}

local function color(name)
  return "\27[" .. (FG[name] or 39) .. "m"
end

-- build(spec) -> PS1 string. spec fields (all optional):
--   hostname=true   show $HOSTNAME
--   cwd=true        show $PWD
--   symbol="# "     trailing prompt symbol
--   colors={host=,path=,symbol=}  ANSI color names
--   twoLine=false   put the symbol on its own line
function prompt.build(spec)
  spec = spec or {}
  local colors = spec.colors or {}
  local parts = {}
  local function add(s) parts[#parts + 1] = s end

  add("\27[0m")  -- reset attributes at the start of every prompt
  if spec.hostname ~= false then
    add(color(colors.host or "green"))
    add("$HOSTNAME")
  end
  if spec.cwd ~= false then
    add(color(colors.path or "cyan"))
    if spec.hostname ~= false then add(" ") end
    add("$PWD")
  end
  if spec.twoLine then add("\n") else add(" ") end
  add(color(colors.symbol or "white"))
  add(spec.symbol or "# ")
  add("\27[0m")  -- reset so typed text is in the default color
  return table.concat(parts)
end

prompt._colors = FG
return prompt
