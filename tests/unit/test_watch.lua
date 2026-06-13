require("shim.oc")
local t = require("aurora.test")
local watch = require("aurora.watch")

t.describe("watch.snapshot/changed", function()
  t.it("snapshots stamps via an injected stat", function()
    local snap = watch.snapshot({"a", "b"}, function(p) return p .. "1" end)
    t.expect(snap).toEqual({a = "a1", b = "b1"})
  end)
  t.it("detects changed stamps", function()
    local old = {a = "1", b = "1"}
    local new = {a = "2", b = "1"}
    t.expect(watch.changed(old, new)).toEqual({"a"})
  end)
  t.it("reports nothing when unchanged", function()
    t.expect(watch.changed({a = "1"}, {a = "1"})).toEqual({})
  end)
  t.it("detects newly appearing paths", function()
    t.expect(watch.changed({}, {a = "1", b = "2"})).toEqual({"a", "b"})
  end)
end)

t.describe("watch.loop", function()
  t.it("fires onChange on a detected content change", function()
    -- stat sequence for path 'f': v1 (prev), v1 (tick1 no change), v2 (tick2 change)
    local seq, i = {"v1", "v1", "v2"}, 0
    local stat = function() i = i + 1; return seq[i] or "v2" end
    local fired = {}
    watch.loop({"f"}, function(p) fired[#fired + 1] = p end,
      {stat = stat, ticks = 2, interval = 0})
    t.expect(fired).toEqual({"f"})
  end)
  t.it("runFirst fires immediately for every path", function()
    local fired = {}
    watch.loop({"a", "b"}, function(p) fired[#fired + 1] = p end,
      {stat = function() return "x" end, ticks = 1, runFirst = true, interval = 0})
    -- both fired at startup, nothing changed afterwards
    t.expect(fired).toEqual({"a", "b"})
  end)
  t.it("default stamp (crc32) detects real edits", function()
    local p = "/tmp/aurora_watch_test"
    require("aurora.fsx").writeAll(p, "one")
    local s1 = watch.snapshot({p})
    require("aurora.fsx").writeAll(p, "two")
    local s2 = watch.snapshot({p})
    t.expect(watch.changed(s1, s2)).toEqual({p})
    os.remove(p)
  end)
end)

os.exit((t.run({quiet = true})))
