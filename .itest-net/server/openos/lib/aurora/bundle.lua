-- aurora.bundle — link a multi-module Lua project into a single self-contained
-- file. It statically scans `require("mod")` calls, resolves each to a file on
-- the search path, and emits every local module into package.preload followed
-- by the entry chunk. Modules it cannot find locally (e.g. "component",
-- "filesystem") are left as ordinary runtime requires.
local fsx = require("aurora.fsx")

local bundle = {}

local function resolve(name, searchPaths)
  local rel = name:gsub("%.", "/")
  for _, base in ipairs(searchPaths) do
    for _, cand in ipairs({base .. "/" .. rel .. ".lua",
                           base .. "/" .. rel .. "/init.lua"}) do
      if fsx.exists(cand) then return cand end
    end
  end
  return nil
end

-- requires(src) -> iterator of module names referenced via require"..."/require("...")
local function eachRequire(src)
  return src:gmatch('require%s*%(?%s*["\']([%w%._%-/]+)["\']')
end

-- build(entry, opts) -> source | nil, err
--   opts.searchPaths  (default: entry dir, /lib, /usr/lib)
--   opts.minify       run the result through aurora.minify
function bundle.build(entry, opts)
  checkArg(1, entry, "string")
  opts = opts or {}
  local entrySrc, err = fsx.readAll(entry)
  if not entrySrc then return nil, "cannot read entry: " .. tostring(err) end

  local searchPaths = opts.searchPaths
    or {fsx.dirname(entry), "/lib", "/usr/lib", "/home/lib"}

  local included, order = {}, {}
  local function scan(src)
    for name in eachRequire(src) do
      if not included[name] then
        local file = resolve(name, searchPaths)
        if file then
          local s = fsx.readAll(file)
          if s then
            included[name] = s
            order[#order + 1] = name
            scan(s)
          end
        end
      end
    end
  end
  scan(entrySrc)

  local parts = {"-- bundled by aurora abundle (", tostring(#order), " modules)\n"}
  for _, name in ipairs(order) do
    parts[#parts + 1] = string.format(
      "package.preload[%q] = package.preload[%q] or function(...)\n", name, name)
    parts[#parts + 1] = included[name]
    parts[#parts + 1] = "\nend\n"
  end
  parts[#parts + 1] = "-- entry: " .. fsx.basename(entry) .. "\n"
  parts[#parts + 1] = entrySrc

  local out = table.concat(parts)
  if opts.minify then out = require("aurora.minify")(out) end
  return out, {modules = order}
end

return bundle
