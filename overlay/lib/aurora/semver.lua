-- aurora.semver — semantic-version parsing, comparison and constraint matching.
-- Supports MAJOR.MINOR.PATCH with optional -prerelease. Constraints understood
-- by `satisfies`: exact ("1.2.3"), "*"/"" (any), ">=", ">", "<=", "<", "=",
-- caret "^1.2.3" (compatible, no major bump), tilde "~1.2.3" (no minor bump).
local semver = {}

local function parse(v)
  checkArg(1, v, "string")
  local core, pre = v:match("^v?(%d+%.%d+%.%d+)%-?(.*)$")
  if not core then
    -- allow short forms 1 or 1.2
    local a, b, c = v:match("^v?(%d+)%.?(%d*)%.?(%d*)")
    if not a then return nil, "invalid version: " .. v end
    return {major = tonumber(a), minor = tonumber(b) or 0,
            patch = tonumber(c) or 0, pre = ""}
  end
  local maj, min, pat = core:match("(%d+)%.(%d+)%.(%d+)")
  return {major = tonumber(maj), minor = tonumber(min),
          patch = tonumber(pat), pre = pre or ""}
end
semver.parse = parse

-- compare(a, b) -> -1 | 0 | 1
function semver.compare(a, b)
  local pa = type(a) == "table" and a or assert(parse(a))
  local pb = type(b) == "table" and b or assert(parse(b))
  for _, k in ipairs({"major", "minor", "patch"}) do
    if pa[k] ~= pb[k] then return pa[k] < pb[k] and -1 or 1 end
  end
  -- a version with a prerelease is lower than one without
  if pa.pre == pb.pre then return 0 end
  if pa.pre == "" then return 1 end
  if pb.pre == "" then return -1 end
  return pa.pre < pb.pre and -1 or 1
end

function semver.eq(a, b) return semver.compare(a, b) == 0 end
function semver.lt(a, b) return semver.compare(a, b) < 0 end
function semver.gt(a, b) return semver.compare(a, b) > 0 end

-- satisfies(version, constraint) -> boolean
function semver.satisfies(version, constraint)
  checkArg(2, constraint, "string")
  constraint = constraint:match("^%s*(.-)%s*$")
  if constraint == "" or constraint == "*" then return true end
  local v = assert(parse(version))

  local op, rest = constraint:match("^([<>=~^]*)%s*(.+)$")
  rest = rest or constraint
  local c = parse(rest)
  if not c then return false end

  if op == "" or op == "=" then
    return semver.compare(v, c) == 0
  elseif op == ">=" then return semver.compare(v, c) >= 0
  elseif op == ">"  then return semver.compare(v, c) > 0
  elseif op == "<=" then return semver.compare(v, c) <= 0
  elseif op == "<"  then return semver.compare(v, c) < 0
  elseif op == "^" then
    -- >= c  and  < (next major) ; for 0.x, caret locks the minor too
    if semver.compare(v, c) < 0 then return false end
    if c.major > 0 then return v.major == c.major
    elseif c.minor > 0 then return v.major == 0 and v.minor == c.minor
    else return v.major == 0 and v.minor == 0 and v.patch == c.patch end
  elseif op == "~" then
    -- >= c  and  < (next minor)
    if semver.compare(v, c) < 0 then return false end
    return v.major == c.major and v.minor == c.minor
  end
  return false
end

-- max(list-of-version-strings) -> highest, or nil
function semver.max(list)
  local best
  for _, v in ipairs(list) do
    if not best or semver.compare(v, best) > 0 then best = v end
  end
  return best
end

-- best(list, constraint) -> highest version satisfying constraint
function semver.best(list, constraint)
  local best
  for _, v in ipairs(list) do
    if semver.satisfies(v, constraint) then
      if not best or semver.compare(v, best) > 0 then best = v end
    end
  end
  return best
end

return semver
