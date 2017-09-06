
// global strings and config values ------------------------------------------

// global S() for internationalizing strings.
var S_ = {}
function S(name, val) {
	if (val && !S_[name])
		S_[name] = val
	return S_[name]
}

// global config() for general config values.
// some of the values come from the server (see config.js.lua).
var C_ = {}
function config(name, val) {
	if (val && !C_[name])
		C_[name] = val
	if (typeof(C_[name]) === 'undefined')
		console.log('warning: missing config value for ', name)
	return C_[name]
}

function lang() {
	return document.documentElement.lang
}

// string formatting ---------------------------------------------------------

// usage:
//		'{1} of {0}'.format(total, current)
//		'{1} of {0}'.format([total, current])
//		'{current} of {total}'.format({'current': current, 'total': total})
String.prototype.format = function() {
	var s = this.toString()
	if (!arguments.length)
		return s
	var type1 = typeof arguments[0]
	var args = ((type1 == 'string' || type1 == 'number') ? arguments : arguments[0])
	for (arg in args)
		s = s.replace(RegExp('\\{' + arg + '\\}', 'gi'), args[arg])
	return s
}

if (typeof String.prototype.trim !== 'function') {
	String.prototype.trim = function() {
		return this.replace(/^\s+|\s+$/g, '')
	}
}

// 'firstname lastname' -> 'firstname'; 'email@domain' -> 'email'
function firstname(name, email) {
	if (name) {
		name = name.trim()
		var a = name.split(' ', 1)
		return a.length > 0 ? a[0] : name
	} else if (email) {
		email = email.trim()
		var a = email.split('@', 1)
		return a.length > 0 ? a[0] : email
	} else {
		return ''
	}
}

// time formatting -----------------------------------------------------------

function rel_time(s) {
	if (s > 2 * 365 * 24 * 3600)
		return S('years', '{0} years').format((s / (365 * 24 * 3600)).toFixed(0))
	else if (s > 2 * 30.5 * 24 * 3600)
		return S('months', '{0} months').format((s / (30.5 * 24 * 3600)).toFixed(0))
	else if (s > 1.5 * 24 * 3600)
		return S('days', '{0} days').format((s / (24 * 3600)).toFixed(0))
	else if (s > 2 * 3600)
		return S('hours', '{0} hours').format((s / 3600).toFixed(0))
	else if (s > 2 * 60)
		return S('minutes', '{0} minutes').format((s / 60).toFixed(0))
	else
		return S('one_minute', '1 minute')
}

function timeago(time) {
	var s = (Date.now() / 1000) - time
	return (s > 0 ? S('time_ago', '{0} ago') : S('in_time', 'in {0}')).format(rel_time(Math.abs(s)))
}

