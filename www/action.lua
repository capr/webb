--Webb Framework | action-based routing module
--Written by Cosmin Apreutesei. Public Domain.

--action aliases -------------------------------------------------------------

--NOTE: it is assumed that action names are always in english even if they
--actually request a page in the default language which can configured
--to be different than english. Action name translation is done
--automatically provided all links go through the lang_url() filter
--and then you use find_action() to find back the action in english
--from unpack(args()), then it's just a matter of declaring aliases
--for actions in different languages. When missing an alias, ?lang=xx
--is appended to the URL automatically and processed accordingly.
--Aliases for the root action are also allowed so as to avoid the ?lang arg.

local aliases = {} --{alias={lang=, action=}}
local aliases_json = {to_en = {}, to_lang = {}}
config('aliases', aliases_json) --we pass those to the client

function alias(alias_lang, alias_action, en_action)
	aliases[alias_action] = {lang = alias_lang, action = en_action}
	--if the default language is not english and we're making
	--an alias for the default language, then we can safely assign
	--the english action name for the english language, whereas before
	--we would use the english action name for the default language.
	local default_lang = config('lang', 'en')
	if default_lang ~= 'en' and alias_lang == default_lang then
		if not aliases[en_action] then --user can override this
			aliases[en_action] = {lang = 'en', action = en_action}
			glue.attr(aliases_json.to_lang, en_action).en = en_action
		end
	end
	aliases_json.to_en[alias_action] = en_action
	glue.attr(aliases_json.to_lang, en_action)[alias_lang] = alias_action
end

local function decode_url(s)
	return type(s) == 'string' and url(s) or s
end

local function url_action(s)
	local t = decode_url(s)
	return t[1] == '' and t[2] or nil
end

--given an url (in encoded or decoded form), if it's an action url,
--replace its action name with a language-specific alias for a given
--(or current) language if any, or add ?lang= if the given language
--is not the default language.
function lang_url(s, target_lang)
	local t = decode_url(s)
	local default_lang = config('lang', 'en')
	local target_lang = target_lang or t.lang or lang()
	local action = url_action(t)
	if not action then
		return s
	end
	local is_root = t[2] == ''
	if is_root then
		action = config('root_action', 'home')
	end
	local at = aliases_json.to_lang[action]
	local lang_action = at and at[target_lang]
	if lang_action then
		if not (is_root and target_lang == default_lang) then
			t[2] = lang_action
		end
	elseif target_lang ~= default_lang then
		t.lang = target_lang
	end
	return url(t)
end

--given a list of path elements, find the action they point to
--and change the current language if necessary.
function find_action(action, ...)
	if action == '' then --root action in current language
		action = config('root_action', 'home')
	else
		local alias = aliases[action] --look for a regional alias
		if alias then
			if not args'lang' then --?lang= has priority
				lang(alias.lang)
			end
			action = alias.action
		end
	end
	action = action:gsub('-', '_') --make actions easier to declare
	return action, ...
end

--html output filter for rewriting links based on current language aliases
function setlinks(s)
	local function repl(prefix, s)
		return prefix..lang_url(s)
	end
	s = s:gsub('(%shref=")([^"]+)', repl)
	s = s:gsub('(%shref=)([^ >]+)', repl)
	return s
end

--action files ---------------------------------------------------------------

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
	if readfile[action] or filepath(action) then --action is a plain file
		return plain_file_action_handler
	end
	local ret_file, ret_handler
	for i,ext in ipairs(actions_list) do
		local file = action..'.'..ext
		if readfile[file] or filepath(file) then
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
	local s = setlinks(filter_lang(filter_comments(s)))
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

--logic

local not_found_actions = {
	['text/html']  = '404.html',
	['image/png']  = '404.png',
	['image/jpeg'] = '404.jpg',
}

local function action_call(actions, action, ...)
	local ext = action:match'%.([^%.]+)$' --get the action's file extension
	local action_no_ext = action
	if not ext then --add the default .html extension to the action
		ext = 'html'
		action = action .. '.' .. ext
	end
	local mime = mime_types[ext]
	local handler =
		actions[action_no_ext] --look in the default action table
		or actions[action] --look again with .html extension
		or actionfile(action) --look on the filesystem
	if not handler then --look for a 404 handler
		local nf_action = not_found_actions[mime]
		if not nf_action or nf_action == action then
			--the 404 action itself was not found
			return false
		end
		return action_call(actions, nf_action, ...)
	end
	if type(handler) ~= 'function' then
		local s = handler
		handler = function()
			return s
		end
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
setmetatable(action, {__call = action_call})

--built-in actions -----------------------------------------------------------

action['404.html'] = function(action, ...)
	check(false, '<h1>File Not Found</h1>')
end

action['404.png'] = function(action, ...)
	redirect'/1x1.png'
end

action['404.jpg'] = action['404.png']

action['config.js'] = function(action, ...)

	local cjson = require'cjson'

	--initialize some required config values with defaults.
	config('lang', 'en')
	config('root_action', 'home')
	config('templates_action', '_templates')

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

	C'facebook_app_id'
	C'analytics_ua'
	C'google_client_id'

end

action['strings.js'] = function(_, ...)
	if lang() == 'en' then return end
	action('strings.'..lang()..'.js', ...)
end

--TODO: how to use config('templates_action') instead of hardcoding the name?
function action._templates()
	for _,name in ipairs(template()) do
		out(mustache_wrap(template(name), name))
	end
end

