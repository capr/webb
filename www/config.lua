setfenv(1, require'g')

config('smtp_host', '93.115.10.161')
config('basepath', '../www')

if config('lang', 'en') == 'ro' then

S('reset_pass_subject', 'Linkul pentru schimbarea parolei')

S('order_placed_email_subject', 'Comanda nr. %s la %s')
S('shiptype_home', 'Prin curier')
S('shiptype_store', 'La magazin')
S('sales', 'comenzi')
S('abandoned_cart_email_subject', 'Ne e dor de tine!')

end
