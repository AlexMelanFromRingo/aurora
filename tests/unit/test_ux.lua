require("shim.oc")
local t = require("aurora.test")
local prompt = require("aurora.prompt")
local theme = require("aurora.theme")
local sysinfo = require("aurora.sysinfo")

t.describe("prompt.build", function()
  t.it("includes placeholders and symbol", function()
    local p = prompt.build({symbol = "# "})
    t.expect(p).toContain("$HOSTNAME")
    t.expect(p).toContain("$PWD")
    t.expect(p).toContain("# ")
  end)
  t.it("honors twoLine", function()
    t.expect(prompt.build({twoLine = true})).toContain("\n")
  end)
  t.it("can omit hostname/cwd", function()
    local p = prompt.build({hostname = false, cwd = true})
    t.expect(p:find("$HOSTNAME", 1, true)).toBeNil()
    t.expect(p).toContain("$PWD")
  end)
  t.it("resets attributes", function()
    t.expect(prompt.build({})).toContain("\27[0m")
  end)
end)

t.describe("theme", function()
  t.it("lists named themes", function()
    local names = theme.list()
    t.expect(names).toContain("default")
    t.expect(names).toContain("matrix")
  end)
  t.it("exposes ps1 and ls_colors per theme", function()
    local th = theme.get("default")
    t.expect(th.ps1).toContain("$PWD")
    t.expect(th.ls_colors).toContain("di=")
  end)
  t.it("apply sets PS1 and LS_COLORS env", function()
    local seen = {}
    local realSet = os.setenv
    os.setenv = function(k, v) seen[k] = v end
    t.expect(theme.apply("matrix")).toBeTruthy()
    os.setenv = realSet
    t.expect(seen.PS1).toContain("\n")          -- matrix is two-line
    t.expect(seen.LS_COLORS).toContain("1;32")
  end)
  t.it("rejects unknown themes", function()
    local ok, err = theme.apply("does-not-exist")
    t.expect(ok).toBeNil()
    t.expect(err).toContain("unknown theme")
  end)
end)

t.describe("sysinfo", function()
  local fakeEnv = {
    osversion = "OpenOS 1.7.7",
    computer = {
      totalMemory = function() return 1048576 end,
      freeMemory = function() return 524288 end,
      uptime = function() return 3725 end,
      address = function() return "abcdef12-0000-0000-0000-000000000000" end,
    },
    component = {
      list = function()
        local items = {a = "gpu", b = "screen", c = "filesystem", d = "filesystem"}
        return pairs(items)
      end,
    },
  }
  t.it("collects memory, uptime and components", function()
    local info = sysinfo.collect(fakeEnv)
    t.expect(info.totalMem).toEqual(1048576)
    t.expect(info.usedMem).toEqual(524288)
    t.expect(info.components.filesystem).toEqual(2)
    t.expect(info.components.gpu).toEqual(1)
  end)
  t.it("renders lines with humanized values", function()
    local lines = sysinfo.render(sysinfo.collect(fakeEnv))
    local blob = table.concat(lines, "\n")
    t.expect(blob).toContain("OpenOS 1.7.7")
    t.expect(blob).toContain("1h 2m")        -- 3725s
    t.expect(blob).toContain("512.0K / 1.0M")
  end)
  t.it("uses localized labels when provided", function()
    local lines = sysinfo.render(sysinfo.collect(fakeEnv),
      {labels = {os = "ОС", memory = "Память"}})
    local blob = table.concat(lines, "\n")
    t.expect(blob).toContain("ОС")
    t.expect(blob).toContain("Память")
    t.expect(blob).toContain("Hardware")     -- unspecified label keeps default
  end)
end)

os.exit((t.run({quiet = true})))
