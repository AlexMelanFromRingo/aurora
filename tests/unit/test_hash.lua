require("shim.oc")
local t = require("aurora.test")
local hash = require("aurora.hash")

-- Known SHA-256 vectors (FIPS 180-4 / common references).
t.describe("sha256", function()
  t.it("hashes empty string", function()
    t.expect(hash.sha256("")).toEqual(
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  end)
  t.it("hashes 'abc'", function()
    t.expect(hash.sha256("abc")).toEqual(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  end)
  t.it("hashes a 56-byte block boundary string", function()
    t.expect(hash.sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
      .toEqual("248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
  end)
  t.it("hashes a long string (multi-block)", function()
    t.expect(hash.sha256(string.rep("a", 1000))).toEqual(
      "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
  end)
end)

t.describe("crc32", function()
  t.it("matches known vectors", function()
    t.expect(hash.crc32("")).toEqual("00000000")
    t.expect(hash.crc32("123456789")).toEqual("cbf43926")
  end)
end)

os.exit((t.run({quiet = true})))
