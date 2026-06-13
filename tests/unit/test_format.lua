require("shim.oc")
local t = require("aurora.test")
local gen = require("aurora.lua.gen")
local parser = require("aurora.lua.parser")

local function fmt(s) return (assert(gen.format(s))) end

t.describe("formatter output", function()
  t.it("indents block bodies with two spaces", function()
    t.expect(fmt("if x then return 1 end")).toEqual("if x then\n  return 1\nend\n")
  end)
  t.it("spaces binary operators", function()
    t.expect(fmt("local a=1+2*3")).toEqual("local a = 1 + 2 * 3\n")
  end)
  t.it("adds parens only where precedence needs them", function()
    t.expect(fmt("return (1+2)*3")).toEqual("return (1 + 2) * 3\n")
    t.expect(fmt("return 1+2*3")).toEqual("return 1 + 2 * 3\n")
  end)
  t.it("keeps ^ right-associative without redundant parens", function()
    t.expect(fmt("return 2^3^4")).toEqual("return 2 ^ 3 ^ 4\n")
    t.expect(fmt("return (2^3)^4")).toEqual("return (2 ^ 3) ^ 4\n")
  end)
  t.it("preserves method syntax", function()
    t.expect(fmt("function a:b(x) return x end"))
      .toEqual("function a:b(x)\n  return x\nend\n")
  end)
  t.it("renders short tables inline, preserving key style", function()
    -- name-shorthand keys stay shorthand; explicit string-literal keys are kept
    t.expect(fmt("local t={a=1, 2}")).toEqual("local t = {a = 1, 2}\n")
    t.expect(fmt("local t={[ 'a' ]=1, 2}")).toEqual("local t = {['a'] = 1, 2}\n")
  end)
  t.it("formats numeric for and local function", function()
    t.expect(fmt("for i=1,3 do print(i) end"))
      .toEqual("for i = 1, 3 do\n  print(i)\nend\n")
  end)
end)

t.describe("formatter correctness", function()
  local IGNORE = {line = true, pos = true, stop = true}
  local function astEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not IGNORE[k] and not astEqual(v, b[k]) then return false end end
    for k in pairs(b) do if not IGNORE[k] and a[k] == nil then return false end end
    return true
  end

  local samples = {
    "local x = 1\nreturn x + 2",
    "for k, v in pairs(t) do print(k, v) end",
    "local f = function(a, ...) return a end",
    "while not done do x = x - 1 if x < 0 then break end end",
    "local t = {a = 1, b = {1, 2, 3}, f = function() return 9 end}",
    "repeat y = y + 1 until y > 10",
    "return a and b or c .. d",
  }

  t.it("preserves the AST (parse(format(x)) == parse(x))", function()
    for _, s in ipairs(samples) do
      local a1 = parser.parse(s)
      local a2 = parser.parse(fmt(s))
      t.expect(astEqual(a1, a2)).toBeTruthy()
    end
  end)

  t.it("is idempotent (format(format(x)) == format(x))", function()
    for _, s in ipairs(samples) do
      local once = fmt(s)
      t.expect(fmt(once)).toEqual(once)
    end
  end)

  t.it("reports a parse error for malformed input", function()
    local out, err = gen.format("local = =")
    t.expect(out).toBeNil()
    t.expect(err).toContain("parse:")
  end)
end)

os.exit((t.run({quiet = true})))
