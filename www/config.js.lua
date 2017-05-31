local function C(name)
	out('C(\''..name..'\', '..pp.format(config(name))..')\n')
end

C'facebook_app_id'
C'analytics_ua'
C'google_client_id'
