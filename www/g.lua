--persistent global environment because OpenResty replaces the global
--environment on every request.
local g = {__index = _G}
g._G = g

function g.init_g()
	g.__index = getfenv(0)._G
	return g
end

return setmetatable(g, g)