var short_months =
	['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
var months =
	['January','February','Mars','April','May','June','July','August','September','October','November','December']

function zeroes(n, d) {
	return Array(Math.max(d - String(n).length + 1, 0)).join(0) + n
}

function parse_date(s) {
	var a = s.split(/[^0-9]/)
	return new Date (a[0], a[1]-1, a[2], a[3], a[4], a[5])
}

function format_time(d) {
	return zeroes(d.getHours(), 2) + ':' + zeroes(d.getMinutes(), 2)
}

function is_today(d) {
	var now = new Date()
	return
		d.getDate() == now.getDate() &&
		d.getMonth() == now.getMonth() &&
		d.getFullYear() == now.getFullYear()
}

function format_date(date, months, showtime) {
	var d = parse_date(date)
	if (is_today(d)) {
		return S('today', 'Today') + (showtime ? format_time(d) : '')
	} else {
		var now = new Date()
		var day = d.getDate()
		var month = S(months[d.getMonth()].toLowerCase(), months[d.getMonth()])
		var year = (d.getFullYear() != now.getFullYear() ? d.getFullYear() : '')
		return S('date_format', '{year} {month} {day} {time}').format({
			day: day,
			month: month,
			year: year,
			time: (showtime == 'always' ? format_time(d) : '')
		})
	}
}

function shortdate(date, showtime) {
	return format_date(date, short_months, showtime)
}

function longdate(date, showtime) {
	return format_date(date, months, showtime)
}

function from_date(d) {
	return (d.match(/Azi/) ? 'de' : S('from', 'from')) + ' ' + d
}

function update_timeago_elem() {
	var time = parseInt($(this).attr('time'))
	if (!time) {
		// set client-relative time from timeago attribute
		var time_ago = parseInt($(this).attr('timeago'))
		if (!time_ago) return
		time = (Date.now() / 1000) - time_ago
		$(this).attr('time', time)
	}
	$(this).html(timeago(time))
}

function update_timeago() {
	$('.timeago').each(update_timeago_elem)
}

setInterval(update_timeago, 60 * 1000)

// pub/sub -------------------------------------------------------------------

var g_events = $({})

function listen(topic, func) {
	g_events.on(topic, function(e, data) {
		func(data)
	})
}

function unlisten(topic) {
	g_events.off(topic)
}

function unlisten_all() {
	g_events.off('.current_action')
}

// broadcast a message to local listeners
function broadcast_local(topic, data) {
	g_events.triggerHandler(topic, data)
}

window.addEventListener('storage', function(e) {
	// decode the message
	if (e.key != 'broadcast') return
	var args = e.newValue
	if (!args) return
	args = JSON.parse(args)
	// broadcast it
	broadcast_local(args.topic, args.data)
})

// broadcast a message to other windows
function broadcast_external(topic, data) {
	if (typeof(Storage) == 'undefined') return
	localStorage.setItem('broadcast', '')
	localStorage.setItem('broadcast',
		JSON.stringify({
			topic: topic,
			data: data
		})
	)
	localStorage.setItem('broadcast', '')
}

function broadcast(topic, data) {
	broadcast_local(topic, data)
	broadcast_external(topic, data)
}

// keyboard navigation -------------------------------------------------------

var keydown_events = {} // {id: handler}

function bind_keydown(id, func) {
	keydown_events[id] = func
}

function unbind_keydown_all() {
	keydown_events = {}
}

$(function() {
	$(document).keydown(function(event) {
		$.each(keydown_events, function(id, func) {
			func(event)
		})
	})
})

// persistence ---------------------------------------------------------------

function store(key, value) {
	Storage.setItem(key, JSON.stringify(value))
}

function getback(key) {
	var value = Storage.getItem(key)
	return value && JSON.parse(value)
}

// ajax requests -------------------------------------------------------------

// 1. optionally restartable and abortable on an id.
// 2. triggers an optional abort() event.
// 3. presence of data defaults to POST method.
// 4. non-string data is converted into json.

var g_xhrs = {} //{id: xhr}

function abort(id) {
	if (!(id in g_xhrs)) return
	g_xhrs[id].abort()
	delete g_xhrs[id]
}

function abort_all() {
	$.each(g_xhrs, function(id, xhr) {
		xhr.abort()
	})
	g_xhrs = {}
}

function _ajax(url, opt) {
	var id = opt.id
	if (id)
		abort(id)

	var data = opt.data
	if (data && (typeof data != 'string'))
		data = {data: JSON.stringify(data)}
	var type = opt.type || (data ? 'POST' : 'GET')

	var xhr = $.ajax({
		url: lang_url(url),
		success: function(data) {
			if (id)
				delete g_xhrs[id]
			if (opt.success)
				opt.success(data)
		},
		error: function(xhr) {
			if (id)
				delete g_xhrs[id]
			if (xhr.statusText == 'abort') {
				if (opt.abort)
					opt.abort(xhr)
			} else {
				if (opt.error)
					opt.error(xhr)
			}
		},
		type: type,
		data: data
	})

	id = id || xhr
	g_xhrs[id] = xhr

	return id
}

// ajax request with UI feedback for slow loading and for failure.
// automatically aborts on ajax() calls over the same dest id.
// NOTE: render() also aborts pending ajax calls on its id.
function ajax(url, opt) {
	opt = opt || {}

	var dst = opt.dst
	if (!dst)
		return _ajax(url, opt)

	dst = $(dst)

	function render_loading(data) {
		dst.html(render(config('loading_template'), data))
		setlinks(dst)
	}

	var slow_watch = setTimeout(render_loading,
		config('slow_loading_feedback_delay', 1500))

	var done = function() {
		clearTimeout(slow_watch)
		dst.html('')
	}

	return _ajax(url,
		$.extend({}, opt, {
			id: dst.attr('id'),
			success: function(data) {
				done()
				if (opt.success)
					opt.success(data)
			},
			error: function(xhr) {
				done()
				render_loading({error: xhr.responseText || xhr.statusText})
				dst.find('.reload')
					.click(function() {
						render_loading()
						ajax(url, opt)
					})
				if (opt.error)
					opt.error(xhr)
			},
			abort: function(xhr) {
				done()
				if (opt.abort)
					opt.abort(xhr)
			},
		}))
}

function get(url, success, error, opt) {
	return ajax(url,
		$.extend({
			success: success,
			error: error,
		}, opt))
}

function post(url, data, success, error, opt) {
	return ajax(url,
		$.extend({
			data: data,
			success: success,
			error: error,
		}, opt))
}

// ajax request on the main pane: restore scroll position on success.
function load_main(url, success, error, opt) {
	ajax(url,
		$.extend({
			dst: '#main',
			success: function(data) {
				if (success)
					success(data)
				setscroll()
			},
			error: error,
		}, opt))
}

// templating ----------------------------------------------------------------

function load_templates(success) {
	get('/'+config('templates_action'), function(s) {
		$('#__templates').html(s)
		if (success)
			success()
	})
}

function template(name) {
	var t = $('#' + _underscores(name) + '_template')
	return t.length > 0 && t.html() || undefined
}

function load_partial_(name) {
	return template(name)
}

function render_string(s, data, dst) {
	var s = Mustache.render(s, data || {}, load_partial_)
	if (dst) {
		var dst_sel = dst
		dst = $(dst)
		if (dst.length == 0)
			console.log('error: render destination not found: '+dst_sel)
		var id = dst.attr('id')
		if (id)
			abort(id)
		dst.html(s)
		setlinks(dst)
		if (id == 'main')
			settitle()
	} else
		return s
}

function render(template_name, data, dst) {
	var s = template(template_name)
	return render_string(s, data, dst)
}

function render_multi_column(template_name, items, col_count) {
	var s = '<table width=100%>'
	var w = 100 / col_count
	$.each(items, function(i, item) {
		if (i % col_count == 0)
			s = s + '<tr>'
		s = s + '<td width='+w+'% valign=top>' + render(template_name, item) + '</td>'
		if (i % col_count == col_count - 1 || i == items.length)
			s = s + '</tr>'
	})
	s = s + '</table>'
	return s
}

function select_map(a, selv) {
	var t = []
	$.each(a, function(i, v) {
		var o = {value: v}
		if (selv == v)
			o.selected = 'selected'
		t.push(o)
	})
	return t
}

// url encoding & decoding ---------------------------------------------------

// 1. decode: url('a/b?k=v') -> {path: ['a','b'], params: {k:'v'}}
// 2. encode: url(['a','b'], {k:'v'}) -> 'a/b?k=v'
// 3. update: url('a/b', {k:'v'}) -> 'a/b?k=v'
// 4. update: url('a/b?k=v', ['c'], {k:'x'}) -> 'c/b?k=x'
function url(path, params, update) {
	if (typeof path == 'string') { // decode or update
		if (params !== undefined || update !== undefined) { // update
			if (typeof params == 'object') { // update params only
				update = params
				params = undefined
			}
			var t = url(path) // decode
			if (params) // update path
				for (var i = 0; i < params.length; i++)
					t.path[i] = params[i]
			if (update) // update params
				for (k in update)
					t.params[k] = update[k]
			return url(t.path, t.params) // encode back
		} else { // decode
			var i = path.indexOf('?')
			var params
			if (i > -1) {
				params = path.substring(i + 1)
				path = path.substring(0, i)
			}
			var a = path.split('/')
			for (var i = 0; i < a.length; i++)
				a[i] = decodeURIComponent(a[i])
			var t = {}
			if (params !== undefined) {
				params = params.split('&')
				for (var i = 0; i < params.length; i++) {
					var kv = params[i].split('=')
					var k = decodeURIComponent(kv[0])
					var v = kv.length == 1 ? true : decodeURIComponent(kv[1])
					if (t[k] !== undefined) {
						if (typeof t[k] != 'array')
							t[k] = [t[k]]
						t[k].push(v)
					} else {
						t[k] = v
					}
				}
			}
			return {path: a, params: t}
		}
	} else { // encode
		if (typeof path == 'object') {
			params = path.params
			path = path.path
		}
		var a = []
		for (var i = 0; i < path.length; i++)
			a[i] = encodeURIComponent(path[i])
		var path = a.join('/')
		var a = []
		var keys = Object.keys(params).sort()
		for (var i = 0; i < keys.length; i++) {
			var pk = keys[i]
			var k = encodeURIComponent(pk)
			var v = params[pk]
			if (typeof v == 'array') {
				for (var j = 0; j < v.length; j++) {
					var z = v[j]
					var kv = k + (z !== true ? '=' + encodeURIComponent(z) : '')
					a.push(kv)
				}
			} else {
				var kv = k + (v !== true ? '=' + encodeURIComponent(v) : '')
				a.push(kv)
			}
		}
		var params = a.join('&')
		return path + (params ? '?' + params : '')
	}
}

/*
//decode
console.log(url('a/b?a&b=1'))
console.log(url('a/b?'))
console.log(url('a/b'))
console.log(url('?a&b=1&b=2'))
console.log(url('/'))
console.log(url(''))
//encode
// TODO
console.log(url(['a', 'b'], {a: true, b: 1}))
//update
// TODO
*/

// actions -------------------------------------------------------------------

function _underscores(action) {
	return action.replace(/-/g, '_')
}

_action_name = _underscores

function _action_urlname(action) {
	return action.replace(/_/g, '-')
}

function _decode_url(path, params) {
	if (typeof path == 'string') {
		var t = url(path)
		if (params)
			for (k in params)
				t.params[k] = params[k]
		return t
	} else {
		return {path: path, params: params || {}}
	}
}

// extract the action from a decoded url
function _url_action(t) {
	if (t.path[0] == '' && t.path.length >= 2)
		return _action_name(t.path[1])
}

// given an url (in encoded or decoded form), if it's an action url,
// replace its action name with a language-specific alias for a given
// (or current) language if any, or add ?lang= if the given language
// is not the default language.
function lang_url(path, params, target_lang) {
	var t = _decode_url(path, params)
	var default_lang = config('lang')
	var target_lang = target_lang || t.params.lang || lang()
	var action = _url_action(t)
	if (action === undefined)
		return url(t)
	var is_root = t.path[1] == ''
	if (is_root)
		action = _action_name(config('root_action'))
	var at = config('aliases').to_lang[action]
	var lang_action = at && at[target_lang]
	if (lang_action) {
		if (! (is_root && target_lang == default_lang))
			t.path[1] = lang_action
	} else if (target_lang != default_lang) {
		t.params.lang = target_lang
	}
	t.path[1] = _action_urlname(t.path[1])
	return url(t)
}

var action = {} // {action: handler}

// given a path (in encoded form), find the action it points to
// and return its handler.
function find_action(path) {
	var t = url(path)
	var act = _url_action(t)
	if (act === undefined)
		return
	if (act == '')
		act = config('root_action')
	else // an alias or the act name directly
		act = config('aliases').to_en[act] || act
	act = _action_name(act)
	var handler = action[act] // find a handler
	if (!handler) {
		// no handler, find a static template
		if (template(act) !== undefined) {
			handler = function() {
				hide_nav()
				render(act, null, '#main')
			}
		}
	}
	var args = t.path
	args.shift(0) // remove /
	args.shift(0) // remove act
	return handler && function() {
		handler.apply(null, args)
	}
}

// address bar, links and scrolling ------------------------------------------

function hide_nav() {
	$('#sidebar').hide()
	$('#homepage').hide()
}

function check(truth) {
	if(!truth) {
		hide_nav()
		render(config('not_found_template'), null, '#main')
	}
}

var g_loading = true

// check if the action was triggered by a page load or by exec()
function loading() {
	return g_loading
}

$(function() {
	var History = window.History
	History.Adapter.bind(window, 'statechange', function() {
		g_loading = false
		url_changed()
	})
})

var g_ignore_url_changed

function set_state_top(top) {
	var state = History.getState()
	g_ignore_url_changed = true
	History.replaceState({top: top}, state.title, state.url)
	g_ignore_url_changed = false
}

function exec(path, params) {
	// store current scroll top in current state first
	set_state_top($(window).scrollTop())
	// push new state without data
	History.pushState(null, null, lang_url(path, params))
}

function url_changed() {
	if (g_ignore_url_changed) return
	unlisten_all()
	unbind_keydown_all()
	analytics_pageview() // note: title is not available at this time
	var handler = find_action(location.pathname)
	if (handler)
		handler()
	else
		check(false)
}

function setlink(a, path, params, hook) {
	if ($(a).data('_hooked'))
		return
	var url = lang_url(path, params)
	var handler = find_action(url)
	if (!(handler || hook)) return
	$(a).click(function(event) {
			// shit/ctrl+click passes through to open in new window or tab
			if (event.shiftKey || event.ctrlKey) return
			event.preventDefault()
			if (hook) hook()
			if (handler)
				exec(path, params)
		}).data('_hooked', true)
}

function setlinks(dst) {
	dst = dst || 'body'
	$(dst).find('a[href],area[href]').each(function() {
		var a = $(this)
		if (a.attr('target')) return
		var url = a.attr('href')
		setlink(this, url)
	})
}

function settitle(title) {
	title = title
		|| $('h1').html()
		|| url(location.pathname).path[1].replace(/[-_]/g, ' ')
	if (title)
		document.title = title + config('page_title_suffix')
}

function slug(id, s) {
	return (s.toLowerCase()
		.replace(/ /g,'-')
		.replace(/[^\w-]+/g,'')
	) + '-' + id
}

function intarg(s) {
	s = s && s.match(/\d+$/)
	return s && parseInt(s) || ''
}

function optarg(s) {
	return s && ('/' + s) || ''
}

function back() {
	History.back()
}

/*
$(function() {
	$(window).scroll(function() {

	})
})
*/

// set scroll back to where it was
function setscroll() {
	var state = History.getState()
	var top = state.data && state.data.top || 0
	$(window).scrollTop(top)
}

function scroll_top() {
	set_state_top(0)
	$(window).scrollTop(0)
}

// UI patterns ---------------------------------------------------------------

// find an id attribute in the parents of an element
function upid(e, attr) {
	return parseInt($(e).closest('['+attr+']').attr(attr))
}

// toasty notifications
function notify(msg, cls) {
	$().toasty({
		message: msg,
		position: 'tc',
		autoHide: 1 / (100 * 5 / 60) * 1000 * msg.length, // assume 100 WPM
		messageClass: cls,
	})
}

// back-top-top button
$(function() {
	var btn = $('.back-to-top')
	$(window).scroll(function() {
		btn.toggleClass('visible', $(this).scrollTop() > $(window).height())
	})
	btn.on('click', function(event) {
		event.preventDefault()
		$('html, body').stop().animate({ scrollTop: 0, }, 700, 'easeOutQuint')
	})
})
