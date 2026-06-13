-- aurora.test — a tiny xUnit-style test framework, pure Lua, runs in-VM and on
-- the host. Powers Aurora's own test suite and is shipped for user programs.
--
--   local t = require("aurora.test")
--   t.describe("math", function()
--     t.it("adds", function() t.expect(1 + 1).toEqual(2) end)
--   end)
--   os.exit(t.run())   -- 0 on success, 1 on any failure
local test = {}

local suites = {}
local stack = {}      -- current describe path
local cases = {}      -- flat list of {name=, fn=}

function test.describe(name, fn)
  checkArg(1, name, "string")
  checkArg(2, fn, "function")
  stack[#stack + 1] = name
  fn()
  stack[#stack] = nil
end

function test.it(name, fn)
  checkArg(1, name, "string")
  checkArg(2, fn, "function")
  local prefix = #stack > 0 and (table.concat(stack, " › ") .. " › ") or ""
  cases[#cases + 1] = {name = prefix .. name, fn = fn}
end

-- ---- expectations ---------------------------------------------------------

local function fmt(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) == "table" then
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(v)
end

local function deepEqual(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function test.expect(value)
  local m = {}
  function m.toEqual(expected)
    if not deepEqual(value, expected) then
      error("expected " .. fmt(value) .. " to equal " .. fmt(expected), 2)
    end
  end
  function m.toBe(expected)
    if value ~= expected then
      error("expected " .. fmt(value) .. " to be (identity) " .. fmt(expected), 2)
    end
  end
  function m.toBeTruthy()
    if not value then error("expected truthy, got " .. fmt(value), 2) end
  end
  function m.toBeFalsy()
    if value then error("expected falsy, got " .. fmt(value), 2) end
  end
  function m.toBeNil()
    if value ~= nil then error("expected nil, got " .. fmt(value), 2) end
  end
  function m.toContain(sub)
    if type(value) == "string" then
      if not string.find(value, sub, 1, true) then
        error("expected " .. fmt(value) .. " to contain " .. fmt(sub), 2)
      end
    elseif type(value) == "table" then
      for _, v in pairs(value) do if v == sub then return end end
      error("expected table to contain " .. fmt(sub), 2)
    else
      error("toContain: unsupported type " .. type(value), 2)
    end
  end
  function m.toBeCloseTo(expected, eps)
    eps = eps or 1e-9
    if math.abs(value - expected) > eps then
      error("expected " .. fmt(value) .. " ≈ " .. fmt(expected), 2)
    end
  end
  function m.toThrow(pattern)
    -- value is expected to be a function here
    local ok, err = pcall(value)
    if ok then error("expected function to throw", 2) end
    if pattern and not string.find(tostring(err), pattern, 1, true) then
      error("expected error to contain " .. fmt(pattern) .. ", got " .. fmt(err), 2)
    end
  end
  return m
end

-- ---- runner ---------------------------------------------------------------

function test.reset()
  suites = {}
  for i = #stack, 1, -1 do stack[i] = nil end
  for i = #cases, 1, -1 do cases[i] = nil end
end

-- run(opts): opts.quiet suppresses per-case PASS lines. Returns exit code
-- (0 ok / 1 fail), and (passed, failed) counts.
function test.run(opts)
  opts = opts or {}
  local write = opts.write or io.write
  local passed, failed = 0, 0
  local failures = {}
  for _, c in ipairs(cases) do
    local ok, err = xpcall(c.fn, function(e) return e end)
    if ok then
      passed = passed + 1
      if not opts.quiet then write("  ok   " .. c.name .. "\n") end
    else
      failed = failed + 1
      failures[#failures + 1] = {name = c.name, err = err}
      write("  FAIL " .. c.name .. "\n")
    end
  end
  if failed > 0 then
    write("\nFailures:\n")
    for _, f in ipairs(failures) do
      write("  ✗ " .. f.name .. "\n      " .. tostring(f.err) .. "\n")
    end
  end
  write(string.format("\n%d passed, %d failed (%d total)\n",
    passed, failed, passed + failed))
  local code = failed == 0 and 0 or 1
  test.reset()
  return code, passed, failed
end

return test
