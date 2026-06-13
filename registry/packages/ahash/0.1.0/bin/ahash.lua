-- ahash — print the sha256 (or crc32) of files or stdin. Handy for verifying
-- downloads. Uses Aurora's aurora.hash (data-card accelerated when present).
--   ahash <file> ...        sha256 of each file
--   ahash --crc32 <file>    crc32 instead
--   ahash                   hash stdin
local shell = require("shell")
local hash = require("aurora.hash")

local args, options = shell.parse(...)
local algo = options.crc32 and "crc32" or "sha256"

local function emit(data, name)
  io.write(hash[algo](data) .. "  " .. name .. "\n")
end

if #args == 0 then
  emit(io.read("*a") or "", "-")
else
  for _, arg in ipairs(args) do
    local f, err = io.open(shell.resolve(arg), "rb")
    if not f then
      io.stderr:write("ahash: " .. arg .. ": " .. tostring(err) .. "\n")
    else
      local data = f:read("*a"); f:close()
      emit(data or "", arg)
    end
  end
end
