-- adoc — generate Markdown API docs from a Lua file's functions and their
-- leading comments.
--   adoc <file.lua> [-o out.md] [--title "Name"]
local shell = require("shell")
local doc = require("aurora.doc")
local fsx = require("aurora.fsx")

local args, options = shell.parse(...)
if #args < 1 then
  io.write("Usage: adoc <file.lua> [-o out.md] [--title NAME] [--all]\n")
  io.write("  documents table members (public API) by default; --all includes locals\n")
  return
end

local path = shell.resolve(args[1])
local src = fsx.readAll(path)
if not src then io.stderr:write("adoc: cannot read " .. args[1] .. "\n"); os.exit(1) end

local title = options.title
if title == nil or title == true then title = fsx.basename(path):gsub("%.lua$", "") end

local md, err = doc.markdown(src, {title = title, publicOnly = not options.all})
if not md then io.stderr:write("adoc: " .. tostring(err) .. "\n"); os.exit(1) end

local out = options.o
if out and out ~= true then
  assert(fsx.atomicWrite(shell.resolve(out), md))
  io.write("wrote " .. out .. "\n")
else
  io.write(md)
end
