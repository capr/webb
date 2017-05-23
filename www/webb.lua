--webb framework
--written by Cosmin Apreutesei. Public Domain.

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
	return S_[name]
end

--per-request memoization ----------------------------------------------------

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

function lang()
	return GET'lang' or config('lang', 'en')
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

function clamp(x, min, max)
	return math.min(math.max(x, min), max)
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

local outbufs = {}
local outbuf

function push_outbuf()
	outbuf = {}
	table.insert(outbufs, outbuf)
end

function pop_outbuf()
	if not outbuf then return end
	local s = table.concat(table.remove(outbufs))
	outbuf = outbufs[#outbufs]
	return s
end

function out(s)
	s = tostring(s)
	if outbuf then
		outbuf[#outbuf+1] = s
	else
		ngx.print(s)
	end
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

pp = require'pp'

_G.print = print --override Lua's print() for pp.

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

--template API ---------------------------------------------------------------

local hige = require'hige'

function render(name, data)
	local file = string.format('%s.%s.m', name, lang())
	local template = assert(glue.readfile(basepath(file)))
	return hige.render(template, data)
end

--gzip filter ----------------------------------------------------------------

local zlib = require'zlib'

local function accept_gzip()
	local e = headers'accept_encoding'
	return e and e:find'gzip' and true or false
end

local function gzip_filter(out_content, gen_etag)

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
			push_outbuf()
			out_content()
			last_buf = zlib.deflate(pop_outbuf(), '', nil, 'gzip')
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

function html_filter(out_content)
	push_outbuf()
	out_content()
	local buf = pop_outbuf()
	buf = filter_lang(buf)
	buf = filter_comments(buf)
	out(buf)
end

--luapages API ---------------------------------------------------------------

local lp = require'lp'

local compile = glue.memoize(function(path)
	lp.setoutfunc'out'
	local template = glue.readfile(path)
	return lp.compile(template, '@'..path, _G)
end)

--TODO: remove env, find a better way to share values
function include(name, env)
	local path = basepath(name..'.lp')
	glue.update(_G, env)
	compile(path)()
end

--catlist API ----------------------------------------------------------------

local function out_catlist(listfile, sep)
	for f in glue.readfile(listfile):gmatch'([^%s]+)' do
		out(glue.readfile(filepath(f)))
		out(sep)
	end
end

local function catlist(listfile, sep)

	local function gen_etag()
		local t = {}
		for f in glue.readfile(listfile):gmatch'([^%s]+)' do
			local path = check(filepath(f))
			local mtime = lfs.attributes(path, 'modification')
			t[#t+1] = tostring(mtime)
		end
		return ngx.md5(table.concat(t, ' '))
	end

	local function out_content()
		out_catlist(listfile, sep)
	end

	return gzip_filter(out_content, gen_etag)
end

--action API -----------------------------------------------------------------

function parse_path() --path -> action, extension, args
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
	json = 'application/json',
	txt  = 'text/plain',
	jpg  = 'image/jpeg',
	png  = 'image/png',
	js   = 'application/javascript',
	css  = 'text/css',
}

function action(action, ...)

	--find the action.
	local chunk = chunks[action]
	if not chunk then
		local path =
			   filepath(action..'.cat')
			or filepath(action..'.lua')
			or filepath(action..'.lp')
		if not path then
			return --action not found
		end
		local ext = path:match'%.([^%.]+)$'
		if ext == 'cat' then
			local fext = action:match'%.([^%.]+)$'
			chunk = catlist(path, fext == 'js' and ';\n' or '\n')
		elseif ext == 'lp' then
			chunk = compile(path)
		else
			chunk = assert(loadfile(path))
		end
		setfenv(chunk, _G)
		chunks[action] = chunk
	end

	--set mime type based on action's file extension.
	local ext = action:match'%.([^%.]+)$'
	local mime = check(mime_types[ext])
	ngx.header.content_type = mime

	--execute the action.
	if mime == 'text/html' then
		local args = glue.pack(...)
		html_filter(function()
			chunk(glue.unpack(args))
		end)
	else
		chunk(...)
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

