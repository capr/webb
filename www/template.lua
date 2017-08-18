
--set the default here so we can send it to the client
config('templates_action', 'templates')

--NOTE: the lang arg is not used but the html action filters on lang, thus
--returning different results that we need to cache separately.
local get_templates = glue.memoize(function(lang)
	local s = record(action, config'templates_action')
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
