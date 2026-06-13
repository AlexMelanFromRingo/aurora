-- acowsay — a tiny cowsay for OpenOS. Installed via `opm install acowsay`.
--   acowsay hello world      |  echo hi | acowsay
local shell = require("shell")
local args = shell.parse(...)

local text
if #args > 0 then
  text = table.concat(args, " ")
else
  text = io.read("*l") or "moo"
end

local width = 0
for _, line in ipairs({text}) do width = math.max(width, #line) end
local top = " " .. string.rep("_", width + 2)
local bot = " " .. string.rep("-", width + 2)
io.write(top .. "\n")
io.write("< " .. text .. " >\n")
io.write(bot .. "\n")
io.write([[        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||
]])
