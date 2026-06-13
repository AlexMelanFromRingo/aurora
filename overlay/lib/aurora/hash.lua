-- aurora.hash — SHA-256 and CRC-32 for integrity checks (opm package verify).
-- Uses the OpenComputers data card when present (fast, native), otherwise a
-- correct pure-Lua SHA-256 (Lua 5.3 native bitwise ops). API returns lowercase
-- hex strings so results are comparable regardless of backend.
local hash = {}

local function tohex(bin)
  return (bin:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

-- ---- pure-Lua SHA-256 ------------------------------------------------------

local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

local MASK = 0xffffffff
local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & MASK end

local function sha256_lua(msg)
  local h0,h1,h2,h3 = 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a
  local h4,h5,h6,h7 = 0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19

  local len = #msg
  msg = msg .. "\128"
  while #msg % 64 ~= 56 do msg = msg .. "\0" end
  -- 64-bit big-endian bit length
  local bits = len * 8
  local lenbytes = {}
  for i = 8, 1, -1 do
    lenbytes[i] = string.char(bits & 0xff)
    bits = bits >> 8
  end
  msg = msg .. table.concat(lenbytes)

  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do
      local a, b, c, d = msg:byte(chunk + i * 4, chunk + i * 4 + 3)
      w[i + 1] = ((a << 24) | (b << 16) | (c << 8) | d) & MASK
    end
    for i = 17, 64 do
      local s0 = rrot(w[i-15], 7) ~ rrot(w[i-15], 18) ~ (w[i-15] >> 3)
      local s1 = rrot(w[i-2], 17) ~ rrot(w[i-2], 19) ~ (w[i-2] >> 10)
      w[i] = (w[i-16] + s0 + w[i-7] + s1) & MASK
    end

    local a,b,c,d,e,f,g,h = h0,h1,h2,h3,h4,h5,h6,h7
    for i = 1, 64 do
      local S1 = rrot(e, 6) ~ rrot(e, 11) ~ rrot(e, 25)
      local ch = (e & f) ~ ((~e & MASK) & g)
      local t1 = (h + S1 + ch + K[i] + w[i]) & MASK
      local S0 = rrot(a, 2) ~ rrot(a, 13) ~ rrot(a, 22)
      local maj = (a & b) ~ (a & c) ~ (b & c)
      local t2 = (S0 + maj) & MASK
      h = g; g = f; f = e; e = (d + t1) & MASK
      d = c; c = b; b = a; a = (t1 + t2) & MASK
    end
    h0=(h0+a)&MASK; h1=(h1+b)&MASK; h2=(h2+c)&MASK; h3=(h3+d)&MASK
    h4=(h4+e)&MASK; h5=(h5+f)&MASK; h6=(h6+g)&MASK; h7=(h7+h)&MASK
  end

  return string.format("%08x%08x%08x%08x%08x%08x%08x%08x",
    h0,h1,h2,h3,h4,h5,h6,h7)
end

-- ---- public API ------------------------------------------------------------

-- sha256(data) -> lowercase hex. Prefers the data card if available.
function hash.sha256(data)
  checkArg(1, data, "string")
  local ok, component = pcall(require, "component")
  if ok and component.isAvailable and component.isAvailable("data") then
    local okv, bin = pcall(function() return component.data.sha256(data) end)
    if okv and type(bin) == "string" then return tohex(bin) end
  end
  return sha256_lua(data)
end

-- always use the pure-Lua path (testing / determinism)
function hash.sha256_pure(data) return sha256_lua(data) end

-- crc32 (pure Lua, table-driven)
local crc_table
local function build_crc()
  crc_table = {}
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
      if c & 1 == 1 then c = 0xedb88320 ~ (c >> 1) else c = c >> 1 end
    end
    crc_table[i] = c & MASK
  end
end

function hash.crc32(data)
  checkArg(1, data, "string")
  if not crc_table then build_crc() end
  local crc = MASK
  for i = 1, #data do
    crc = crc_table[(crc ~ data:byte(i)) & 0xff] ~ (crc >> 8)
  end
  return string.format("%08x", (crc ~ MASK) & MASK)
end

return hash
