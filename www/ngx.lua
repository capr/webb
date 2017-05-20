
--overwrite these because they are only appended to package.c/path by default.
package.path = os.getenv'LUA_PATH'
package.cpath = os.getenv'LUA_CPATH'

--cached config function.
local conf = {}
local null = conf
local function config(var, default)
	local val = conf[var]
	if val == nil then
		val = os.getenv(var:upper())
		if val == nil then
			val = ngx.var[var]
			if val == nil then
				val = default
			end
		end
		conf[var] = val == nil and null or val
	end
	if val == null then
		return nil
	else
		return val
	end
end

--global S() for internationalizing strings.
local S_ = {}
local function S(name, val)
	if val and not S_[name] then
		S_[name] = val
	end
	return S_[name]
end

--global error handler: log or print the error.
local function try_call(func, ...)
	local function pass(ok, ...)
		if ok then return ... end
		local err = ...
		ngx.log(ngx.ERR, err)
		if config('hide_errors', false) then
			err = 'Internal error'
		end
		ngx.status = 500
		ngx.header.content_type = 'text/plain'
		ngx.say(err)
		ngx.exit(0)
	end
	return pass(xpcall(func, debug.traceback, ...))
end

local g = require'g'
g.config = config
g.S = S
require'config' --load static config

local main = require'main'
try_call(function()
	g.__index = _G
	main()
end)
