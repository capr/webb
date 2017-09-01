--Webb Framework | main module
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
			if select('#', ...) == 0 then
				t = {}
				ngx.ctx[f] = t
			else
				local k = ...
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
			local v = t[enc(k)]
			if v == nil then
				v = f(k)
				t[enc(k)] = enc(v)
			else
				v = dec(v)
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

function scheme(s)
	if s then
		return scheme() == s
	end
	return headers'X-Forwarded-Proto' or ngx.var.scheme
end

function host(s)
	if s then
		return host() == s
	end
	return ngx.var.host
end

function port(p)
	if p then
		return port() == tonumber(p)
	end
	return tonumber(headers'X-Forwarded-Port' or ngx.var.server_port)
end

function absurl(path)
	path = path or ''
	return config'base_url' or
		scheme()..'://'..host()..
			(((scheme'https' and port(443)) or
			  (scheme'http' and port(80))) and '' or ':'..port())..path
end

function email(user)
	return string.format('%s@%s', assert(user), host())
end

function client_ip()
	return ngx.var.remote_addr
end

function lang(s)
	if s then
		ngx.ctx.lang = s
	else
		return ngx.ctx.lang or args'lang' or config('lang', 'en')
	end
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
		--TODO: strip all non-url chars!
		return tostring(id)..'-'..s:gsub('[ ]', '-'):lower()
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
	if s == nil then return end
	local outfunc = ngx.ctx.outfunc or default_outfunc
	outfunc(tostring(s))
end

local function pass(...)
	return pop_out(), ...
end
function record(out_content, ...)
	push_out()
	return pass(out_content(...))
end

function html(s)
	if s == nil then return '' end
	return tostring(s):gsub('[&"<>\\]', function(c)
		if c == '&' then return '&amp;'
		elseif c == '"' then return '\"'
		elseif c == '\\' then return '\\\\'
		elseif c == '<' then return '&lt;'
		elseif c == '>' then return '&gt;'
		else return c end
	end)
end

