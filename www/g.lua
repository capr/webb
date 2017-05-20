--persistent global environment because OpenResty replaces the global
--environment on every request. This means g.__index must be replaced
--on every request.
local g = {__index = _G}
g._G = g
return setmetatable(g, g)
