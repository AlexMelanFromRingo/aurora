local shim = require("shim.oc")
local t = require("aurora.test")
local fsx = require("aurora.fsx")

-- ---- fsx -------------------------------------------------------------------

t.describe("fsx paths", function()
  t.it("normalizes", function()
    t.expect(fsx.normalize("/a/b/../c")).toEqual("/a/c")
    t.expect(fsx.normalize("a/./b/")).toEqual("a/b")
    t.expect(fsx.normalize("/a/../../x")).toEqual("/x")
  end)
  t.it("joins", function()
    t.expect(fsx.join("/a", "b", "c")).toEqual("/a/b/c")
  end)
  t.it("basename/dirname/ext", function()
    t.expect(fsx.basename("/a/b/c.lua")).toEqual("c.lua")
    t.expect(fsx.dirname("/a/b/c.lua")).toEqual("/a/b")
    t.expect(fsx.dirname("/x")).toEqual("/")
    t.expect(fsx.ext("/a/b/c.lua")).toEqual("lua")
  end)
end)

t.describe("fsx atomic I/O", function()
  local p = "/tmp/aurora_fsx_test.txt"
  t.it("writes and reads atomically", function()
    os.remove(p)
    t.expect(fsx.atomicWrite(p, "hello\nworld")).toBeTruthy()
    t.expect(fsx.readAll(p)).toEqual("hello\nworld")
    -- no leftover temp file
    t.expect(fsx.readAll(p .. ".tmp")).toBeNil()
    os.remove(p)
  end)
end)

-- ---- ahttp -----------------------------------------------------------------

local ahttp = require("ahttp")

local function fakeInternet(handler)
  return {
    request = function(url, body, headers, method)
      local r = handler(url, body, headers, method)
      local sent = false
      return {
        finishConnect = function() return true end,
        response = function() return r.status, r.message, r.headers or {} end,
        read = function()
          if not sent then sent = true; return r.body or "" end
          return nil
        end,
        close = function() end,
      }
    end,
  }
end

t.describe("ahttp", function()
  t.it("GETs and reports 2xx ok", function()
    shim.clear()
    shim.set("internet", fakeInternet(function(url)
      return {status = 200, message = "OK", body = "PONG"}
    end))
    local res = ahttp.get("https://x/ping")
    t.expect(res.ok).toBe(true)
    t.expect(res.status).toEqual(200)
    t.expect(res.body).toEqual("PONG")
  end)
  t.it("flags non-2xx as not ok", function()
    shim.clear()
    shim.set("internet", fakeInternet(function() return {status = 404, message = "Not Found", body = "nope"} end))
    local res = ahttp.get("https://x/missing")
    t.expect(res.ok).toBe(false)
    t.expect(res.status).toEqual(404)
  end)
  t.it("decodes JSON", function()
    shim.clear()
    shim.set("internet", fakeInternet(function() return {status = 200, body = '{"a":1,"b":[2,3]}'} end))
    local data = ahttp.getJSON("https://x/data.json")
    t.expect(data).toEqual({a = 1, b = {2, 3}})
  end)
  t.it("errors without an internet card", function()
    shim.clear()
    local res, err = ahttp.get("https://x")
    t.expect(res).toBeNil()
    t.expect(err).toContain("internet card")
  end)
  t.it("downloads and verifies sha256", function()
    shim.clear()
    shim.set("internet", fakeInternet(function() return {status = 200, body = "abc"} end))
    local p = "/tmp/aurora_dl_test"
    os.remove(p)
    -- sha256("abc")
    local sum = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    t.expect(ahttp.download("https://x/f", p, {sha256 = sum})).toBeTruthy()
    t.expect(fsx.readAll(p)).toEqual("abc")
    os.remove(p)
  end)
  t.it("rejects a checksum mismatch", function()
    shim.clear()
    shim.set("internet", fakeInternet(function() return {status = 200, body = "abc"} end))
    local ok, err = ahttp.download("https://x/f", "/tmp/aurora_dl_bad", {sha256 = "deadbeef"})
    t.expect(ok).toBeNil()
    t.expect(err).toContain("checksum mismatch")
  end)
end)

os.exit((t.run({quiet = true})))
