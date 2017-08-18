local function C(name)
	out('config(\''..name..'\', '..pp.format(config(name))..')\n')
end

C'lang'
C'root_action'
C'templates_action'
C'facebook_app_id'
C'analytics_ua'
C'google_client_id'
