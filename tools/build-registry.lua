-- build-registry.lua (host) — generate registry/index.json from the packages
-- under registry/packages/. Each package dir has a package.lua descriptor and,
-- per version, a tree of files that mirror their install path:
--   registry/packages/<name>/<ver>/bin/x.lua  ->  installs to /bin/x.lua
-- File URLs in the index are repo-relative to the registry base.
-- Run from the repo root: lua5.3 tools/build-registry.lua
package.path = "overlay/lib/?.lua;overlay/lib/?/init.lua;" .. package.path
_G.checkArg = _G.checkArg or function() end
local hash = require("aurora.hash")
local json = require("json")

local function lines(cmd)
  local out, h = {}, assert(io.popen(cmd)); for l in h:lines() do out[#out + 1] = l end
  h:close(); return out
end
local function readAll(p) local f = assert(io.open(p, "rb")); local d = f:read("*a"); f:close(); return d end
local function isDir(p) return select(3, os.execute("test -d '" .. p .. "'")) == 0 end

local index = {registry = "aurora", packages = json.object({})}

for _, pkgPath in ipairs(lines("find registry/packages -mindepth 1 -maxdepth 1 -type d")) do
  local name = pkgPath:match("([^/]+)$")
  local descriptor = assert(load(readAll(pkgPath .. "/package.lua")))()
  local versions = json.object({})
  for ver, vmeta in pairs(descriptor.versions) do
    local vdir = pkgPath .. "/" .. ver
    if isDir(vdir) then
      local files = {}
      for _, fpath in ipairs(lines("find '" .. vdir .. "' -type f")) do
        local rel = fpath:gsub("^" .. vdir .. "/", "")
        files[#files + 1] = {
          path = "/" .. rel,
          url = "packages/" .. name .. "/" .. ver .. "/" .. rel,
          sha256 = hash.sha256(readAll(fpath)),
        }
      end
      table.sort(files, function(a, b) return a.path < b.path end)
      versions[ver] = {deps = vmeta.deps or json.object({}), files = files}
    end
  end
  index.packages[name] = {description = descriptor.description, versions = versions}
end

local out = assert(io.open("registry/index.json", "w"))
out:write(json.encode(index, {pretty = true})); out:close()

local n = 0; for _ in pairs(index.packages) do n = n + 1 end
print("wrote registry/index.json: " .. n .. " package(s)")
