require("shim.oc")
local t = require("aurora.test")
local lexer = require("aurora.lua.lexer")
local minify = require("aurora.minify")
local transpile = require("aurora.transpile")
local bundle = require("aurora.bundle")
local lint = require("aurora.lint")

local function eval(src)
  local f = assert(load(src, "=t", "t"))
  return f()
end

-- ---- lexer -----------------------------------------------------------------

t.describe("lexer", function()
  t.it("tokenizes a basic statement", function()
    local toks = lexer.tokenize("local x = 1 + 2")
    t.expect(toks[1].type).toEqual("keyword")
    t.expect(toks[1].value).toEqual("local")
    t.expect(toks[2].type).toEqual("name")
    t.expect(toks[3].value).toEqual("=")
    t.expect(toks[4].type).toEqual("number")
    t.expect(toks[#toks].type).toEqual("eof")
  end)
  t.it("records byte spans for each token", function()
    local toks = lexer.tokenize("local x")
    t.expect(toks[1].pos).toEqual(1)
    t.expect(toks[1].stop).toEqual(5)   -- "local"
    t.expect(toks[2].pos).toEqual(7)    -- "x"
  end)
  t.it("handles long strings and comments", function()
    local toks = lexer.tokenize("--[[c]] x = [==[hi]==]", {comments = true})
    t.expect(toks[1].type).toEqual("comment")
    local hasLong = false
    for _, tok in ipairs(toks) do if tok.value == "[==[hi]==]" then hasLong = true end end
    t.expect(hasLong).toBeTruthy()
  end)
  t.it("handles numeric forms", function()
    local toks = lexer.tokenize("0xFF 3.14 1e3 0x1p4")
    t.expect(toks[1].value).toEqual("0xFF")
    t.expect(toks[2].value).toEqual("3.14")
    t.expect(toks[3].value).toEqual("1e3")
  end)
  t.it("tracks line numbers", function()
    local toks = lexer.tokenize("a\nb\nc")
    t.expect(toks[3].line).toEqual(3)
  end)
end)

-- ---- minify ----------------------------------------------------------------

t.describe("minify", function()
  t.it("removes comments and is shorter", function()
    local src = "-- a comment\nlocal x = 1 -- trailing\nreturn x"
    local out = minify(src)
    t.expect(out).toContain("local x=1")
    t.expect(#out < #src).toBeTruthy()
  end)
  t.it("preserves semantics (round-trip exec)", function()
    local src = "local a = 10\nlocal b = 3\nreturn a * b + 4"
    t.expect(eval(minify(src))).toEqual(34)
  end)
  t.it("keeps keyword boundaries", function()
    t.expect(eval(minify("return true and false"))).toBe(false)
    t.expect(eval(minify("return not nil"))).toBe(true)
  end)
  t.it("guards the 1..2 token hazard", function()
    t.expect(eval(minify("return 1 .. 2"))).toEqual("12")
    t.expect(eval(minify("return 3 == 3"))).toBe(true)
  end)
  t.it("preserves string contents", function()
    t.expect(eval(minify([[return "a  b -- not comment"]]))).toEqual("a  b -- not comment")
  end)
end)

-- ---- transpile -------------------------------------------------------------

t.describe("transpile (token-based)", function()
  t.it("expands a simple compound assignment", function()
    t.expect(transpile.run("count += 1")).toEqual("count = count +(1)")
  end)
  t.it("wraps the RHS to preserve precedence", function()
    -- a += b or c must be a + (b or c), never (a+b) or c
    local f = assert(load("local a=1\nlocal b,c=nil,9\n" ..
      transpile.run("a += b or c") .. "\nreturn a"))
    t.expect(f()).toEqual(10)
  end)
  t.it("handles table/index/dotted lvalues", function()
    local src = [==[
local t = {n = 1, list = {10}}
t.n += 4
t.list[1] *= 2
return t.n, t.list[1]]==]
    local a, b = eval(transpile.run(src))
    t.expect(a).toEqual(5)
    t.expect(b).toEqual(20)
  end)
  t.it("supports all operators incl. ..= and bitwise", function()
    local src = [[
local s = "a"
local x = 12
s ..= "b"
x //= 5
x |= 1
return s, x]]
    local s, x = eval(transpile.run(src))
    t.expect(s).toEqual("ab")
    t.expect(x).toEqual(3)   -- (12//5)=2, 2|1=3
  end)
  t.it("never touches += inside strings or comments", function()
    local out = transpile.run('local s = "x += y"  -- a += b\nreturn s')
    t.expect(out).toContain('"x += y"')
    t.expect(eval(out)).toEqual("x += y")
  end)
  t.it("handles a multiline RHS", function()
    local src = "local x = 1\nx +=\n  2 +\n  3\nreturn x"
    t.expect(eval(transpile.run(src))).toEqual(6)
  end)
  t.it("handles several compound statements (semicolon and adjacency)", function()
    local a, b = eval("local a,b=1,1\n" ..
      transpile.run("a += 2; b += 3") .. "\nreturn a, b")
    t.expect(a).toEqual(3)
    t.expect(b).toEqual(4)
  end)
  t.it("stops the RHS at a following statement with no separator", function()
    -- `a += 1 b = a` : RHS is just `1`, then a new statement
    local a, b = eval("local a,b=0,0\n" ..
      transpile.run("a += 1 b = a") .. "\nreturn a, b")
    t.expect(a).toEqual(1)
    t.expect(b).toEqual(1)
  end)
  t.it("passes ordinary code through unchanged", function()
    local src = "local x = a == b\nif x <= 3 then end\ny = -z\n"
    t.expect(transpile.run(src)).toEqual(src)
  end)
  t.it("round-trips a loop body", function()
    local src = [[
local s = 0
local t = {n = 1}
for i = 1, 4 do
  s += i
  t.n *= 2
end
return s, t.n]]
    local a, b = eval(transpile.run(src))
    t.expect(a).toEqual(10)
    t.expect(b).toEqual(16)
  end)
end)

-- ---- bundle ----------------------------------------------------------------

t.describe("bundle", function()
  local dir = "/tmp/aurora_bundle_" .. tostring(os.time())
  t.it("links a project's require graph", function()
    os.execute("mkdir -p '" .. dir .. "'")
    local fsx = require("aurora.fsx")
    fsx.writeAll(dir .. "/greet.lua", "local M = {}\nfunction M.hi(n) return 'hi ' .. n end\nreturn M\n")
    fsx.writeAll(dir .. "/main.lua", "local g = require('greet')\nreturn g.hi('aurora')\n")
    local out, info = bundle.build(dir .. "/main.lua")
    t.expect(out).toContain('package.preload["greet"]')
    t.expect(#info.modules).toEqual(1)
    -- the bundled file must run standalone (no filesystem access)
    t.expect(eval(out)).toEqual("hi aurora")
    os.execute("rm -rf '" .. dir .. "'")
  end)
end)

-- ---- lint ------------------------------------------------------------------

t.describe("lint", function()
  t.it("reports syntax errors with a line", function()
    local f = lint.check("local x =\n= 5")
    t.expect(#f >= 1).toBeTruthy()
    t.expect(f[1].severity).toEqual("error")
  end)
  t.it("flags implicit globals", function()
    local f = lint.check("local ok = 1\noops = 2\nreturn ok")
    local found
    for _, x in ipairs(f) do if x.message:find("implicit global 'oops'") then found = x end end
    t.expect(found).toBeTruthy()
    t.expect(found.line).toEqual(2)
  end)
  t.it("does not flag declared locals or known globals", function()
    local f = lint.check("local x = 1\nx = 2\nprint(x)\n")
    for _, x in ipairs(f) do
      t.expect(x.message:find("implicit global")).toBeNil()
    end
  end)
end)

os.exit((t.run({quiet = true})))
