-- aurora.sandbox — run untrusted Lua in a restricted environment. The sandbox
-- exposes only pure standard-library functions: no io, no filesystem, no
-- component/computer, no require/load/dofile (so sandboxed code cannot reach the
-- host or load more code), and only a read-only slice of os. An optional step
-- limit aborts runaway loops where the debug hook is available.
--
--   local sandbox = require("aurora.sandbox")
--   local ok, result = sandbox.run("return 2 + 2")          -- ok=true, 4
--   local ok, err = sandbox.run("os.remove('/x')")          -- ok=false (os.remove is nil)
--   sandbox.run(code, {env = {answer = 42}, steps = 1e6})
local sandbox = {}

-- a deliberately small, side-effect-free standard library
local function safeBuiltins()
  return {
    assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs,
    pcall = pcall, xpcall = xpcall, select = select, tonumber = tonumber,
    tostring = tostring, type = type, unpack = table.unpack,
    rawequal = rawequal, rawget = rawget, rawlen = rawlen, rawset = rawset,
    setmetatable = setmetatable, getmetatable = getmetatable,
    _VERSION = _VERSION,
    math = math, string = string, table = table, utf8 = utf8,
    coroutine = coroutine,
    -- read-only slice of os (no execute/remove/exit/setenv/rename)
    os = {time = os.time, clock = os.clock, date = os.date, difftime = os.difftime},
  }
end

-- newEnv(extra) -> a fresh sandbox environment, optionally augmented.
function sandbox.newEnv(extra)
  local env = safeBuiltins()
  if extra then for k, v in pairs(extra) do env[k] = v end end
  env._G = env          -- code that reaches for _G stays inside the sandbox
  return env
end

-- run(code, opts) -> ok, result-or-error
--   opts.env    extra globals to expose
--   opts.name   chunk name (for error messages)
--   opts.steps  abort after ~this many VM instructions (best-effort; needs debug)
--   opts.args   passed to the chunk as ...
function sandbox.run(code, opts)
  checkArg(1, code, "string")
  opts = opts or {}
  local env = sandbox.newEnv(opts.env)
  local chunk, err = load(code, opts.name or "=sandbox", "t", env)
  if not chunk then return false, "compile error: " .. tostring(err) end

  local hooked = false
  if opts.steps and type(debug) == "table" and debug.sethook then
    pcall(debug.sethook, function() error("sandbox: step limit exceeded", 2) end,
      "", math.floor(opts.steps))
    hooked = true
  end

  local results = table.pack(pcall(chunk, table.unpack(opts.args or {})))
  if hooked then pcall(debug.sethook) end

  local ok = results[1]
  if not ok then return false, results[2] end
  return true, table.unpack(results, 2, results.n)
end

-- eval(expr, opts) -> ok, value : convenience wrapper that returns an expression
function sandbox.eval(expr, opts)
  return sandbox.run("return (" .. expr .. ")", opts)
end

return sandbox
