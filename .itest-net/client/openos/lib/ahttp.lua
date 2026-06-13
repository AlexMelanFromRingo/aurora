-- ahttp — an ergonomic HTTP client for OpenComputers' internet card.
--
--   local ahttp = require("ahttp")
--   local res = ahttp.get("https://example.com/x.json")
--   if res.ok then print(res.status, #res.body) end
--   ahttp.download(url, "/tmp/x", {sha256 = "...", onProgress = fn})
--
-- Returns a response table {ok, status, message, headers, body} or (nil, err).
-- Uses the low-level component.internet directly so behavior is predictable and
-- the library is unit-testable against a mocked component.
local ahttp = {}

local component = require("component")
local computer = require("computer")

local DEFAULT_TIMEOUT = 15
local DEFAULT_UA = "Aurora-ahttp/1.0 (OpenComputers)"

local function inet()
  if not component.isAvailable("internet") then
    return nil, "no internet card available"
  end
  return component.internet
end

-- request(method, url, opts) -> response | nil, err
function ahttp.request(method, url, opts)
  checkArg(1, method, "string")
  checkArg(2, url, "string")
  opts = opts or {}
  local card, err = inet()
  if not card then return nil, err end

  local headers = {}
  for k, v in pairs(opts.headers or {}) do headers[k] = v end
  headers["User-Agent"] = headers["User-Agent"] or DEFAULT_UA

  local timeout = opts.timeout or DEFAULT_TIMEOUT
  local handle, rerr = card.request(url, opts.body, headers, method)
  if not handle then return nil, rerr or "request rejected" end

  -- 1) wait for the connection to establish
  local deadline = computer.uptime() + timeout
  while true do
    local ok, ferr = handle.finishConnect()
    if ok then break end
    if ok == nil and ferr then handle.close(); return nil, ferr end
    if computer.uptime() > deadline then
      handle.close(); return nil, "connection timed out"
    end
    os.sleep(0.05)
  end

  -- 2) obtain status line + headers (may lag a tick behind connect)
  local status, message, rheaders
  while computer.uptime() <= deadline do
    local s, m, h = handle.response()
    if s then status, message, rheaders = s, m, h; break end
    os.sleep(0.05)
  end

  -- 3) stream the body
  local chunks, total = {}, 0
  while true do
    local chunk, reason = handle.read(math.maxinteger or 8192)
    if chunk == nil then
      if reason then handle.close(); return nil, reason end
      break -- eof
    elseif #chunk > 0 then
      chunks[#chunks + 1] = chunk
      total = total + #chunk
      if opts.onProgress then opts.onProgress(total) end
    else
      os.sleep(0)
    end
    if computer.uptime() > deadline then
      handle.close(); return nil, "read timed out"
    end
  end
  handle.close()

  local body = table.concat(chunks)
  return {
    ok = (status or 0) >= 200 and (status or 0) < 300,
    status = status or 0,
    message = message,
    headers = rheaders or {},
    body = body,
  }
end

function ahttp.get(url, opts) return ahttp.request("GET", url, opts) end

function ahttp.post(url, body, opts)
  opts = opts or {}
  opts.body = body
  return ahttp.request("POST", url, opts)
end

-- getJSON(url) -> decoded, response | nil, err
function ahttp.getJSON(url, opts)
  local res, err = ahttp.get(url, opts)
  if not res then return nil, err end
  if not res.ok then return nil, "HTTP " .. res.status .. " " .. tostring(res.message) end
  local ok, decoded = pcall(require("json").decode, res.body)
  if not ok then return nil, "invalid JSON: " .. tostring(decoded) end
  return decoded, res
end

-- download(url, path, opts) -> true | nil, err
-- opts.sha256 (hex) verifies integrity; opts.onProgress(bytes) for UI.
-- Writes atomically: temp file, verify, then rename into place.
function ahttp.download(url, path, opts)
  checkArg(1, url, "string")
  checkArg(2, path, "string")
  opts = opts or {}
  local res, err = ahttp.get(url, {onProgress = opts.onProgress, timeout = opts.timeout})
  if not res then return nil, err end
  if not res.ok then return nil, "HTTP " .. res.status .. " " .. tostring(res.message) end

  if opts.sha256 then
    local sum = require("aurora.hash").sha256(res.body)
    if sum:lower() ~= opts.sha256:lower() then
      return nil, string.format("checksum mismatch: got %s, expected %s", sum, opts.sha256)
    end
  end

  local fsx = require("aurora.fsx")
  fsx.ensureParent(path)
  local ok, werr = fsx.atomicWrite(path, res.body)
  if not ok then return nil, werr end
  return true, res
end

return ahttp
