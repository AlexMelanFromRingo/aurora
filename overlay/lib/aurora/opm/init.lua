-- aurora.opm — package manager core. Orchestrates registry + resolver + db +
-- ahttp to install/remove/list/upgrade packages. Side-effecting functions take
-- an optional `out` writer (defaults to io.write) so callers/tests can capture.
local registry = require("aurora.opm.registry")
local resolver = require("aurora.opm.resolver")
local db = require("aurora.opm.db")
local semver = require("aurora.semver")
local fsx = require("aurora.fsx")
local json = require("json")

local opm = {}
opm.registry = registry
opm.db = db

local function w(out, ...) (out or io.write)(table.concat({...})) end

-- parse "name@^1.2.0" -> name, constraint
local function parseSpec(spec)
  local name, constraint = spec:match("^([^@]+)@(.+)$")
  return name or spec, constraint or "*"
end

-- update — refresh registry caches from the network.
function opm.update(out)
  w(out, "Updating package lists...\n")
  local ok, err = registry.update()
  if not ok then return nil, err end
  local reg = registry.build()
  local n = 0
  for _ in pairs(reg.packages) do n = n + 1 end
  w(out, "Registry updated: ", tostring(n), " packages available.\n")
  return true
end

-- install(specs, opts) — specs = {"name", "name@constraint", ...}
function opm.install(specs, opts)
  opts = opts or {}
  local out = opts.out
  local reg = registry.build({fresh = opts.fresh})

  local requests = {}
  for _, spec in ipairs(specs) do
    local name, constraint = parseSpec(spec)
    requests[#requests + 1] = {name = name, constraint = constraint}
  end

  local order, err = resolver.resolve(reg, requests)
  if not order then return nil, err end

  -- decide what actually needs installing
  local todo = {}
  for _, p in ipairs(order) do
    local cur = db.get(p.name)
    if cur and cur.version == p.version and not opts.force then
      w(out, "  ", p.name, " ", p.version, " already installed\n")
    else
      todo[#todo + 1] = p
    end
  end
  if #todo == 0 then w(out, "Nothing to do.\n"); return true end

  w(out, "Installing: ")
  for i, p in ipairs(todo) do w(out, i > 1 and ", " or "", p.name, "@", p.version) end
  w(out, "\n")

  local ahttp = require("ahttp")
  for _, p in ipairs(todo) do
    w(out, "  ", p.name, " ", p.version, "\n")
    local installed = {}
    for _, f in ipairs(p.files) do
      if not f.abs then
        return nil, p.name .. ": file " .. tostring(f.path) .. " has no download url"
      end
      w(out, "    -> ", f.path, "\n")
      local ok, derr = ahttp.download(f.abs, f.path, {sha256 = f.sha256})
      if not ok then
        -- roll back files written for this package
        for _, done in ipairs(installed) do os.remove(done) end
        return nil, string.format("%s: %s (%s)", p.name, derr, f.abs)
      end
      installed[#installed + 1] = f.path
    end
    db.record({
      name = p.name, version = p.version, deps = p.deps,
      files = installed,
    })
  end
  w(out, "Done.\n")
  return true
end

-- remove(names, opts)
function opm.remove(names, opts)
  opts = opts or {}
  local out = opts.out
  for _, name in ipairs(names) do
    local m = db.get(name)
    if not m then
      w(out, name, " is not installed\n")
    else
      -- guard: don't remove if another installed package depends on it
      if not opts.force then
        for _, other in ipairs(db.list()) do
          local om = db.get(other.name)
          if om and om.deps and om.deps[name] then
            return nil, string.format("%s is required by %s (use --force)", name, other.name)
          end
        end
      end
      w(out, "Removing ", name, " ", tostring(m.version), "\n")
      for _, path in ipairs(m.files or {}) do
        if fsx.exists(path) then os.remove(path); w(out, "    x ", path, "\n") end
      end
      db.forget(name)
    end
  end
  return true
end

-- list() -> array of {name, version}
function opm.list() return db.list() end

-- info(name) -> {name, description, versions={...}, installed=ver|nil} | nil
function opm.info(name, opts)
  local reg = registry.build({fresh = opts and opts.fresh})
  local pkg = reg.packages[name]
  if not pkg then return nil, "unknown package: " .. name end
  local versions = {}
  for v in pairs(pkg.versions) do versions[#versions + 1] = v end
  table.sort(versions, function(a, b) return semver.compare(a, b) > 0 end)
  local cur = db.get(name)
  return {
    name = name,
    description = pkg.description,
    versions = versions,
    installed = cur and cur.version or nil,
  }
end

-- search(query) -> array of {name, description}
function opm.search(query, opts)
  local reg = registry.build({fresh = opts and opts.fresh})
  query = (query or ""):lower()
  local out = {}
  for name, pkg in pairs(reg.packages) do
    local hay = (name .. " " .. (pkg.description or "")):lower()
    if query == "" or hay:find(query, 1, true) then
      out[#out + 1] = {name = name, description = pkg.description or ""}
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- upgrade(opts) — install newest registry version for each installed package.
function opm.upgrade(opts)
  opts = opts or {}
  local out = opts.out
  local reg = registry.build({fresh = opts.fresh})
  local specs = {}
  for _, item in ipairs(db.list()) do
    local pkg = reg.packages[item.name]
    if pkg then
      local versions = {}
      for v in pairs(pkg.versions) do versions[#versions + 1] = v end
      local best = semver.max(versions)
      if best and semver.compare(best, item.version) > 0 then
        w(out, "  ", item.name, ": ", item.version, " -> ", best, "\n")
        specs[#specs + 1] = item.name .. "@" .. best
      end
    end
  end
  if #specs == 0 then w(out, "Everything is up to date.\n"); return true end
  return opm.install(specs, opts)
end

-- freeze() -> lockfile table {aurora_lock=1, packages={{name=, version=}, ...}}
-- A snapshot of exactly what is installed, for reproducing the same set later.
function opm.freeze()
  local pkgs = {}
  for _, item in ipairs(db.list()) do
    pkgs[#pkgs + 1] = {name = item.name, version = item.version}
  end
  return {aurora_lock = 1, packages = pkgs}
end

-- freezeJSON() -> pretty JSON string of the lockfile
function opm.freezeJSON()
  return json.encode(opm.freeze(), {pretty = true})
end

-- restore(lock, opts) -> install every package at its pinned version.
-- `lock` may be a table (from freeze) or a JSON string.
function opm.restore(lock, opts)
  if type(lock) == "string" then
    local ok, decoded = pcall(json.decode, lock)
    if not ok then return nil, "invalid lockfile JSON" end
    lock = decoded
  end
  if type(lock) ~= "table" or type(lock.packages) ~= "table" then
    return nil, "not an Aurora lockfile"
  end
  local specs = {}
  for _, p in ipairs(lock.packages) do
    if p.name and p.version then
      specs[#specs + 1] = p.name .. "@" .. p.version   -- exact version pin
    end
  end
  if #specs == 0 then return true end
  return opm.install(specs, opts)
end

-- outdated(opts) -> array of {name, current, latest} for installed packages that
-- have a newer version in the registry (read-only; does not install anything).
function opm.outdated(opts)
  local reg = registry.build({fresh = opts and opts.fresh})
  local out = {}
  for _, item in ipairs(db.list()) do
    local pkg = reg.packages[item.name]
    if pkg then
      local versions = {}
      for v in pairs(pkg.versions) do versions[#versions + 1] = v end
      local best = semver.max(versions)
      if best and semver.compare(best, item.version) > 0 then
        out[#out + 1] = {name = item.name, current = item.version, latest = best}
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- why(name) -> array of {name, constraint} : installed packages that declare a
-- dependency on `name` (explains why it is present).
function opm.why(name)
  local out = {}
  for _, item in ipairs(db.list()) do
    local m = db.get(item.name)
    if m and m.deps and m.deps[name] then
      out[#out + 1] = {name = item.name, constraint = m.deps[name]}
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

return opm
