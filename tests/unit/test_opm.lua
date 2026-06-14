local shim = require("shim.oc")
local t = require("aurora.test")
local resolver = require("aurora.opm.resolver")
local db = require("aurora.opm.db")
local registry = require("aurora.opm.registry")
local opm = require("aurora.opm")
local hash = require("aurora.hash")

-- ---- resolver --------------------------------------------------------------

t.describe("opm resolver", function()
  local reg = {packages = {
    a = {versions = {["1.0.0"] = {deps = {b = "^1.0.0"}, files = {}}}},
    b = {versions = {["1.0.0"] = {deps = {}, files = {}},
                     ["1.2.0"] = {deps = {}, files = {}}}},
    cyc1 = {versions = {["1.0.0"] = {deps = {cyc2 = "*"}, files = {}}}},
    cyc2 = {versions = {["1.0.0"] = {deps = {cyc1 = "*"}, files = {}}}},
  }}
  t.it("orders dependencies first and picks best version", function()
    local order = resolver.resolve(reg, {{name = "a", constraint = "*"}})
    t.expect(#order).toEqual(2)
    t.expect(order[1].name).toEqual("b")
    t.expect(order[1].version).toEqual("1.2.0")
    t.expect(order[2].name).toEqual("a")
  end)
  t.it("errors on unknown package", function()
    local order, err = resolver.resolve(reg, {{name = "ghost"}})
    t.expect(order).toBeNil()
    t.expect(err).toContain("unknown package")
  end)
  t.it("detects dependency cycles", function()
    local order, err = resolver.resolve(reg, {{name = "cyc1"}})
    t.expect(order).toBeNil()
    t.expect(err).toContain("cycle")
  end)
  t.it("errors when no version satisfies", function()
    local order, err = resolver.resolve(reg, {{name = "b", constraint = ">=9.0.0"}})
    t.expect(order).toBeNil()
    t.expect(err).toContain("satisfies")
  end)
end)

-- ---- db --------------------------------------------------------------------

t.describe("opm db", function()
  -- NB: describe bodies run at registration; per-test state is set inside it().
  local root = "/tmp/opm_db_test_" .. tostring(os.time())

  t.it("records, gets and lists", function()
    db.root = root
    os.execute("rm -rf '" .. root .. "'")
    db.record({name = "foo", version = "1.0.0", files = {"/x/foo.lua"}})
    db.record({name = "bar", version = "2.1.0", files = {}})
    t.expect(db.get("foo").version).toEqual("1.0.0")
    t.expect(db.isInstalled("bar")).toBeTruthy()
    t.expect(db.isInstalled("nope")).toBeFalsy()
    local list = db.list()
    t.expect(#list).toEqual(2)
    t.expect(list[1].name).toEqual("bar")  -- sorted
  end)
  t.it("forgets", function()
    db.root = root
    db.forget("foo")
    t.expect(db.isInstalled("foo")).toBeFalsy()
    os.execute("rm -rf '" .. root .. "'")
  end)
end)

-- ---- full install/remove flow (mocked registry + http) ---------------------

t.describe("opm install/remove flow", function()
  local root = "/tmp/opm_flow_" .. tostring(os.time())
  os.execute("rm -rf '" .. root .. "'")
  db.root = root .. "/etc/opm"

  local fileBody = "return 'aurora-demo'\n"
  local sum = hash.sha256(fileBody)
  local target = root .. "/lib/demo.lua"

  -- a synthetic two-package registry: demo depends on libdemo
  local libBody = "return 42\n"
  local libSum = hash.sha256(libBody)
  local libTarget = root .. "/lib/libdemo.lua"

  local synthetic = {packages = {
    demo = {description = "demo pkg", versions = {["1.0.0"] = {
      deps = {libdemo = "^1.0.0"},
      files = {{path = target, abs = "http://reg/demo.lua", sha256 = sum}},
    }}},
    libdemo = {description = "demo dep", versions = {["1.0.0"] = {
      deps = {},
      files = {{path = libTarget, abs = "http://reg/libdemo.lua", sha256 = libSum}},
    }}},
  }}
  -- Activate the mocked registry + internet + db root. Done inside the first
  -- it() (which runs during run(), not at registration) and persists for the
  -- rest of the describe because these are module-level fields.
  local function activate()
    registry.build = function() return synthetic end
    db.root = root .. "/etc/opm"
    shim.clear()
    shim.set("internet", {
      request = function(url)
        local body = ({["http://reg/demo.lua"] = fileBody,
                       ["http://reg/libdemo.lua"] = libBody})[url] or ""
        local sent = false
        return {
          finishConnect = function() return true end,
          response = function() return 200, "OK", {} end,
          read = function() if not sent then sent = true; return body end end,
          close = function() end,
        }
      end,
    })
  end

  t.it("installs a package with its dependency", function()
    activate()
    local out = {}
    local ok, err = opm.install({"demo"}, {out = function(s) out[#out + 1] = s end})
    t.expect(ok).toBeTruthy()
    t.expect(require("aurora.fsx").readAll(target)).toEqual(fileBody)
    t.expect(require("aurora.fsx").readAll(libTarget)).toEqual(libBody)
    t.expect(db.get("demo").version).toEqual("1.0.0")
    t.expect(db.get("libdemo").version).toEqual("1.0.0")
    -- dependency installed before dependent
    t.expect(table.concat(out)).toContain("libdemo")
  end)

  t.it("is idempotent on reinstall", function()
    local out = {}
    opm.install({"demo"}, {out = function(s) out[#out + 1] = s end})
    t.expect(table.concat(out)).toContain("already installed")
  end)

  t.it("refuses to remove a depended-on package", function()
    local ok, err = opm.remove({"libdemo"}, {})
    t.expect(ok).toBeNil()
    t.expect(err).toContain("required by")
  end)

  t.it("removes packages and their files", function()
    opm.remove({"demo"}, {})
    opm.remove({"libdemo"}, {})
    t.expect(require("aurora.fsx").exists(target)).toBeFalsy()
    t.expect(db.isInstalled("demo")).toBeFalsy()
    os.execute("rm -rf '" .. root .. "'")
  end)
end)

t.describe("opm freeze/restore", function()
  local root = "/tmp/opm_freeze_" .. tostring(os.time())
  local body = "return 1\n"
  local sum = hash.sha256(body)
  local target = root .. "/lib/x.lua"
  local synthetic = {packages = {
    xpkg = {description = "x", versions = {["1.0.0"] =
      {deps = {}, files = {{path = target, abs = "http://reg/x.lua", sha256 = sum}}}}},
  }}
  local function activate()
    registry.build = function() return synthetic end
    db.root = root .. "/etc/opm"
    shim.clear()
    shim.set("internet", {request = function()
      local sent = false
      return {finishConnect = function() return true end,
              response = function() return 200, "OK", {} end,
              read = function() if not sent then sent = true; return body end end,
              close = function() end}
    end})
  end

  t.it("freezes installed packages to a lockfile", function()
    activate()
    os.execute("rm -rf '" .. root .. "'")
    db.record({name = "a", version = "1.2.3", files = {}})
    db.record({name = "b", version = "0.1.0", files = {}})
    local lock = opm.freeze()
    t.expect(lock.aurora_lock).toEqual(1)
    t.expect(#lock.packages).toEqual(2)
    t.expect(opm.freezeJSON()).toContain("aurora_lock")
  end)

  t.it("restores exact versions from a lockfile", function()
    activate()
    os.execute("rm -rf '" .. root .. "'")
    local ok = opm.restore({aurora_lock = 1, packages = {{name = "xpkg", version = "1.0.0"}}},
      {out = function() end})
    t.expect(ok).toBeTruthy()
    t.expect(db.get("xpkg").version).toEqual("1.0.0")
    os.execute("rm -rf '" .. root .. "'")
  end)

  t.it("round-trips freeze -> JSON -> restore", function()
    activate()
    local json = require("json")
    local lock = {aurora_lock = 1, packages = {{name = "xpkg", version = "1.0.0"}}}
    local ok = opm.restore(json.encode(lock), {out = function() end})
    t.expect(ok).toBeTruthy()
    os.execute("rm -rf '" .. root .. "'")
  end)

  t.it("rejects malformed lockfiles", function()
    t.expect(select(2, opm.restore("not json{", {}))).toContain("invalid lockfile")
    t.expect(select(2, opm.restore({foo = 1}, {}))).toContain("not an Aurora lockfile")
  end)
end)

t.describe("opm outdated/why", function()
  local root = "/tmp/opm_oq_" .. tostring(os.time())
  local twoVersions = {packages = {demo = {versions = {["1.0.0"] = {}, ["2.0.0"] = {}}}}}

  t.it("lists packages with a newer version available", function()
    db.root = root
    os.execute("rm -rf '" .. root .. "'")
    db.record({name = "demo", version = "1.0.0", files = {}})
    registry.build = function() return twoVersions end
    local list = opm.outdated()
    t.expect(#list).toEqual(1)
    t.expect(list[1].name).toEqual("demo")
    t.expect(list[1].current).toEqual("1.0.0")
    t.expect(list[1].latest).toEqual("2.0.0")
  end)

  t.it("reports nothing when everything is current", function()
    db.root = root
    os.execute("rm -rf '" .. root .. "'")
    db.record({name = "demo", version = "2.0.0", files = {}})
    registry.build = function() return twoVersions end
    t.expect(opm.outdated()).toEqual({})
  end)

  t.it("explains reverse dependencies (why)", function()
    db.root = root
    os.execute("rm -rf '" .. root .. "'")
    db.record({name = "app", version = "1.0.0", deps = {lib = "^1.0.0"}, files = {}})
    db.record({name = "lib", version = "1.0.0", deps = {}, files = {}})
    local why = opm.why("lib")
    t.expect(#why).toEqual(1)
    t.expect(why[1].name).toEqual("app")
    t.expect(why[1].constraint).toEqual("^1.0.0")
    t.expect(opm.why("nobody")).toEqual({})
    os.execute("rm -rf '" .. root .. "'")
  end)
end)

os.exit((t.run({quiet = true})))
