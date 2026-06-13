-- arepl — an improved interactive Lua prompt for OpenOS:
--   * multiline input (keeps reading until the chunk compiles)
--   * results pretty-printed with inspect
--   * `=expr` (or a bare expression) prints its value
--   * persistent environment across lines; `exit`/Ctrl-D to quit
local inspect = require("inspect")

local env = setmetatable({}, {__index = _ENV or _G})
env._ENV = env

io.write("Aurora REPL — Lua " .. _VERSION .. "  (type 'exit' to quit)\n")

local buf = ""
while true do
  io.write(buf == "" and "\27[36m»\27[m " or "\27[36m..\27[m ")
  local line = io.read()
  if line == nil then io.write("\n"); break end
  if buf == "" and (line == "exit" or line == "quit") then break end

  local source = buf .. line
  if buf == "" then source = (source:gsub("^%s*=", "return ")) end

  local chunk, err = load("return " .. source, "=repl", "t", env)
  if not chunk then chunk, err = load(source, "=repl", "t", env) end

  if not chunk then
    if err and err:match("near .?<eof>.?$") then
      buf = source .. "\n"          -- incomplete; keep reading
    else
      io.stderr:write("\27[31m! " .. tostring(err) .. "\27[m\n")
      buf = ""
    end
  else
    buf = ""
    local res = table.pack(pcall(chunk))
    if not res[1] then
      io.stderr:write("\27[31m! " .. tostring(res[2]) .. "\27[m\n")
    else
      for i = 2, res.n do
        io.write(inspect(res[i]) .. "\n")
      end
    end
  end
end