local function url_path(path)
	if type(path) == 'table' then --encode
		local t = {}
		for i,s in ipairs(path) do
			t[i] = ngx.escape_uri(s)
		end
		return #t > 0 and table.concat(t, '/') or nil
	else --decode
		local t = {}
		for s in glue.gsplit(path, '/', 1, true) do
			t[#t+1] = ngx.unescape_uri(s)
		end
		return t
	end
end

local function url_params(params)
	if type(params) == 'table' then --encode
		return ngx.encode_args(params)
	else --decode
		return ngx.decode_args(params)
	end
end

--use cases:
--  decode url: url('a/b?a&b=1') -> {'a', 'b', a=true, b='1'}
--  encode url: url{'a', 'b', a=true, b='1'} -> 'a/b?a&b=1'
--  update url: url('a/b?a&b=1', {'c', b=2}) -> 'c/b?a&b=2'
--  decode params only: url(nil, 'a&b=1') -> {a=true, b=1}
--  encode params only: url(nil, {a=true, b=1}) -> 'a&b=1'
function url(path, params)
	if type(path) == 'string' then --decode or update url
		local t
		local i = path:find('?', 1, true)
		if i then
			t = url_path(path:sub(1, i-1))
			glue.update(t, url_params(path:sub(i + 1)))
		else
			t = url_path(path)
		end
		if params then --update url
			glue.update(t, params) --also updates any path elements
			return url(t) --re-encode url
		else --decode url
			return t
		end
	elseif path then --encode url
		local s1 = url_path(path)
		--strip away the array part so that ngx.encode_args() doesn't complain
		local t = {}
		for k,v in pairs(path) do
			if type(k) ~= 'number' then
				t[k] = v
			end
		end
		local s2 = next(t) ~= nil and url_params(t) or nil
		return (s1 or '') .. (s1 and s2 and '?' or '') .. (s2 or '')
	else --encode or decode params only
		return url_params(params)
	end
end

--[[
ngx.say(require'pp'.format(url('a/b?a&b=1')))
ngx.say(url{'a', 'b', a=true, b=1})
ngx.say()
ngx.say(require'pp'.format(url('?a&b=1')))
ngx.say(url{'', a=true, b=1})
ngx.say()
ngx.say(require'pp'.format(url('a/b?')))
ngx.say(url{'a', 'b', ['']=true})
ngx.say()
ngx.say(require'pp'.format(url('a/b')))
ngx.say(url{'a', 'b'})
ngx.say()
ngx.say(url('a/b?a&b=1', {'c', b=2}))
ngx.say()
ngx.say(require'pp'.format(url(nil, 'a&b=1')))
ngx.say(url(nil, {a=true, b=1}))
ngx.say()
]]

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
		return tostring(code)..(msg ~= nil and ' '..tostring(msg) or '')
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
	return assert(config'webb_dir')..(file and '/'..file or '')
end

local lfs = require'lfs'

function filepath(file) --file -> path (if exists)
	if file:find('..', 1, true) then return end --trying to escape
	local path = basepath(file)
	if not lfs.attributes(path, 'mode') then return end
	return path
end

local function readfile_call(files, file)
	local f = files[file]
	if type(f) == 'function' then
		return f(file)
	elseif f then
		return f
	else
		local s = glue.readfile(basepath(file))
		return glue.assert(s, 'file not found: %s', file)
	end
end

readfile = {} --{filename -> content | handler(filename)}
setmetatable(readfile, {__call = readfile_call})

--TODO: outfile(file) which skips the accumulation/concat
--so it can work with very large files

--mustache templates ---------------------------------------------------------

local hige = require'hige'

function render_string(s, data)
	return hige.render(s, data or env())
end

function render_file(file, data)
	return render_string(readfile(file), data)
end

function mustache_wrap(s, name)
	return '<script type="text/mustache" id="'..name..
		'_template">\n'..s..'\n</script>\n'
end

--TODO: make this parser more robust so we can have <script> tags in templates
--without the <{{undefined}}/script> hack (mustache also needs it though).
function mustache_unwrap(s, t)
	t = t or {}
	local i = 0
	for name,s in s:gmatch('<script%s+type=?"text/mustache?"%s+'..
		'id="?(.-)_template"?>(.-)</script>') do
		t[name] = s
		i = i + 1
	end
	return t, i
end

local template_names = {} --keep template names in insertion order

local function add_template(templates, name, s)
	rawset(templates, name, s)
	table.insert(template_names, name)
end

--gather all the templates from the filesystem
local load_templates = glue.memoize(function()
	local t = {}
	for file in lfs.dir(basepath()) do
		if file:find'%.mu$' and
			lfs.attributes(basepath(file), 'mode') == 'file'
		then
			t[#t+1] = file
		end
	end
	table.sort(t)
	for i,file in ipairs(t) do
		local s = readfile(file)
		local _, i = mustache_unwrap(s, template)
		if i == 0 then --must be without the <script> tag
			local name = file:gsub('%.mu$', '')
			template[name] = s
		end
	end
end)

local function template_call(templates, name)
	load_templates()
	if not name then
		return template_names
	else
		local s = glue.assert(templates[name], 'template not found: %s', name)
		if type(s) == 'function' then
			s = s(name)
		end
		return filter_lang(filter_comments(s))
	end
end

template = {} --{template = html | handler(name)}
setmetatable(template, {__call = template_call, __newindex = add_template})

function render(name, ...)
	return render_string(template(name), ...)
end

template.loading = [[
<div class="loading_outer">
	<div class="loading_middle">
		<div class="loading_inner reload loading{{#error}}_error{{/error}}">
		</div>
	</div>
</div>
]]

template.not_found = [[
<h1>404 Not Found</h1>
]]

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

local function compile_lua_string(s, chunkname)
	local f = assert(loadstring(s, chunkname))
	return function(_env, ...)
		setfenv(f, _env or env())
		return f(...)
	end
end

local compile_lua = glue.memoize(function(file)
	return compile_lua_string(readfile(file), file)
end)

function run_string(s, env, ...)
	return compile_lua_string(s)(env, ...)
end

function run(file, env, ...)
	return compile_lua(file)(env, ...)
end

--html filters ---------------------------------------------------------------

function filter_lang(s, lang_)
	local lang0 = lang_ or lang()

	--replace <t class=lang>
	s = s:gsub('<t class=([^>]+)>(.-)</t>', function(lang, html)
		assert(not html:find('<t class=', 1, true), html)
		if lang ~= lang0 then return '' end
		return html
	end)

	--replace attr:lang="val" and attr:lang=val
	local function repl_attr(attr, lang, val)
		if lang ~= lang0 then return '' end
		return attr .. val
	end
	s = s:gsub('(%s[%w_%:%-]+)%:(%a?%a?)(=%b"")', repl_attr)
	s = s:gsub('(%s[%w_%:%-]+)%:(%a?%a?)(=[^%s>]*)', repl_attr)

	return s
end

function filter_comments(s)
	return (s:gsub('<!%-%-.-%-%->', ''))
end

--concatenated files preprocessor --------------------------------------------

--NOTE: can also concatenate actions if the actions module is loaded.
--NOTE: favors plain files over actions because it can generate etags without
--actually reading the files.
function catlist(listfile, ...)
	local js = listfile:find'%.js%.cat$'
	local sep = js and ';\n' or '\n'

	--generate and check etag
	local t = {} --etag seeds
	local c = {} --output generators
	for file in readfile(listfile):gmatch'([^%s]+)' do
		if readfile[file] then --virtual file
			table.insert(t, readfile(file))
			table.insert(c, function() out(readfile(file)) end)
		else
			local path = filepath(file)
			if path then --plain file, get its mtime
				local mtime = lfs.attributes(path, 'modification')
				table.insert(t, tostring(mtime))
				table.insert(c, function() out(readfile(file)) end)
			elseif action then --file not found, try an action
				local s, found = record(action, file, ...)
				if found then
					table.insert(t, s)
					table.insert(c, function() out(s) end)
				else
					glue.assert(false, 'file not found: %s', file)
				end
			else
				glue.assert(false, 'file not found: %s', file)
			end
		end
	end
	check_etag(table.concat(t, '\0'))

	--output the content
	for i,f in ipairs(c) do
		f()
		out(sep)
	end
end

