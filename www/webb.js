
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

// global lang() for conditionally setting S() values based on language.
function lang() {
	return document.documentElement.lang || config('lang')
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
// 4. non-string data turns json.

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

function ajax(url, opt) {
	opt = opt || {}
	var id = opt.id
	if (id)
		abort(id)

	var data = opt.data
	if (data && (typeof data != 'string'))
		data = {data: JSON.stringify(data)}
	var type = opt.type || (data ? 'POST' : 'GET')

	var xhr = $.ajax({
		url: url,
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

// ajax request with ui feedback for slow loading and failure.
// automatically aborts on load_content() and render() calls over the same dst.
function load_content(dst, url, success, error, opt) {

	var dst = $(dst)
	function set_loading() {
		return dst.html('<div class="loading_outer">'+
						'<div class="loading_middle">'+
							'<div class="loading_inner loading">'+
							'</div>'+
						'</div>'+
					'</div>').find('.loading_inner')
	}
	var slow_watch = setTimeout(set_loading, config('slow_loading_feedback_delay', 1500))

	var done = function() {
		clearTimeout(slow_watch)
		dst.html('')
	}

	return ajax(url,
		$.extend({
			id: $(dst).attr('id'),
			success: function(data) {
				done()
				if (success)
					success(data)
			},
			error: function(xhr) {
				done()
				set_loading()
					.removeClass('loading')
					.addClass('loading_error')
					.attr('title', xhr.responseText)
					.click(function() {
						set_loading()
						load_content(dst, url, success, error)
					})
				if (error)
					error(xhr)
			},
			abort: done,
		}, opt))
}

// ajax request on the main pane: restore scroll position.
function load_main(url, success, error, opt) {
	load_content('#main', url,
		function(data) {
			if (success)
				success(data)
			setscroll()
		},
		error,
		opt)
}

// templating ----------------------------------------------------------------

var templates_loaded = false

function load_templates(success) {
	if (templates_loaded == lang()) {
		if (success)
			success()
	} else {
		var templates_html = config('templates_action', 'templates.html')
		get(full_url('/'+templates_html), function(s) {
			$('#templates').html(s)
			templates_loaded = lang()
			if (success)
				success()
		})
	}
}

function template_object(name) {
	return $('#' + name + '_template')
}

function load_partial_(name) {
	return template_object(name).html()
}

function render_(template_name, data, dst) {
	var t = template_object(template_name).html()
	var s = Mustache.render(t, data || {}, load_partial_)
	if (dst) {
		dst = $(dst)
		var id = dst.attr('id')
		abort(id)
		dst.html(s)
		setlinks(dst)
	} else
		return s
}

function render(template_name, data, dst) {
	load_templates(function() {
		render_(template_name, data, dst)
	})
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

// address bar, links and scrolling ------------------------------------------

function hide_nav() {
	$('#sidebar').hide()
	$('#homepage').hide()
}

function check(truth) {
	if(!truth)
		window.location = '/'
}

function allow(truth) {
	if(!truth)
		window.location = '/account'
}

$(function() {
	var History = window.History
	History.Adapter.bind(window, 'statechange', url_changed)
})

function full_url(path, params) {
	// encode params and add lang param to url if needed.
	var lang_ = lang()
	var explicit_lang = lang_ != config('lang')
	var url = path
	if (params || explicit_lang) {
		if (explicit_lang)
			params = $.extend({}, params, {lang: lang_})
		url = url + '?' + $.param(params)
	}
	return url
}

function set_state_top(top) {
	var state = History.getState()
	g_ignore_url_changed = true
	History.replaceState({top: top}, state.title, state.url)
	g_ignore_url_changed = false
}

function exec(url, params) {
	// store current scroll top in current state first
	set_state_top($(window).scrollTop())
	// push new state without data
	History.pushState(null, null, full_url(url, params))
}

var action = {} // {action: handler}

function parse_url(url) {
	var args = url.split('/')
	if (args[0]) return // not an action url
	args.shift() // remove ""
	var act = args[0] || config('default_action')
	args.shift() // remove the action
	act = act.replace('-', '_') // make it easier to declare actions
	var handler = action[act] // find a handler
	if (!handler) {
		// no handler, find a static template
		if (template_object(act).length) {
			handler = function() {
				hide_nav()
				render(act, null, '#main')
			}
		}
	} else {
		for (var i = 0; i < args.length; i++)
			args[i] = decodeURIComponent(args[i])
	}
	return {
		action: act,
		handler: handler,
		args: args,
	}
}

var g_ignore_url_changed

function url_changed() {
	if (g_ignore_url_changed) return
	unlisten_all()
	unbind_keydown_all()
	analytics_pageview() // note: title is not available at this time
	var t = parse_url(location.pathname)
	t.handler.apply(null, t.args)
}

function setlink(a, url, params, hook) {
	$(a).attr('href', full_url(url, params))
		.click(function(event) {
			// shit/ctrl+click passes through to open in new window or tab
			if (event.shiftKey || event.ctrlKey) return
			event.preventDefault()
			if (hook) hook()
			exec(url, params)
		})
}

function setlinks(dst) {
	dst = dst || 'body'
	$(dst).find('a[href],area[href]').each(function() {
		var a = $(this)
		if (a.attr('target')) return
		var url = a.attr('href')
		var t = parse_url(url)
		if (!t || !t.handler) return
		setlink(this, url)
	})
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

// TODO: not working on OSX
function follow_scroll(element_id, margin) {
	var el = $(element_id)
	var ey = el.position().top + 46 // TODO: account for margins of parents!
	var adjust_position = function() {
		var y = $(this).scrollTop()
		if (y < ey - margin || window.innerHeight < el.height() + margin) {
			el.css({position: 'relative', top: ''})
		} else {
			el.css({position: 'fixed', top: margin})
		}
	}
	$(window).scroll(adjust_position)
	$(window).resize(adjust_position)
}

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

