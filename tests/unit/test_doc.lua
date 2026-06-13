require("shim.oc")
local t = require("aurora.test")
local doc = require("aurora.doc")

t.describe("doc.extract", function()
  t.it("finds functions of every form with signatures", function()
    local src = [[
local M = {}
function M.add(a, b) return a + b end
function M:method(x) return x end
local function helper(...) end
M.assigned = function(y) return y end
return M]]
    local api = doc.extract(src)
    local byName = {}
    for _, it in ipairs(api.items) do byName[it.name] = it end
    t.expect(byName["M.add"].signature).toEqual("M.add(a, b)")
    t.expect(byName["M:method"].signature).toEqual("M:method(x)")  -- self dropped
    t.expect(byName["helper"].signature).toEqual("helper(...)")
    t.expect(byName["M.assigned"].signature).toEqual("M.assigned(y)")
  end)

  t.it("attaches an immediately-preceding comment as the doc", function()
    local src = [[
-- adds two numbers
-- (second line)
local function add(a, b) return a + b end
return add]]
    local api = doc.extract(src)
    t.expect(api.items[1].doc).toEqual("adds two numbers\n(second line)")
  end)

  t.it("does not attach a comment separated by a blank line", function()
    local src = "-- far away\n\nlocal function f() end\nreturn f"
    local api = doc.extract(src)
    t.expect(api.items[1].doc).toBeNil()
  end)

  t.it("returns nil + error on a parse failure", function()
    local api, err = doc.extract("local = =")
    t.expect(api).toBeNil()
    t.expect(err).toContain("parse:")
  end)
end)

t.describe("doc.markdown", function()
  t.it("renders signatures and docs", function()
    local src = "-- greet someone\nfunction hello(name) end"
    local md = doc.markdown(src, {title = "greeter"})
    t.expect(md).toContain("# greeter")
    t.expect(md).toContain("### `hello(name)`")
    t.expect(md).toContain("greet someone")
  end)
  t.it("notes when there are no functions", function()
    t.expect(doc.markdown("local x = 1\nreturn x")).toContain("No public functions")
  end)
end)

os.exit((t.run({quiet = true})))
