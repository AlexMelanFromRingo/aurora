-- aurora.opm.registry — load package sources, fetch their index files and merge
-- them into one registry table the resolver understands. Indexes are cached so
-- offline `opm install` works after one `opm update`. File download URLs are
-- resolved to absolute during merge (source base + relative file url).
local json = require("json")
local fsx = require("aurora.fsx")

local registry = {}
registry.configRoot = "/etc/opm"

local DEFAULT_SOURCES = {
  {name = "aurora",
   url = "https://raw.githubusercontent.com/AlexMelanFromRingo/aurora/main/registry"},
}

local function sourcesPath() return fsx.join(registry.configRoot, "sources.lua") end
local function cachePath(name) return fsx.join(registry.configRoot, "cache", name .. ".json") end

-- loadSources() -> array of {name, url}
function registry.loadSources()
  local path = sourcesPath()
  if fsx.exists(path) then
    local chunk = loadfile(path)
    if chunk then
      local ok, list = pcall(chunk)
      if ok and type(list) == "table" and #list > 0 then return list end
    end
  end
  return DEFAULT_SOURCES
end

-- merge(name, index, baseUrl, into) — fold one source index into `into`.
function registry.merge(name, index, baseUrl, into)
  into.packages = into.packages or {}
  for pkg, meta in pairs(index.packages or {}) do
    local dst = into.packages[pkg]
    if not dst then
      dst = {description = meta.description, versions = {}}
      into.packages[pkg] = dst
    end
    for ver, entry in pairs(meta.versions or {}) do
      -- resolve absolute file URLs against the source base
      local files = {}
      for i, f in ipairs(entry.files or {}) do
        files[i] = {
          path = f.path,
          sha256 = f.sha256,
          abs = (f.url and (f.url:match("^https?://") and f.url
                 or (baseUrl .. "/" .. f.url))) or nil,
        }
      end
      dst.versions[ver] = {deps = entry.deps or {}, files = files, source = name}
    end
  end
  return into
end

-- fetchIndex(source) -> index | nil, err  (also writes the cache)
function registry.fetchIndex(source)
  local ahttp = require("ahttp")
  local index, err = ahttp.getJSON(source.url .. "/index.json")
  if not index then return nil, err end
  fsx.ensureParent(cachePath(source.name))
  fsx.atomicWrite(cachePath(source.name), json.encode(index))
  return index
end

-- cachedIndex(source) -> index | nil
function registry.cachedIndex(source)
  local path = cachePath(source.name)
  if not fsx.exists(path) then return nil end
  local data = fsx.readAll(path)
  local ok, index = pcall(json.decode, data or "")
  return ok and index or nil
end

-- update() -> true | nil, err  (refresh every source's cache from the network)
function registry.update()
  local sources = registry.loadSources()
  local errs = {}
  for _, s in ipairs(sources) do
    local _, err = registry.fetchIndex(s)
    if err then errs[#errs + 1] = s.name .. ": " .. err end
  end
  if #errs > 0 then return nil, table.concat(errs, "; ") end
  return true
end

-- build(opts) -> registry table. opts.fresh forces a network fetch; otherwise
-- cached indexes are used and only fetched if missing.
function registry.build(opts)
  opts = opts or {}
  local sources = registry.loadSources()
  local merged = {packages = {}}
  for _, s in ipairs(sources) do
    local index
    if opts.fresh then
      index = registry.fetchIndex(s)
    else
      index = registry.cachedIndex(s) or registry.fetchIndex(s)
    end
    if index then registry.merge(s.name, index, s.url, merged) end
  end
  return merged
end

return registry
