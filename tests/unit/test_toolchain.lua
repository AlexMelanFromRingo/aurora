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
    t.expect(toks[1]).toEqual({type = "keyword", value = "local", line = 1})
    t.expect(toks[2].type).toEqual("name")
    t.expect(toks[3].value).toEqual("=")
    t.expect(toks[4].type).toEqual("number")
    t.expect(toks[#toks].type).toEqual("eof")
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

t.describe("transpile", function()
  t.it("expands compound assignment", function()
    t.expect(transpile.line("count += 1")).toEqual("count = count + (1)")
    t.expect(transpile.line("  t[i] ..= \"x\"")).toEqual("  t[i] = t[i] .. (\"x\")")
    t.expect(transpile.line("a.b.c //= 2")).toEqual("a.b.c = a.b.c // (2)")
  end)
  t.it("leaves ordinary lines untouched", function()
    t.expect(transpile.line("local x = a == b")).toEqual("local x = a == b")
    t.expect(transpile.line("if x <= 3 then")).toEqual("if x <= 3 then")
    t.expect(transpile.line("y = -z")).toEqual("y = -z")
  end)
  t.it("round-trips to correct behavior", function()
    local src = [[
local s = 0
local t = {}
t.n = 1
for i = 1, 4 do
  s += i
  t.n *= 2
end
return s, t.n]]
    local a, b = eval(transpile.run(src))
    t.expect(a).toEqual(10)   -- 1+2+3+4
    t.expect(b).toEqual(16)   -- 1*2^4
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
