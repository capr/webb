--Webb Framework
--Written by Cosmin Apreutesei. Public Domain.

glue = require'glue'

--cached config function -----------------------------------------------------

local conf = {}
local null = conf
function config(var, default)
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

--separate config function for internationalizing strings.
local S_ = {}
function S(name, val)
	if val and not S_[name] then
		S_[name] = val
	end
	return S_[name] or name
end

--per-request environment ----------------------------------------------------

--per-request memoization.
local NIL = {}
local function enc(v) if v == nil then return NIL else return v end end
local function dec(v) if v == NIL then return nil else return v end end
function once(f, clear_cache, ...)
	if clear_cache then
		local t = ngx.ctx[f]
		if t then
			if select(1, ...) == 0 then
				t = {}
				ngx.ctx[f] = t
			else
				t[enc(k)] = nil
			end
		end
	else
		return function(k)
			local t = ngx.ctx[f]
			if not t then
				t = {}
				ngx.ctx[f] = t
			end
			local v = dec(t[enc(k)])
			if v == nil then
				v = f(k)
				t[enc(k)] = enc(v)
			end
			return v
		end
	end
end

--per-request shared environment to use in all app code.
function env(t)
	local env = ngx.ctx.env
	if not env then
		env = {__index = _G}
		setmetatable(env, env)
		ngx.ctx.env = env
	end
	if t then
		t.__index = env
		return setmetatable(t, t)
	else
		return env
	end
end

--request API ----------------------------------------------------------------

local _method = once(function()
	return ngx.req.get_method()
end)

function method(which)
	if which then
		return _method():lower() == which:lower()
	else
		return _method():lower()
	end
end

local _headers = once(function()
	return ngx.req.get_headers()
end)

function headers(h)
	if h then
		return _headers()[h]
	else
		return _headers()
	end
end

