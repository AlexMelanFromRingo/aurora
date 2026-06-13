-- aurora.opm.db — the local record of installed packages. One JSON manifest per
-- package under <root>/installed/<name>.json holding {name, version, files}.
-- `root` is overridable so the database can be exercised in host tests.
local json = require("json")
local fsx = require("aurora.fsx")

local db = {}
db.root = "/etc/opm"

local function installedDir() return fsx.join(db.root, "installed") end
local function manifestPath(name) return fsx.join(installedDir(), name .. ".json") end

-- record(manifest) — manifest = {name=, version=, files={paths...}}
function db.record(manifest)
  checkArg(1, manifest, "table")
  assert(manifest.name, "manifest needs a name")
  fsx.mkdirs(installedDir())
  return fsx.atomicWrite(manifestPath(manifest.name), json.encode(manifest, {pretty = true}))
end

-- get(name) -> manifest | nil
function db.get(name)
  local path = manifestPath(name)
  if not fsx.exists(path) then return nil end
  local data = fsx.readAll(path)
  if not data then return nil end
  local ok, m = pcall(json.decode, data)
  return ok and m or nil
end

function db.isInstalled(name) return db.get(name) ~= nil end

-- list() -> sorted array of {name, version}
function db.list()
  local dir = installedDir()
  if not fsx.exists(dir) then return {} end
  local out = {}
  for _, file in ipairs(fsx.list(dir)) do
    local name = file:match("^(.*)%.json$")
    if name then
      local m = db.get(name)
      out[#out + 1] = {name = name, version = m and m.version or "?"}
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- forget(name) — remove the manifest only (file removal is opm core's job)
function db.forget(name)
  local path = manifestPath(name)
  if fsx.exists(path) then return require("filesystem").remove(path) end
  return true
end

return db
