-- wget (Aurora-patched) — drop-in compatible with stock OpenOS wget, but:
--   * checks the HTTP status (stock wget saves a 404/500 error body as if it
--     were your file — this version treats non-2xx as a failure),
--   * writes atomically (download to a temp file, then rename, so an
--     interrupted transfer never leaves a partial/garbage file), and
--   * adds --sha256=HEX integrity verification.
-- The CLI, defaults and function return values match stock wget, so existing
-- scripts (including `require`-style callers) keep working unchanged.
local shell = require("shell")
local text = require("text")

local args, options = shell.parse(...)
options.q = options.q or options.Q

if #args < 1 then
  io.write("Usage: wget [-fq] [--sha256=HEX] <url> [<filename>]\n")
  io.write(" -f: Force overwriting existing files.\n")
  io.write(" -q: Quiet mode - no status messages.\n")
  io.write(" -Q: Superquiet mode - no error messages.\n")
  io.write(" --sha256=HEX: verify the download against a sha256 digest.\n")
  return
end

local url = text.trim(args[1])
local filename = args[2]
if not filename then
  filename = url
  local index = string.find(filename, "/[^/]*$")
  if index then filename = string.sub(filename, index + 1) end
  index = string.find(filename, "?", 1, true)
  if index then filename = string.sub(filename, 1, index - 1) end
end
filename = text.trim(filename)
if filename == "" then
  if not options.Q then
    io.stderr:write("could not infer filename, please specify one")
  end
  return nil, "missing target filename"
end
filename = shell.resolve(filename)

if require("filesystem").exists(filename) and not options.f then
  if not options.Q then io.stderr:write("file already exists") end
  return nil, "file already exists"
end

if not options.q then io.write("Downloading... ") end

-- ahttp.download performs the status check, atomic temp+rename and optional
-- sha256 verification for us.
local ahttp = require("ahttp")
local ok, res = ahttp.download(url, filename, {sha256 = options.sha256})
if not ok then
  if not options.q then io.write("failed.\n") end
  if not options.Q then io.stderr:write("HTTP request failed: " .. tostring(res) .. "\n") end
  return nil, res
end

if not options.q then
  io.write("success.\n")
  io.write("Saved data to " .. filename .. "\n")
end
return true
