-- ahexdump — a canonical hex + ASCII dump of a file or stdin.
--   ahexdump <file>      (no file = stdin)
local shell = require("shell")
local args = shell.parse(...)

local data
if args[1] then
  local f, err = io.open(shell.resolve(args[1]), "rb")
  if not f then io.stderr:write("ahexdump: " .. tostring(err) .. "\n"); os.exit(1) end
  data = f:read("*a") or ""; f:close()
else
  data = io.read("*a") or ""
end

for off = 0, #data - 1, 16 do
  local chunk = data:sub(off + 1, off + 16)
  local hex = {}
  for i = 1, 16 do
    if i <= #chunk then hex[#hex + 1] = string.format("%02x", chunk:byte(i))
    else hex[#hex + 1] = "  " end
    if i == 8 then hex[#hex + 1] = "" end  -- gap after 8 bytes
  end
  local ascii = chunk:gsub("[^\32-\126]", ".")
  io.write(string.format("%08x  %s  |%s|\n", off, table.concat(hex, " "), ascii))
end
io.write(string.format("%08x\n", #data))
