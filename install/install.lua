-- Aurora online installer. Self-contained: depends only on stock OpenOS, so it
-- runs on a fresh system before any Aurora library exists.
--
--   wget https://raw.githubusercontent.com/AlexMelanFromRingo/aurora/main/install/install.lua /tmp/ai.lua
--   /tmp/ai.lua            # or:  /tmp/ai.lua <branch-or-base-url>
--
-- It downloads the checksummed manifest, fetches every file (status-checked),
-- verifies each against its sha256, writes atomically, backs up any core file
-- it patches, wires the login hook, and is safe to re-run (idempotent).
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")

local DEFAULT_BASE =
  "https://raw.githubusercontent.com/AlexMelanFromRingo/aurora/main"

local arg = ({...})[1]
local BASE = DEFAULT_BASE
if arg then
  if arg:match("^https?://") then BASE = arg:gsub("/+$", "")
  else BASE = "https://raw.githubusercontent.com/AlexMelanFromRingo/aurora/" .. arg end
end

local function say(...) io.write(...) end
local function die(msg) io.stderr:write("\naurora-install: " .. tostring(msg) .. "\n"); os.exit(1) end

-- status-checked HTTP GET returning the body (a 404 page is an error, not data)
local function http_get(url)
  if not component.isAvailable("internet") then return nil, "no internet card" end
  local inet = component.internet
  local h, err = inet.request(url)
  if not h then return nil, err end
  local deadline = computer.uptime() + 30
  while true do
    local ok, e = h.finishConnect()
    if ok then break end
    if ok == nil and e then h.close(); return nil, e end
    if computer.uptime() > deadline then h.close(); return nil, "timeout" end
    os.sleep(0.05)
  end
  local status
  while computer.uptime() <= deadline do
    local s = h.response()
    if s then status = s; break end
    os.sleep(0.05)
  end
  local chunks = {}
  while true do
    local c, r = h.read(8192)
    if c == nil then if r then h.close(); return nil, r end break end
    if #c > 0 then chunks[#chunks + 1] = c else os.sleep(0) end
    if computer.uptime() > deadline then h.close(); return nil, "read timeout" end
  end
  h.close()
  if status and (status < 200 or status >= 300) then
    return nil, "HTTP " .. status
  end
  return table.concat(chunks)
end

local function ensure_parent(path)
  local dir = path:match("^(.*)/[^/]*$")
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDirectory(dir) end
end

local function atomic_write(path, data)
  ensure_parent(path)
  local tmp = path .. ".tmp-ai"
  local f, err = io.open(tmp, "wb")
  if not f then return nil, err end
  f:write(data); f:close()
  fs.remove(path)
  local ok, rerr = os.rename(tmp, path)
  if not ok then fs.remove(tmp); return nil, rerr or "rename failed" end
  return true
end

say("\n=== Aurora installer ===\nSource: " .. BASE .. "\n\n")

-- 1) manifest
say("Fetching manifest... ")
local manifest_src, merr = http_get(BASE .. "/install/manifest.lua")
if not manifest_src then die("could not fetch manifest: " .. tostring(merr)) end
local manifest_fn, lerr = load(manifest_src, "=manifest", "t")
if not manifest_fn then die("bad manifest: " .. tostring(lerr)) end
local manifest = manifest_fn()
say("ok (" .. #manifest.files .. " files, v" .. manifest.version .. ")\n")

-- 2) bootstrap the hash library so we can verify everything (including itself)
local hashlib
for _, entry in ipairs(manifest.files) do
  if entry.dst == "/lib/aurora/hash.lua" then
    local body = http_get(BASE .. "/" .. entry.src)
    if body then hashlib = load(body, "=hash", "t")() end
    break
  end
end
if not hashlib then say("! checksum lib unavailable; installing WITHOUT verification\n") end

-- 3) download, verify, write
local installed, patched = 0, 0
for _, entry in ipairs(manifest.files) do
  local body, gerr = http_get(BASE .. "/" .. entry.src)
  if not body then die("download failed for " .. entry.dst .. ": " .. tostring(gerr)) end
  if hashlib and entry.sha256 then
    local sum = hashlib.sha256(body)
    if sum ~= entry.sha256 then
      die(string.format("checksum mismatch for %s\n  got %s\n  want %s",
        entry.dst, sum, entry.sha256))
    end
  end
  -- back up a core file we are about to patch (once)
  if entry.kind == "patch" and fs.exists(entry.dst)
     and not fs.exists(entry.dst .. ".orig-aurora") then
    local cur = io.open(entry.dst, "rb")
    if cur then
      local old = cur:read("*a"); cur:close()
      atomic_write(entry.dst .. ".orig-aurora", old)
    end
  end
  local ok, werr = atomic_write(entry.dst, body)
  if not ok then die("write failed for " .. entry.dst .. ": " .. tostring(werr)) end
  if entry.kind == "patch" then patched = patched + 1 else installed = installed + 1 end
  say(".")
end
say(string.format("\nInstalled %d files, applied %d patches.\n", installed, patched))

-- 4) wire the login hook into /etc/profile.lua (guarded + idempotent)
local PROFILE = "/etc/profile.lua"
local MARK_BEGIN = "-- >>> aurora >>>"
local function profile_has_hook()
  local f = io.open(PROFILE, "r"); if not f then return false end
  local s = f:read("*a"); f:close()
  return s:find(MARK_BEGIN, 1, true) ~= nil
end
if fs.exists(PROFILE) and not profile_has_hook() then
  if not fs.exists(PROFILE .. ".orig-aurora") then
    local f = io.open(PROFILE, "r"); local s = f:read("*a"); f:close()
    atomic_write(PROFILE .. ".orig-aurora", s)
  end
  local f = io.open(PROFILE, "r"); local s = f:read("*a"); f:close()
  s = s .. "\n" .. MARK_BEGIN ..
    "\npcall(dofile, \"/etc/aurora/login.lua\")\n-- <<< aurora <<<\n"
  atomic_write(PROFILE, s)
  say("Login hook added to /etc/profile.lua.\n")
end

say("\nAurora " .. manifest.version .. " installed. Run `afetch`, `opm`, `atheme`.\n")
say("Open a new shell or reboot to load the Aurora environment.\n")
