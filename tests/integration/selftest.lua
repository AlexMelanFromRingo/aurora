-- Aurora in-emulator self-test. Runs inside a real OpenOS boot (under ocvm),
-- exercising the libraries against the genuine OpenComputers environment — real
-- `filesystem`, the data card's hardware sha256, real `component.list()`, real
-- os.setenv — then writes /selftest.log and shuts the machine down. The host
-- harness reads the log and fails the build on any "FAIL " line.
local results = {}
local pass, fail = 0, 0

local function check(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
    results[#results + 1] = "PASS " .. name
  else
    fail = fail + 1
    results[#results + 1] = "FAIL " .. name .. " :: " .. tostring(err)
  end
end

local function assertEq(a, b, msg)
  if a ~= b then error((msg or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
end

-- ---- core libraries load and work under real OpenOS ------------------------

check("json round-trips", function()
  local json = require("json")
  local v = {name = "aurora", nums = {1, 2, 3}, on = true}
  assert(type(json.decode(json.encode(v))) == "table")
  assertEq(json.decode(json.encode(v)).name, "aurora")
end)

check("semver constraints", function()
  local s = require("aurora.semver")
  assert(s.satisfies("1.4.0", "^1.2.0"))
  assert(not s.satisfies("2.0.0", "^1.2.0"))
end)

check("hash sha256 (pure path)", function()
  local h = require("aurora.hash")
  assertEq(h.sha256_pure("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
end)

check("hash sha256 (data card path)", function()
  local component = require("component")
  if not component.isAvailable("data") then error("no data card to test") end
  local h = require("aurora.hash")
  -- the public sha256 prefers the data card; must match the known vector
  assertEq(h.sha256("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
end)

check("minify preserves semantics", function()
  local minify = require("aurora.minify")
  local out = minify("local a = 21\nreturn a * 2 -- comment")
  assertEq(load(out)(), 42)
end)

check("transpile compound assignment", function()
  local tp = require("aurora.transpile")
  local out = tp.run("local x = 1\nx += 4\nreturn x")
  assertEq(load(out)(), 5)
end)

check("opm resolver orders deps", function()
  local r = require("aurora.opm.resolver")
  local reg = {packages = {
    a = {versions = {["1.0.0"] = {deps = {b = "*"}, files = {}}}},
    b = {versions = {["1.0.0"] = {deps = {}, files = {}}}},
  }}
  local order = r.resolve(reg, {{name = "a"}})
  assertEq(order[1].name, "b")
  assertEq(order[2].name, "a")
end)

check("lint flags implicit global", function()
  local lint = require("aurora.lint")
  local f = lint.check("oops = 1\n")
  assert(#f >= 1)
end)

check("parser builds an AST", function()
  local parser = require("aurora.lua.parser")
  local ast = parser.parse("local a = 1 + 2 * 3\nreturn a")
  assert(ast.tag == "Block")
  assert(ast.stmts[1].tag == "Local")
end)

check("analyzer finds undefined names", function()
  local analyze = require("aurora.analyze")
  local f = analyze.check("return nonexistent_thing")
  assert(#f == 1 and f[1].message:find("undefined name"))
  assertEq(#analyze.check("local x = 1\nreturn x"), 0, "clean code has no findings")
end)

check("formatter is meaning-preserving and idempotent", function()
  local gen = require("aurora.lua.gen")
  local out = gen.format("if x then return 1+2*3 end")
  assertEq(out, "if x then\n  return 1 + 2 * 3\nend\n")
  assertEq(gen.format(out), out, "format is idempotent")
end)

check("doc generator extracts public API", function()
  local doc = require("aurora.doc")
  local md = doc.markdown("-- greets\nfunction M.hi(name) end", {publicOnly = true})
  assert(md:find("M.hi(name)", 1, true) and md:find("greets", 1, true))
end)

check("sandbox isolates untrusted code", function()
  local sandbox = require("aurora.sandbox")
  local ok, r = sandbox.run("return 6 * 7")
  assert(ok and r == 42)
  -- no access to the system from inside the sandbox
  assertEq(select(2, sandbox.eval("os.remove")), nil, "os.remove must be hidden")
  assertEq(select(2, sandbox.eval("require")), nil, "require must be hidden")
end)

check("watch detects content changes (real fs)", function()
  local watch = require("aurora.watch")
  local fsx = require("aurora.fsx")
  local p = "/tmp/aurora_itest_watch"
  fsx.writeAll(p, "a")
  local s1 = watch.snapshot({p})
  fsx.writeAll(p, "b")
  assertEq(#watch.changed(s1, watch.snapshot({p})), 1, "edit detected")
  require("filesystem").remove(p)
end)

-- ---- things that need the real OpenOS environment --------------------------

check("fsx atomic write to real fs", function()
  local fsx = require("aurora.fsx")
  local p = "/tmp/aurora_itest.txt"
  assert(fsx.atomicWrite(p, "hello"))
  assertEq(fsx.readAll(p), "hello")
  require("filesystem").remove(p)
end)

check("opm db records to real fs", function()
  local db = require("aurora.opm.db")
  db.root = "/tmp/aurora_itest_opm"
  db.record({name = "demo", version = "1.2.3", files = {}})
  assertEq(db.get("demo").version, "1.2.3")
end)

check("sysinfo collects real components", function()
  local sysinfo = require("aurora.sysinfo")
  local info = sysinfo.collect({
    computer = require("computer"),
    component = require("component"),
    osversion = _OSVERSION,
  })
  assert(info.totalMem > 0)
  assert(info.components.gpu and info.components.gpu >= 1)
end)

check("theme applies to real env", function()
  local theme = require("aurora.theme")
  assert(theme.apply("matrix"))
  assert(os.getenv("PS1"):find("\n", 1, true))   -- matrix is two-line
end)

check("anet wire protocol", function()
  local anet = require("anet")
  assertEq(anet.decode(anet.encode({x = 5})).x, 5)
end)

check("ahttp present with internet card", function()
  local ahttp = require("ahttp")
  assert(type(ahttp.get) == "function")
  assert(require("component").isAvailable("internet"))
end)

check("strict guards undeclared globals", function()
  local strict = require("aurora.strict")
  local e = {}
  strict.enable(e)
  assert(not pcall(function() return e.nope end))
end)

-- ---- write the log and shut down -------------------------------------------

local summary = string.format("\n%d passed, %d failed (%d total)\n", pass, fail, pass + fail)
results[#results + 1] = summary

local log = table.concat(results, "\n")

-- The boot filesystem is read-only, so write the log to the writable disk
-- (the filesystem labelled "data") via its component proxy.
local function writeLog(text)
  local component = require("component")
  for addr in component.list("filesystem") do
    local proxy = component.proxy(addr)
    if proxy.getLabel() == "data" and not proxy.isReadOnly() then
      local h = proxy.open("/selftest.log", "w")
      if h then proxy.write(h, text); proxy.close(h); return true end
    end
  end
  -- fallback: maybe root is writable after all
  local f = io.open("/selftest.log", "w")
  if f then f:write(text); f:close(); return true end
  return false
end
writeLog(log)

-- also echo to the screen for interactive runs
io.write("\n===== AURORA SELFTEST =====\n")
io.write(log)
io.write("===========================\n")

os.sleep(0.2)
require("computer").shutdown(false)
