-- aurora.strict — opt-in hardening for scripts. `strict.enable()` makes reads
-- and writes of undeclared globals raise an error (catches typos and accidental
-- globals, like Lua's classic strict.lua but scoped to the calling chunk's
-- environment). `strict.safe_remove` is a guard that refuses obviously
-- dangerous recursive deletes.
local strict = {}

local declared = setmetatable({}, {__mode = "k"})

-- enable([env]) — install strict global access on env (default _G of caller).
function strict.enable(env)
  env = env or _G
  if declared[env] then return end
  declared[env] = {}
  local known = declared[env]
  -- seed with everything currently present so existing globals stay readable
  for k in pairs(env) do known[k] = true end
  setmetatable(env, {
    __newindex = function(t, k, v)
      if not known[k] then
        if type(v) ~= "function" and not k:match("^_") then
          error("strict: assignment to undeclared global '" .. tostring(k) .. "'", 2)
        end
      end
      known[k] = true
      rawset(t, k, v)
    end,
    __index = function(_, k)
      if not known[k] then
        error("strict: read of undeclared global '" .. tostring(k) .. "'", 2)
      end
    end,
  })
end

-- declare(name) — explicitly allow a global before first use under strict mode.
function strict.declare(name, env)
  env = env or _G
  if declared[env] then declared[env][name] = true end
end

-- A path is "dangerous" to recursively remove if it is root or a top-level
-- system directory. safe_remove refuses these unless force is set.
local PROTECTED = {["/"] = true, ["/bin"] = true, ["/lib"] = true,
  ["/etc"] = true, ["/boot"] = true, ["/usr"] = true, ["/home"] = true}

function strict.isProtected(path)
  local fsx = require("aurora.fsx")
  return PROTECTED[fsx.normalize(path)] == true
end

function strict.safe_remove(path, force)
  if not force and strict.isProtected(path) then
    return nil, "refusing to remove protected path '" .. path .. "' (force required)"
  end
  return require("filesystem").remove(path)
end

return strict
