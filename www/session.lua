local random_string = require'resty_random'
local resty_session = require'resty_session'

require'query'

local function fullname(firstname, lastname)
	return glue.trim((firstname or '')..' '..(lastname or ''))
end

--session cookie -------------------------------------------------------------

session = once(function()
	resty_session.cookie.persistent = true
	resty_session.check.ssi = false --ssi will change after browser closes
	resty_session.check.ua = false  --user could upgrade the browser
	resty_session.cookie.lifetime = 2 * 365 * 24 * 3600 --2 years
	resty_session.secret = config'session_secret'
	return assert(resty_session.start())
end)

function session_uid()
	return session().data.uid
end

local clear_uid_cache --fw. decl

local function save_uid(uid)
	local session = session()
	if uid ~= session.data.uid then
		session.data.uid = uid
		session:save()
		clear_uid_cache()
	end
end

--authentication frontend ----------------------------------------------------

local auth = {} --auth.<type>(auth) -> uid, can_create

function authenticate(a)
	return auth[a and a.type or 'session'](a)
end

local userinfo = once(function(uid)
	if not uid then return {} end
	local t = query1([[
		select
			uid,
			email,
			anonymous,
			emailvalid,
			if(pass is not null, 1, 0) as haspass,
			googleid,
			facebookid,
			admin,
			--extra non-functional fields
			name,
			phone,
			gimgurl
		from
			usr
		where
			active = 1 and uid = ?
		]], uid)
	if not t then return {} end
	t.anonymous = t.anonymous == 1
	t.emailvalid = t.emailvalid == 1
	t.haspass = tonumber(t.haspass) == 1
	t.admin = t.admin == 1
	return t
end)

function clear_userinfo_cache(uid)
	once(userinfo, true, uid)
end

--session-cookie authentication ----------------------------------------------

local function valid_uid(uid)
	return userinfo(uid).uid
end

local function anonymous_uid(uid)
	return userinfo(uid).anonymous and uid
end

local function create_user()
	ngx.sleep(0.2) --make filling it up a bit harder
	return iquery([[
		insert into usr
			(clientip, atime, ctime, mtime)
		values
			(?, now(), now(), now())
	]], client_ip())
end

function auth.session()
	return valid_uid(session_uid()) or create_user()
end

--anonymous authentication ---------------------------------------------------

function auth.anonymous()
	return anonymous_uid(session_uid()) or create_user()
end

--password authentication ----------------------------------------------------

local function salted_hash(token, salt)
	token = ngx.hmac_sha1(assert(salt), assert(token))
	return glue.tohex(token) --40 bytes
end

local function pass_hash(pass)
	return salted_hash(pass, config'pass_salt')
end

local function pass_uid(email, pass)
	ngx.sleep(0.2) --slow down brute-forcing
	return query1([[
		select uid from usr where
			active = 1 and email = ? and pass = ?
		]], email, pass_hash(pass))
end

local function pass_email_uid(email)
	return query1([[
		select uid from usr where
			active = 1 and pass is not null and email = ?
		]], email)
end

local function delete_user(uid)
	query('delete from usr where uid = ?', uid)
end

--no-password authentication: use only for debugging!
function auth.nopass(auth)
	return pass_email_uid(auth.email)
end

