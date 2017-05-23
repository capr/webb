
--overwrite these because they are only appended to package.c/path by default.
package.path = os.getenv'LUA_PATH'
package.cpath = os.getenv'LUA_CPATH'

--global error handler: log and print the error and exit with 500.
local function try_call(func, ...)
	local function pass(ok, ...)
		if ok then return ... end
		local err = ...
		ngx.log(ngx.ERR, err)
		if ngx.var.hide_errors then --can't use config() here
			err = 'Internal error'
		end
		ngx.status = 500
		ngx.header.content_type = 'text/plain'
		ngx.say(err)
		ngx.exit(0)
	end
	return pass(xpcall(func, debug.traceback, ...))
end

try_call(function()
	local handle_request = require'main'
	handle_request()
end)
