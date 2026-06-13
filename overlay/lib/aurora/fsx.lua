-- aurora.fsx — filesystem conveniences with a safety bias. Path helpers are
-- pure (host-testable); content I/O uses standard io/os (works in OpenOS and on
-- the host); directory ops lazily require the OpenOS `filesystem` library.
local fsx = {}

-- ---- pure path helpers -----------------------------------------------------

function fsx.normalize(path)
  checkArg(1, path, "string")
  local absolute = path:sub(1, 1) == "/"
  local parts = {}
  for seg in path:gmatch("[^/]+") do
    if seg == ".." then
      if #parts > 0 and parts[#parts] ~= ".." then
        parts[#parts] = nil
      elseif not absolute then
        parts[#parts + 1] = ".."
      end
    elseif seg ~= "." then
      parts[#parts + 1] = seg
    end
  end
  return (absolute and "/" or "") .. table.concat(parts, "/")
end

function fsx.join(...)
  local parts = {...}
  return fsx.normalize(table.concat(parts, "/"))
end

function fsx.basename(path)
  return (path:gsub("/+$", ""):match("([^/]*)$")) or path
end

function fsx.dirname(path)
  path = path:gsub("/+$", "")
  local dir = path:match("^(.*)/[^/]*$")
  if dir == nil then return "." end
  if dir == "" then return "/" end
  return dir
end

function fsx.ext(path)
  return (fsx.basename(path):match("%.([^.]+)$")) or ""
end

-- ---- content I/O -----------------------------------------------------------

function fsx.readAll(path)
  checkArg(1, path, "string")
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data = f:read("*a")
  f:close()
  return data
end

function fsx.writeAll(path, data)
  checkArg(1, path, "string")
  checkArg(2, data, "string")
  local f, err = io.open(path, "wb")
  if not f then return nil, err end
  f:write(data)
  f:close()
  return true
end

-- atomicWrite: write to <path>.tmp-<n>, fsync via close, then rename over the
-- target. A crash mid-write never leaves a half-written destination file.
function fsx.atomicWrite(path, data)
  checkArg(1, path, "string")
  checkArg(2, data, "string")
  local tmp = path .. ".tmp"
  local ok, err = fsx.writeAll(tmp, data)
  if not ok then return nil, err end
  os.remove(path)                 -- rename onto an existing file fails in OC
  local rok, rerr = os.rename(tmp, path)
  if not rok then
    os.remove(tmp)
    return nil, rerr or "rename failed"
  end
  return true
end

-- ---- directory ops (lazy OpenOS filesystem) --------------------------------

local function fs() return require("filesystem") end

function fsx.exists(path) return fs().exists(path) end
function fsx.isDir(path) return fs().isDirectory(path) end

-- mkdirs: create a directory and all missing parents. Idempotent.
function fsx.mkdirs(path)
  checkArg(1, path, "string")
  local f = fs()
  if f.exists(path) then
    return f.isDirectory(path) or nil, "exists and is not a directory"
  end
  return f.makeDirectory(path)
end

function fsx.list(path)
  local out = {}
  for name in fs().list(path) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- ensureParent: make sure the directory that will hold `path` exists.
function fsx.ensureParent(path)
  local dir = fsx.dirname(path)
  if dir ~= "." and dir ~= "/" and not fs().exists(dir) then
    return fsx.mkdirs(dir)
  end
  return true
end

return fsx
