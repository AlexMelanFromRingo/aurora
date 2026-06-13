-- awget — a safer wget. Unlike stock wget it checks the HTTP status (a 404 body
-- is an error, not your file), writes atomically (temp file, then rename, so a
-- failed transfer never leaves a half / wrong file), and can verify integrity.
--   awget [-f] [-q] [--sha256=HEX] <url> [filename]
local shell = require("shell")
local ahttp = require("ahttp")
local fsx = require("aurora.fsx")

local args, options = shell.parse(...)
if #args < 1 then
  io.write([[Usage: awget [-f] [-q] [--sha256=HEX] <url> [file]
  -f           overwrite an existing file
  -q           quiet (no progress)
  --sha256=H   verify the download against a sha256 hex digest
]])
  return
end

local url = args[1]
local filename = args[2]
if not filename then
  filename = url:gsub("[?#].*$", ""):match("([^/]+)$") or ""
end
if filename == "" then
  io.stderr:write("awget: could not infer a filename; please specify one\n")
  return nil, "missing filename"
end
filename = shell.resolve(filename)

if fsx.exists(filename) and not options.f then
  io.stderr:write("awget: file exists (use -f to overwrite): " .. filename .. "\n")
  return nil, "file exists"
end

if not options.q then io.write("Downloading " .. url .. " ... ") end
local lastPct
local ok, res = ahttp.download(url, filename, {
  sha256 = options.sha256,
  onProgress = (not options.q) and function(bytes)
    -- light progress: print a dot every ~8 KiB
    local pct = math.floor(bytes / 8192)
    if pct ~= lastPct then io.write("."); lastPct = pct end
  end or nil,
})
if not ok then
  if not options.q then io.write("failed\n") end
  io.stderr:write("awget: " .. tostring(res) .. "\n")
  return nil, res
end
if not options.q then
  io.write(string.format(" done\nSaved %d bytes to %s\n", #res.body, filename))
end
return true
