-- ajson — pretty-print or validate JSON. Requires Aurora's json library.
--   ajson <file.json>            pretty-print
--   ajson -c <file.json>         compact (minified) JSON
--   ajson --check <file.json>    validate only (exit 0 ok, 1 invalid)
--   echo '{"a":1}' | ajson       read from stdin
local shell = require("shell")
local json = require("json")

local args, options = shell.parse(...)

local data
if #args >= 1 then
  local f, err = io.open(shell.resolve(args[1]), "rb")
  if not f then io.stderr:write("ajson: " .. tostring(err) .. "\n"); os.exit(1) end
  data = f:read("*a"); f:close()
else
  data = io.read("*a")
end
if not data or data == "" then io.stderr:write("ajson: no input\n"); os.exit(1) end

local ok, value = pcall(json.decode, data)
if not ok then
  io.stderr:write("ajson: invalid JSON: " .. tostring(value) .. "\n")
  os.exit(1)
end

if options.check then
  io.write("valid JSON\n")
  return
end

io.write(json.encode(value, {pretty = not options.c}) .. "\n")
