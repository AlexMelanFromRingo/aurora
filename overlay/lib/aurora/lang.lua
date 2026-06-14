-- aurora.lang — lightweight i18n for Aurora. Messages live in flat key→string
-- catalogs (one per locale under /etc/locale/<code>.lua). `t(key, vars)` looks
-- the key up in the active locale, falls back to English, and finally returns
-- the key itself, substituting {name} placeholders from `vars`.
--
--   local lang = require("aurora.lang")
--   lang.setLocale("ru")
--   lang.t("locale.set", {code = "ru"})   -- "Язык установлен: ru"
local lang = {}

local catalogs = {}     -- code -> {key = string}
local current = "en"
local FALLBACK = "en"
lang.localePath = "/etc/aurora/locale"

-- register(code, tbl) — add/extend a catalog from a table.
function lang.register(code, tbl)
  checkArg(1, code, "string")
  checkArg(2, tbl, "table")
  local c = catalogs[code] or {}
  for k, v in pairs(tbl) do c[k] = v end
  catalogs[code] = c
end

function lang.setLocale(code) current = code end
function lang.getLocale() return current end
function lang.has(code) return catalogs[code] ~= nil end

function lang.locales()
  local out = {}
  for code in pairs(catalogs) do out[#out + 1] = code end
  table.sort(out)
  return out
end

local function lookup(code, key)
  local c = catalogs[code]
  return c and c[key]
end

-- t(key [, vars]) -> localized string
function lang.t(key, vars)
  checkArg(1, key, "string")
  local s = lookup(current, key) or lookup(FALLBACK, key) or key
  if type(vars) == "table" then
    s = s:gsub("{([%w_]+)}", function(n)
      local v = vars[n]
      return v ~= nil and tostring(v) or ("{" .. n .. "}")
    end)
  end
  return s
end

-- load(code, path) -> true | nil, err : load a catalog file (returns a table)
function lang.load(code, path)
  local chunk, err = loadfile(path)
  if not chunk then return nil, err end
  local ok, tbl = pcall(chunk)
  if not ok or type(tbl) ~= "table" then return nil, "invalid catalog: " .. path end
  lang.register(code, tbl)
  return true
end

-- loadDir(dir) — load every <code>.lua catalog in a directory.
function lang.loadDir(dir)
  local fs = require("filesystem")
  if not fs.exists(dir) then return 0 end
  local n = 0
  for name in fs.list(dir) do
    local code = name:match("^(%w+)%.lua$")
    if code and lang.load(code, dir .. "/" .. name) then n = n + 1 end
  end
  return n
end

-- persistence (mirrors aurora.theme)
function lang.persist(code)
  return require("aurora.fsx").atomicWrite(lang.localePath, code .. "\n")
end

function lang.applyPersisted()
  local fsx = require("aurora.fsx")
  if not fsx.exists(lang.localePath) then return false end
  local code = (fsx.readAll(lang.localePath) or ""):gsub("%s+$", "")
  if catalogs[code] then lang.setLocale(code); return true end
  return false
end

return lang
