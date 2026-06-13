require("shim.oc")
local t = require("aurora.test")
local hash = require("aurora.hash")

local ROOT = os.getenv("AURORA_ROOT") or "."

local function readAll(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local d = f:read("*a"); f:close(); return d
end

t.describe("install manifest", function()
  local manifest_src = readAll(ROOT .. "/install/manifest.lua")
  local manifest = manifest_src and assert(load(manifest_src))()

  t.it("exists and is well-formed", function()
    t.expect(manifest).toBeTruthy()
    t.expect(type(manifest.files)).toEqual("table")
    t.expect(#manifest.files > 0).toBeTruthy()
    t.expect(manifest.version).toBeTruthy()
  end)

  t.it("references files that all exist with matching sha256", function()
    for _, e in ipairs(manifest.files) do
      local body = readAll(ROOT .. "/" .. e.src)
      t.expect(body).toBeTruthy()
      if body then t.expect(hash.sha256(body)).toEqual(e.sha256) end
    end
  end)

  t.it("includes hash.lua so the installer can self-bootstrap verification", function()
    local found
    for _, e in ipairs(manifest.files) do
      if e.dst == "/lib/aurora/hash.lua" then found = true end
    end
    t.expect(found).toBeTruthy()
  end)

  t.it("maps overlay/patch sources to absolute system paths", function()
    for _, e in ipairs(manifest.files) do
      t.expect(e.dst:sub(1, 1)).toEqual("/")
      t.expect(e.kind == "overlay" or e.kind == "patch").toBeTruthy()
    end
  end)

  t.it("carries the wget and transfer patches", function()
    local dsts = {}
    for _, e in ipairs(manifest.files) do dsts[e.dst] = e.kind end
    t.expect(dsts["/bin/wget.lua"]).toEqual("patch")
    t.expect(dsts["/lib/tools/transfer.lua"]).toEqual("patch")
  end)
end)

os.exit((t.run({quiet = true})))
