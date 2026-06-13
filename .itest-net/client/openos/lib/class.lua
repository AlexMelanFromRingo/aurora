-- class — minimal single-inheritance OOP for Lua 5.3.
--
--   local Animal = class("Animal")
--   function Animal:init(name) self.name = name end
--   function Animal:speak() return "..." end
--
--   local Dog = class("Dog", Animal)
--   function Dog:speak() return self.name .. " says woof" end
--
--   local d = Dog("Rex")           -- calls Dog:init -> Animal:init
--   d:speak(); d:isInstanceOf(Animal) -> true
local function class(name, base)
  checkArg(1, name, "string")
  checkArg(2, base, "table", "nil")

  local klass = {}
  klass.__index = klass
  klass.__name = name
  klass.__base = base

  function klass:isInstanceOf(other)
    local c = getmetatable(self)
    while c do
      if c == other then return true end
      c = c.__base
    end
    return false
  end

  -- default no-op constructor (subclasses override :init)
  if not klass.init then
    function klass:init(...) if base and base.init then base.init(self, ...) end end
  end

  return setmetatable(klass, {
    __index = base,
    __name = name,
    __call = function(_, ...)
      local obj = setmetatable({}, klass)
      obj:init(...)
      return obj
    end,
  })
end

return class
