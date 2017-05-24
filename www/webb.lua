--webb framework
--written by Cosmin Apreutesei. Public Domain.

local glue = require'glue'

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
	return S_[name]
end

--per-request environment ----------------------------------------------------

--per-request memoization.
local NIL = {}
local function enc(v) if v == nil then return NIL else return v end end
local function dec(v) if v == NIL then return nil else return v end end
function once(f)
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

--per-request shared environment to use in all app code.
function env()
	local env = ngx.ctx.env
	if not env then
		env = {__index = _G}
		setmetatable(env, env)
		ngx.ctx.env = env
	end
	return env
end

--request API ----------------------------------------------------------------

local method = once(function()
	return ngx.req.get_method()
end)

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

local _uri_args = once(function()
	return ngx.req.get_uri_args()
end)

function GET(v)
	if v then
		return _uri_args()[v]
	else
		return _uri_args()
	end
end

local _post_args = once(function()
	if method() ~= 'POST' then return end
	ngx.req.read_body()
	return ngx.req.get_post_args()
end)

function POST(v)
	local t = _post_args()
	if not t then return end
	if v then
		return t[v]
	else
		return t
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
	return string.format('%s@%s', user or 'no-reply', domain())
end

function client_ip()
	return ngx.var.remote_addr
end

function lang()
	return GET'lang' or config('lang', 'en')
end

function uint_arg(s)
	local n = s and tonumber(s:match'(%d+)$')
	assert(not n or n >= 0)
	return n
end

function str_arg(s)
	if not s then return end
	s = glue.trim(s)
	return s ~= '' and s or nil
end

function enum_arg(s, ...)
	for i=1,select('#',...) do
		if s == select(i,...) then
			return s
		end
	end
end

function list_arg(s, arg_f)
	local s = str_arg(s)
	if not s then return end
	arg_f = arg_f or str_arg
	local t = {}
	for s in glue.gsplit(s, ',') do
		table.insert(t, arg_f(s))
	end
	return t
end

function check(ret, err)
	if ret then return ret end
	ngx.status = 404
	if err then ngx.print(err) end
	ngx.exit(0)
end

function allow(ret, err)
	if ret then return ret, err end
	ngx.status = 403
	if err then ngx.print(err) end
	ngx.exit(0)
end

--output API -----------------------------------------------------------------

local function default_outfunc(s)
	ngx.print(s)
end

local function outbuf()
	local t = {}
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
	outfunc(tostring(s))
end

function record(out_content)
	push_out()
	out_content()
	return pop_out()
end

--print API ------------------------------------------------------------------

function print(...)
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
	return config('basepath') .. '/' .. file
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
	return function(data)
		setfenv(f, data or env())
		f()
	end
end

local compile = glue.memoize(function(file)
	return compile_string(readfile(file), '@'..file)
end)

function include_string(s, data, chunkname)
	return compile_string(s, chunkname)(data)
end

function include(file, data)
	compile(file)(data)
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

function run_string(s, _env, ...)
	return compile_lua_string(s)(_env, ...)
end

function run(file, _env, ...)
	return compile_lua(file)(_env, ...)
end

--gzip filter ----------------------------------------------------------------

local zlib = require'zlib'

local function accept_gzip()
	local e = headers'accept_encoding'
	return e and e:find'gzip' and true or false
end

function gzip_filter(out_content, gen_etag)

	local last_etag, last_buf

	return function()

		--send it chunked if the client doesn't do gzip
		if not accept_gzip() then
			out_content()
			return
		end

		--generate etag
		local etag = gen_etag()
		--compare etag with client's

		local etag0 = headers'if_none_match'
		if etag0 and etag0 == etag then
			ngx.status = 304
			ngx.exit(0)
		end

		--compare etag with cached
		if etag ~= last_etag then
			--generate content
			local s = record(out_content)
			last_buf = zlib.deflate(s, '', nil, 'gzip')
			last_etag = etag
		end

		--send it
		ngx.header['Content-Encoding'] = 'gzip'
		ngx.header['Content-Length'] = #last_buf
		ngx.header.ETag = last_etag
		out(last_buf)
	end
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

local catlist_filter = glue.memoize(function(listfile)

	local js = listfile:find'%.js%.cat$'
	local sep = js and ';\n' or '\n'

	local function out_content()
		for file in readfile(listfile):gmatch'([^%s]+)' do
			out(readfile(file))
			out(sep)
		end
	end

	local function gen_etag()
		local t = {}
		for file in readfile(listfile):gmatch'([^%s]+)' do
			local path = check(filepath(file))
			local mtime = lfs.attributes(path, 'modification')
			t[#t+1] = tostring(mtime)
		end
		return ngx.md5(table.concat(t, ' '))
	end

	return gzip_filter(out_content, gen_etag)
end)

function catlist(listfile)
	catlist_filter(listfile)()
end

--action API -----------------------------------------------------------------

function parse_path() --path -> action, args
	local path = ngx.var.uri

	--split path
	local action, sargs = path:match'^/([^/]+)(/?.*)$' --action/sargs

	--missing action defaults to the "index" action
	action = action or 'index'

	--missing file extension in action name defaults to ".html" extension
	local ext = action:match'%.([^%.]+)$'
	if not ext then
		ext = 'html'
		action = action .. '.' .. ext
	end

	--collect args
	sargs = sargs or ''
	local args = {}
	for s in sargs:gmatch'[^/]+' do
		args[#args+1] = ngx.unescape_uri(s)
	end

	return action, args
end

local chunks = {} --{action = chunk}

local mime_types = {
	html = 'text/html',
	txt  = 'text/plain',
	css  = 'text/css',
	json = 'application/json',
	js   = 'application/javascript',
	jpg  = 'image/jpeg',
	png  = 'image/png',
}

function action(action, ...)

	--set mime type based on action's file extension.
	local ext = action:match'%.([^%.]+)$'
	local mime = assert(mime_types[ext])

	if mime == 'text/html' then
		push_out()
	end

	if filepath(action..'.cat') then
		ngx.header.content_type = mime
		catlist(action..'.cat')
	elseif filepath(action..'.lua') then
		ngx.header.content_type = mime
		run(action..'.lua', env(), ...)
	elseif filepath(action..'.lp') then
		ngx.header.content_type = mime
		include(action..'.lp')
	else
		if mime == 'text/html' then
			pop_out()
		end
		return
	end

	--apply html filters
	if mime == 'text/html' then
		out(filter_lang(filter_comments(pop_out())))
	end

	return true
end

--missing image fallback -----------------------------------------------------

function check_img()
	local path = ngx.var.uri
	if path:find'%.jpg$' or path:find'%.png$' then
		--redirect to empty image (default is 302-moved-temporarily)
		ngx.redirect('/0.png')
	end
end

