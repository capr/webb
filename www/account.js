// documentation--------------------------------------------------------------
/*
	#account_section
		#login_form
			#email
			#pass
			#btn_facebook
			#btn_google
			#btn_no_account
			#btn_login
			#btn_create_account
		#usr_form
			#usr_email
			#usr_name
			#usr_phone
			#relogin
			#logout
			#btn_save
			#btn_cancel
*/

// session vocabulary --------------------------------------------------------

function login(auth, success, error, opt, arg) {
	function logged_in(usr) {
		broadcast('usr', usr)
		if (success)
			success(usr)
	}
	function login_failed(xhr) {
		var err = xhr.responseText
		S('server_error', 'There was an error.<br>Please try again or contact us.')
		S('login_error_email_taken', 'This email is already taken')
		S('login_error_user_pass', 'Wrong email address or password')
		var msg = S('login_error_'+err) || S('server_error')
		notify(msg)
		if (error)
			error()
	}
	return ajax('/login.json' + (arg || ''), $.extend({
			success: logged_in,
			error: login_failed,
			data: auth,
		}, opt))
}

function logout(success, error, opt) {
	return login(null, success, error, opt, '/logout')
}

var g_admin = false
function admin() {
	return g_admin
}

function editmode() {
	return admin()
}

function init_admin() {
	listen('usr.admin', function(usr) {
		g_admin = usr.admin
	})
}

// account widget ------------------------------------------------------------

// account_widget({options...}) -> account
// account.validate() -> true|nothing
function account_widget(acc) {

	acc = $.extend({
		section: '#account_section',
	}, acc)

	var want_anonymous = false
	var email_taken = false
	var validator

	// form validation --------------------------------------------------------

	function error_placement(error, element) {
		var div = $('.error[for="'+$(element).attr('id')+'"]')
		div.css('left', $(element).width() + 20 + 60)
		div.append(error)
		return false
	}

	// login section ----------------------------------------------------------

	function enable_save() {
		$('#btn_save').prop('disabled', false)
		if (!$('#btn_cancel').is(':visible'))
			$('#btn_cancel').css('width', 0).show()
				.animate({width: '100'}, 300, 'easeOutQuint')
	}

	function login_failed(xhr) {

		// animate the whole section as if saying "no no"
		var a = $(acc.section)
		a.css({position: 'relative'})
		// note: top: 0 is just beacause the animation won't start with no attrs.
		a.animate({top: 0}, {
			duration: 400,
			progress: function(_,t) {
				a.css('left', 30 * (1-t) * Math.sin(t * Math.PI * 6))
			},
		})

		// re-enable the buttons
		$('#btn_login').prop('disabled', false)
		$('#btn_create_account').prop('disabled', false)
		enable_save()

		// focus on email, if email taken
		var err = xhr.responseText
		if (err == 'email_taken') {
			email_taken = true
			validator.element('#usr_email')
			validator.focusInvalid()
			email_taken = null
		}
	}

	var validate_login

	function create_login_section() {

		render('account_login', null, acc.section)

		$('.fa-eye').click(function() {
			$('#pass').attr('type',
				$('#pass').attr('type') == 'password' ? 'text' : 'password')
		})

		$('#btn_facebook').click(function() {
			facebook_login(null, login_failed)
		})

		$('#btn_google').click(function() {
			google_login(null, login_failed)
		})

		$('#btn_no_account').click(function() {
			want_anonymous = true
			login({type: 'anonymous'})
		})

		$('#email').keypress(function(e) {
			if(e.keyCode == 13)
				$('#pass').focus()
		})

		$('#pass').keypress(function(e) {
			if(e.keyCode == 13)
				$('#btn_login').click()
		})

		validator = $('#login_form').validate({
			rules: {
				pass: { minlength: 6 }
			},
			messages: {
				email: {
					required: S('email_required_error',
						'We need your email to contact you'),
					email: S('email_format_error',
						'Your email must be valid'),
					email_taken: S('email_taken',
						'This email is already taken'),
				},
				pass: {
					required: S('pass_required_error',
						'You need a password to sign in'),
					minlength: $.validator.format(S('pass_format_error',
						'Enter at least {0} characters')),
				},
			},
			errorPlacement: error_placement,
		})

		$.validator.addMethod('email_taken', function() {
			return !email_taken
		})

		validate_login = function() {
			if (!$('#login_form').valid()) {
				validator.focusInvalid()
				login_failed()
				return false
			}
			return true
		}

		function pass_auth(action) {
			return {
				type:  'pass',
				action: action,
				email:  $('#email').val(),
				pass:   $('#pass').val(),
			}
		}

		$('#btn_login').click(function() {
			if (validate_login()) {
				$(this).prop('disabled', true)
				login(pass_auth('login'), null, login_failed)
			}
		})

		$('#btn_create_account').click(function() {
			if (validate_login()) {
				$(this).prop('disabled', true)
				login(pass_auth('create'), null, login_failed)
			}
		})
	}

	// user section --------------------------------------------------------------

	var validate_usr

	function create_user_section(usr) {

		usr.firstname = firstname(usr.name, usr.email)
		render('account_info', usr, acc.section)

		$('#relogin').click(function() {
			create_login_section()
		})

		$('#logout').click(function() {
			$('#logout').prop('disabled', true)
			logout()
		})

		validator = $('#usr_form').validate({
			rules: {
				usr_email: { email_taken: true, },
				usr_phone: { phone_number: true, },
			},
			messages: {
				usr_email: {
					required: S('email_required_error',
						'We need your email to contact you'),
					email: S('email_format_error',
						'Your email must be valid'),
					email_taken: S('email_taken',
						'This email is already taken'),
				},
				usr_name: {
					required: S('name_required_error',
						'We need your name to contact you'),
				},
				usr_phone: {
					required: S('phone_required_error',
						'We need your phone to contact you'),
					phone_number: S('phone_invalid_error',
						'Invalid phone number'),
				},
			},
			errorPlacement: error_placement,
		})

		$.validator.addMethod('email_taken', function() {
			return !email_taken
		})

		$.validator.addMethod('phone_number', function(s) {
			return /^[0-9\+\.\-\s]+$/.test(s)
		})

		validate_usr = function() {
			if (!$('#usr_form').valid()) {
				validator.focusInvalid()
				return false
			}
			return true
		}

		$('#usr_email, #usr_name, #usr_phone')
			.on('input', enable_save)
			.keypress(function(e) {
					if(e.keyCode == 13 && !$('#btn_save').prop('disabled'))
						$('#btn_save').click()
				})

		$('#btn_save').click(function() {
			if (!validate_usr())
				return
			$('#btn_save').prop('disabled', true)
			login({
				type: 'update',
				email: $('#usr_email').val(),
				name:  $('#usr_name').val(),
				phone: $('#usr_phone').val(),
			}, function(usr) {
				notify(S('changes_saved', 'Changes saved'))
			}, login_failed)
		})

		$('#btn_cancel').click(function() {
			login()
			return true
		})

	}

	// account ----------------------------------------------------------------

	acc.validate = function() {

		if ($('#login_form').length) {
			if (!validate_login())
				return
			$('#email').focus() // login form validates but we're not logged in
			return
		}

		if ($('#usr_form').length)
			if (!validate_usr())
				return

		return true
	}

	listen('usr.account_widget.current_action', function(usr) {
		if (usr.anonymous && !want_anonymous)
			create_login_section()
		else
			create_user_section(usr)
	})

	login()

	return acc
}

// account page --------------------------------------------------------------

action.account = function() {

	listen('usr.account_page.current_action', function() {
		//
	})

	render('account', null, '#main')
	account_widget()
}

