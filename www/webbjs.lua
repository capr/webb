--Webb Framework | supporting actions and templates for webb.js
--Written by Cosmin Apreutesei. Public Domain.

require'webb'
require'action'

--pass required config values to the client
action['config.js'] = function()

	local cjson = require'cjson'

	--initialize some required config values with defaults.
	config('lang', 'en')
	config('root_action', 'home')
	config('templates_action', '__templates')
	config('loading_template', 'loading')
	config('not_found_template', 'not_found')
	config('page_title_suffix', ' - '..host())

	local function C(name)
		if config(name) == nil then return end
		out('config('
			..cjson.encode(name)..', '
			..cjson.encode(config(name))..')\n')
	end

	C'lang'
	C'aliases'
	C'root_action'
	C'templates_action'
	C'loading_template'
	C'not_found_template'
	C'page_title_suffix'

	C'facebook_app_id'
	C'analytics_ua'
	C'google_client_id'

end

--return a standard message for missing client-side actions.
template.not_found = [[
<h1>Not Found</h1>
]]

--organize string translations in separate files for each langauge
action['strings.js'] = function()
	if lang() == 'en' then return end
	action('strings.'..lang()..'.js')
end

--make render() work on the client-side
function action.__templates()
	for _,name in ipairs(template()) do
		out(mustache_wrap(template(name), name))
	end
end

--simple API to add js and css snippets and files from server-side code

local function sepbuffer(sep)
	local buf = stringbuffer()
	return function(s)
		if s then
			buf(s)
			buf(sep)
		else
			return buf()
		end
	end
end

cssfile = sepbuffer'\n'
readfile['all.css.cat'] = function()
	return cssfile()
end

jsfile = sepbuffer'\n'
readfile['all.js.cat'] = function()
	return jsfile()
end

css = sepbuffer'\n'
readfile['inline.css'] = function()
	return css()
end

js = sepbuffer';\n'
readfile['inline.js'] = function()
	return js()
end

cssfile[[
normalize.css
inline.css         // result of css() calls
]]

jsfile[[
jquery.js
jquery.history.js  // for URL rewriting
mustache.js
webb.js
config.js          // config values needed by webb.js
strings.js         // translated strings for current language
analytics.js
inline.js          // result of js() calls
]]

--loading template for slow-to-load page sections.

template.loading = [[
{{#error}}
	<div class="reload loading_error" title="{{error}}">
{{/error}}
{{^error}}
	<div class="loading">
{{/error}}
]]

css[[
/* ajax requests with user visual feedback and manual retry */

.loading {
	background-image: url(/loading.gif);
	background-repeat: no-repeat;
	width: 16px;
	height: 16px;
	cursor: pointer;
}

.loading_error {
	background-image: url(/load_error.gif);
	background-repeat: no-repeat;
	width: 32px;
	height: 32px;
	cursor: pointer;
}
]]

--format js and css refs as separate refs or as a single ref based on a .cat action

local function list(listfile)
	local s = readfile(listfile)
	s = s:gsub('//[^\n\r]*', '') --strip out comments
	return s:gmatch'([^%s]+)'
end

function jslist(cataction, separate)
	if not separate then
		return string.format('	<script src="%s"></script>', lang_url('/'..cataction))
	end
	local out = stringbuffer()
	for file in list(cataction..'.cat') do
		out(string.format('	<script src="%s"></script>\n', lang_url('/'..file)))
	end
	return out()
end

function csslist(cataction, separate)
	if not separate then
		return string.format('	<link rel="stylesheet" type="text/css" href="/%s">', cataction)
	end
	local out = stringbuffer()
	for file in list(cataction..'.cat') do
		out(string.format('	<link rel="stylesheet" type="text/css" href="/%s">\n', file))
	end
	return out()
end

--main template gluing it all together

template.webbjs = [[
<!DOCTYPE html>
<html lang="{{lang}}">
<head>
	<meta charset="UTF-8">
	<title>{{title}}{{title_suffix}}</title>
{{{all_js}}}
{{{all_css}}}
{{{head}}}
	<script>
		analytics_init()
		$(function() {
			load_templates(function() {
				setlinks()
				{{#client_action}}
					url_changed()
				{{/client_action}}
			})
		})
	</{{undefined}}script>
</head>
<body>
	<div style="display: none;" id="__templates"></div>
{{{body}}}
</body>
</html>
]]

function page_title(title, body)
	return title
		or (body and body:match'<h1[^>]*>(.-)</h1>') --infer it from the top heading
		or args(1):gsub('[-_]', ' ') --infer it from the name of the action
end

function webbjs(p)
	local t = {}
	t.lang = lang()
	t.title = page_title(p.title, p.body)
	t.title_suffix = config('page_title_suffix', ' - '..host())
	t.body = p.body
	t.head = p.head
	t.client_action = p.client_action
	t.all_js = jslist('all.js', config('separate_js_refs', false))
	t.all_css = csslist('all.css', config('separate_css_refs', false))
	out(render('webbjs', t))
end
