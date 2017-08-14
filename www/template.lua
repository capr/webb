
--set the default here so we can send it to the client
config('templates_action', 'templates.html')

local get_templates = glue.memoize(function()
	local s = readfile(config'templates_action')
	local t = {}
	for id,s in s:gmatch'<script%s+type="?text/x%-mustache"?%s+id="?(.-)"?>(.-)</script>' do
		assert(not s:find('<script', 1, true), 'embedded <script> tag found')
		t[id] = s
	end
	return t
end)

function template(name)
	return get_templates()[name..'_template']
end

function render_template(name, ...)
	return render_string(template(name), ...)
end
