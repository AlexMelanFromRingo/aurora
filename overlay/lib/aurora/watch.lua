-- aurora.watch — watch files for changes and react. The change-detection core
-- (snapshot/changed) is pure and injectable, so it is unit-tested; the loop
-- uses os.sleep. By default a file's "stamp" is a crc32 of its contents, so any
-- edit is detected (not just size changes) using only standard io.
local watch = {}

-- default stamp: crc32 of the file contents (or "" when unreadable)
local function defaultStat(path)
  local f = io.open(path, "rb")
  if not f then return "" end
  local data = f:read("*a"); f:close()
  return require("aurora.hash").crc32(data or "")
end

-- snapshot(paths [, stat]) -> { path = stamp }
function watch.snapshot(paths, stat)
  stat = stat or defaultStat
  local snap = {}
  for _, p in ipairs(paths) do snap[p] = stat(p) end
  return snap
end

-- changed(old, new) -> sorted array of paths whose stamp differs
function watch.changed(old, new)
  local out = {}
  for p, s in pairs(new) do
    if old[p] ~= s then out[#out + 1] = p end
  end
  table.sort(out)
  return out
end

-- loop(paths, onChange [, opts]) — poll forever, calling onChange(path) for each
-- file whose contents changed. opts.interval (seconds, default 1), opts.stat,
-- opts.runFirst (fire onChange once for every path at startup), opts.ticks
-- (stop after N polls — for tests; nil = forever).
function watch.loop(paths, onChange, opts)
  opts = opts or {}
  local interval = opts.interval or 1
  local stat = opts.stat or defaultStat
  if opts.runFirst then
    for _, p in ipairs(paths) do onChange(p) end
  end
  local prev = watch.snapshot(paths, stat)
  local n = 0
  while true do
    os.sleep(interval)
    local cur = watch.snapshot(paths, stat)
    for _, p in ipairs(watch.changed(prev, cur)) do onChange(p) end
    prev = cur
    n = n + 1
    if opts.ticks and n >= opts.ticks then break end
  end
end

return watch