local _args = once(function()
	local t = {}
	for s in glue.gsplit(ngx.var.uri, '/', 2, true) do
		t[#t+1] = ngx.unescape_uri(s)
	end
	glue.update(t, ngx.req.get_uri_args()) --add in the query args
	return t
end)

function args(v)
	if v then
		return _args()[v]
	else
		return _args()
	end
end

local _post_args = once(function()
	if not method'post' then return end
	ngx.req.read_body()
	return ngx.req.get_post_args()
end)

function post(v)
	if v then
		local t = _post_args()
		return t and t[v]
	else
		return _post_args()
	end
end

function absurl(path)
	path = path or ''
	return (config'base_url' or ngx.var.scheme..'://'..ngx.var.host) .. path
end

function domain()
	return ngx.var.host
end

function email(user)
	return string.format('%s@%s', assert(user), domain())
end

function client_ip()
	return ngx.var.remote_addr
end

function lang()
	return args'lang' or config('lang', 'en')
end

--arg validation

function uint_arg(s)
	local n = s and tonumber(s:match'(%d+)$')
	assert(not n or n >= 0)
	return n
end

function str_arg(s)
	s = glue.trim(s or '')
	return s ~= '' and s or nil
end

function enum_arg(s, ...)
	for i=1,select('#',...) do
		if s == select(i,...) then
			return s
		end
	end
	return nil
end

function list_arg(s, arg_f)
	local s = str_arg(s)
	if not s then return nil end
	arg_f = arg_f or str_arg
	local t = {}
	for s in glue.gsplit(s, ',') do
		table.insert(t, arg_f(s))
	end
	return t
end

function id_arg(id, s)
	if not id then return nil end
	if type(id) == 'string' then --decode
		return tonumber((id:gsub('%-.*$', '')))
	else --encode
		s = s or ''
		return tostring(id)..'-'..s:gsub('[ ]', '-'):lower() --TODO: strip all non-url chars!
	end
end

--output API -----------------------------------------------------------------

function out_buffering()
	return ngx.ctx.outfunc ~= nil
end

local function default_outfunc(s)
	ngx.print(s)
end

local function outbuf(t)
	t = t or {}
	return function(s)
		if s then
			t[#t+1] = s
		else --flush it
			return table.concat(t)
		end
	end
end

function push_out(f)
	ngx.ctx.outfunc = f or outbuf()
	if not ngx.ctx.outfuncs then
		ngx.ctx.outfuncs = {}
	end
	table.insert(ngx.ctx.outfuncs, ngx.ctx.outfunc)
end

function pop_out()
	if not ngx.ctx.outfunc then return end
	local s = ngx.ctx.outfunc()
	local outfuncs = ngx.ctx.outfuncs
	table.remove(outfuncs)
	ngx.ctx.outfunc = outfuncs[#outfuncs]
	return s
end

function out(s)
	local outfunc = ngx.ctx.outfunc or default_outfunc
	if s == nil then return end
	outfunc(tostring(s))
end

local function pass(...)
	return pop_out(), ...
end
function record(out_content, ...)
	push_out()
	return pass(out_content(...))
end

function html(str)
	if not str then return '' end
	return tostring(str):gsub('[&"<>\\]', function(c)
		if c == '&' then return '&amp;'
		elseif c == '"' then return '\"'
		elseif c == '\\' then return '\\\\'
		elseif c == '<' then return '&lt;'
		elseif c == '>' then return '&gt;'
		else return c end
	end)
end

function setheader(name, val)
	if out_buffering() then
		return
	end
	ngx.header[name] = val
end

function print(...)
	local out = default_outfunc
	ngx.header.content_type = 'text/plain'
	local n = select('#', ...)
	for i=1,n do
		out(tostring((select(i, ...))))
		if i < n then
			out'\t'
		end
	end
	out'\n'
end

--response API ---------------------------------------------------------------

local function http_error(code, msg)
	local t = {http_code = code, message = msg}
	function t:__tostring()
		return tostring(code)..(msg and ' '..tostring(msg) or '')
	end
	setmetatable(t, t)
	error(t, 2)
end

redirect = ngx.redirect

function check(ret, err)
	if ret then return ret end
	http_error(404, err)
end

function allow(ret, err)
	if ret then return ret, err end
	http_error(403, err)
end

function push_out_etag()
	if not headers'if_none_match' then return end
	push_out()
end

function pop_out_etag()
	local etag0 = headers'if_none_match'
	if not etag0 then return end
	local s = pop_out()
	local etag = ngx.md5(s)
	if etag0 == etag then
		http_error(304)
	end
	out(s)
end

function check_etag(s)
	if out_buffering() or not method'get' then
		return
	end
	local etag0 = headers'if_none_match'
	local etag = ngx.md5(s)
	if etag0 == etag then
		http_error(304)
	end
	--send etag to client as weak etag so that nginx gzip filter still apply
	setheader('ETag', 'W/'..etag)
end

--json API -------------------------------------------------------------------

local cjson = require'cjson'
cjson.encode_sparse_array(false, 0, 0) --encode all sparse arrays

function json(v)
	if type(v) == 'table' then
		return cjson.encode(v)
	elseif type(v) == 'string' then
		return cjson.decode(v)
	else
		error('invalid arg '..type(v))
	end
end

--filesystem API -------------------------------------------------------------

function basepath(file)
	return assert(config'webb_dir') .. '/' .. file
end

local lfs = require'lfs'

function filepath(file) --file -> path (if exists)
	if file:find('..', 1, true) then return end --trying to escape
	local path = basepath(file)
	if not lfs.attributes(path, 'mode') then return end
	return path
end

function readfile(file)
	return assert(glue.readfile(basepath(file)))
end

--TODO: outfile(file) which skips the accumulation/concat
--so it can work with very large files

--mustache templates ---------------------------------------------------------

local hige = require'hige'

function render_string(s, data)
	return hige.render(s, data or env())
end

function render(file, data)
	return render_string(readfile(file), data)
end

--LuaPages templates ---------------------------------------------------------

local lp = require'lp'

local function compile_string(s, chunkname)
	lp.setoutfunc'out'
	local f = lp.compile(s, chunkname)
	return function(_env, ...)
		setfenv(f, _env or env())
		f(...)
	end
end

local compile = glue.memoize(function(file)
	return compile_string(readfile(file), '@'..file)
end)

function include_string(s, env, chunkname, ...)
	return compile_string(s, chunkname)(env, ...)
end

function include(file, env, ...)
	compile(file)(env, ...)
end

--Lua scripts ----------------------------------------------------------------

local function compile_lua_string(s)
	local f = assert(loadstring(s))
	return function(_env, ...)
		setfenv(f, _env or env())
		return f(...)
	end
end

local compile_lua = glue.memoize(function(file)
	local f = assert(loadfile(basepath(file)))
	return function(_env, ...)
		setfenv(f, _env or env())
		return f(...)
	end
end)

function run_string(s, env, ...)
	return compile_lua_string(s)(env, ...)
end

function run(file, env, ...)
	return compile_lua(file)(env, ...)
end

--html filters ---------------------------------------------------------------

function filter_lang(buf)
	local lang0 = lang()

	--replace <t class=lang>
	buf = buf:gsub('<t class=([^>]+)>(.-)</t>', function(lang, html)
		assert(not html:find('<t class=', 1, true), html)
		if lang ~= lang0 then return '' end
		return html
	end)

	--replace attr:lang="val" and attr:lang=val
	local function repl_attr(attr, lang, val)
		if lang ~= lang0 then return '' end
		return attr .. val
	end
	buf = buf:gsub('(%s[%w_%:%-]+)%:(%a?%a?)(=%b"")', repl_attr)
	buf = buf:gsub('(%s[%w_%:%-]+)%:(%a?%a?)(=[^%s>]*)', repl_attr)

	return buf
end

function filter_comments(buf)
	return buf:gsub('<!%-%-.-%-%->', '')
end

--concatenated files preprocessor --------------------------------------------

function catlist(listfile, ...)
	local js = listfile:find'%.js%.cat$'
	local sep = js and ';\n' or '\n'

	--generate and check etag
	local t = {} --etag seeds
	local c = {} --output generators
	for file in readfile(listfile):gmatch'([^%s]+)' do
		local path = filepath(file)
		if path then --plain file, get its mtime
			local mtime = lfs.attributes(path, 'modification')
			table.insert(t, tostring(mtime))
			table.insert(c, function() out(readfile(file)) end)
		else --file not found, try an action
			local s, found = record(action, file, ...)
			if found then
				table.insert(t, s)
				table.insert(c, function() out(s) end)
			else
				error('file not found '..file)
			end
		end
	end
	check_etag(table.concat(t, '\n'))

	--output the content
	for i,f in ipairs(c) do
		f()
		out(sep)
	end
end

--action API -----------------------------------------------------------------

--action files

local action_handlers = {
	cat = function(action, ...)
		catlist(action..'.cat', ...)
	end,
	lua = function(action, ...)
		return run(action..'.lua', nil, ...)
	end,
	lp = function(action, ...)
		include(action..'.lp')
	end,
}

local actions_list = glue.keys(action_handlers, true)

local function plain_file_action_handler(action)
	out(readfile(action))
end

local actionfile = glue.memoize(function(action)
	if filepath(action) then --action is a plain file
		return plain_file_action_handler
	end
	local ret_file, ret_handler
	for i,ext in ipairs(actions_list) do
		local file = action..'.'..ext
		if filepath(file) then
			assert(not ret_file, 'multiple action files for action '..action)
			ret_file = file
			ret_handler = action_handlers[ext]
		end
	end
	return ret_handler
end)

--mime type inferrence

local mime_types = {
	html = 'text/html',
	txt  = 'text/plain',
	css  = 'text/css',
	json = 'application/json',
	js   = 'application/javascript',
	jpg  = 'image/jpeg',
	jpeg = 'image/jpeg',
	png  = 'image/png',
	ico  = 'image/ico',
}

--output filters

local function html_filter(handler, action, ...)
	local s = record(handler, action, ...)
	local s = filter_lang(filter_comments(s))
	check_etag(s)
	out(s)
end

local function json_filter(handler, action, ...)
	local t = handler(action, ...)
	if type(t) == 'table' then
		local s = json(t)
		check_etag(s)
		out(s)
	end
end

local mime_type_filters = {
	['text/html']        = html_filter,
	['application/json'] = json_filter,
}

local not_found_actions = {
	['text/html']  = config('html_404_action', '404.html'),
	['image/png']  = config('png_404_action',  '404.png'),
	['image/jpeg'] = config('jpeg_404_action', '404.jpg'),
}

--logic

config('root_action', 'home') --set it here so we can see it client-side

local function run_action(actions, action, ...)
	if action == '' then
		action = config'root_action'
	end
	local handler = actions[action] --look for a local action
	local ext = action:match'%.([^%.]+)$' --get the action's file extension
	if not ext then --add the default .html extension to the action
		ext = 'html'
		action = action .. '.' .. ext
	end
	local mime = mime_types[ext]
	handler = handler or actions[action] --look again after adding .html
	handler = handler or actionfile(action) --look on the filesystem
	if not handler then --look for a 404 handler
		local nf_action = not_found_actions[mime]
		if not nf_action or nf_action == action then
			--the 404 action itself was not found
			return false
		end
		return run_action(actions, nf_action, ...)
	end
	if mime then
		setheader('content_type', mime)
	end
	local filter = mime_type_filters[mime]
	if filter then
		filter(handler, action, ...)
	else
		handler(action, ...)
	end
	return true
end

action = {} --{action=handler}
setmetatable(action, {__call = run_action})

