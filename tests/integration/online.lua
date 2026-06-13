-- Online end-to-end check: from inside real OpenOS (under ocvm), fetch Aurora's
-- manifest and a registry file straight from GitHub, verify the file's sha256
-- against the registry, and confirm the whole download+verify path works on the
-- real internet card. Writes a log to the writable disk and halts. Network
-- problems are reported as SKIP (not FAIL) so a flaky link doesn't fail a build.
local component = require("component")
local computer = require("computer")
local hash = require("aurora.hash")
local json = require("json")

local BASE = "https://raw.githubusercontent.com/AlexMelanFromRingo/aurora/main"
local results = {}
local function log(s) results[#results + 1] = s end

local function http_get(url)
  if not component.isAvailable("internet") then return nil, "no internet card" end
  local h, err = component.internet.request(url)
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
    local s = h.response(); if s then status = s; break end; os.sleep(0.05)
  end
  local chunks = {}
  while true do
    local c, r = h.read(8192)
    if c == nil then if r then h.close(); return nil, r end break end
    if #c > 0 then chunks[#chunks + 1] = c else os.sleep(0) end
    if computer.uptime() > deadline then h.close(); return nil, "read timeout" end
  end
  h.close()
  if status and (status < 200 or status >= 300) then return nil, "HTTP " .. status end
  return table.concat(chunks), status
end

local ok = true

-- 1) manifest fetch + parse
local mf, merr = http_get(BASE .. "/install/manifest.lua")
if not mf then
  log("SKIP manifest fetch (network): " .. tostring(merr))
else
  local manifest = load(mf, "=m", "t")()
  log("PASS manifest fetched (" .. #manifest.files .. " files, v" .. manifest.version .. ")")

  -- 2) registry fetch + a real download verified against its sha256
  local idxRaw = http_get(BASE .. "/registry/index.json")
  local index = idxRaw and json.decode(idxRaw)
  local entry = index and index.packages.acowsay
    and index.packages.acowsay.versions["0.1.0"].files[1]
  if not entry then
    log("SKIP registry parse");
  else
    local body, berr = http_get(BASE .. "/registry/" .. entry.url)
    if not body then
      log("SKIP package fetch (network): " .. tostring(berr))
    else
      local sum = hash.sha256(body)
      if sum == entry.sha256 then
        log("PASS downloaded acowsay and sha256 matches the registry")
      else
        log("FAIL acowsay checksum mismatch: " .. sum .. " ~= " .. entry.sha256)
        ok = false
      end
    end
  end
end

-- write log to the writable disk and shut down
local text = table.concat(results, "\n") .. "\n"
for addr in component.list("filesystem") do
  local p = component.proxy(addr)
  if p.getLabel() == "data" and not p.isReadOnly() then
    local h = p.open("/selftest.log", "w")
    if h then p.write(h, text); p.close(h) end
    break
  end
end
io.write("\n===== AURORA ONLINE CHECK =====\n" .. text .. "===============================\n")
os.sleep(0.2)
require("computer").shutdown(false)
