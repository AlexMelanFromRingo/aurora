-- gen-catalog.lua (host) — render the opm registry (registry/index.json) into a
-- human-friendly package catalog at docs/packages.md (published on the docs
-- site). Run from the repo root: lua5.3 tools/gen-catalog.lua
package.path = "overlay/lib/?.lua;overlay/lib/?/init.lua;" .. package.path
_G.checkArg = _G.checkArg or function() end
local json = require("json")
local semver = require("aurora.semver")

local function readAll(p) local f = assert(io.open(p, "rb")); local d = f:read("*a"); f:close(); return d end

local index = json.decode(readAll("registry/index.json"))

local names = {}
for name in pairs(index.packages) do names[#names + 1] = name end
table.sort(names)

local out = {
  "# Package Catalog\n",
  "_Auto-generated from `registry/index.json` by `tools/gen-catalog.lua`._\n",
  "Install any of these on an Aurora system with `opm install <name>`.\n",
  "| Package | Latest | Description |",
  "|---------|--------|-------------|",
}
for _, name in ipairs(names) do
  local pkg = index.packages[name]
  local versions = {}
  for v in pairs(pkg.versions) do versions[#versions + 1] = v end
  local latest = semver.max(versions) or "?"
  local desc = (pkg.description or ""):gsub("|", "\\|")
  out[#out + 1] = string.format("| `%s` | %s | %s |", name, latest, desc)
end
out[#out + 1] = ""
out[#out + 1] = string.format("_%d package(s)._", #names)

local f = assert(io.open("docs/packages.md", "w"))
f:write(table.concat(out, "\n") .. "\n"); f:close()
print("wrote docs/packages.md (" .. #names .. " packages)")