function auth.pass(auth)
	if auth.action == 'login' then
		local uid = pass_uid(auth.email, auth.pass)
		if not uid then
			return nil, 'user_pass'
		else
			return uid
		end
	elseif auth.action == 'create' then
		local email = glue.trim(assert(auth.email))
		assert(#email >= 1)
		local pass = assert(auth.pass)
		assert(#pass >= 1)
		if pass_email_uid(email) then
			return nil, 'email_taken'
		end
		local uid = anonymous_uid(session_uid()) or create_user()
		--first non-anonymous user to be created is made admin
		local admin = tonumber(query1([[
			select count(1) from usr where anonymous = 0
			]])) == 0
		query([[
			update usr set
				anonymous = 0,
				emailvalid = 0,
				email = ?,
				pass = ?,
				admin = ?
			where
				uid = ?
			]], email, pass_hash(pass), admin, uid)
		clear_userinfo_cache(uid)
		return uid
	end
end

function set_pass(pass)
	local usr = userinfo(allow(session_uid()))
	allow(usr.uid)
	allow(usr.haspass)
	query('update usr set pass = ? where uid = ?', pass_hash(pass), usr.uid)
	clear_userinfo_cache(uid)
end

--update info (not really auth, but related) ---------------------------------

function auth.update(auth)
	local uid = allow(session_uid())
	local usr = userinfo(uid)
	allow(usr.uid)
	local email = glue.trim(assert(auth.email))
	local name = glue.trim(assert(auth.name))
	local phone = glue.trim(assert(auth.phone))
	assert(#email >= 1)
	if usr.haspass then
		local euid = pass_email_uid(email)
		if euid and euid ~= uid then
			return nil, 'email_taken'
		end
	end
	query([[
		update usr set
			email = ?,
			name = ?,
			phone = ?,
			emailvalid = if(email <> ?, 0, emailvalid)
		where
			uid = ?
		]], email, name, phone, email, uid)
	clear_userinfo_cache(uid)
	return uid
end

--one-time token authentication ----------------------------------------------

local token_lifetime = config('pass_token_lifetime', 3600)

local function gen_token(uid)

	--now it's a good time to garbage-collect expired tokens
	query('delete from usrtoken where ctime < now() - ?', token_lifetime)

	--check if too many tokens were requested
	local n = query1([[
		select count(1) from usrtoken where
			uid = ? and ctime > now() - ?
		]], uid, token_lifetime)
	if tonumber(n) >= config('pass_token_maxcount', 2) then
		return
	end

	local token = pass_hash(random_string(32))

	--add the token to db (break on collisions)
	query([[
		insert into usrtoken
			(token, uid, ctime)
		values
			(?, ?, now())
		]], pass_hash(token), uid)

	return token
end

function send_auth_token(email)
	--find the user with this email
	local uid = pass_email_uid(email)
	if not uid then return end --hide the error for privacy

	--generate a new token for this user if we can
	local token = gen_token(uid)
	if not token then return end --hide the error for privacy

	--send it to the user
	local subj = S('reset_pass_subject', 'Your reset password link')
	local msg = render('reset_pass_email', {
		url = absurl('/login/'..token),
	})
	local from = config'noreply_email' or email'no-reply'
	sendmail(from, email, subj, msg)
end

local function token_uid(token)
	ngx.sleep(0.2) --slow down brute-forcing
	return query1([[
		select uid from usrtoken where token = ? and ctime > now() - ?
		]], pass_hash(token), token_lifetime)
end

function auth.token(auth)
	--find the user
	local uid = token_uid(auth.token)
	if not uid then return nil, 'invalid_token' end

	--remove the token because it's single use, and also to allow
	--the user to keep forgetting his password as much as he wants.
	query('delete from usrtoken where token = ?', pass_hash(auth.token))

	return uid
end

--facebook authentication ----------------------------------------------------

local function facebook_uid(facebookid)
	return query1('select uid from usr where facebookid = ?', facebookid)
end

local function facebook_graph_request(url, args)
	local res = ngx.location.capture('/graph.facebook.com'..url, {args = args})
	if res and res.status == 200 then
		local t = json(res.body)
		if t and not t.error then
			return t
		end
	end
	ngx.log(ngx.ERR, 'facebook_graph_request: ', url, ' ',
		pp.format(args, ' '), ' -> ', pp.format(res, ' '))
end

function auth.facebook(auth)
	--get info from facebook
	local t = facebook_graph_request('/v2.1/me',
		{access_token = auth.access_token})
	if not t then return end

	--grab a uid
	local uid =
		facebook_uid(t.id)
		or anonymous_uid(session_uid())
		or create_user()

	--deanonimize user and update its info
	query([[
		update usr set
			anonymous = 0,
			emailvalid = 1,
			email = ?,
			facebookid = ?,
			name = ?,
			gender = ?
		where
			uid = ?
		]], t.email, t.id, fullname(t.first_name, t.last_name), t.gender, uid)
	clear_userinfo_cache(uid)

	return uid
end

--google+ authentication -----------------------------------------------------

local function google_uid(googleid)
	return query1('select uid from usr where googleid = ?', googleid)
end

local function google_api_request(url, args)
	local res = ngx.location.capture('/content.googleapis.com'..url, {args = args})
	if res and res.status == 200 then
		return json(res.body)
	end
	ngx.log(ngx.ERR, 'google_api_request: ', url, ' ',
		pp.format(args, ' '), ' -> ', pp.format(res, ' '))
end

function auth.google(auth)
	--get info from google
	local t = google_api_request('/plus/v1/people/me',
		{access_token = auth.access_token})
	if not t then return end

	--grab a uid
	local uid =
		google_uid(t.id)
		or anonymous_uid(session_uid())
		or create_user()

	--deanonimize user and update its info
	query([[
		update usr set
			anonymous = 0,
			emailvalid = 1,
			email = ?,
			googleid = ?,
			gimgurl = ?,
			name = ?
		where
			uid = ?
		]],
		t.emails and t.emails[1] and t.emails[1].value,
		t.id,
		t.image and t.image.url,
		t.name and fullname(t.name.givenName, t.name.familyName),
		uid)
	clear_userinfo_cache(uid)

	return uid
end

--authentication logic -------------------------------------------------------

function login(auth, switch_user)
	switch_user = switch_user or glue.pass
	local uid, err = authenticate(auth)
	local suid = valid_uid(session_uid())
	if uid then
		if uid ~= suid then
			if suid then
				switch_user(suid, uid)
				if anonymous_uid(suid) then
					delete_user(suid)
				end
			end
			save_uid(uid)
		end
	end
	return uid, err
end

uid = once(function(attr)
	local uid = login()
	if attr == '*' then
		return userinfo(uid)
	elseif attr then
		return userinfo(uid)[attr]
	else
		return uid
	end
end)

function clear_uid_cache(uid) --local, fw. declared
	once(login, true)
end

function logout()
	save_uid(nil)
	return authenticate()
end

function admin()
	return userinfo(uid()).admin
end

function editmode()
	return admin()
end

function touch_usr()
	local uid = session_uid()
	if not uid then return end
	query([[
		update usr set
			atime = now(), mtime = mtime
		where uid = ?
	]], uid)
end
