require("shim.oc")
local t = require("aurora.test")
local strict = require("aurora.strict")
local optimize = require("aurora.optimize")

t.describe("strict globals", function()
  t.it("blocks reads of undeclared globals", function()
    local e = {}
    strict.enable(e)
    t.expect(function() return e.missing end).toThrow("undeclared")
  end)
  t.it("allows declared names", function()
    local e = {}
    strict.enable(e)
    strict.declare("ok", e)
    -- reading a declared-but-unset name returns nil without raising
    local v = e.ok
    t.expect(v).toBeNil()
  end)
  t.it("blocks accidental non-function globals but allows functions", function()
    local e = {}
    strict.enable(e)
    t.expect(function() e.count = 5 end).toThrow("undeclared")
    e.helper = function() return 1 end   -- functions are allowed
    t.expect(e.helper()).toEqual(1)
  end)
end)

t.describe("strict safe_remove", function()
  t.it("identifies protected paths", function()
    t.expect(strict.isProtected("/bin")).toBe(true)
    t.expect(strict.isProtected("/bin/")).toBe(true)
    t.expect(strict.isProtected("/home/user/x")).toBe(false)
  end)
  t.it("refuses to remove protected paths without force", function()
    local ok, err = strict.safe_remove("/lib")
    t.expect(ok).toBeNil()
    t.expect(err).toContain("protected")
  end)
end)

t.describe("optimize", function()
  t.it("memoizes single-arg functions", function()
    local calls = 0
    local f = optimize.memoize(function(x) calls = calls + 1; return x * 2 end)
    t.expect(f(21)).toEqual(42)
    t.expect(f(21)).toEqual(42)
    t.expect(calls).toEqual(1)
  end)
  t.it("warm() skips already-loaded modules", function()
    package.loaded["fake_warm_mod"] = {}
    t.expect(optimize.warm({"fake_warm_mod"})).toEqual(0)
    package.loaded["fake_warm_mod"] = nil
  end)
  t.it("slurp reads a whole file", function()
    local p = "/tmp/aurora_slurp_test"
    require("aurora.fsx").writeAll(p, string.rep("x", 5000))
    t.expect(#optimize.slurp(p, 1024)).toEqual(5000)
    os.remove(p)
  end)
end)

os.exit((t.run({quiet = true})))
