setfenv(1, require'webb')

return function()
	init_g()
	check_img()
	local act, args = parse_path()
	touch_usr() --update usr.atime on all requests, except image requests.
	if act:find'%.html$' then --html files can contain <t> tags and xxx:lang attrs.
		push_outbuf()
		action(act, unpack(args))
		local buf = pop_outbuf()
		buf = filter_lang(buf)
		buf = filter_comments(buf)
		out(buf)
	else
		action(act, unpack(args))
	end
end
