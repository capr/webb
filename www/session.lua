setfenv(1, require'g')
local random_string = require'resty_random'
local session_ = require'resty_session'

local function fullname(firstname, lastname)
	return glue.trim((firstname or '')..' '..(lastname or ''))
end

--session cookie -------------------------------------------------------------

session = once(function()
	session_.cookie.persistent = true
	session_.check.ssi = false --ssi will change after browser closes
	session_.check.ua = false  --user could upgrade the browser
	session_.cookie.lifetime = 2 * 365 * 24 * 3600 --2 years
	return assert(session_.start())
end)

function session_uid()
	return session().data.uid
end

local function save_uid(uid)
	local session = session()
	if uid ~= session.data.uid then
		session.data.uid = uid
		session:save()
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
			admin
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
	]], clientip())
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

local function transfer_cart(cur_uid, new_uid)
	--if the current cart contains buy-now items, we assume that the user
	--wants to buy those items instead of the items in its account cart,
	--and so we move those last-session items into the "buy later" bin.
	if tonumber(query1([[
		select count(1) from cartitem where
			buylater = 0 and uid = ?
		]], cur_uid)) > 1
	then
		query('update cartitem set buylater = 1 where uid = ?', new_uid)
	end
	if anonymous_uid(cur_uid) then
		--move the items in the throw-away account into the user's account.
		query('update cartitem set uid = ? where uid = ?', new_uid, cur_uid)
	else
		--we don't know if the items in the current cart belong to the user
		--that is logging in now, or to the current user that is logging out.
		--so we copy the items from the current acount to the new account,
		--so that both users have them.
		query([[
			insert into cartitem
				(uid, pid, coid, qty, pos, buylater, ctime, mtime)
			select
				?, pid, coid, qty, pos, buylater, ctime, mtime
			from cartitem where
				uid = ?
		]], new_uid, cur_uid)
	end
end

function auth.pass(auth)
	if auth.action == 'login' then
		return allow(pass_uid(auth.email, auth.pass), 'user_pass')
	elseif auth.action == 'create' then
		local email = glue.trim(assert(auth.email))
		assert(#email >= 1)
		local pass = assert(auth.pass)
		assert(#pass >= 1)
		allow(not pass_email_uid(email), 'email_taken')
		local uid = anonymous_uid(session_uid()) or create_user()
		--first non-anonymous user is admin
		local admin = tonumber(query1([[
			select count(1) from usr where anonymous = 0
			]])) == 0
		--users that admin creates are also admins
		if not admin and session_uid() then
			local usr = userinfo(session_uid())
			admin = usr.admin
		end
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
		return uid
	end
end

function set_pass(pass)
	local usr = userinfo(allow(session_uid()))
	allow(usr.uid)
	allow(usr.haspass)
	query('update usr set pass = ? where uid = ?', pass_hash(pass), usr.uid)
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
		allow(not euid or euid == uid, 'email_taken')
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
		url = home_url('/login/'..token),
	})
	local from = config'noreply_email' or home_email'no-reply'
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
	if not uid then return end

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

	return uid
end

--authentication logic -------------------------------------------------------

function login(auth)
	local uid = authenticate(auth)
	local suid = valid_uid(session_uid())
	if uid then
		if uid ~= suid then
			if suid then
				transfer_cart(suid, uid)
				if anonymous_uid(suid) then
					delete_user(suid)
				end
			end
			assert(uid)
			save_uid(uid)
		end
	end
	return uid
end

uid = once(login) --TODO: reset cache when suid changes

function logout()
	save_uid(nil)
	return authenticate()
end

function admin() --TODO: same here
	return userinfo(uid()).admin
end

function editmode()
	return admin()
end
