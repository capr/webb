
--NOTE: the lang arg is not used but the html action filters on lang, thus
--returning different results that we need to cache separately.
--NOTE: uses actions if the action module is loaded, otherwise works
--with plain files.
local get_templates = glue.memoize(function(lang)
	local templates_action = config('templates_action', 'templates')
	local s
	if action then
		s = record(action, templates_action)
	else
		if not templates_action:find'%.html$' then
			templates_action = templates_action .. '.html'
		end
		s = readfile(templates_action)
	end
	local t = {}
	for id,s in s:gmatch'<template%s+hidden%s+id="?(.-)_template"?>(.-)</template>' do
		t[id] = s
	end
	return t
end)

function template(name)
	return assert(get_templates(lang())[name], 'template not found')
end

function render_template(name, ...)
	return render_string(template(name), ...)
end
