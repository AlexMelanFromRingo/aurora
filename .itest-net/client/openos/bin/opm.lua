-- opm — Aurora package manager CLI.
--   opm update                 refresh package lists
--   opm search <query>         find packages
--   opm info <name>            show package details
--   opm install <name[@ver]>…  install packages (+deps)
--   opm remove <name>…         uninstall packages
--   opm list                   list installed packages
--   opm upgrade                upgrade all installed packages
local opm = require("aurora.opm")
local shell = require("shell")

local args, options = shell.parse(...)
local cmd = table.remove(args, 1)

local function fail(msg)
  io.stderr:write("opm: " .. tostring(msg) .. "\n")
  os.exit(1)
end

local function usage()
  io.write([[Usage: opm <command> [args]
  update                 refresh package lists from sources
  search <query>         search available packages
  info <name>            show details about a package
  install <name[@ver]>…  install packages and dependencies
  remove <name>…         uninstall packages
  list                   list installed packages
  upgrade                upgrade all installed packages

Flags: -f/--force  --fresh (bypass cache)
]])
end

local opts = {out = io.write, force = options.f or options.force, fresh = options.fresh}

if cmd == "update" then
  local ok, err = opm.update(io.write)
  if not ok then fail(err) end

elseif cmd == "install" then
  if #args == 0 then fail("install needs a package name") end
  local ok, err = opm.install(args, opts)
  if not ok then fail(err) end

elseif cmd == "remove" or cmd == "rm" then
  if #args == 0 then fail("remove needs a package name") end
  local ok, err = opm.remove(args, opts)
  if not ok then fail(err) end

elseif cmd == "list" or cmd == "ls" then
  local items = opm.list()
  if #items == 0 then io.write("No packages installed.\n") end
  for _, it in ipairs(items) do
    io.write(string.format("%-24s %s\n", it.name, it.version))
  end

elseif cmd == "search" then
  local results, err = opm.search(args[1], opts)
  if not results then fail(err) end
  if #results == 0 then io.write("No matches.\n") end
  for _, r in ipairs(results) do
    io.write(string.format("%-24s %s\n", r.name, r.description))
  end

elseif cmd == "info" then
  if #args == 0 then fail("info needs a package name") end
  local i, err = opm.info(args[1], opts)
  if not i then fail(err) end
  io.write("Package:   " .. i.name .. "\n")
  io.write("About:     " .. (i.description or "") .. "\n")
  io.write("Versions:  " .. table.concat(i.versions, ", ") .. "\n")
  io.write("Installed: " .. (i.installed or "(no)") .. "\n")

elseif cmd == "upgrade" then
  local ok, err = opm.upgrade(opts)
  if not ok then fail(err) end

elseif cmd == "help" or cmd == nil or options.h or options.help then
  usage()

else
  fail("unknown command '" .. tostring(cmd) .. "' (try: opm help)")
end
