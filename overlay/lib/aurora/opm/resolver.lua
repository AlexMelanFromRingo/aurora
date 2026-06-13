-- aurora.opm.resolver — pure dependency resolution for opm. Given a registry
-- table, a set of requested packages and what's already installed, produce a
-- dependencies-first install order with concrete versions chosen by semver.
-- No I/O here, so it is fully host-unit-testable.
local semver = require("aurora.semver")

local resolver = {}

-- resolve(registry, requests) -> order, chosen  | nil, err
--   registry.packages[name].versions[ver] = {deps = {dep = constraint}, files = {...}}
--   requests = { {name=, constraint=}, ... }
--   order   = { {name=, version=, files=, deps=}, ... }  (deps before dependents)
--   chosen  = { name = version }
function resolver.resolve(registry, requests)
  local packages = (registry and registry.packages) or {}
  local chosen, order, visiting = {}, {}, {}

  local function versionsOf(pkg)
    local out = {}
    for v in pairs(pkg.versions or {}) do out[#out + 1] = v end
    return out
  end

  local visit
  visit = function(name, constraint, fromChain)
    constraint = constraint or "*"
    local pkg = packages[name]
    if not pkg then
      return nil, "unknown package: " .. name ..
        (fromChain and (" (required by " .. fromChain .. ")") or "")
    end
    if chosen[name] then
      if not semver.satisfies(chosen[name], constraint) then
        return nil, string.format(
          "version conflict for %s: %s chosen but %s requires %s",
          name, chosen[name], fromChain or "request", constraint)
      end
      return true
    end
    if visiting[name] then
      return nil, "dependency cycle involving " .. name
    end
    local ver = semver.best(versionsOf(pkg), constraint)
    if not ver then
      return nil, string.format("no version of %s satisfies '%s'", name, constraint)
    end
    visiting[name] = true
    local entry = pkg.versions[ver]
    -- deterministic dependency order
    local depNames = {}
    for d in pairs(entry.deps or {}) do depNames[#depNames + 1] = d end
    table.sort(depNames)
    for _, dep in ipairs(depNames) do
      local ok, err = visit(dep, entry.deps[dep], name)
      if not ok then return nil, err end
    end
    visiting[name] = nil
    chosen[name] = ver
    order[#order + 1] =
      {name = name, version = ver, files = entry.files or {}, deps = entry.deps or {}}
    return true
  end

  for _, req in ipairs(requests) do
    local ok, err = visit(req.name, req.constraint)
    if not ok then return nil, err end
  end
  return order, chosen
end

return resolver
