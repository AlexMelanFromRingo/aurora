-- aurora.optimize — small, opt-in performance helpers. None of these are forced
-- onto the system; programs require them when they want the speedup.
local optimize = {}

-- warm(modules) — eagerly require a list of modules so the first interactive use
-- doesn't pay the load cost. Returns how many were newly loaded. Failures are
-- swallowed (a missing optional module shouldn't break warming).
function optimize.warm(modules)
  local n = 0
  for _, name in ipairs(modules) do
    if not package.loaded[name] then
      if pcall(require, name) then n = n + 1 end
    end
  end
  return n
end

-- A sensible default hot-set for an interactive Aurora shell.
optimize.HOT = {
  "json", "inspect", "argparse", "aurora.util", "aurora.fsx", "aurora.hash",
}

function optimize.warmDefaults() return optimize.warm(optimize.HOT) end

-- slurp(path) — read a whole file in large blocks (fewer component round-trips
-- than line-by-line). Returns the contents or nil, err.
function optimize.slurp(path, blockSize)
  blockSize = blockSize or (64 * 1024)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local parts = {}
  while true do
    local chunk = f:read(blockSize)
    if not chunk then break end
    parts[#parts + 1] = chunk
  end
  f:close()
  return table.concat(parts)
end

-- memoize(fn) — cache results of a single-argument pure function.
function optimize.memoize(fn)
  local cache = {}
  return function(x)
    local v = cache[x]
    if v == nil then v = fn(x); cache[x] = v end
    return v
  end
end

return optimize
