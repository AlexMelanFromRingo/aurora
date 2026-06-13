-- Aurora offline applier. Installs Aurora from a local copy of the repository
-- (e.g. a disk you cloned with git, or an unpacked archive) with no network.
--
--   apply.lua <repo-dir>        # defaults to the current directory
--
-- Reads install/manifest.lua from the repo, verifies each file's sha256, backs
-- up any core file it patches, writes atomically, and wires the login hook.
local shell = require("shell")
local fs = require("filesystem")

local args = shell.parse(...)
local SRC = (args[1] and shell.resolve(args[1])) or shell.getWorkingDirectory()
SRC = SRC:gsub("/+$", "")

local function die(m) io.stderr:write("aurora-apply: " .. tostring(m) .. "\n"); os.exit(1) end
local function readAll(p) local f = io.open(p, "rb"); if not f then return nil end
  local d = f:read("*a"); f:close(); return d end

local manifest_src = readAll(SRC .. "/install/manifest.lua")
  or die("no install/manifest.lua under " .. SRC .. " (is this the repo root?)")
local manifest = assert(load(manifest_src, "=manifest", "t"))()

-- checksum lib (from the source tree)
local hashlib
do
  local hsrc = readAll(SRC .. "/overlay/lib/aurora/hash.lua")
  if hsrc then hashlib = load(hsrc, "=hash", "t")() end
end

local function ensure_parent(path)
  local dir = path:match("^(.*)/[^/]*$")
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDirectory(dir) end
end
local function atomic_write(path, data)
  ensure_parent(path)
  local tmp = path .. ".tmp-ap"
  local f = io.open(tmp, "wb"); if not f then return nil, "open failed" end
  f:write(data); f:close()
  fs.remove(path)
  local ok = os.rename(tmp, path)
  if not ok then fs.remove(tmp); return nil, "rename failed" end
  return true
end

io.write("Applying Aurora " .. manifest.version .. " from " .. SRC .. "\n")
local n, np = 0, 0
for _, e in ipairs(manifest.files) do
  local body = readAll(SRC .. "/" .. e.src) or die("missing source file: " .. e.src)
  if hashlib and e.sha256 and hashlib.sha256(body) ~= e.sha256 then
    die("checksum mismatch for " .. e.dst)
  end
  if e.kind == "patch" and fs.exists(e.dst) and not fs.exists(e.dst .. ".orig-aurora") then
    local cur = readAll(e.dst)
    if cur then atomic_write(e.dst .. ".orig-aurora", cur) end
  end
  assert(atomic_write(e.dst, body))
  if e.kind == "patch" then np = np + 1 else n = n + 1 end
  io.write(".")
end
io.write(string.format("\nInstalled %d files, applied %d patches.\n", n, np))

-- login hook
local PROFILE = "/etc/profile.lua"
local cur = readAll(PROFILE)
if cur and not cur:find("-- >>> aurora >>>", 1, true) then
  if not fs.exists(PROFILE .. ".orig-aurora") then atomic_write(PROFILE .. ".orig-aurora", cur) end
  atomic_write(PROFILE, cur .. "\n-- >>> aurora >>>\npcall(dofile, \"/etc/aurora/login.lua\")\n-- <<< aurora <<<\n")
  io.write("Login hook added to /etc/profile.lua.\n")
end

io.write("\nAurora applied. Open a new shell or reboot.\n")
